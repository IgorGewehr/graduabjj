/**
 * access_control/ingest.js — NÚCLEO da ingestão de acesso (Arquitetura C)
 * ============================================================================
 *
 * GREENFIELD / ADITIVO — NÃO está wired a nada live e NÃO foi deployado.
 * Exporta UMA Cloud Function HTTPS nova (`ingestAccessEvent`, generalizada p/ 3
 * fabricantes) sem tocar nenhum fluxo existente. Deve passar em `node --check`.
 *
 * O que este arquivo (o NÚCLEO) faz, e SÓ ele:
 *   1. Resolve (academyId, deviceId) da query e carrega
 *      academies/{academyId}/devices/{deviceId} (segredo NUNCA sai do server).
 *   2. SEGURANÇA fail-closed na ordem do spec §4: método/identidade → device
 *      enabled → IP allowlist → rate-limit → auth do corpo (HMAC timing-safe OU
 *      token fraco no path/query, igual padrão mercadoPagoMarketplaceWebhook).
 *   3. Faz DISPATCH p/ o adapter do vendor via REGISTRY ESTÁTICO
 *      ({controlid,zkteco,intelbras} -> require('./adapters/<vendor>')). NUNCA
 *      require(input) — o vendor vem do doc do device, mas só indexa o mapa.
 *   4. Para cada AccessEvent canônico devolvido pelo adapter:
 *        - IDEMPOTÊNCIA estrita por accessEvents/{deviceId}_{eventId} via
 *          .create() dentro de transação (re-entrega = no-op, não duplica).
 *        - Resolve externalUserId -> studentId via device.userMap.
 *        - Grava presença IDEMPOTENTE (check-in SINTÉTICO de catraca, doc-id
 *          determinístico por dia), espelhando grantPrivateLessonAttendance /
 *          attendance_service.dart. PRESERVA occurredAt ORIGINAL (nunca now()).
 *   5. Responde 200 rápido. CONTRATO DE RESPOSTA por fabricante:
 *        - zkteco    : text/plain "OK"  (JSON => device re-entrega o lote)
 *        - intelbras : JSON {message, code:'200', auth:'true'|'false'} (síncrono)
 *        - controlid : 200 simples (push fire-and-forget)
 *
 * O wire format de cada device vive SÓ nos adapters (contrato em canonical.js).
 * ============================================================================
 */

'use strict';

const crypto = require('crypto');
const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { resolveActiveClass } = require('./class_resolver');
const { checkOverdueGate } = require('./financial_gate');

// Reaproveita o app default já inicializado pelo index.js (initializeApp()).
// Se este módulo um dia for o entrypoint, init defensivo abaixo evita crash.
if (!admin.apps || admin.apps.length === 0) {
  try { admin.initializeApp(); } catch (_) { /* já inicializado em outro path */ }
}
const db = admin.firestore();

// SECURITY (auditoria C1 — path injection): qualquer identificador que vira
// SEGMENTO de path no Firestore precisa de charset estrito. db.doc() NAO
// normaliza '/' nem '..', entao um id como 'a/b/c' ou '../../x' cria/le um
// documento em caminho ARBITRARIO (ex.: roubar o read do device pre-auth, ou
// burlar o ledger de idempotencia / gravar presenca em path inesperado).
const SAFE_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const isSafeSegment = (s) => typeof s === 'string' && SAFE_ID_RE.test(s);
const sanitizeSegment = (s) =>
  String(s == null ? '' : s).replace(/[^A-Za-z0-9_-]/g, '').slice(0, 128);

// ---------------------------------------------------------------------------
// REGISTRY ESTÁTICO de adapters. Mapa fixo (NUNCA require(input)). O vendor vem
// do doc do device e só INDEXA este mapa; vendor desconhecido => null => 400.
//
// ASSUMPTION/TODO: os 3 arquivos ./adapters/<vendor>.js serão implementados
// pelos agentes seguintes (contrato: parse(req, device) -> AccessEvent[]|null,
// ver canonical.js). Os require ficam dentro de getAdapter() com try/catch p/
// este NÚCLEO passar em `node --check` e carregar mesmo antes dos adapters
// existirem (greenfield). Quando um adapter faltar, o evento daquele vendor é
// rejeitado com 'adapter-missing' — sem quebrar os demais.
// ---------------------------------------------------------------------------
const ADAPTER_LOADERS = Object.freeze({
  controlid: () => require('./adapters/controlid'),
  zkteco: () => require('./adapters/zkteco'),
  intelbras: () => require('./adapters/intelbras'),
});

const _adapterCache = {};
/** Carrega (cache) o adapter do vendor a partir do REGISTRY estático. */
function getAdapter(vendor) {
  const key = String(vendor || '').toLowerCase();
  if (!Object.prototype.hasOwnProperty.call(ADAPTER_LOADERS, key)) return null;
  if (_adapterCache[key] !== undefined) return _adapterCache[key];
  try {
    const mod = ADAPTER_LOADERS[key]();
    // Contrato: o adapter exporta `parse(req, device)` (ou { parse }).
    const parse = typeof mod === 'function' ? mod
      : (mod && typeof mod.parse === 'function' ? mod.parse : null);
    _adapterCache[key] = parse || null;
  } catch (e) {
    // Adapter ainda não implementado (greenfield) ou erro de require → null.
    console.warn('[ingestAccessEvent] adapter load failed', key, e && e.message);
    _adapterCache[key] = null;
  }
  return _adapterCache[key];
}

// ---------------------------------------------------------------------------
// Tunables (espelham intelbras_access / turnstile_ingest)
// ---------------------------------------------------------------------------
const REPLAY_WINDOW_MS = 5 * 60 * 1000;   // janela anti-replay (= MP webhook)
const RATE_LIMIT_WINDOW_MS = 10 * 1000;   // janela do rate-limit naive
const RATE_LIMIT_MAX = 60;                // eventos/janela/device (catraca real
                                          //   emite poucos/s; lote re-entregue
                                          //   é absorvido pela idempotência)

// ---------------------------------------------------------------------------
// SEGURANÇA — timing-safe + anti-replay (padrão mercadoPagoMarketplaceWebhook)
// ---------------------------------------------------------------------------

/** Comparação timing-safe sobre buffers de IGUAL comprimento (sem leak). */
function safeEqual(a, b) {
  const ba = Buffer.from(String(a == null ? '' : a), 'utf8');
  const bb = Buffer.from(String(b == null ? '' : b), 'utf8');
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

/**
 * Valida a auth do corpo, dois caminhos (fail-closed):
 *   FORTE (preferido): x-device-signature = HMAC-SHA256(secret, `${ts}.${rawBody}`)
 *     + x-device-timestamp (epoch ms), anti-replay 5 min, timing-safe.
 *   FRACO (firmware stock): token compartilhado no path/query
 *     (?k= Control iD / pushcommkey ZKTeco / token no path Intelbras),
 *     comparado timing-safe contra device.secret. Só aceitável atrás de HTTPS.
 * Sem device.secret => 401 (igual ao MP webhook sem secret configurado).
 *
 * @returns {{ok:boolean, mode?:string, reason?:string}}
 */
function verifyDeviceAuth({ device, headers, rawBody, query, nowMs }) {
  const secret = device && device.secret;
  if (!secret) return { ok: false, reason: 'no-secret' }; // fail closed

  const sig = String(headers['x-device-signature'] || '').replace(/^sha256=/i, '');
  const ts = String(headers['x-device-timestamp'] || '');

  // --- FORTE: HMAC sobre `${ts}.${rawBody}` ---
  if (sig && ts) {
    const tsNum = Number(ts);
    if (!Number.isFinite(tsNum) || Math.abs(nowMs - tsNum) > REPLAY_WINDOW_MS) {
      return { ok: false, reason: 'stale-timestamp' };
    }
    const expected = crypto.createHmac('sha256', secret)
      .update(`${ts}.${rawBody}`).digest('hex');
    if (!safeEqual(sig, expected)) return { ok: false, reason: 'bad-signature' };
    return { ok: true, mode: 'hmac' };
  }

  // --- FRACO: token compartilhado no path/query (firmware stock) ---
  // Aceita ?k= (Control iD), pushcommkey/key (ZKTeco) ou header x-device-token.
  const token = String(
    query.k || query.pushcommkey || query.key ||
    headers['x-device-token'] || '');
  if (token && safeEqual(token, secret)) {
    return { ok: true, mode: 'shared-token' };
  }
  return { ok: false, reason: 'no-credentials' };
}

/** IP allowlist opcional: device.ipAllowlist (array). Vazio/ausente = sem filtro. */
function ipAllowed(device, ip) {
  const list = Array.isArray(device.ipAllowlist) ? device.ipAllowlist : [];
  if (list.length === 0) return true;
  return list.includes(String(ip || ''));
}

/**
 * Rate-limit naive por device (janela em deviceRateLimits/{deviceId}).
 * Fail-OPEN em erro de infra: nunca prende um aluno no portão por isso.
 * @returns {Promise<boolean>} true = permitido.
 */
async function checkRateLimit(academyId, deviceId, nowMs) {
  const ref = db.doc(`academies/${academyId}/deviceRateLimits/${deviceId}`);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const d = snap.exists ? snap.data() : {};
      const windowStart = Number(d.windowStart) || 0;
      if (nowMs - windowStart > RATE_LIMIT_WINDOW_MS) {
        tx.set(ref, { windowStart: nowMs, count: 1 });
        return true;
      }
      const count = (Number(d.count) || 0) + 1;
      tx.set(ref, { windowStart, count }, { merge: true });
      return count <= RATE_LIMIT_MAX;
    });
  } catch (_) {
    return true; // fail-open
  }
}

// ---------------------------------------------------------------------------
// Idempotência + gravação de presença (espelha grantPrivateLessonAttendance e
// attendance_service.dart). Check-in SINTÉTICO de catraca: doc-id determinístico
// POR DIA -> no máximo 1 presença/aluno/device/dia, idempotente por construção.
// ---------------------------------------------------------------------------

/**
 * YYYYMMDD em wall-clock BR (process.env.TZ pinado em America/Sao_Paulo no
 * index.js). Usado por AMBOS os caminhos (turma real e sintético) para que o
 * "dia" do doc-id de idempotência alinhe com o calendário da academia e com a
 * decisão de turma ativa (que é wall-clock BR em class_resolver/class_service).
 * Antes era getUTC* (latente bug perto da meia-noite / offset -3h BR).
 */
function ymdBR(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}${m}${day}`;
}

/**
 * Resolve studentId a partir do externalUserId via device.userMap (fonte da
 * verdade no caminho crítico — lida junto com o device, uma só leitura).
 * ASSUMPTION: userMap inline; alternativa de escala = subcoleção users/.
 */
function resolveStudentId(device, externalUserId) {
  const map = (device && device.userMap) || {};
  const id = String(externalUserId == null ? '' : externalUserId);
  if (!id || id === '0') return null; // '0'/vazio = não identificado
  return map[id] || null;
}

/**
 * Grava (exactly-once) UM AccessEvent canônico.
 *  - Dedupe duro por accessEvents/{deviceId}_{eventId} via .create() em transação
 *    (re-entrega do device = no-op atômico; create() falha se já existe).
 *  - !granted        -> só auditoria (outcome:'denied'), sem presença.
 *  - sem studentId   -> auditoria (outcome:'no_match'), sem presença.
 *  - direction 'out' -> auditoria (outcome:'out_ignored'), sem presença.
 *  - caso novo no dia-> presença determinística + increment(attendanceCount).
 *  - PRESERVA occurredAt ORIGINAL em date/occurredAt (nunca now()).
 *
 * @param {import('./canonical').AccessEvent} ev
 * @param {object} device  doc do device (p/ name/userMap/sport/category)
 * @param {Array<object>} [classesCache]  classes ativas JÁ lidas (id+data), p/
 *   resolver a turma real. Ausente/vazio => fallback sintético.
 * @param {object} [accessControlCfg]  academies/{id}.accessControl (gate
 *   financeiro). Ausente/off => nunca bloqueia (default OFF, fail-open).
 * @returns {Promise<{outcome:string, attendanceId?:string|null, displayMsg?:string}>}
 */
async function recordAccessEvent(academyId, ev, device, classesCache, accessControlCfg) {
  // SECURITY (C1): eventId/deviceId chegam (via adapter) de campos do CORPO do
  // device e compõem doc-ids (ledger de idempotência + presença). Sanitiza para
  // não injetar segmentos de path. Sem id estável não há idempotência → aborta.
  const safeDeviceId = sanitizeSegment(ev.deviceId);
  const safeEventId = sanitizeSegment(ev.eventId);
  if (!safeDeviceId || !safeEventId) return { outcome: 'bad_id' };
  const eventDocId = `${safeDeviceId}_${safeEventId}`;
  const eventRef = db.doc(`academies/${academyId}/accessEvents/${eventDocId}`);
  const occurredAt = ev.occurredAt instanceof Date ? ev.occurredAt : new Date(NaN);
  if (isNaN(occurredAt.getTime())) {
    // Sem timestamp ORIGINAL válido não gravamos presença (não usar now()).
    // Ainda registramos o evento p/ auditoria, marcando o problema.
  }

  let studentId = resolveStudentId(device, ev.externalUserId);
  // Defensivo (C1): studentId vem do device.userMap (staff), mas se vier sujo
  // não pode injetar path no doc da presença/aluno.
  if (studentId && !isSafeSegment(studentId)) studentId = null;

  // Decide o outcome (sem efeito colateral) p/ a parte de auditoria.
  let plannedOutcome;
  if (!ev.granted) plannedOutcome = 'denied';
  else if (isNaN(occurredAt.getTime())) plannedOutcome = 'bad_time';
  else if (!studentId) plannedOutcome = 'no_match';
  else if (ev.direction === 'out') plannedOutcome = 'out_ignored';
  else plannedOutcome = 'attendance_granted'; // pode virar 'duplicate' na tx

  // ===========================================================================
  // PRÉ-TRANSAÇÃO: gate financeiro + resolução de turma (LEITURAS já feitas no
  // handler — classesCache; financials lido aqui via helper FAIL-OPEN). Tudo
  // FORA de runTransaction p/ não inflar o read-set nem regredir a barreira de
  // idempotência (tx.create(eventRef) continua a única barreira atômica).
  // ===========================================================================
  // Defaults sintéticos (fallback exato do comportamento atual).
  let classId = `catraca_${safeDeviceId}`;
  let className = 'Acesso por Catraca';
  let sport = 'bjj'; // ASSUMPTION: porta genérica não sabe a modalidade.
  let weight = 1;
  let matchVia = 'synthetic';
  let denyMsg = null;

  if (plannedOutcome === 'attendance_granted') {
    // (a) GATE FINANCEIRO — FAIL-OPEN dentro do helper (erro/off => liberado).
    //     `now` = occurredAt (coerente com a presença que preserva o original).
    const gate = await checkOverdueGate(academyId, studentId, occurredAt, accessControlCfg);
    if (gate && gate.blocked) {
      plannedOutcome = 'denied_overdue'; // novo ramo: SEM presença, NÃO libera.
      denyMsg = 'Financeiro pendente - procure a recepcao';
    } else {
      // (b) RESOLUÇÃO DE TURMA — turma ativa real OU fallback sintético (null).
      //     SECURITY (C1): o classId real é revalidado por isSafeSegment dentro
      //     do resolver antes de retornar (não regride C1).
      const m = resolveActiveClass(classesCache, studentId, occurredAt, device);
      if (m) {
        classId = m.classId;
        className = m.className;
        sport = m.sport;
        weight = (typeof m.weight === 'number' && Number.isFinite(m.weight)) ? m.weight : 1;
        matchVia = 'schedule';
      }
      // else: mantém os defaults sintéticos acima (contrato aditivo preservado).
    }
  }

  // Defensivo (C1): classId resolvido (real ou sintético) vira SEGMENTO de path
  // no doc-id da presença. Sintético já é seguro; o real passou pelo resolver,
  // mas revalidamos aqui antes de compor o doc-id (não regride C1).
  if (!isSafeSegment(classId)) {
    classId = `catraca_${safeDeviceId}`;
    className = 'Acesso por Catraca';
    sport = 'bjj';
    weight = 1;
    matchVia = 'synthetic';
  }

  // Doc-id determinístico POR TURMA/DIA (studentId_classId_YYYYMMDD em BR).
  // TODO (granularidade de presença): 1 presença por turma/dia. Confirmar com a
  // academia se essa é a semântica desejada (vs. por entrada/giro).
  const willGrant = (plannedOutcome === 'attendance_granted');
  const dayId = (studentId && willGrant && !isNaN(occurredAt.getTime()))
    ? `${studentId}_${classId}_${ymdBR(occurredAt)}`
    : null;
  const attendanceRef = dayId
    ? db.doc(`academies/${academyId}/attendance/${dayId}`) : null;
  const studentRef = studentId
    ? db.doc(`academies/${academyId}/students/${studentId}`) : null;

  const deviceName = (device && device.name) || ev.deviceId;
  const tsOriginal = isNaN(occurredAt.getTime())
    ? null : admin.firestore.Timestamp.fromDate(occurredAt);

  return db.runTransaction(async (tx) => {
    // (1) Dedupe duro: lê o ledger PRIMEIRO. create() abaixo é a barreira atômica.
    const evSnap = await tx.get(eventRef);
    if (evSnap.exists) return { outcome: 'duplicate' };

    // (2) Se vai conceder, checa a presença determinística do dia.
    let attExists = false;
    if (plannedOutcome === 'attendance_granted' && attendanceRef) {
      const attSnap = await tx.get(attendanceRef);
      attExists = attSnap.exists;
    }

    const outcome = (plannedOutcome === 'attendance_granted' && attExists)
      ? 'duplicate_day' : plannedOutcome;
    const willCountNew = plannedOutcome === 'attendance_granted' && !attExists;

    // (3) Registra SEMPRE o accessEvent (auditoria + lock de idempotência).
    //     .create() falha se o doc já existe → segunda barreira contra corrida.
    //     'denied_overdue' TAMBÉM grava (auditoria + lock) → re-entrega = no-op.
    tx.create(eventRef, {
      eventId: ev.eventId,
      deviceId: ev.deviceId,
      vendor: ev.vendor,
      externalUserId: ev.externalUserId == null ? null : String(ev.externalUserId),
      studentId: studentId || null,
      occurredAt: tsOriginal, // ORIGINAL (pode ser null se time inválido)
      direction: ev.direction || 'unknown',
      method: ev.method || 'unknown',
      granted: !!ev.granted,
      eventCode: ev.eventCode == null ? null : ev.eventCode,
      attendanceId: willCountNew ? dayId : null,
      // Auditoria de reconciliação: turma resolvida e via (schedule|synthetic).
      // Em denied_overdue não houve resolução de turma → resolvedClassId null.
      resolvedClassId: willCountNew ? classId : null,
      matchVia: willCountNew ? matchVia : null,
      outcome,
      raw: ev.raw || {},
      receivedAt: admin.firestore.FieldValue.serverTimestamp(), // só metadado
    });

    // denied_overdue OU qualquer não-concessão: NÃO grava presença, NÃO incrementa.
    if (!willCountNew) {
      return {
        outcome,
        attendanceId: attExists ? dayId : null,
        displayMsg: denyMsg, // mensagem de bloqueio (null p/ os demais outcomes)
      };
    }

    // (4) Presença nova do dia — shape espelha grantPrivateLessonAttendance /
    //     markPresent. classId/className/sport REAIS quando matchVia=schedule;
    //     sintéticos no fallback. weight só persiste quando != 1 (markPresent).
    const att = {
      studentId,
      studentName: (device.userNames && device.userNames[String(ev.externalUserId)]) || null,
      classId,
      className,
      date: tsOriginal,
      verifiedBy: 'system:catraca',
      verifiedByName: `Catraca ${deviceName}`,
      notes: `Acesso por catraca — evento ${ev.eventId}`,
      sport,
      source: `catraca:${ev.vendor}`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (typeof weight === 'number' && weight !== 1) att.weight = weight;
    tx.set(attendanceRef, att);
    if (studentRef) {
      tx.update(studentRef, {
        attendanceCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return { outcome: 'attendance_granted', attendanceId: dayId };
  });
}

// ---------------------------------------------------------------------------
// CONTRATO DE RESPOSTA por fabricante (crítico p/ NÃO causar re-entrega).
// ---------------------------------------------------------------------------
// Resposta do modo ONLINE/Pro da Control iD: o device espera, no MESMO POST, o
// veredito + a AÇÃO física (abrir porta / liberar giro da catraca). Formato:
//   { "result": { "event": 7, "user_id": N, "actions": [ ... ] } }
// TODO/FIELD-CONFIRM: os códigos de `event` e o formato de `actions`/`parameters`
// variam por firmware (iDFace / iDBlock). Confirmar no piloto com sniffer. Tudo
// é configurável pelo doc do device (controlidAction/catraSense/portalDoor).
function controlidOnlineResult(device, { granted, message, externalUserId }) {
  const dev = device || {};
  const action = String(dev.controlidAction || 'door').toLowerCase();
  const actions = [];
  if (granted) {
    if (action === 'catra') {
      const sense = String(dev.catraSense || 'clockwise');
      actions.push({ action: 'catra', parameters: `allow=${sense}` });
    } else {
      const door = Number(dev.portalDoor) > 0 ? Number(dev.portalDoor) : 1;
      actions.push({ action: 'door', parameters: `door=${door}` });
    }
  }
  const uid = Number(externalUserId);
  return {
    result: {
      event: granted ? 7 : 6, // 7 = concedido; 6/sem action = negado.
      user_id: Number.isFinite(uid) ? uid : 0,
      actions,
      ...(message ? { message } : {}),
    },
  };
}

function respond(res, vendor, { granted, message, online, device, externalUserId }) {
  // Control iD em modo ONLINE: resposta síncrona grant/deny + ação física.
  if (vendor === 'controlid' && online) {
    return res.status(200).json(
      controlidOnlineResult(device, { granted, message, externalUserId }));
  }
  switch (vendor) {
    case 'zkteco':
      // DEVE ser text/plain "OK" — JSON faz o device achar que falhou e
      // re-entregar o lote inteiro.
      return res.status(200).set('Content-Type', 'text/plain').send('OK');
    case 'intelbras':
      // Síncrono: device bloqueia esperando veredito. auth é STRING, code '200'.
      return res.status(200).json({
        message: message || (granted ? 'Bem-vindo' : 'Acesso negado'),
        code: '200',
        auth: granted ? 'true' : 'false',
      });
    case 'controlid':
    default:
      // Push fire-and-forget: corpo irrelevante, 200 basta.
      return res.status(200).set('Content-Type', 'text/plain').send('OK');
  }
}

// ---------------------------------------------------------------------------
// THE PUBLIC ENDPOINT — ingestAccessEvent (generalizado p/ 3 fabricantes)
// ---------------------------------------------------------------------------
const ingestAccessEvent = onRequest(
  { region: 'us-central1', cors: false, maxInstances: 10, timeoutSeconds: 15 },
  async (req, res) => {
    const nowMs = Date.now();
    // vendor pode ser desconhecido até carregar o device; default zkteco-ish
    // text/plain p/ não quebrar re-entrega antes de sabermos.
    let vendor = String(req.query.vendor || '').toLowerCase();
    // Modo ONLINE/Pro da Control iD (resposta síncrona grant/deny). Declarados no
    // escopo externo para o catch fatal também responder no formato certo.
    let controlidOnline = false;
    let deviceForResp = null;
    try {
      // §4.1 — método. GET = handshake/heartbeat: responde 200 e sai (não parseia).
      if (req.method !== 'POST') {
        if (req.method === 'GET') {
          return res.status(200).set('Content-Type', 'text/plain').send('OK');
        }
        return res.status(405).send('Method Not Allowed');
      }

      // §4.2 — resolve academyId + deviceId (device não conhece multi-tenant).
      const academyId = String(req.query.acad || req.query.academyId || '');
      const sn = String(req.query.SN || req.query.sn || '');
      const deviceId = String(req.query.deviceId || sn || '');
      if (!academyId || !deviceId) return res.status(400).send('missing acad/deviceId');
      // SECURITY (C1): valida ANTES do read do device (que é pré-auth) — bloqueia
      // injeção de segmentos de path via academyId/deviceId vindos da query.
      if (!isSafeSegment(academyId) || !isSafeSegment(deviceId)) {
        return res.status(400).send('bad id');
      }

      // Corpo CRU (iclock/multipart não são JSON). functions v2 popula req.rawBody.
      const rawBody = (req.rawBody && req.rawBody.toString('utf8')) ||
        (typeof req.body === 'string' ? req.body : '') || '';

      // §4.3 — carrega o device. Inexistente OU disabled => 403 sem revelar.
      const devSnap = await db.doc(`academies/${academyId}/devices/${deviceId}`).get();
      if (!devSnap.exists) return res.status(403).send('forbidden');
      const device = devSnap.data() || {};
      if (device.enabled === false) return res.status(403).send('forbidden');
      vendor = String(device.vendor || vendor || '').toLowerCase();
      deviceForResp = device;
      // Online/Pro: o device chama .../new_user_identified.fcgi esperando o
      // veredito+ação na resposta. (No Monitor o path é /dao|/catra_event.)
      controlidOnline = vendor === 'controlid' &&
        /(^|\/)new_(user|card)_identified(\.fcgi)?$/
          .test(String(req.path || '').toLowerCase());

      // §4.4 — IP allowlist opcional.
      const clientIp = (req.headers['x-forwarded-for'] || '')
        .toString().split(',')[0].trim() || req.ip || '';
      if (!ipAllowed(device, clientIp)) return res.status(403).send('forbidden');

      // §4.5 — rate-limit naive por device.
      if (!(await checkRateLimit(academyId, deviceId, nowMs))) {
        return respond(res, vendor, {
          granted: false, message: 'Tente novamente',
          online: controlidOnline, device,
        });
      }

      // §4.6 — auth do corpo (HMAC timing-safe OU token fraco). Fail closed.
      const auth = verifyDeviceAuth({
        device, headers: req.headers, rawBody, query: req.query, nowMs,
      });
      if (!auth.ok) {
        console.warn('[ingestAccessEvent] auth fail', { deviceId, reason: auth.reason });
        return res.status(401).send('unauthorized');
      }

      // DISPATCH p/ o adapter do vendor via REGISTRY estático.
      const parse = getAdapter(vendor);
      if (!parse) {
        console.warn('[ingestAccessEvent] no adapter', { vendor, deviceId });
        // Vendor desconhecido / adapter não implementado: ACK p/ não re-entregar.
        return respond(res, vendor, {
          granted: false, message: 'Indisponivel',
          online: controlidOnline, device,
        });
      }

      const adapterReq = {
        rawBody,
        query: req.query || {},
        headers: req.headers || {},
        method: req.method,
        path: req.path || '',
      };

      let events;
      try {
        events = parse(adapterReq, { ...device, vendor, deviceId });
      } catch (e) {
        console.error('[ingestAccessEvent] adapter threw', vendor, e && e.message);
        events = null;
      }

      // null = payload irreconhecível; [] = heartbeat/sem eventos. Ambos => ACK.
      // No Online, "sem evento" = ninguém reconhecido => NEGA (não abre).
      if (!Array.isArray(events) || events.length === 0) {
        return respond(res, vendor, {
          granted: !controlidOnline,
          message: controlidOnline ? 'Nao reconhecido' : 'OK',
          online: controlidOnline, device,
        });
      }

      // LEITURAS pré-transação, UMA vez por POST (fora de runTransaction):
      //  (a) classes ATIVAS da academia → resolução de turma real (passadas por
      //      parâmetro ao recordAccessEvent; nunca lidas dentro da tx).
      //  (b) academies/{id}.accessControl → gate de inadimplência (default OFF).
      // Ambas FAIL-OPEN: erro de leitura cai p/ fallback sintético / gate off.
      let classesCache = [];
      let accessControlCfg = null;
      try {
        const clsSnap = await db.collection(`academies/${academyId}/classes`)
          .where('isActive', '==', true).get();
        classesCache = clsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
      } catch (e) {
        console.warn('[ingestAccessEvent] classes read failed', e && e.message);
        classesCache = []; // fallback sintético (contrato atual preservado).
      }
      try {
        const acadSnap = await db.doc(`academies/${academyId}`).get();
        const acad = acadSnap.exists ? (acadSnap.data() || {}) : {};
        accessControlCfg = acad.accessControl || null;
      } catch (e) {
        console.warn('[ingestAccessEvent] academy cfg read failed', e && e.message);
        accessControlCfg = null; // gate OFF (fail-open).
      }

      // Processa cada AccessEvent idempotentemente. Veredito (Intelbras síncrono)
      // = OR dos grants; mensagem do último concedido. Mensagem de NEGAÇÃO por
      // inadimplência tem prioridade quando anyGranted permanece false. Política
      // fail-open do giro: liberar mesmo se a gravação falhar; negar p/ não-mapeado
      // e p/ inadimplente (denied_overdue).
      let anyGranted = false;
      let displayMsg = null;
      let denyMsg = null; // mensagem de bloqueio (só vale se nada for concedido).
      // Auditoria M1: para o vendor SÍNCRONO (intelbras), a resposta GATEIA o giro
      // físico — 1 POST = 1 pessoa. Se um lote anômalo trouxer >1 evento, o veredito
      // do giro deve refletir SÓ o 1º (a pessoa sendo decidida), nunca ser "salvo"
      // por outro aluno do lote (um inadimplente não pode passar de carona). Os
      // demais eventos AINDA são gravados (auditoria/idempotência). Para vendors de
      // LOTE (zkteco/controlid) a resposta é ACK fire-and-forget (não gateia o giro
      // físico, decidido embarcado), então todos contam no agregado.
      // Online também é síncrono/1-pessoa (a resposta gateia o giro): veredito só
      // do 1º evento, como o Intelbras.
      const verdictFromFirstOnly = vendor === 'intelbras' || controlidOnline;
      let idx = -1;
      for (const ev of events) {
        idx++;
        const countsForVerdict = !verdictFromFirstOnly || idx === 0;
        // Garante deviceId/vendor canônicos vindos do contexto seguro do núcleo.
        const canonical = { ...ev, deviceId, vendor };
        let result;
        try {
          result = await recordAccessEvent(
            academyId, canonical, device, classesCache, accessControlCfg);
        } catch (e) {
          // Erro de infra ao gravar: NÃO prende o aluno. Para Intelbras síncrono
          // liberamos o giro se o usuário foi reconhecido/concedido pelo device.
          // TODO (fail-open vs. inadimplente): um aluno bloqueado por inadimplência
          // que sofra erro de INFRA aqui cairia liberado. O gate é fail-open por
          // design (checkOverdueGate nunca throwa), mas confirmar com a academia
          // se erro de infra deve liberar mesmo um inadimplente confirmado.
          console.error('[ingestAccessEvent] record error', e && e.message);
          if (countsForVerdict && canonical.granted &&
              resolveStudentId(device, canonical.externalUserId)) {
            anyGranted = true;
          }
          continue;
        }
        if (result.outcome === 'attendance_granted' ||
            result.outcome === 'duplicate' ||
            result.outcome === 'duplicate_day') {
          if (countsForVerdict) {
            anyGranted = true;
            if (result.outcome === 'attendance_granted') displayMsg = 'Presenca registrada';
            else if (!displayMsg) displayMsg = 'Bem-vindo';
          }
        } else if (result.outcome === 'denied_overdue') {
          // NÃO entra em anyGranted → giro NÃO libera. Carrega a mensagem de
          // bloqueio p/ exibir SE nenhum outro evento conceder.
          if (countsForVerdict && !denyMsg) {
            denyMsg = result.displayMsg || 'Financeiro pendente - procure a recepcao';
          }
        }
      }

      // Mensagem final: concedido usa displayMsg; negado por inadimplência usa
      // denyMsg (só quando anyGranted é false).
      const finalMsg = anyGranted ? displayMsg : (denyMsg || displayMsg);

      console.log('[ingestAccessEvent]', {
        academyId, deviceId, vendor, count: events.length, anyGranted,
        denied: !anyGranted && !!denyMsg ? 'overdue' : undefined,
      });
      // externalUserId da pessoa decidida (1º evento no modo síncrono/online) —
      // ecoado de volta na resposta Online p/ o device casar com quem passou.
      const decidedUserId = events[0] && events[0].externalUserId;
      return respond(res, vendor, {
        granted: anyGranted, message: finalMsg,
        online: controlidOnline, device, externalUserId: decidedUserId,
      });
    } catch (e) {
      console.error('[ingestAccessEvent] fatal', e && e.message);
      // 500 faz ZKTeco re-entregar (idempotência cobre); p/ Intelbras síncrono
      // respondemos veredito negativo 200 p/ não pendurar o device.
      if (vendor === 'intelbras') {
        return respond(res, 'intelbras', { granted: false, message: 'Erro interno' });
      }
      // Control iD Online: nega com 200 (não pendura a catraca esperando resposta).
      if (controlidOnline) {
        return respond(res, 'controlid', {
          granted: false, message: 'Erro interno',
          online: true, device: deviceForResp,
        });
      }
      return res.status(500).send('error');
    }
  },
);

module.exports = {
  ingestAccessEvent,
  // exportados p/ teste / wiring:
  verifyDeviceAuth,
  resolveStudentId,
  recordAccessEvent,
  getAdapter,
  ADAPTER_LOADERS,
};
