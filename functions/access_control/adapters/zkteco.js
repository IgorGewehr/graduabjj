/**
 * access_control/adapters/zkteco.js — ADAPTER ZKTeco (Push/ADMS "iclock")
 * ============================================================================
 *
 * Módulo PURO (sem firebase-admin, sem I/O). Implementa o contrato do adapter
 * definido em ../canonical.js:
 *
 *     parse(req, device) -> AccessEvent[] | null
 *
 * Converte o payload de ACESSO da ZKTeco (protocolo PUSH/ADMS, paths "iclock")
 * no AccessEvent canônico. O adapter NÃO resolve studentId (o núcleo faz via
 * device.userMap[externalUserId]), NÃO grava no Firestore, NÃO valida HMAC e NÃO
 * escreve a resposta HTTP (o ACK "OK" text/plain é do núcleo).
 *
 * ----------------------------------------------------------------------------
 * PROTOCOLO ZKTeco PUSH (resumo — confirmado via docs do vendor):
 *
 *  O device INICIA a conexão de saída (não precisa de IP público). Ele POSTa:
 *    POST /iclock/cdata?SN=<sn>&table=rtlog   → CONTROLE DE ACESSO (catraca/porta),
 *                                               key=value separado por TAB. NOSSO CASO.
 *    POST /iclock/cdata?SN=<sn>&table=ATTLOG  → terminal de PONTO, TAB posicional.
 *  Um POST pode conter N eventos (uma linha por evento) → retornamos AccessEvent[].
 *
 *  PAYLOAD rtlog (acesso) — key=value TAB-delim, uma transação por linha:
 *    time=2017-01-10 11:49:32\tpin=1001\tcardno=0\teventaddr=1\tevent=0\t
 *    inoutstatus=0\tverifytype=15\tindex=42
 *
 *    Campos:
 *      time         timestamp ORIGINAL do device, hora LOCAL "YYYY-MM-DD HH:MM:SS"
 *                   SEM timezone → aplicar device.tzOffsetMinutes p/ virar UTC.
 *      pin          ID do usuário NO device → externalUserId (núcleo resolve studentId)
 *      cardno       nº do cartão RFID (0 se biométrico)
 *      eventaddr    endereço da porta/leitora (qual lado da catraca)
 *      event        código do evento (0 = abertura normal por verificação OK;
 *                   >0 = negado/coação/porta-forçada/alarme — Appendix 2 do vendor)
 *      inoutstatus  DIREÇÃO (0=IN/entrada, 1=OUT/saída)
 *      verifytype   MÉTODO (0=senha 1=digital 4=cartão 15=face ...)
 *      index        contador monotônico do device → base do eventId p/ idempotência
 *
 *  PAYLOAD ATTLOG (ponto) — TAB posicional:
 *    pin \t time \t status \t verify \t workcode \t r1 \t r2
 *    Ex.: 1001\t2017-01-10 11:49:32\t0\t1\t0
 *
 *  NÃO-EVENTOS (retornar null ou [] conforme o caso):
 *    - GET handshake/options, GET /iclock/getrequest (poll de comandos),
 *      POST /iclock/devicecmd (ACK de comando), POST ...&table=OPERLOG (upload de
 *      template biométrico) → não são eventos de acesso. Retornamos null
 *      (irreconhecível p/ este parser de acesso) p/ o núcleo só ACKar.
 *    - rtlog/ATTLOG com corpo vazio (heartbeat de baixa carga) → [].
 *
 * ⚠️ CAVEATS / TODO field-confirm (numeração VARIA por firmware/modelo — Appendix 2):
 *    - GRANTED_EVENT_CODES, VERIFY_TYPE, IN_OUT devem ser validados no device real.
 *    - O campo `time` é hora LOCAL sem tz → depende de device.tzOffsetMinutes.
 *    - eventId usa `index` (monotônico); sem index, cai em hash do conteúdo.
 * ============================================================================
 */

'use strict';

const crypto = require('crypto');
const { normalizeDirection, normalizeMethod } = require('../canonical');

const VENDOR = 'zkteco';

// ---------------------------------------------------------------------------
// Tabelas de tradução (ZKTeco). TODO/ASSUMPTION: validar contra o modelo real.
// A numeração do Appendix 2 do vendor VARIA por firmware — confirmar em campo.
// ---------------------------------------------------------------------------

/** verifytype (rtlog/ATTLOG) → rótulo de método canônico-friendly.
 *  Fonte: VF_STYLE_* do PUSH SDK. ASSUMPTION: confirmar no device-alvo.
 *  Códigos altos (200/201/...) costumam ser combos (face+card etc.) → caem no
 *  default 'unknown' via normalizeMethod. TODO field-confirm. */
const VERIFY_TYPE = Object.freeze({
  '0': 'password', // → 'pin' canônico
  '1': 'fingerprint', // → 'finger'
  '2': 'palm', // → 'unknown' (sem rótulo canônico próprio) TODO
  '3': 'vein', // → 'unknown' TODO
  '4': 'card',
  '9': 'password',
  '15': 'face',
});

/** event (rtlog) → conjunto de códigos que representam ACESSO CONCEDIDO.
 *  event=0 é a abertura normal por verificação OK. Códigos >0 incluem
 *  negado/coação/alarme/porta-forçada → NÃO concedem presença.
 *  ASSUMPTION: Appendix 2 lista ~50 códigos; tratamos só "0 = ok" como grant.
 *  TODO field-confirm: mapear outros códigos "concedido" do firmware real. */
const GRANTED_EVENT_CODES = new Set(['0']);

// ---------------------------------------------------------------------------
// Parsing do payload cru ZKTeco
// ---------------------------------------------------------------------------

/**
 * Parseia o corpo rtlog (controle de acesso): linhas key=value TAB-delim.
 * @returns {Array<Object>} um registro normalizado (chaves crus) por linha.
 */
function parseRtlog(rawBody) {
  const out = [];
  const lines = String(rawBody || '').split(/\r?\n/);
  for (const line of lines) {
    if (!line.trim()) continue;
    const rec = {};
    for (const pair of line.split('\t')) {
      const idx = pair.indexOf('=');
      if (idx === -1) continue;
      rec[pair.slice(0, idx).trim()] = pair.slice(idx + 1).trim();
    }
    if (Object.keys(rec).length === 0) continue;
    out.push(rec);
  }
  return out;
}

/**
 * Parseia o corpo ATTLOG (terminal de ponto): linhas TAB posicionais.
 *   pin \t time \t status \t verify \t workcode \t r1 \t r2
 * Normaliza para o MESMO shape do rtlog (chaves pin/time/verifytype/...).
 * ATTLOG não tem `event` (ponto não tem "negado") nem `index`.
 */
function parseAttlog(rawBody) {
  const out = [];
  const lines = String(rawBody || '').split(/\r?\n/);
  for (const line of lines) {
    if (!line.trim()) continue;
    const f = line.split('\t');
    if (f.length < 2) continue;
    out.push({
      pin: (f[0] || '').trim(),
      time: (f[1] || '').trim(),
      // ATTLOG "status" = punch state (check-in/out de ponto), não in/out de
      // porta. Mapeamos heuristicamente via normalizeDirection. ASSUMPTION:
      // confirmar no device — pode não corresponder a entrada/saída física.
      inoutstatus: (f[2] || '0').trim(),
      verifytype: (f[3] || '').trim(),
      event: '0', // ATTLOG é sempre verificação OK (não há "negado" no ponto)
      cardno: '0',
      eventaddr: '0',
      index: '', // sem index → eventId cai no fallback (hash da linha)
    });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Tempo: hora LOCAL do device → Date (UTC). PRESERVA o timestamp ORIGINAL.
// ---------------------------------------------------------------------------

/** Converte "YYYY-MM-DD HH:MM:SS" (hora LOCAL do device, SEM tz) para Date.
 *  CAVEAT: o device emite hora local sem timezone. Aplicamos
 *  device.tzOffsetMinutes (minutos a leste de UTC; ex.: -180 p/ BRT) p/ gravar
 *  o instante UTC correto. NUNCA usa now(). Retorna null se a string não casar. */
function parseDeviceTime(s, tzOffsetMinutes) {
  const m = String(s || '').match(
    /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/);
  if (!m) return null;
  const [, Y, Mo, D, H, Mi, S] = m.map(Number);
  const off = Number.isFinite(Number(tzOffsetMinutes)) ? Number(tzOffsetMinutes) : 0;
  return new Date(Date.UTC(Y, Mo - 1, D, H, Mi, S) - off * 60 * 1000);
}

// ---------------------------------------------------------------------------
// eventId determinístico e ESTÁVEL (base da idempotência do núcleo)
// ---------------------------------------------------------------------------

/**
 * Prefere `${deviceId}_${sn}_${index}` (index = contador monotônico do device,
 * estável em re-entregas do MESMO evento). Sem index (ATTLOG) → hash do conteúdo
 * (pin+time+verifytype+eventaddr), que ainda dedupa re-entregas do mesmo evento.
 * O núcleo deduplica por accessEvents/{deviceId}_{eventId}.
 */
function computeEventId(deviceId, sn, rec) {
  if (rec.index !== undefined && rec.index !== '') {
    return `${deviceId}_${sn}_${rec.index}`;
  }
  const h = crypto.createHash('sha256')
    .update(`${deviceId}|${sn}|${rec.pin}|${rec.time}|${rec.verifytype}|${rec.eventaddr}`)
    .digest('hex').slice(0, 24);
  return `${deviceId}_${sn}_h${h}`;
}

// ---------------------------------------------------------------------------
// Roteamento iclock: este adapter só entende EVENTOS de acesso (rtlog/ATTLOG).
// ---------------------------------------------------------------------------

/** GETs (handshake/options, getrequest poll) e POSTs que não são tabela de
 *  evento (devicecmd ACK, OPERLOG template) NÃO são eventos de acesso. */
function isAccessTable(table) {
  return table === 'rtlog' || table === 'attlog';
}

// ---------------------------------------------------------------------------
// CONTRATO: parse(req, device) -> AccessEvent[] | null
// ---------------------------------------------------------------------------

/**
 * @param {{rawBody:string, query:object, headers:object, method:string, path:string}} req
 *        recortado pelo núcleo (corpo CRU já lido; HMAC já validado).
 * @param {object} device  doc devices/{deviceId} já carregado. Usa:
 *        deviceId (ou derivado de query.SN), tzOffsetMinutes.
 * @returns {Array<import('../canonical').AccessEvent>|null}
 *   - AccessEvent[] (um por linha de evento; [] p/ corpo vazio/heartbeat)
 *   - null se o payload for irreconhecível como evento de acesso (handshake,
 *     poll de comandos, ACK, upload de template) → o núcleo só ACKa "OK".
 */
function parse(req, device) {
  const query = (req && req.query) || {};
  const method = String((req && req.method) || 'POST').toUpperCase();

  // GET = handshake/options ou getrequest (poll de comandos) → não é evento.
  if (method !== 'POST') return null;

  // Identidade física do device. O núcleo já carregou `device`; preferimos o
  // deviceId do nosso sistema, com fallback ao SN da query.
  // ASSUMPTION: device.deviceId === doc id; SN é o serial do device ZKTeco.
  const sn = String(query.SN || query.sn || '');
  const deviceId = String(
    (device && (device.deviceId || device.id)) || query.deviceId || sn || '');

  // Tabela determina o formato. Default 'rtlog' (controle de acesso, nosso caso).
  // TODO/ASSUMPTION: confirmar que o device-alvo posta rtlog (e não só ATTLOG).
  const table = String(query.table || 'rtlog').toLowerCase();
  if (!isAccessTable(table)) {
    // OPERLOG (template), devicecmd ACK, etc. → não é evento de acesso.
    return null;
  }

  const rawBody = String((req && req.rawBody) || '');
  const records = table === 'attlog' ? parseAttlog(rawBody) : parseRtlog(rawBody);

  // Corpo vazio (heartbeat de baixa carga) → array vazio, núcleo só ACKa.
  if (records.length === 0) return [];

  const events = [];
  for (const rec of records) {
    const occurredAt = parseDeviceTime(
      rec.time, device && device.tzOffsetMinutes);
    // Sem timestamp parseável → não podemos preservar o instante ORIGINAL nem
    // dar um eventId estável por tempo. Pulamos a linha (auditoria do núcleo
    // não recebe lixo). ASSUMPTION: linhas sem `time` válido são raras/heartbeat.
    if (!occurredAt) continue;

    const externalUserId = String(rec.pin || '').trim();
    const eventCode = String(rec.event !== undefined ? rec.event : '0').trim();

    events.push({
      deviceId,
      vendor: VENDOR,
      externalUserId, // '0'/'' => não identificado (núcleo decide granted/no-match)
      eventId: computeEventId(deviceId, sn, rec),
      occurredAt, // ORIGINAL (hora local do device → UTC via tzOffsetMinutes)
      direction: normalizeDirection(rec.inoutstatus), // ZKTeco 0=in,1=out (TODO confirm)
      method: normalizeMethod(rec.verifytype, VERIFY_TYPE), // TODO field-confirm
      granted: GRANTED_EVENT_CODES.has(eventCode), // só event=0 (TODO field-confirm)
      eventCode,
      raw: {
        // recorte bruto p/ auditoria/forense e field-confirm da numeração.
        sn,
        table,
        pin: rec.pin,
        time: rec.time,
        cardno: rec.cardno,
        eventaddr: rec.eventaddr,
        event: rec.event,
        inoutstatus: rec.inoutstatus,
        verifytype: rec.verifytype,
        index: rec.index,
      },
    });
  }

  return events;
}

module.exports = {
  parse,
  vendor: VENDOR,
  // helpers exportados p/ teste/uso interno (não fazem parte do contrato):
  parseRtlog,
  parseAttlog,
  parseDeviceTime,
  computeEventId,
  VERIFY_TYPE,
  GRANTED_EVENT_CODES,
};
