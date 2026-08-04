/**
 * §2.1(b) / §9.2 — Materialização SERVER-SIDE dos marcos de feed dirigidos por
 * presença. Chamado pela CF `onAttendanceWrite` (e pelo job diário, se quiser
 * varrer) para que o feed NÃO dependa do autor abrir o app: aluno que some 3
 * semanas e volta a treinar tem o marco no feed dos parceiros no mesmo dia.
 *
 * PORT FIEL do emissor client-side (`lib/providers/friend_providers.dart:
 * _emitFeedPosts`) para os 3 marcos deriváveis de PRESENÇA:
 *   - streak_milestone  → streak semanal (semanas ISO consecutivas, fusão
 *                         attendance ∪ training_logs do esporte PRINCIPAL,
 *                         grace da semana corrente + PONTE de semanas
 *                         congeladas em users/{uid}.streakFreezes —
 *                         lib/services/weekly_streak.dart)
 *                         quando cruza EXATAMENTE 4/8/12/26/52 semanas;
 *   - mat_milestone     → total de aulas cruzou 100/250/500/1000, e aniversários
 *                         de tatame 1/2/3/5 anos desde a primeira presença;
 *   - weekly_volume     → resumo da última semana ISO FECHADA (>=1 treino nela).
 * (graduacao/competicao/sparring_record continuam client-side — não são
 * dirigidos por presença.)
 *
 * INVARIANTES (não-negociáveis, §10 do plano):
 *   - Doc-ids DETERMINÍSTICOS idênticos aos do cliente (lib/models/feed_post.dart:
 *     streakId/matId/volId) — a idempotência entre cliente e servidor depende
 *     de byte-igualdade dos ids.
 *   - Create-if-absent ATÔMICO: JAMAIS sobrescreve doc existente — preserva
 *     hiddenByAuthor/hiddenByStaff/staffHeadline/likeCount de posts já emitidos
 *     (mesma garantia do FeedPostsService.emitIfAbsent; aqui via `ref.create()`,
 *     que é o get+set transacional nativo do Admin SDK).
 *   - Self-log (training_logs) alimenta SÓ streak/volume do feed — NUNCA
 *     ranking/graduação (mesma regra do cliente).
 *   - Nada de retention/riskScore aqui: este módulo só escreve `feedPosts`.
 *
 * FRUGALIDADE: roda a cada presença (inclusive bulk da chamada). Fluxo:
 *   1 read do aluno + 1 getAll dos ≤14 posts candidatos → early-return se nada
 *   falta; as queries pesadas (attendance ~12 meses + training_logs) só rodam
 *   se algum marco de streak/volume ainda não existe, com janela mínima.
 */

const { Timestamp, FieldValue } = require('firebase-admin/firestore');

// ============================================================
// Constantes de marco — espelho de lib/models/feed_post.dart:172-178.
// Mudar aqui sem mudar lá quebra a idempotência cliente↔servidor.
// ============================================================

/** Streaks (semanas ISO consecutivas) que geram `streak_milestone`. */
const STREAK_MILESTONES = [4, 8, 12, 26, 52];

/** Totais de aulas que geram `mat_milestone`. */
const MAT_MILESTONES = [100, 250, 500, 1000];

/** Anos de tatame que geram `mat_milestone` de aniversário. */
const MAT_ANNIVERSARIES = [1, 2, 3, 5];

const DAY_MS = 24 * 60 * 60 * 1000;

// America/Sao_Paulo = UTC-3 FIXO (Brasil aboliu o horário de verão em 2019).
// O cliente normaliza dias com o calendário LOCAL do device; no servidor (UTC)
// aplicamos o offset para reproduzir o mesmo dia calendário — sem isso, uma
// presença às 22h BRT viraria o dia seguinte e mudaria a semana ISO do marco.
const SP_UTC_OFFSET_MS = 3 * 60 * 60 * 1000;

// ============================================================
// Helpers de data/semana ISO — portas fiéis do Dart.
// ============================================================

/** Parse tolerante de datas vindas do Firestore (Timestamp | Date | millis | ISO). */
function toDate(v) {
  if (v == null) return null;
  if (typeof v.toDate === 'function') return v.toDate(); // Timestamp
  if (v instanceof Date) return v;
  if (typeof v === 'number') return new Date(v);
  if (typeof v === 'string') {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

/**
 * Dia CALENDÁRIO do instante em America/Sao_Paulo, materializado como Date
 * UTC-midnight (chave estável de dedup por dia, imune a DST — espelha o
 * `DateTime(y,m,d)` local do cliente).
 */
function spCalendarDayUtc(instant) {
  const shifted = new Date(instant.getTime() - SP_UTC_OFFSET_MS);
  return new Date(Date.UTC(
    shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate()));
}

/**
 * Segunda-feira (UTC 00:00) da semana ISO que contém [dayUtc] (já UTC-midnight).
 * Porta de `FeedPost.mondayUtcOf` / `weekly_streak.dart:_mondayUtc`.
 */
function mondayUtcOf(dayUtc) {
  const dow = dayUtc.getUTCDay();        // 0=Dom .. 6=Sáb
  const isoDow = dow === 0 ? 7 : dow;    // ISO: Seg=1 .. Dom=7
  return new Date(dayUtc.getTime() - (isoDow - 1) * DAY_MS);
}

/**
 * Millis (UTC) da SEGUNDA da semana ISO 'YYYY-Www' — porta fiel de
 * `weekly_streak.dart:mondayUtcOfIsoWeekKey` (ISO 8601: 4 de janeiro está
 * SEMPRE na semana 1 do seu ano ISO). null p/ chave malformada — dado sujo em
 * users/{uid}.streakFreezes não derruba a materialização.
 */
function mondayUtcMsOfIsoKey(key) {
  const m = /^(\d{4})-W(\d{2})$/.exec(String(key || ''));
  if (!m) return null;
  const week = Number(m[2]);
  if (week < 1 || week > 53) return null;
  const jan4 = new Date(Date.UTC(Number(m[1]), 0, 4));
  const dow = jan4.getUTCDay() === 0 ? 7 : jan4.getUTCDay();
  return jan4.getTime() - (dow - 1) * DAY_MS + (week - 1) * 7 * DAY_MS;
}

// ============================================================
// Doc-ids determinísticos — BYTE-IGUAIS aos de lib/models/feed_post.dart.
// ============================================================

/** `streak_{uid}_{weeks}` — feed_post.dart:333. */
function streakId(uid, weeks) {
  return `streak_${uid}_${weeks}`;
}

/** `mat_{uid}_{marco}` — feed_post.dart:350. marco = '100'…'1000' | '1yr'…'5yr'. */
function matId(uid, marco) {
  return `mat_${uid}_${marco}`;
}

/**
 * `vol_{uid}_{isoYear}W{ww}` — porta fiel de feed_post.dart:341 (ISO week-year
 * via quinta-feira da semana, tratando a virada Dez/Jan igual ao Dart).
 */
function volId(uid, mondayUtc) {
  const thursday = new Date(mondayUtc.getTime() + 3 * DAY_MS);
  const jan1 = Date.UTC(thursday.getUTCFullYear(), 0, 1);
  const ordinal = Math.floor((thursday.getTime() - jan1) / DAY_MS) + 1;
  const weekNum = Math.floor((ordinal + 6) / 7);
  return `vol_${uid}_${thursday.getUTCFullYear()}W${String(weekNum).padStart(2, '0')}`;
}

// ============================================================
// Identidade do autor — mesmas regras do myShowcaseProvider
// (friend_providers.dart:85-91 + student.dart:getPrimarySport/getGrade).
// ============================================================

function primarySportOf(student) {
  if (student.primarySport) return String(student.primarySport);
  const sports = Array.isArray(student.sports) ? student.sports : null;
  return sports && sports.length ? String(sports[0]) : 'bjj';
}

/** Porta de Student.getGrade: sportData[sport] com fallback BJJ legado. */
function gradeOf(student, sport) {
  const sportData = student.sportData || {};
  if (sport === 'bjj' && sportData.bjj == null) {
    return {
      belt: String(student.currentBelt || 'white'),
      stripes: Number(student.currentStripes) || 0,
    };
  }
  const entry = sportData[sport];
  if (entry && typeof entry === 'object') {
    return {
      belt: String(entry.currentGrade || 'white'),
      stripes: Number(entry.currentStripes) || 0,
    };
  }
  // Sem standing no esporte → mesmo fallback do provider (?? currentBelt).
  return {
    belt: String(student.currentBelt || 'white'),
    stripes: Number(student.currentStripes) || 0,
  };
}

function authorIdentityOf(student, sport) {
  const nickname = typeof student.nickname === 'string' ? student.nickname.trim() : '';
  const name = nickname !== '' ? nickname : String(student.fullName || 'Lutador');
  const { belt, stripes } = gradeOf(student, sport);
  return {
    name,
    belt,
    stripes,
    photoUrl: typeof student.photoUrl === 'string' && student.photoUrl !== ''
      ? student.photoUrl
      : null,
  };
}

// ============================================================
// Streak semanal — porta da parte "streak atual" de
// lib/services/weekly_streak.dart:computeWeeklyStreak (com GRACE da semana
// corrente: semana atual sem treino ainda NÃO quebra o run; e com PONTE de
// semanas congeladas: users/{uid}.streakFreezes — modo lesão/descanso —
// não conta como treinada, não quebra o run; treino vence o freeze).
// A semântica TEM que ser a mesma do app, senão o post de marco diverge do
// streak que o aluno vê.
// ============================================================

/**
 * @param {Set<number>} trainedDayKeys millis UTC-midnight dos dias treinados
 * @param {Date} todayUtc dia calendário atual (UTC-midnight, já em SP)
 * @param {Set<number>} [frozenWeekMs] millis UTC-midnight das SEGUNDAS das
 *   semanas congeladas (via mondayUtcMsOfIsoKey sobre streakFreezes)
 * @returns {number} semanas ISO TREINADAS no run que termina na semana atual
 *   (pontes congeladas não somam nem quebram)
 */
function computeCurrentStreakWeeks(trainedDayKeys, todayUtc, frozenWeekMs = new Set()) {
  const trainedWeeks = new Set();
  for (const key of trainedDayKeys) {
    trainedWeeks.add(mondayUtcOf(new Date(key)).getTime());
  }
  const currentWeek = mondayUtcOf(todayUtc).getTime();
  const maxUseful = STREAK_MILESTONES[STREAK_MILESTONES.length - 1] + 2;
  let weeks = 0;
  let cursor = currentWeek;
  let isCurrent = true;
  // Bound defensivo de iterações: 53 semanas de janela de dados + ~60 freezes
  // podados; > maxUseful semanas treinadas já não cruza marco nenhum.
  for (let i = 0; i < 130 && weeks <= maxUseful; i++) {
    if (trainedWeeks.has(cursor)) {
      weeks++;
    } else if (frozenWeekMs.has(cursor)) {
      // PONTE — modo lesão/descanso: não soma, não quebra.
    } else if (isCurrent) {
      // GRACE — semana corrente sem treino é só pendente.
    } else {
      break;
    }
    isCurrent = false;
    cursor -= 7 * DAY_MS;
  }
  return weeks;
}

// ============================================================
// Escrita — create-if-absent atômico com o shape EXATO de FeedPost.toMap()
// (lib/models/feed_post.dart:365-385).
// ============================================================

function buildPostDoc({ postId, authorUid, type, payload, occurredAt, academyId, author }) {
  const doc = {
    postId,
    authorUid,
    type,
    payload,
    occurredAt: Timestamp.fromDate(occurredAt),
    createdAt: FieldValue.serverTimestamp(),
    academyId,
    hiddenByAuthor: false, // explícito no create → filtro server-side confiável
    hiddenByStaff: false,
    likeCount: 0,
    authorName: author.name,
    authorBelt: author.belt,
    authorStripes: author.stripes,
    dedupeKey: postId, // cópia redundante — auto-documenta o contrato de dedup
  };
  if (author.photoUrl != null) doc.authorPhotoUrl = author.photoUrl;
  return doc;
}

/**
 * Cria `feedPosts/{postId}` APENAS se ainda não existe. `ref.create()` é o
 * equivalente atômico (server-side) do get+set transacional do cliente
 * (FeedPostsService.emitIfAbsent): se o doc já existe — inclusive oculto por
 * hiddenByAuthor/hiddenByStaff — falha com ALREADY_EXISTS e NADA é tocado.
 * @returns {Promise<boolean>} true se criou, false se já existia
 */
async function createIfAbsent(db, postId, doc) {
  try {
    await db.collection('feedPosts').doc(postId).create(doc);
    return true;
  } catch (e) {
    if (e.code === 6 || e.code === 'already-exists') return false; // gRPC ALREADY_EXISTS
    throw e;
  }
}

// ============================================================
// Materializador principal.
// ============================================================

/**
 * Recomputa e emite (create-if-absent) os marcos de feed dirigidos por presença
 * do aluno afetado. Idempotente e barato o suficiente para rodar a cada write
 * de attendance (inclusive bulk da chamada).
 *
 * @param {object} args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {string} args.academyId
 * @param {string} args.studentId
 * @returns {Promise<{uid: string|null, emitted: string[]}>} ids emitidos nesta chamada
 */
async function materializeAttendanceMarcos({ db, academyId, studentId }) {
  const emitted = [];

  // ── 1. Aluno + gate de conta fighter ───────────────────────────────────────
  const studentSnap = await db
    .collection('academies').doc(academyId)
    .collection('students').doc(studentId)
    .get();
  if (!studentSnap.exists) return { uid: null, emitted };

  const student = studentSnap.data() || {};
  const uid = typeof student.linkedUserId === 'string' && student.linkedUserId !== ''
    ? student.linkedUserId
    : null;
  if (!uid) return { uid: null, emitted }; // sem conta fighter = sem feed

  const sport = primarySportOf(student);
  const author = authorIdentityOf(student, sport);

  const now = new Date();
  const todayUtc = spCalendarDayUtc(now);
  const currentMonday = mondayUtcOf(todayUtc);
  const closedMonday = new Date(currentMonday.getTime() - 7 * DAY_MS);

  // ── 2. Cheque frugal: 1 getAll dos ≤14 posts candidatos ───────────────────
  // (streak 5 + mat count 4 + aniversário 4 + volume da semana fechada 1).
  // Se tudo já existe, early-return sem tocar em attendance/training_logs.
  const candidateIds = [
    ...STREAK_MILESTONES.map((w) => streakId(uid, w)),
    ...MAT_MILESTONES.map((m) => matId(uid, String(m))),
    ...MAT_ANNIVERSARIES.map((y) => matId(uid, `${y}yr`)),
    volId(uid, closedMonday),
  ];
  const candidateSnaps = await db.getAll(
    ...candidateIds.map((id) => db.collection('feedPosts').doc(id)));
  const exists = new Map();
  candidateSnaps.forEach((snap, i) => exists.set(candidateIds[i], snap.exists));

  const missingStreak = STREAK_MILESTONES.filter((w) => !exists.get(streakId(uid, w)));
  const missingMatCounts = MAT_MILESTONES.filter((m) => !exists.get(matId(uid, String(m))));
  const missingAnniversaries = MAT_ANNIVERSARIES.filter((y) => !exists.get(matId(uid, `${y}yr`)));
  const volPostId = volId(uid, closedMonday);
  const volMissing = !exists.get(volPostId);

  if (!missingStreak.length && !missingMatCounts.length
      && !missingAnniversaries.length && !volMissing) {
    return { uid, emitted }; // nada a materializar — caminho quente do bulk
  }

  // ── 3. MAT MILESTONES de contagem (100/250/500/1000) ──────────────────────
  // total = mesma fórmula de Student.totalAttendanceCount:
  // (initialAttendanceCount ?? 0) + attendanceCount, com fallback count() se o
  // denorm não existe no doc. occurredAt = data da presença que cruzou o marco
  // (retention.lastAttendanceDate quando já semeado; senão agora — a CF roda
  // no write da presença, então "agora" ≈ a presença gatilho).
  if (missingMatCounts.length) {
    let attendanceCount = typeof student.attendanceCount === 'number'
      ? student.attendanceCount
      : null;
    if (attendanceCount == null) {
      const agg = await db
        .collection('academies').doc(academyId).collection('attendance')
        .where('studentId', '==', studentId)
        .count().get();
      attendanceCount = agg.data().count;
    }
    const total = (Number(student.initialAttendanceCount) || 0) + attendanceCount;
    const crossedAt = toDate(student.retention && student.retention.lastAttendanceDate) || now;

    for (const milestone of missingMatCounts) {
      if (total < milestone) continue;
      const postId = matId(uid, String(milestone));
      const created = await createIfAbsent(db, postId, buildPostDoc({
        postId,
        authorUid: uid,
        type: 'mat_milestone',
        payload: { marco: String(milestone) },
        occurredAt: crossedAt,
        academyId,
        author,
      }));
      if (created) emitted.push(postId);
    }
  }

  // ── 4. MAT MILESTONES de aniversário (1/2/3/5 anos de tatame) ─────────────
  // firstTrainingDate = startDate do aluno (mesma fonte do ShowcaseBuilder,
  // showcase_builder.dart:131); aniversário = +yr*365 dias (idem cliente).
  const startDate = toDate(student.startDate);
  if (startDate && missingAnniversaries.length) {
    for (const yr of missingAnniversaries) {
      const anniversary = new Date(startDate.getTime() + yr * 365 * DAY_MS);
      if (now.getTime() < anniversary.getTime()) continue;
      const postId = matId(uid, `${yr}yr`);
      const created = await createIfAbsent(db, postId, buildPostDoc({
        postId,
        authorUid: uid,
        type: 'mat_milestone',
        payload: { marco: `${yr}yr` },
        occurredAt: anniversary,
        academyId,
        author,
      }));
      if (created) emitted.push(postId);
    }
  }

  // ── 5. Coleta de dias treinados (só se streak ou volume precisam) ─────────
  // Streak precisa de ~53 semanas (maior milestone 52 + grace); volume só da
  // semana fechada. Uma query única com a MENOR janela necessária.
  // Boundary: dia SP `D` (UTC-midnight) cobre instantes [D+3h, D+3h+24h) UTC.
  const needStreak = missingStreak.length > 0;
  const needVol = volMissing;

  if (needStreak || needVol) {
    const windowStartDay = needStreak
      ? new Date(currentMonday.getTime() - 53 * 7 * DAY_MS)
      : closedMonday;
    const windowStartInstant = new Date(windowStartDay.getTime() + SP_UTC_OFFSET_MS);
    const windowStartTs = Timestamp.fromDate(windowStartInstant);

    // Presenças verificadas da academia (índice composto studentId+date já
    // existe em firestore.indexes.json).
    const attSnap = await db
      .collection('academies').doc(academyId).collection('attendance')
      .where('studentId', '==', studentId)
      .where('date', '>=', windowStartTs)
      .get();
    const attendance = [];
    attSnap.forEach((doc) => {
      const d = doc.data();
      const date = toDate(d.date);
      if (date) attendance.push({ day: spCalendarDayUtc(date), sport: d.sport || 'bjj' });
    });

    // Self-logs do lutador (users/{uid}/training_logs — training_log.dart:
    // `date` = midnight local, `sparringCount` = rolas do dia, `sport` legado
    // null → bjj). NUNCA alimenta ranking/graduação — só streak/volume do feed.
    const logsSnap = await db
      .collection('users').doc(uid).collection('training_logs')
      .where('date', '>=', windowStartTs)
      .get();
    const logs = [];
    logsSnap.forEach((doc) => {
      const d = doc.data();
      const date = toDate(d.date);
      if (!date) return;
      logs.push({
        day: spCalendarDayUtc(date),
        sport: d.sport || 'bjj',
        sparringCount: Number(d.sparringCount) || 0,
      });
    });

    // ── 5a. STREAK MILESTONE — esporte PRINCIPAL, dedup por dia, grace ──────
    // Emite APENAS quando o streak atual é EXATAMENTE um milestone ainda não
    // emitido (semântica do cliente: streakMilestones.contains(currentWeeks)).
    // Como rodamos a cada presença e o streak só avança 1 semana por vez, o
    // cruzamento exato é observado de forma confiável.
    if (needStreak) {
      const streakDayKeys = new Set();
      let latestStreakDay = null;
      for (const a of attendance) {
        if (a.sport !== sport) continue;
        streakDayKeys.add(a.day.getTime());
        if (!latestStreakDay || a.day > latestStreakDay) latestStreakDay = a.day;
      }
      for (const l of logs) {
        if (l.sport !== sport) continue;
        streakDayKeys.add(l.day.getTime());
        if (!latestStreakDay || l.day > latestStreakDay) latestStreakDay = l.day;
      }

      // MODO LESÃO/DESCANSO — users/{uid}.streakFreezes ('YYYY-Www' → motivo,
      // escrito pelo próprio aluno via StreakFreezeService): semana congelada
      // vira PONTE, a MESMA semântica de weekly_streak.dart(frozenWeeks:).
      // 1 read enxuto (fieldMask), só quando algum marco de streak falta.
      // Fail-open (set vazio): erro transitório degrada p/ semântica antiga.
      const frozenWeekMs = new Set();
      try {
        const [freezeSnap] = await db.getAll(
          db.collection('users').doc(uid), { fieldMask: ['streakFreezes'] });
        const raw = freezeSnap.exists ? (freezeSnap.data() || {}).streakFreezes : null;
        if (raw && typeof raw === 'object') {
          for (const k of Object.keys(raw)) {
            const ms = mondayUtcMsOfIsoKey(k);
            if (ms !== null) frozenWeekMs.add(ms);
          }
        }
      } catch (e) {
        console.warn(`[feed] leitura de streakFreezes falhou uid=${uid}:`, e.message);
      }

      const currentWeeks =
        computeCurrentStreakWeeks(streakDayKeys, todayUtc, frozenWeekMs);
      if (missingStreak.includes(currentWeeks)) {
        const postId = streakId(uid, currentWeeks);
        // occurredAt = a presença/treino mais recente do run (o dia que cruzou).
        const created = await createIfAbsent(db, postId, buildPostDoc({
          postId,
          authorUid: uid,
          type: 'streak_milestone',
          payload: { weeks: currentWeeks },
          occurredAt: latestStreakDay || now,
          academyId,
          author,
        }));
        if (created) emitted.push(postId);
      }
    }

    // ── 5b. WEEKLY VOLUME — última semana ISO FECHADA, TODOS os esportes ────
    // trainings = dias distintos (attendance ∪ logs) na semana fechada;
    // rolas = soma de sparringCount dos logs da semana (idem cliente).
    if (needVol) {
      const closedEnd = closedMonday.getTime() + 7 * DAY_MS;
      const inClosedWeek = (day) =>
        day.getTime() >= closedMonday.getTime() && day.getTime() < closedEnd;

      const weekDayKeys = new Set();
      for (const a of attendance) {
        if (inClosedWeek(a.day)) weekDayKeys.add(a.day.getTime());
      }
      let weekRolas = 0;
      for (const l of logs) {
        if (!inClosedWeek(l.day)) continue;
        weekDayKeys.add(l.day.getTime());
        weekRolas += l.sparringCount;
      }

      if (weekDayKeys.size > 0) {
        const created = await createIfAbsent(db, volPostId, buildPostDoc({
          postId: volPostId,
          authorUid: uid,
          type: 'weekly_volume',
          payload: { trainings: weekDayKeys.size, rolas: weekRolas },
          // occurredAt = domingo da semana fechada (idem cliente).
          occurredAt: new Date(closedMonday.getTime() + 6 * DAY_MS),
          academyId,
          author,
        }));
        if (created) emitted.push(volPostId);
      }
    }
  }

  return { uid, emitted };
}

module.exports = { materializeAttendanceMarcos };
