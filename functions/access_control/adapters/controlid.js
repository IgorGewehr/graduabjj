/**
 * access_control/adapters/controlid.js — ADAPTER Control iD (push "Monitor")
 * ============================================================================
 *
 * Converte o payload de ACESSO da Control iD (iDAccess / iDBlock / iDFace) no
 * AccessEvent canônico (../canonical). Módulo PURO: não toca rede nem Firestore,
 * não resolve studentId, não valida HMAC, não escreve resposta — só traduz o
 * wire format para a forma canônica. Contrato: parse(req, device) -> AccessEvent[]|null
 * (ver ../canonical.js). Passa em `node --check`.
 *
 * ----------------------------------------------------------------------------
 * PROTOCOLO (Modo "Monitor" / push standalone)
 * ----------------------------------------------------------------------------
 * O device é configurado com host/port/path base e faz POST autônomo para
 * `hostname:port/{path}/{evento}` quando há mudança no log. Sub-paths relevantes:
 *
 *   POST {path}/dao             -> mudanças no log de acesso (access_logs). É o
 *                                  evento de ACESSO/presença que nos interessa.
 *   POST {path}/catra_event     -> giro físico confirmado da catraca (iDBlock):
 *                                  TURN LEFT/RIGHT / abandono de giro.
 *   POST {path}/device_is_alive -> heartbeat (~30s). NÃO é evento → retorna [].
 *
 * Em Cloud Function única o device anexa o sub-path ao `path` configurado; o
 * núcleo entrega esse sub-path em `req.path` e este adapter roteia internamente.
 *
 * ----------------------------------------------------------------------------
 * PAYLOAD /dao (JSON) — exemplo REAL (object_changes[] de access_logs):
 *   {
 *     "object_changes": [
 *       { "object": "access_logs", "type": "inserted", "values": {
 *           "id": "519", "time": "1532977090", "event": "12",
 *           "device_id": "478435", "identifier_id": "0", "user_id": "0",
 *           "portal_id": "1", "identification_rule_id": "0",
 *           "card_value": "0", "log_type_id": "-1" } }
 *     ],
 *     "device_id": 478435
 *   }
 *
 * PAYLOAD /catra_event (JSON) — giro confirmado:
 *   { "event": { "type": 7, "name": "TURN LEFT", "time": 1484126902,
 *                "uuid": "0e039178" },
 *     "access_event_id": 15, "device_id": 935107, "time": 1484126902 }
 *
 * CAVEATS de campo (marcados TODO/ASSUMPTION abaixo):
 *  - `values.time` é UNIX em SEGUNDOS (×1000 p/ ms). É o timestamp ORIGINAL.
 *  - A tabela de códigos `values.event` (concedido/negado/sentido) NÃO está
 *    limpa na doc pública (ex. observado event="12"). GRANTED_EVENT_CODES é
 *    field-confirm por firmware (iDAccess vs iDBlock vs iDFace).
 *  - direção deriva de `portal_id` via device.portalDirection (config física).
 *  - método deriva de identifier_id / identification_rule_id — sem string
 *    legível; mapeamento por device (METHOD_BY_RULE) field-confirm.
 *  - user_id "0"/"" = não identificado/negado → granted=false (o núcleo não
 *    grava presença sem studentId, mas registra o evento p/ auditoria).
 *  - idempotência: eventId = `${device_id}_${values.id}` (id sequencial NO
 *    device, estável em re-entregas). /catra_event usa access_event_id.
 * ============================================================================
 */

'use strict';

const { normalizeDirection, normalizeMethod } = require('../canonical');

const VENDOR = 'controlid';

// ---------------------------------------------------------------------------
// Tabelas de tradução — TODO/ASSUMPTION: field-confirm por firmware do device.
// ---------------------------------------------------------------------------

/**
 * Códigos de `values.event` que representam ACESSO CONCEDIDO (entrada liberada
 * por face/digital/cartão/pin). A doc pública NÃO expõe esta tabela de forma
 * limpa; o único valor OBSERVADO em exemplo foi "12". Confirmar EM CAMPO o set
 * completo de códigos de "concedido" no firmware-alvo (iDAccess / iDBlock /
 * iDFace) antes de conceder presença em produção.
 * TODO/FIELD-CONFIRM: validar/expandir este conjunto no device real.
 */
const GRANTED_EVENT_CODES = new Set(['12']);

/**
 * Mapa de fallback identification_rule_id / identifier_id -> método canônico,
 * quando o device não entrega o método de forma legível. É inerentemente
 * dependente da config do device — por isso o caminho preferido é
 * `device.methodByRule` (por-device, vindo do doc) e ESTA tabela é só o default.
 * TODO/FIELD-CONFIRM: o significado exato de identifier_id/identification_rule_id
 * varia por modelo/config; capturar com sniffer e mapear por device.
 */
const DEFAULT_METHOD_BY_RULE = Object.freeze({
  // '0': 'face',  // exemplo — NÃO assumir; field-confirm.
});

// Nomes de evento do /catra_event que confirmam passagem física (giro feito).
// TODO/FIELD-CONFIRM: confirmar os rótulos exatos no firmware (TURN LEFT/RIGHT).
const TURN_EVENT_NAMES = new Set(['TURN LEFT', 'TURN RIGHT']);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Tenta JSON.parse do corpo cru; retorna {} em falha (heartbeat/garbage). */
function safeJson(rawBody) {
  if (typeof rawBody !== 'string' || rawBody.trim() === '') return null;
  try {
    const v = JSON.parse(rawBody);
    return (v && typeof v === 'object') ? v : null;
  } catch (_) {
    return null;
  }
}

/**
 * Converte `values.time` (UNIX em SEGUNDOS, string ou number) p/ Date.
 * PRESERVA o timestamp ORIGINAL do evento — NUNCA usa now().
 * TODO/ASSUMPTION: a Control iD emite epoch em SEGUNDOS (confirmado nos
 * exemplos). Se algum firmware emitir ms, ajustar aqui.
 */
function controlidTimeToDate(raw) {
  if (raw === null || raw === undefined || raw === '') return null;
  const secs = Number(raw);
  if (!Number.isFinite(secs) || secs <= 0) return null;
  const d = new Date(secs * 1000);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Normaliza o sub-path do evento ('/dao', '/catra_event', '/device_is_alive'). */
function eventPathOf(req) {
  const p = String((req && req.path) || '').toLowerCase();
  // O device anexa o sub-evento ao path base; pegamos o último segmento.
  if (p.endsWith('/dao') || p === 'dao' || p.endsWith('dao')) {
    // cuidado p/ não casar "dao" dentro de outra palavra: exige separador.
    if (/(^|\/)dao$/.test(p)) return 'dao';
  }
  if (/(^|\/)catra_event$/.test(p)) return 'catra_event';
  if (/(^|\/)device_is_alive$/.test(p)) return 'device_is_alive';
  return ''; // desconhecido → caímos na heurística por shape do corpo.
}

/**
 * Resolve a direção do acesso a partir de `portal_id`.
 * Caminho preferido: device.portalDirection[portal_id] -> 'in'|'out'
 * (config física por device, vinda do doc). Sem mapa → 'unknown' (o núcleo
 * decide; mas por padrão NÃO assumimos 'in' às cegas — field-confirm).
 * TODO/FIELD-CONFIRM: portal_id 1/2 = entrada/saída é o TÍPICO, mas depende da
 * instalação. Preencher device.portalDirection no enroll/config.
 */
function resolveDirection(device, portalId) {
  const map = (device && device.portalDirection) || {};
  const mapped = map[String(portalId)];
  if (mapped) return normalizeDirection(mapped);
  return 'unknown';
}

/**
 * Resolve o método (face/finger/card/pin) de um access_log.
 * Preferência: cartão presente (card_value != 0) => 'card'. Senão tenta mapear
 * identification_rule_id e depois identifier_id via tabela por-device
 * (device.methodByRule) com fallback p/ DEFAULT_METHOD_BY_RULE. Sem match =>
 * 'unknown' (método é só auditoria, não gateia presença).
 */
function resolveMethod(device, values) {
  const cardVal = String((values && values.card_value) || '0');
  if (cardVal && cardVal !== '0') return 'card';

  const table = (device && device.methodByRule) || DEFAULT_METHOD_BY_RULE;
  const ruleId = values && values.identification_rule_id;
  const identId = values && values.identifier_id;

  // normalizeMethod aceita uma tabela código->rótulo p/ valores numéricos.
  let m = normalizeMethod(ruleId, table);
  if (m === 'unknown') m = normalizeMethod(identId, table);
  return m; // 'unknown' se nada bateu — field-confirm o mapeamento por device.
}

/**
 * Constrói um AccessEvent a partir de um access_log (/dao). Pode retornar null
 * se faltarem campos essenciais (time inválido).
 */
function accessLogToEvent(device, topDeviceId, values) {
  const occurredAt = controlidTimeToDate(values.time);
  if (!occurredAt) return null; // sem timestamp ORIGINAL confiável → descarta.

  const externalUserId = String(values.user_id == null ? '' : values.user_id);
  const eventCode = values.event == null ? '' : String(values.event);
  // user_id '0'/'' = não identificado/negado; granted exige código concedido
  // E usuário identificado.
  const identified = externalUserId !== '' && externalUserId !== '0';
  const granted = identified && GRANTED_EVENT_CODES.has(eventCode);

  // eventId determinístico e estável: device_id + id sequencial do log NO device.
  // `values.id` é monotônico no device e se repete igual em re-entregas →
  // idempotência forte. Fallback p/ deviceId do nosso sistema se top device_id
  // ausente. Sem `values.id` cairíamos sem chave estável — então exigimos id.
  const logId = values.id == null ? '' : String(values.id);
  const devId = String(values.device_id || topDeviceId || device.deviceId || '');
  const eventId = logId !== ''
    ? `${devId}_${logId}`
    // TODO/ASSUMPTION: sem `values.id` não há chave estável nativa; derivamos
    // um id por conteúdo p/ ainda deduplicar a MESMA re-entrega. Confirmar que
    // `values.id` sempre vem em campo (esperado: sim).
    : `${devId}_t${String(values.time)}_u${externalUserId}_p${String(values.portal_id || '')}`;

  return {
    deviceId: device.deviceId,
    vendor: VENDOR,
    externalUserId,
    eventId,
    occurredAt,
    direction: resolveDirection(device, values.portal_id),
    method: resolveMethod(device, values),
    granted,
    eventCode,
    raw: {
      source: 'dao',
      values,
      topDeviceId: topDeviceId == null ? null : topDeviceId,
    },
  };
}

/**
 * Constrói um AccessEvent a partir de um /catra_event (giro confirmado).
 * RELEVÂNCIA: para iDBlock o giro confirma passagem FÍSICA. Aqui o emitimos com
 * granted=false e SEM externalUserId (o /catra_event não traz user_id — só
 * access_event_id que correlaciona com o access_log já recebido via /dao).
 * O núcleo o registrará como auditoria (no_match/denied) sem conceder presença.
 *
 * TODO/DOMÍNIO (device.grantOn): se a academia quiser conceder presença só no
 * GIRO confirmado (iDBlock) em vez de na autorização (/dao), a correlação
 * por access_event_id precisa ser feita no núcleo/reconciliação — fora do
 * escopo deste adapter, que só traduz o evento. Documentado, não implementado.
 */
function catraEventToEvent(device, body) {
  const ev = (body && body.event) || {};
  const name = String(ev.name || '').toUpperCase().trim();
  // Só nos importam giros confirmados; abandono/erro de giro → ignora.
  if (!TURN_EVENT_NAMES.has(name)) return null;

  const occurredAt = controlidTimeToDate(ev.time != null ? ev.time : body.time);
  if (!occurredAt) return null;

  const devId = String(body.device_id || device.deviceId || '');
  const accessEventId = body.access_event_id == null
    ? '' : String(body.access_event_id);
  // eventId distinto do /dao p/ não colidir: prefixo 'catra'. Estável por
  // (device, access_event_id) — re-entrega do mesmo giro deduplica.
  const eventId = accessEventId !== ''
    ? `${devId}_catra_${accessEventId}`
    : `${devId}_catra_t${String(ev.time != null ? ev.time : body.time)}_${ev.uuid || ''}`;

  return {
    deviceId: device.deviceId,
    vendor: VENDOR,
    externalUserId: '', // /catra_event não traz user_id (correlaciona via /dao).
    eventId,
    occurredAt,
    direction: 'in', // TURN = passagem; sentido fino depende de LEFT/RIGHT +
                     // config física. TODO/FIELD-CONFIRM: mapear LEFT/RIGHT->in/out.
    method: 'unknown',
    granted: false, // giro sozinho não concede presença sem o user do /dao.
    eventCode: name, // 'TURN LEFT' | 'TURN RIGHT' (auditoria).
    raw: { source: 'catra_event', event: ev, access_event_id: body.access_event_id },
  };
}

// ---------------------------------------------------------------------------
// CONTRATO: parse(req, device) -> AccessEvent[] | null
// ---------------------------------------------------------------------------
/**
 * @param {{rawBody:string, query:object, headers:object, method:string, path:string}} req
 * @param {object} device  doc devices/{deviceId} JÁ carregado, com `deviceId`,
 *                         `vendor`, `portalDirection`, `methodByRule`, etc.
 * @returns {import('../canonical').AccessEvent[]|null}
 *   - []   heartbeat / giro irrelevante (núcleo ACKa).
 *   - null payload irreconhecível como Control iD.
 */
function parse(req, device) {
  const dev = device || {};
  const body = safeJson(req && req.rawBody);
  const path = eventPathOf(req);

  // Heartbeat explícito → não é evento de acesso.
  if (path === 'device_is_alive') return [];

  if (!body) {
    // Corpo não-JSON ou vazio. Se o path indicava dao/catra mas veio garbage,
    // tratamos como irreconhecível (null) p/ o núcleo logar; senão (path vazio)
    // também null — não é um payload Control iD válido.
    return null;
  }

  // ---- /catra_event (giro confirmado) ----
  // Detecta por path OU por shape (tem `event.name` + `access_event_id`).
  const looksLikeCatra =
    path === 'catra_event' ||
    (body.event && (body.access_event_id !== undefined || body.event.name !== undefined));
  if (looksLikeCatra && path !== 'dao') {
    const ce = catraEventToEvent(dev, body);
    return ce ? [ce] : [];
  }

  // ---- /dao (mudanças no log de acesso) ----
  const changes = Array.isArray(body.object_changes) ? body.object_changes : null;
  if (changes) {
    const topDeviceId = body.device_id;
    const out = [];
    for (const ch of changes) {
      // Só inserções em access_logs são eventos de acesso. templates/cards/
      // alarmes/outros objetos no mesmo /dao são ignorados.
      if (!ch || ch.object !== 'access_logs' || ch.type !== 'inserted') continue;
      const values = ch.values || {};
      const ev = accessLogToEvent(dev, topDeviceId, values);
      if (ev) out.push(ev);
    }
    // Array vazio (ex.: /dao só com templates) → heartbeat-like, ACK sem gravar.
    return out;
  }

  // JSON válido mas sem object_changes nem event → não é evento de acesso
  // reconhecível (pode ser outro sub-path do Monitor). ACK vazio em vez de null
  // p/ não poluir log, já que é JSON Control iD plausível.
  if (body.access_logs !== undefined || body.device_id !== undefined) {
    return [];
  }

  return null;
}

module.exports = {
  parse,
  // exportados p/ teste/uso interno (não são parte do contrato do núcleo):
  GRANTED_EVENT_CODES,
  controlidTimeToDate,
  accessLogToEvent,
  catraEventToEvent,
  eventPathOf,
};
