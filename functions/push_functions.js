/**
 * F2 — Pushes do loop de treino/social do ALUNO.
 * (§9.1 + §4 de docs/b2c/REPAGINADA_ADMIN_ALUNO100_PLANO.md — gap A1.)
 *
 * Exporta:
 *  - sendPushIfAllowed({ db, uid, category, title, body, data }) — helper
 *    compartilhado que TODA CF de push do aluno deve usar. Aplica, NA ORDEM:
 *      (1) users/{uid}.notificationPrefs[CATEGORY_PREF_KEY[category]] —
 *          campo AUSENTE = true (opt-out); 'billing' não passa por aqui
 *          (não é desligável). FIX (jul/2026): a leitura é pela chave PT-BR
 *          real que o cliente grava (ver CATEGORY_PREF_KEY abaixo) — antes
 *          lia `prefs[category]` (EN) direto e os toggles "Treino"/
 *          "Academia" eram placebo (a chave nunca batia, então sempre caía
 *          no default "permitido").
 *      (2) quiet hours 21h–8h America/Sao_Paulo — dentro da janela o push é
 *          DROPADO com log (não enfileira para depois).
 *      (3) cap semanal para category 'training': máx. 3 pushes de
 *          treino/retenção por semana ISO, contados em users/{uid}.pushMeta
 *          = { weekKey: 'YYYY-Www', count } via transação (reset ao virar a
 *          semana). 'social' e 'academy' não consomem o cap.
 *    O envio em si espelha o mecanismo canônico de server_functions.js
 *    (subcoleção users/{uid}/fcmTokens + sendEachForMulticast + limpeza de
 *    tokens inválidos) — mesmo storage de token, sem inventar outro.
 *
 *  - streakRiskCheck      (qui/sex 18:00 SP)  — "a semana ainda tá aberta"
 *  - weeklyRecapSunday    (dom 19:00 SP)      — recap da semana que fecha
 *  - classReminderHourly  (06–21h SP, hora em hora) — "hoje tem treino" ~2h antes
 *
 * INVARIANTES (§10 do plano):
 *  - Tom NUNCA punitivo (nada de "você sumiu").
 *  - Ranking JAMAIS em push.
 *  - Self-log (users/{uid}/training_logs) aqui é usado SÓ para evitar falso
 *    positivo/contar rolas em push — NUNCA alimenta ranking/graduação.
 *  - riskScore/contactLog nunca aparecem em push nem em payload.
 *  - MODO LESÃO/DESCANSO (§4.3 da pesquisa de retenção): users/{uid}
 *    .streakFreezes = { 'YYYY-Www': 'lesao'|'descanso' }, escrito pelo
 *    PRÓPRIO aluno (lib/services/streak_freeze_service.dart). Semana corrente
 *    congelada = o aluno avisou que está parado → streakRiskCheck NUNCA
 *    cutuca. Semana congelada no meio de um run = PONTE (não conta como
 *    treinada, não quebra) — mesma semântica de lib/services/weekly_streak.dart,
 *    para o número do push jamais divergir do streak que o aluno vê no app.
 *
 * CUSTO (documentado por exigência do plano): streakRiskCheck e
 * weeklyRecapSunday NÃO varrem users/ — iteram academies/{aid}/students com
 * projeção select(linkedUserId, status, retention). Custo por run:
 * O(nº de alunos da plataforma) leituras de doc (projeção reduz bandwidth,
 * não billing) + ~2 leituras de users/{uid} por CANDIDATO que passa nos
 * filtros (subconjunto pequeno; a 2ª é o fieldMask de streakFreezes) + 1
 * query em training_logs por candidato. Com ~10³–10⁴ alunos e 3 runs/semana,
 * isso fica na casa de dezenas de milhares de reads semanais — ordens de
 * magnitude abaixo de varrer users/ inteiro por dia.
 */

const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

const db = admin.firestore();
const messaging = admin.messaging();

// ============================================================
// Constantes de guardrail (§4 do plano)
// ============================================================

const SP_TIMEZONE = 'America/Sao_Paulo';
// SP é UTC-3 fixo (Brasil aboliu o horário de verão em 2019).
const SP_UTC_OFFSET_HOURS = 3;

const QUIET_HOURS_START = 21; // >= 21h → silêncio
const QUIET_HOURS_END = 8;    // < 8h  → silêncio (8h em diante volta a enviar)
const TRAINING_WEEKLY_CAP = 3; // máx. pushes category 'training' por semana ISO

// 'attendance' (retention_functions.js — push do ATO da presença, jul/2026)
// NÃO consome TRAINING_WEEKLY_CAP (ver step 3 de sendPushIfAllowed abaixo):
// é auto-limitado a 1x/presença e já gated pela janela de 12h no próprio
// handler, então competir pelo mesmo orçamento semanal do streak/recap/
// lembrete faria o push do "momento de pico" sumir justamente para quem
// mais treina — o oposto do objetivo.
const PUSH_CATEGORIES = new Set(['social', 'training', 'academy', 'attendance']);

/**
 * Categoria interna (como os handlers chamam sendPushIfAllowed) → chave
 * PT-BR gravada por `_NotifPrefs.toMap()` em
 * lib/screens/portal/notification_prefs_screen.dart. FIX (jul/2026): antes
 * o código lia `prefs[category]` DIRETAMENTE — como o cliente grava em
 * PT-BR ('treino'/'academia') e aqui a categoria é em EN ('training'/
 * 'academy'), os toggles "Treino" e "Academia" eram PLACEBO: a chave lida
 * nunca batia com a gravada, então caía sempre no default "ausente =
 * permitido" e o push saía do mesmo jeito com o toggle desligado. 'social'
 * já funcionava, por coincidência (mesma grafia nos dois lados).
 * 'attendance' não tem toggle dedicado na UI — reaproveita a MESMA chave
 * 'treino' ("Streak, lembretes de aula e recap da semana"): semanticamente
 * é o mesmo balde de preferência.
 */
const CATEGORY_PREF_KEY = {
  social: 'social',
  training: 'treino',
  academy: 'academia',
  attendance: 'treino',
};

// ============================================================
// Helpers de tempo — wall-clock de São Paulo + semana ISO
// ============================================================

/**
 * Partes do relógio de parede de São Paulo para um instante.
 * weekdayIndex segue a convenção da grade de classes (ClassSchedule em
 * lib/services/class_service.dart): 0 = domingo … 6 = sábado.
 */
function spNowParts(date = new Date()) {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: SP_TIMEZONE,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
    hourCycle: 'h23', weekday: 'short',
  });
  const parts = {};
  for (const p of fmt.formatToParts(date)) parts[p.type] = p.value;
  const weekdayIndex =
    { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }[parts.weekday];
  return {
    year: Number(parts.year),
    month: Number(parts.month), // 1..12
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    weekdayIndex,
  };
}

/** true se o wall-clock SP está dentro das quiet hours (21h–8h). */
function isInQuietHours(spParts) {
  return spParts.hour >= QUIET_HOURS_START || spParts.hour < QUIET_HOURS_END;
}

/**
 * Chave ISO-8601 'YYYY-Www' (segunda = início; ISO week-year) da data civil
 * (y, m, d), com deslocamento opcional em dias. Convenção compartilhada com o
 * mapa retention.weeklyBuckets escrito por onAttendanceWrite.
 */
function isoWeekKey(year, month, day, offsetDays = 0) {
  const d = new Date(Date.UTC(year, month - 1, day + offsetDays));
  const dayNum = d.getUTCDay() === 0 ? 7 : d.getUTCDay(); // 1=Seg..7=Dom
  d.setUTCDate(d.getUTCDate() + 4 - dayNum); // quinta-feira da semana ISO
  const isoYear = d.getUTCFullYear();
  const yearStart = new Date(Date.UTC(isoYear, 0, 1));
  const week = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}

/** Chave 'YYYY-Www' da semana ISO corrente no relógio de SP. */
function currentIsoWeekKey(spParts) {
  return isoWeekKey(spParts.year, spParts.month, spParts.day, 0);
}

/**
 * Instante UTC da meia-noite (SP) da SEGUNDA-FEIRA da semana ISO corrente.
 * Usado como piso das queries em users/{uid}/training_logs (o campo `date` é
 * Timestamp da meia-noite local do dia do treino).
 */
function isoWeekMondayUtc(spParts) {
  const d = new Date(Date.UTC(spParts.year, spParts.month - 1, spParts.day));
  const dayNum = d.getUTCDay() === 0 ? 7 : d.getUTCDay();
  d.setUTCDate(d.getUTCDate() - (dayNum - 1)); // volta até segunda
  return new Date(Date.UTC(
    d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(),
    SP_UTC_OFFSET_HOURS, 0, 0));
}

/** 'YYYY-MM-DD' do dia corrente em SP (chave de dedup diário). */
function spTodayKey(spParts) {
  const mm = String(spParts.month).padStart(2, '0');
  const dd = String(spParts.day).padStart(2, '0');
  return `${spParts.year}-${mm}-${dd}`;
}

/**
 * Streak em SEMANAS com bucket > 0 em retention.weeklyBuckets, andando para
 * trás a partir da semana corrente (includeCurrent=true) ou da anterior
 * (includeCurrent=false). Como weeklyBuckets guarda ~9 semanas (poda
 * automática — ver contrato de retention), o streak reportado satura nesse
 * horizonte; a mensagem continua verdadeira ("pelo menos N").
 *
 * [streakFreezes] = users/{uid}.streakFreezes ({ 'YYYY-Www': motivo }):
 * semana congelada SEM treino é PONTE — não soma no streak, não quebra o run
 * (mesma semântica de lib/services/weekly_streak.dart). Semana congelada COM
 * treino conta normalmente (treino vence).
 */
function computeStreakWeeks(weeklyBuckets, spParts, includeCurrent, streakFreezes) {
  const buckets = weeklyBuckets || {};
  const freezes = streakFreezes || {};
  let streak = 0;
  for (let k = includeCurrent ? 0 : 1; k < 60; k++) {
    const key = isoWeekKey(spParts.year, spParts.month, spParts.day, -7 * k);
    if ((Number(buckets[key]) || 0) > 0) streak++;
    else if (freezes[key]) { /* PONTE — modo lesão/descanso */ }
    else break;
  }
  return streak;
}

// ============================================================
// Envio FCM — espelho do mecanismo canônico de server_functions.js
// (subcoleção users/{uid}/fcmTokens, doc-id = token; sendEachForMulticast;
// remove tokens invalid/not-registered). server_functions.js não exporta os
// helpers internos, então replicamos AQUI o mesmo mecanismo — mesmo storage,
// mesma limpeza — em vez de inventar outro canal.
// ============================================================

async function getUserTokens(dbRef, uid) {
  const snap = await dbRef.collection('users').doc(uid)
    .collection('fcmTokens').get();
  return snap.docs.map((doc) => doc.data().token).filter(Boolean);
}

/** FCM `data` só aceita string→string — coage tudo para string. */
function stringifyData(data) {
  const out = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (v === undefined || v === null) continue;
    out[k] = String(v);
  }
  return out;
}

async function sendFcmToUser(dbRef, uid, title, body, data) {
  const tokens = await getUserTokens(dbRef, uid);
  if (tokens.length === 0) {
    console.log(`[push] sem tokens FCM para user ${uid}`);
    return false;
  }

  const message = {
    notification: { title, body },
    data: stringifyData(data),
    tokens,
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
    console.log(`[push] ${response.successCount}/${tokens.length} devices para ${uid}`);

    // Limpa tokens inválidos (mesmo critério de server_functions.js).
    if (response.failureCount > 0) {
      const deletes = [];
      response.responses.forEach((resp, idx) => {
        if (resp.success) return;
        const code = resp.error && resp.error.code;
        if (code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered') {
          deletes.push(
            dbRef.collection('users').doc(uid)
              .collection('fcmTokens').doc(tokens[idx]).delete()
              .catch((e) => console.warn('[push] falha ao remover token', e.message)));
        }
      });
      await Promise.all(deletes);
    }
    return response.successCount > 0;
  } catch (e) {
    console.error(`[push] erro ao enviar para ${uid}:`, e);
    return false;
  }
}

// ============================================================
// sendPushIfAllowed — o portão único de push do aluno (§4)
// ============================================================

/**
 * Envia um push ao usuário SE os guardrails permitirem, NA ORDEM:
 *  1. notificationPrefs[category] (ausente = true; false = opt-out).
 *  2. Quiet hours 21h–8h SP → dropa com log (não enfileira).
 *  3. category 'training' → cap TRAINING_WEEKLY_CAP/semana ISO via transação
 *     em users/{uid}.pushMeta { weekKey, count } (reset ao virar a semana).
 *
 * @param {object} args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {string} args.uid       users/{uid}
 * @param {'social'|'training'|'academy'} args.category
 * @param {string} args.title
 * @param {string} args.body
 * @param {object} [args.data]    payload FCM (valores coagidos p/ string)
 * @returns {Promise<{sent: boolean, reason?: string}>}
 */
async function sendPushIfAllowed({ db: dbRef, uid, category, title, body, data }) {
  const database = dbRef || db;
  if (!uid) return { sent: false, reason: 'no-uid' };
  if (!PUSH_CATEGORIES.has(category)) {
    console.warn(`[push] categoria desconhecida '${category}' para ${uid} — drop`);
    return { sent: false, reason: 'bad-category' };
  }

  const userRef = database.collection('users').doc(uid);

  // (1) Preferências — campo AUSENTE = true (opt-out explícito com false).
  // Lê pela chave PT-BR REAL (CATEGORY_PREF_KEY) — NÃO pela categoria crua
  // (era a raiz do bug de toggle-placebo, ver comentário do mapa acima).
  const userSnap = await userRef.get();
  if (!userSnap.exists) return { sent: false, reason: 'no-user' };
  const prefs = (userSnap.data() || {}).notificationPrefs || {};
  const prefKey = CATEGORY_PREF_KEY[category] || category;
  if (prefs[prefKey] === false) {
    console.log(`[push] drop (prefs.${prefKey}=false, categoria ${category}) uid=${uid}`);
    return { sent: false, reason: 'prefs-opt-out' };
  }

  // (2) Quiet hours 21h–8h SP — dropa, NÃO enfileira.
  const sp = spNowParts();
  if (isInQuietHours(sp)) {
    console.log(`[push] drop (quiet hours ${sp.hour}h SP) uid=${uid} cat=${category}`);
    return { sent: false, reason: 'quiet-hours' };
  }

  // (3) Cap semanal de treino/retenção — transação para não estourar em runs
  // concorrentes. set(merge) é merge RECURSIVO: preserva outras chaves de
  // pushMeta (ex.: lastClassReminderDate).
  if (category === 'training') {
    const weekKey = currentIsoWeekKey(sp);
    let allowed = false;
    try {
      allowed = await database.runTransaction(async (tx) => {
        const snap = await tx.get(userRef);
        const meta = (snap.data() || {}).pushMeta || {};
        const count = meta.weekKey === weekKey ? (Number(meta.count) || 0) : 0;
        if (count >= TRAINING_WEEKLY_CAP) return false;
        tx.set(userRef, { pushMeta: { weekKey, count: count + 1 } }, { merge: true });
        return true;
      });
    } catch (e) {
      console.error(`[push] tx do cap falhou uid=${uid}:`, e.message);
      return { sent: false, reason: 'cap-tx-failed' };
    }
    if (!allowed) {
      console.log(`[push] drop (cap ${TRAINING_WEEKLY_CAP}/semana ${weekKey}) uid=${uid}`);
      return { sent: false, reason: 'weekly-cap' };
    }
  }

  const sent = await sendFcmToUser(database, uid, title, body,
    { category, ...(data || {}) });
  return sent ? { sent: true } : { sent: false, reason: 'no-tokens-or-error' };
}

// Export interno — outras CFs (ex.: feed_like_counter.js) usam este portão.
exports.sendPushIfAllowed = sendPushIfAllowed;

// ============================================================
// Iteração de alunos — NUNCA varre users/ (custo, ver header)
// ============================================================

/**
 * Itera academies/{aid}/students projetando só (linkedUserId, status, retention)
 * e invoca cb(academyId, studentDoc) para alunos ATIVOS (status ausente =
 * active, retrocompat) com linkedUserId preenchido. Filtro em memória de
 * propósito: where('status'=='active') perderia docs legados sem o campo, e
 * linkedUserId != null exigiria índice extra sem reduzir billing de reads
 * de forma relevante.
 */
async function forEachLinkedActiveStudent(cb) {
  const academyRefs = await db.collection('academies').listDocuments();
  for (const academyRef of academyRefs) {
    let snap;
    try {
      snap = await academyRef.collection('students')
        .select('linkedUserId', 'status', 'retention')
        .get();
    } catch (e) {
      console.error(`[push] falha lendo students de ${academyRef.id}:`, e.message);
      continue;
    }
    for (const doc of snap.docs) {
      const s = doc.data() || {};
      const status = s.status || 'active';
      if (status !== 'active') continue;
      if (!s.linkedUserId) continue;
      // eslint-disable-next-line no-await-in-loop
      await cb(academyRef.id, doc.id, s);
    }
  }
}

/**
 * Lê users/{uid}.streakFreezes ({ 'YYYY-Www': 'lesao'|'descanso' }) com
 * fieldMask — 1 read enxuto por CANDIDATO, mesmo perfil de custo do header.
 * Fail-open ({}): erro transitório degrada para o comportamento pré-freeze
 * (melhor 1 push a mais que run quebrada), com log.
 */
async function getStreakFreezes(uid) {
  try {
    const [snap] = await db.getAll(
      db.collection('users').doc(uid), { fieldMask: ['streakFreezes'] });
    const raw = snap.exists ? (snap.data() || {}).streakFreezes : null;
    return (raw && typeof raw === 'object') ? raw : {};
  } catch (e) {
    console.warn(`[push] leitura de streakFreezes falhou uid=${uid}:`, e.message);
    return {};
  }
}

/** true se o aluno tem QUALQUER training_log (self-log) na semana ISO corrente. */
async function hasSelfLogThisWeek(uid, mondayUtc) {
  try {
    const snap = await db.collection('users').doc(uid)
      .collection('training_logs')
      .where('date', '>=', mondayUtc)
      .limit(1)
      .get();
    return !snap.empty;
  } catch (e) {
    console.warn(`[push] query training_logs falhou uid=${uid}:`, e.message);
    return false; // fail-open para o check de streak (melhor 1 push a mais que crash)
  }
}

/** Soma de sparringCount dos training_logs da semana ISO corrente (p/ recap). */
async function sumRolasThisWeek(uid, mondayUtc) {
  try {
    const snap = await db.collection('users').doc(uid)
      .collection('training_logs')
      .where('date', '>=', mondayUtc)
      .get(); // dedup 1 doc/dia no client → ≤7 docs
    let total = 0;
    snap.docs.forEach((d) => { total += Number((d.data() || {}).sparringCount) || 0; });
    return total;
  } catch (e) {
    console.warn(`[push] soma de rolas falhou uid=${uid}:`, e.message);
    return 0;
  }
}

// ============================================================
// 1. streakRiskCheck — qui/sex 18:00 SP
// ============================================================

/**
 * Streak em risco: aluno com streak ativo ≥2 semanas (semanas ANTERIORES em
 * retention.weeklyBuckets) e semana ISO corrente sem treino. Antes de enviar,
 * consulta users/{uid}/training_logs da semana corrente: quem já fez self-log
 * NÃO recebe (falso positivo — a pessoa treinou, só não tem presença
 * verificada ainda). Tom SEMPRE acolhedor — nunca culpa.
 */
exports.streakRiskCheck = onSchedule(
  { schedule: '0 18 * * 4,5', timeZone: SP_TIMEZONE, timeoutSeconds: 540 },
  async () => {
    console.log('[streakRiskCheck] start');
    const sp = spNowParts();
    const currentKey = currentIsoWeekKey(sp);
    const mondayUtc = isoWeekMondayUtc(sp);

    // Dedup por uid: um usuário linkado em 2 academias recebe no máximo 1.
    const seen = new Set();
    let sentCount = 0;

    await forEachLinkedActiveStudent(async (academyId, studentId, s) => {
      const uid = s.linkedUserId;
      if (seen.has(uid)) return;

      const buckets = s.retention && s.retention.weeklyBuckets;
      if (!buckets) return; // sem agregados de retenção ainda → sem sinal

      // Semana corrente COM treino verificado → streak não está em risco.
      if ((Number(buckets[currentKey]) || 0) > 0) return;

      // Gate de candidatura SEM freezes (barato, zero reads extras): streak
      // cru das semanas anteriores. Conservador de propósito — quem teve a
      // semana passada congelada sem treino (lesionado recente) fica de fora
      // do nudge, exatamente o que §4.3 pede.
      const streak = computeStreakWeeks(buckets, sp, false);
      if (streak < 2) return;

      seen.add(uid);

      // MODO LESÃO/DESCANSO (§4.3): semana corrente congelada = o aluno JÁ
      // AVISOU que está parado. Cutucar aqui seria o anti-padrão exato da
      // pesquisa ("deletei o Strava... não suportava ver os outros treinando").
      const freezes = await getStreakFreezes(uid);
      if (freezes[currentKey]) return;

      // Guard de falso positivo: self-log na semana = pessoa treinou.
      if (await hasSelfLogThisWeek(uid, mondayUtc)) return;

      // Nº do push com semântica de PONTE (freezes no meio do run não
      // quebram) — bate com o streak que o aluno vê no app.
      const bridgedStreak = computeStreakWeeks(buckets, sp, false, freezes);

      const res = await sendPushIfAllowed({
        db, uid,
        category: 'training',
        title: 'A semana ainda tá aberta 🔥',
        body: `Seu streak de ${bridgedStreak} semanas segue vivo — um treino essa semana mantém a chama.`,
        // actionUrl: diário do lutador (streak/treinos) — mesmo vocabulário
        // de rotas usado pelo createInternalNotification server-side.
        data: { type: 'streak_risk', academyId, weekKey: currentKey, actionUrl: '/portal/diario' },
      });
      if (res.sent) sentCount++;
    });

    console.log(`[streakRiskCheck] done — ${sentCount} pushes enviados`);
  }
);

// ============================================================
// 2. weeklyRecapSunday — dom 19:00 SP
// ============================================================

/**
 * Recap da semana ISO que fecha (domingo é o último dia — semana começa na
 * segunda). SÓ envia se houve ≥1 treino VERIFICADO na semana (bucket da
 * semana corrente em retention.weeklyBuckets) — NUNCA "sua semana: 0".
 * Rolas vêm do self-log (training_logs) — só enfeite de recap; jamais
 * alimenta ranking/graduação.
 */
exports.weeklyRecapSunday = onSchedule(
  { schedule: '0 19 * * 0', timeZone: SP_TIMEZONE, timeoutSeconds: 540 },
  async () => {
    console.log('[weeklyRecapSunday] start');
    const sp = spNowParts();
    const currentKey = currentIsoWeekKey(sp);
    const mondayUtc = isoWeekMondayUtc(sp);

    const seen = new Set();
    let sentCount = 0;

    await forEachLinkedActiveStudent(async (academyId, studentId, s) => {
      const uid = s.linkedUserId;
      if (seen.has(uid)) return;

      const buckets = s.retention && s.retention.weeklyBuckets;
      if (!buckets) return;

      const trainings = Number(buckets[currentKey]) || 0;
      // Nunca "sua semana: 0" — cobre TAMBÉM a semana congelada sem treino
      // (modo lesão/descanso): lesionado que não treinou não recebe recap.
      if (trainings < 1) return;

      seen.add(uid);

      // Freezes p/ o nº do streak com semântica de PONTE — semana congelada
      // no meio do run não quebra; o push não pode divergir do que o aluno vê
      // no hub. 1 read (fieldMask) por destinatário do recap.
      const freezes = await getStreakFreezes(uid);
      const streak = computeStreakWeeks(buckets, sp, true, freezes); // inclui a corrente
      const rolas = await sumRolasThisWeek(uid, mondayUtc);

      const treinoTxt = `${trainings} treino${trainings === 1 ? '' : 's'}`;
      const rolasTxt = rolas > 0 ? `, ${rolas} rola${rolas === 1 ? '' : 's'}` : '';
      const streakTxt = `streak de ${streak} semana${streak === 1 ? '' : 's'}`;

      const res = await sendPushIfAllowed({
        db, uid,
        category: 'training',
        title: 'Semana fechada 🥋',
        body: `Sua semana: ${treinoTxt}${rolasTxt} — ${streakTxt}.`,
        // actionUrl: mesmo destino do streak_risk — o recap É sobre o diário.
        data: { type: 'weekly_recap', academyId, weekKey: currentKey, actionUrl: '/portal/diario' },
      });
      if (res.sent) sentCount++;
    });

    console.log(`[weeklyRecapSunday] done — ${sentCount} pushes enviados`);
  }
);

// ============================================================
// 3. classReminderHourly — hora em hora, 06:00–21:00 SP
// ============================================================

/** Parser tolerante de 'HH:mm' (docs de schedule sujos existem — ver
 * lib/services/class_service.dart). Retorna minutos desde 00:00 ou null. */
function parseStartMinutes(raw) {
  if (typeof raw !== 'string') return null;
  const m = raw.trim().match(/^(\d{1,2})(?::(\d{1,2}))?/);
  if (!m) return null;
  const h = Number(m[1]);
  const min = m[2] === undefined ? 0 : Number(m[2]);
  if (!Number.isFinite(h) || h < 0 || h > 23) return null;
  if (!Number.isFinite(min) || min < 0 || min > 59) return null;
  return h * 60 + min;
}

/**
 * "Hoje tem treino": lembra alunos MATRICULADOS (studentIds explícito) ~2h
 * antes da turma. Janela ancorada na HORA do cron (robusta a atraso do
 * scheduler): a run das H:00 cobre turmas que começam em [H+2:00, H+3:00) —
 * cada início cai em exatamente uma run. Turmas ABERTAS (studentIds vazio /
 * isOpenClass) NÃO disparam lembrete: sem roster explícito, push para a
 * academia inteira seria spam.
 *
 * Dedup: 1 lembrete/dia por aluno via users/{uid}.pushMeta.lastClassReminderDate
 * (só marcado quando o push realmente sai). Nota: as runs das 06:00 e 07:00
 * caem inteiras nas quiet hours (<8h) e são dropadas pelo portão — mantidas no
 * cron por contrato do plano; turmas das 08:00–09:59 ficam sem lembrete de
 * propósito (guardrail vence).
 *
 * Custo: 1 query de classes ativas por academia por hora (turmas são poucas
 * dezenas/academia) + getAll dos alunos SÓ das turmas que batem na janela.
 */
exports.classReminderHourly = onSchedule(
  { schedule: '0 6-21 * * *', timeZone: SP_TIMEZONE, timeoutSeconds: 540 },
  async () => {
    const sp = spNowParts();
    const todayKey = spTodayKey(sp);
    const windowStart = (sp.hour + 2) * 60;       // início inclusivo (min)
    const windowEnd = windowStart + 60;           // fim exclusivo
    console.log(`[classReminder] start ${todayKey} ${sp.hour}h SP — janela [${windowStart},${windowEnd})`);
    if (windowStart >= 24 * 60) return; // nada começa depois da meia-noite

    const seen = new Set(); // dedup por uid dentro da run
    let sentCount = 0;

    const academyRefs = await db.collection('academies').listDocuments();
    for (const academyRef of academyRefs) {
      let classesSnap;
      try {
        classesSnap = await academyRef.collection('classes')
          .where('isActive', '==', true)
          .get();
      } catch (e) {
        console.error(`[classReminder] falha lendo classes de ${academyRef.id}:`, e.message);
        continue;
      }

      for (const classDoc of classesSnap.docs) {
        const cls = classDoc.data() || {};
        const schedule = Array.isArray(cls.schedule) ? cls.schedule : [];

        // Entrada de grade de HOJE (dayOfWeek 0=domingo, igual ao app) cujo
        // início cai na janela [agora+2h, agora+3h).
        const entry = schedule.find((sch) => {
          if (!sch || Number(sch.dayOfWeek) !== sp.weekdayIndex) return false;
          const start = parseStartMinutes(sch.startTime);
          return start !== null && start >= windowStart && start < windowEnd;
        });
        if (!entry) continue;

        const studentIds = Array.isArray(cls.studentIds) ? cls.studentIds : [];
        if (studentIds.length === 0) continue; // turma aberta — sem roster, sem push

        const startLabel = String(entry.startTime || '').trim();
        const className = String(cls.name || 'Seu treino');

        // Resolve alunos em lotes (projeção: só o que precisamos).
        for (let i = 0; i < studentIds.length; i += 200) {
          const refs = studentIds.slice(i, i + 200)
            .map((sid) => academyRef.collection('students').doc(String(sid)));
          let studentSnaps;
          try {
            // eslint-disable-next-line no-await-in-loop
            studentSnaps = await db.getAll(...refs, { fieldMask: ['linkedUserId', 'status'] });
          } catch (e) {
            console.error(`[classReminder] getAll falhou ${academyRef.id}/${classDoc.id}:`, e.message);
            continue;
          }

          for (const snap of studentSnaps) {
            if (!snap.exists) continue;
            const s = snap.data() || {};
            if ((s.status || 'active') !== 'active') continue;
            const uid = s.linkedUserId;
            if (!uid || seen.has(uid)) continue;
            seen.add(uid);

            // Dedup diário persistente (só marcado após envio real).
            // eslint-disable-next-line no-await-in-loop
            const userSnap = await db.collection('users').doc(uid).get();
            if (!userSnap.exists) continue;
            const meta = (userSnap.data() || {}).pushMeta || {};
            if (meta.lastClassReminderDate === todayKey) continue;

            // eslint-disable-next-line no-await-in-loop
            const res = await sendPushIfAllowed({
              db, uid,
              category: 'training',
              title: 'Hoje tem treino 🥋',
              body: startLabel
                ? `${className} começa às ${startLabel}. Bora pro tatame!`
                : `${className} começa daqui a pouco. Bora pro tatame!`,
              data: {
                type: 'class_reminder',
                academyId: academyRef.id,
                classId: classDoc.id,
                // actionUrl: grade de horários — é literalmente do que o push fala.
                actionUrl: '/portal/horarios',
              },
            });
            if (res.sent) {
              sentCount++;
              // eslint-disable-next-line no-await-in-loop
              await db.collection('users').doc(uid).set(
                { pushMeta: { lastClassReminderDate: todayKey } },
                { merge: true });
            }
          }
        }
      }
    }

    console.log(`[classReminder] done — ${sentCount} pushes enviados`);
  }
);
