/**
 * access_control/adapters/intelbras.js — ADAPTER Intelbras (Bio-T "Modo Online")
 * ============================================================================
 *
 * Módulo PURO (sem firebase-admin, sem I/O de rede). Implementa o CONTRATO de
 * canonical.js:
 *
 *     parse(req, device) -> AccessEvent[] | null
 *
 * Converte o payload de ACESSO da Intelbras (linha Bio-T facial/digital: SS
 * 5531/5541 MF W, SS 5532/5542, SS 3532/3542, SS 5530, família CAP) rodando em
 * "Modo Online" no AccessEvent canônico. O device faz o match biométrico
 * EMBARCADO e POSTa cada tentativa direto nesta Cloud Function (Arquitetura C),
 * BLOQUEANDO até a resposta de autorização — a resposta (giro/nega) é do NÚCLEO
 * (ingest.js), não deste adapter.
 *
 * Este adapter NÃO resolve studentId (núcleo: device.userMap[externalUserId]),
 * NÃO grava no Firestore, NÃO valida HMAC e NÃO escreve a resposta HTTP.
 *
 * ---------------------------------------------------------------------------
 * WIRE FORMAT (Modo Online, observado no servidor de exemplo oficial main.js e
 * na HTTP API V3.35 §12.1.9 [Event] AccessControl):
 *   - Content-Type: multipart/* com separadores `--myboundary` (NÃO é JSON
 *     plano). Tipicamente 2 partes:
 *       * `Content-Type: image/jpeg`  — a face capturada (~200k), descartada.
 *       * `Content-Type: text/plain`  — o evento, que conforme o firmware vem
 *         como (a) JSON  {"UserID":"101",...}  OU  (b) Dahua key=value pontilhado
 *         `Events[0].UserID=101`. Parseamos AMBOS, defensivamente.
 *   - Alguns firmwares podem POSTar um corpo JSON plano (sem multipart). Tratado.
 *
 *   >>> ASSUMPTION / FIELD-CONFIRM: a shape EXATA da parte text/plain (JSON vs
 *       key=value), o boundary real e as unidades de tempo dependem do firmware.
 *       Capturar com sniffer (o NÚCLEO loga raw) antes de confiar em produção. <<<
 *
 * CAMPOS do [Event] AccessControl que nos interessam:
 *   UserID    (string)  — id do usuário cadastrado NO device == externalUserId.
 *   Type      ("Entry"|"Exit") => direction.
 *   Status    (int)     — 0=falhou, 1=sucesso, AUSENTE=sucesso => granted.
 *   Method    (int)     — enum de método (0=senha,1=cartão,6=digital,15=face...).
 *   CardNo    (string)  — presente quando abre por cartão.
 *   RecNo     (int)     — id do registro NO device => base do eventId idempotente.
 *   CreateTime/UTC (epoch SEGUNDOS) ou Time ("YYYY-MM-DD HH:MM:SS") => occurredAt
 *                         ORIGINAL (PRESERVAR; nunca now()).
 *   Code/EventBaseInfo.Code ("AccessControl") — discrimina evento de acesso de
 *                         heartbeat/keepalive (Code ausente / outro => não-evento).
 *
 * Sources:
 *   https://intelbras-caco-api.intelbras.com.br/modo_online
 *   https://github.com/johwconst/IntelbrasModoOnlineElectron
 *   HTTP API V3.35 §12.1.9  (botminio.apps.intelbras.com.br)
 * ============================================================================
 */

'use strict';

const { normalizeDirection, normalizeMethod } = require('../canonical');

const VENDOR = 'intelbras';

// ---------------------------------------------------------------------------
// Tabela de método (HTTP API V3.35 §12.1.9). Parcial — os que esperamos. O
// núcleo só usa `method` p/ auditoria (não gateia presença).
// TODO/FIELD-CONFIRM: a enumeração completa (0-47) e quais aparecem no firmware
// alvo devem ser confirmados em campo. normalizeMethod aterra no enum canônico.
// ---------------------------------------------------------------------------
const METHOD_TABLE = Object.freeze({
  '0': 'pin',     // senha
  '1': 'card',    // cartão
  '6': 'finger',  // digital
  '12': 'pin',    // chave
  '14': 'pin',    // qrcode local — sem rótulo canônico próprio; trata como pin
  '15': 'face',   // face local
  '17': 'card',   // RG/documento
  '19': 'card',   // bluetooth
  '43': 'pin',    // qrcode remoto
  '44': 'face',   // face remota
});

// ---------------------------------------------------------------------------
// GRANTED_EVENT_CODES — quais valores de `Status` significam ACESSO CONCEDIDO.
// Na Intelbras o veredito de sucesso/falha vem em Status (1=sucesso, 0=falhou),
// e Status AUSENTE é tratado como sucesso (firmwares que só POSTam concessões).
// TODO/FIELD-CONFIRM: confirmar se algum firmware usa outros códigos de status
// ou um campo separado (ex.: Result) p/ a decisão. Ponto único de mudança.
// ---------------------------------------------------------------------------
const GRANTED_STATUS = Object.freeze(new Set(['1']));

// ===========================================================================
// CONTRATO: parse(req, device) -> AccessEvent[] | null
// ===========================================================================
/**
 * @param {{rawBody:string, query:object, headers:object, method:string, path:string}} req
 * @param {object} device  doc devices/{deviceId} já carregado pelo núcleo
 *                          (dá deviceId, vendor, portalDirection, userMap...).
 * @returns {Array<object>|null}  AccessEvent[] (pode ser [] p/ heartbeat) ou null
 *          se o payload for irreconhecível para Intelbras.
 */
function parse(req, device) {
  // GET = handshake / keepalive (Keep Alive Path). Sem eventos.
  if (req && req.method && req.method.toUpperCase() === 'GET') return [];

  const deviceId = (device && device.deviceId) || null;
  const contentType = headerOf(req && req.headers, 'content-type');
  const rawText = extractEventText(req && req.rawBody, contentType);

  // Nada parseável no corpo => irreconhecível p/ este vendor.
  if (rawText == null || rawText === '') return null;

  // Pode haver N eventos (Events[0], Events[1], ... no formato key=value) ou um
  // único objeto JSON. extractEvents normaliza p/ uma lista de objetos planos.
  const rawEvents = extractEvents(rawText);
  if (!Array.isArray(rawEvents)) return null;
  if (rawEvents.length === 0) return []; // corpo reconhecido mas sem evento

  const out = [];
  for (let i = 0; i < rawEvents.length; i++) {
    const ev = rawEvents[i];
    const accessEvent = toAccessEvent(ev, device, deviceId, i, rawText);
    if (accessEvent) out.push(accessEvent);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Converte UM objeto de evento plano (já extraído) no AccessEvent canônico.
// Retorna null se NÃO for um evento de acesso (heartbeat/keepalive/outro Code).
// ---------------------------------------------------------------------------
function toAccessEvent(ev, device, deviceId, index, rawText) {
  // Discrimina evento de acesso. Code/EventBaseInfo.Code == 'AccessControl'.
  // Se Code estiver presente e NÃO for AccessControl => não-evento (heartbeat,
  // status de porta, etc.). Se ausente, assumimos acesso (firmwares que só
  // POSTam tentativas de acesso e omitem Code).
  // TODO/FIELD-CONFIRM: confirmar o conjunto de Codes que o firmware emite.
  const code = firstDefined(ev, ['Code', 'EventBaseInfo.Code', 'Events.Code']);
  if (code != null && String(code).toLowerCase() !== 'accesscontrol') {
    return null;
  }

  // externalUserId — UserID. '0'/'' => não identificado (núcleo não grava
  // presença sem studentId; emitimos granted=false p/ auditoria).
  const userIdRaw = firstDefined(ev, ['UserID', 'UserId', 'userId', 'user_id']);
  const externalUserId = userIdRaw != null ? String(userIdRaw).trim() : '';

  // Status => granted (1=sucesso, 0=falhou, AUSENTE=sucesso).
  const statusRaw = firstDefined(ev, ['Status', 'status']);
  const statusKey = statusRaw == null ? '1' : String(statusRaw).trim();
  let granted = GRANTED_STATUS.has(statusKey);
  // Usuário não identificado nunca concede presença.
  if (!externalUserId || externalUserId === '0') granted = false;

  // direction — Type "Entry"/"Exit". normalizeDirection aterra em in/out/unknown.
  const typeRaw = firstDefined(ev, ['Type', 'type', 'Direction', 'direction']);
  let direction = normalizeDirection(typeRaw);
  // Catraca de giro único sem Type costuma ser entrada. Fallback p/ portal map
  // opcional (Name/Door -> in/out) se o device.portalDirection o definir.
  if (direction === 'unknown') {
    const portalId = firstDefined(ev, ['Name', 'Door', 'door', 'Channel', 'channel']);
    const pd = device && device.portalDirection;
    if (pd && portalId != null && pd[String(portalId)]) {
      direction = pd[String(portalId)] === 'out' ? 'out' : 'in';
    } else {
      direction = 'in'; // ASSUMPTION: giro único => entrada. FIELD-CONFIRM.
    }
  }

  // method — Method enum -> rótulo canônico (auditoria).
  const methodRaw = firstDefined(ev, ['Method', 'method']);
  const method = normalizeMethod(methodRaw, METHOD_TABLE);

  // occurredAt — ORIGINAL. Prioridade: CreateTime/UTC (epoch SEGUNDOS) > Time
  // ("YYYY-MM-DD HH:MM:SS"). NUNCA now().
  // TODO/FIELD-CONFIRM: confirmar a UNIDADE de CreateTime (s vs ms). Aqui
  // assumimos SEGUNDOS (×1000), conforme V3.35. parseOccurredAt heurística-guarda
  // contra valores já em ms (10 dígitos = s; 13 dígitos = ms).
  const occurredAt = parseOccurredAt(ev);

  // eventCode — código bruto do fabricante p/ auditoria + base da regra granted.
  const eventCode = statusKey;

  // eventId — ESTÁVEL p/ idempotência. Prefere RecNo (id do registro NO device);
  // sem RecNo, deriva determinístico do conteúdo (hash) + índice no lote.
  // TODO/FIELD-CONFIRM: confirmar que RecNo é único/estável por evento no
  // firmware alvo (não reinicia). Caso não, trocar p/ hash do evento.
  const recNo = firstDefined(ev, ['RecNo', 'recNo', 'recno']);
  const eventId = buildEventId(deviceId, recNo, ev, occurredAt, index);

  return {
    deviceId,
    vendor: VENDOR,
    externalUserId,
    eventId,
    occurredAt,
    direction,
    method,
    granted,
    eventCode,
    raw: redactRaw(ev, rawText),
  };
}

// ---------------------------------------------------------------------------
// Multipart / corpo: extrai o TEXTO do evento (parte text/plain) do corpo cru.
// Descarta a parte image/jpeg. Suporta corpo JSON plano (sem multipart).
// Retorna string (o texto do evento) ou null se nada utilizável.
// ---------------------------------------------------------------------------
function extractEventText(rawBody, contentType) {
  const raw = rawBody == null ? '' : String(rawBody);
  if (!raw) return null;

  const ct = String(contentType || '');
  const isMultipart = /multipart\//i.test(ct) || /--[A-Za-z0-9'()+_,\-./:=?]+\r?\n/.test(raw);

  if (isMultipart) {
    // Boundary do Content-Type, senão default 'myboundary' (exemplo oficial).
    let boundary = 'myboundary';
    const m = /boundary=([^;\s]+)/i.exec(ct);
    if (m) boundary = m[1].replace(/^"|"$/g, '');

    const parts = raw.split('--' + boundary);
    let eventText = null;
    for (const part of parts) {
      if (/Content-Type:\s*image\/jpeg/i.test(part)) continue; // face: descarta
      if (/Content-Type:\s*text\/plain/i.test(part) ||
          /Content-Type:\s*application\/json/i.test(part)) {
        const idx = indexOfHeaderEnd(part);
        eventText = (idx >= 0 ? part.slice(idx) : part).replace(/--\s*$/, '').trim();
        if (eventText) break;
      }
    }
    if (eventText) return eventText;
    // Multipart sem parte de texto reconhecível.
    // Última tentativa: alguma parte que pareça JSON/kv.
    for (const part of parts) {
      const idx = indexOfHeaderEnd(part);
      const body = (idx >= 0 ? part.slice(idx) : part).replace(/--\s*$/, '').trim();
      if (body && (body.startsWith('{') || /=/.test(body))) return body;
    }
    return null;
  }

  // Corpo plano (JSON ou key=value direto).
  return raw.trim();
}

// Fim do bloco de headers de uma parte multipart (linha em branco). Retorna o
// índice do INÍCIO do corpo, ou -1.
function indexOfHeaderEnd(part) {
  let idx = part.indexOf('\r\n\r\n');
  if (idx >= 0) return idx + 4;
  idx = part.indexOf('\n\n');
  if (idx >= 0) return idx + 2;
  return -1;
}

// ---------------------------------------------------------------------------
// Texto do evento -> lista de objetos de evento planos.
//   - JSON objeto único        -> [obj]
//   - JSON { Events: [...] }    -> [...]  (cada item achatado)
//   - JSON array               -> [...]
//   - Dahua key=value pontilhado (Events[0].UserID=101, Events[1].UserID=...)
//                              -> agrupa por índice [N] => um objeto por evento
//   - key=value sem índice     -> [obj único]
// Retorna [] se reconhecido mas vazio; null se irreconhecível.
// ---------------------------------------------------------------------------
function extractEvents(text) {
  const t = String(text).trim();
  if (!t) return [];

  // --- JSON ---
  if (t.startsWith('{') || t.startsWith('[')) {
    let parsed;
    try {
      parsed = JSON.parse(t);
    } catch (_) {
      // não era JSON válido — cai p/ kv abaixo.
      parsed = undefined;
    }
    if (parsed !== undefined) {
      if (Array.isArray(parsed)) return parsed.map(flattenObject);
      if (parsed && Array.isArray(parsed.Events)) {
        return parsed.Events.map(flattenObject);
      }
      if (parsed && typeof parsed === 'object') return [flattenObject(parsed)];
      return [];
    }
  }

  // --- Dahua key=value pontilhado ---
  const lines = t.split(/\r?\n/);
  const byIndex = new Map();   // 'Events[0]' agrupado por índice numérico
  const flat = {};             // pares sem índice de evento
  let sawAny = false;

  for (const line of lines) {
    const eq = line.indexOf('=');
    if (eq < 0) continue;
    sawAny = true;
    const fullKey = line.slice(0, eq).trim();
    const val = line.slice(eq + 1).trim();

    // Captura índice do evento, se houver: "Events[2].UserID" -> idx 2.
    const idxMatch = /\[(\d+)\]/.exec(fullKey);
    // Chave curta: último segmento sem prefixo/array. "Events[0].UserID" -> "UserID".
    const short = fullKey.replace(/^.*\./, '').replace(/\[\d+\]$/, '');
    if (!short) continue;

    if (idxMatch) {
      const idx = Number(idxMatch[1]);
      if (!byIndex.has(idx)) byIndex.set(idx, {});
      byIndex.get(idx)[short] = val;
    } else {
      flat[short] = val;
    }
  }

  if (!sawAny) return null; // nem JSON nem key=value => irreconhecível.

  if (byIndex.size > 0) {
    return [...byIndex.keys()].sort((a, b) => a - b).map((k) => {
      // Mescla pares globais (sem índice) em cada evento — campos comuns.
      return Object.assign({}, flat, byIndex.get(k));
    });
  }
  return [flat];
}

// Achata um objeto aninhado em chaves pontilhadas E também expõe a chave curta
// (último segmento), p/ firstDefined achar tanto "EventBaseInfo.Code" quanto
// "Code". Não recursa em arrays (Events já tratado fora).
function flattenObject(obj, prefix, acc) {
  acc = acc || {};
  if (obj == null || typeof obj !== 'object') return acc;
  for (const key of Object.keys(obj)) {
    const val = obj[key];
    const dotted = prefix ? prefix + '.' + key : key;
    if (val != null && typeof val === 'object' && !Array.isArray(val)) {
      flattenObject(val, dotted, acc);
      // também guarda a forma pontilhada caso alguém busque por ela
    } else {
      acc[dotted] = val;
      acc[key] = val; // chave curta (último segmento) p/ lookup tolerante
    }
  }
  return acc;
}

// ---------------------------------------------------------------------------
// occurredAt ORIGINAL. CreateTime/UTC epoch (s, guarda contra ms); Time string.
// ---------------------------------------------------------------------------
function parseOccurredAt(ev) {
  const epochRaw = firstDefined(ev, ['CreateTime', 'createTime', 'UTC', 'utc', 'Time1']);
  if (epochRaw != null && /^\d+$/.test(String(epochRaw))) {
    const n = Number(epochRaw);
    // 13 dígitos ~ ms; 10 dígitos ~ s. Heurística-guarda p/ a unidade de campo.
    // TODO/FIELD-CONFIRM: confirmar unidade exata de CreateTime no firmware.
    const ms = String(epochRaw).length >= 13 ? n : n * 1000;
    const d = new Date(ms);
    if (!isNaN(d.getTime())) return d;
  }

  const timeStr = firstDefined(ev, ['Time', 'time', 'CreateTimeStr', 'DateTime']);
  if (timeStr) {
    // "YYYY-MM-DD HH:MM:SS" (com ou sem tz). Troca espaço por 'T' p/ ISO.
    const d = new Date(String(timeStr).trim().replace(' ', 'T'));
    if (!isNaN(d.getTime())) return d;
  }

  // SECURITY/idempotência (auditoria H1): NUNCA usar now() aqui. now() (a) viola
  // "preservar o occurredAt ORIGINAL" e (b) — quando o evento não traz RecNo —
  // vazava para o hash do eventId (buildEventId), gerando um id DIFERENTE a cada
  // re-entrega → presença DUPLICADA. Retornar null (igual zkteco/controlid): o
  // núcleo audita como 'bad_time' (sem presença) e o eventId fica 100% derivado
  // do conteúdo (estável em re-entregas). Raro: o raw fica gravado p/ reconciliar.
  return null;
}

// ---------------------------------------------------------------------------
// eventId determinístico e estável (repete igual em re-entregas do MESMO evento).
// ---------------------------------------------------------------------------
function buildEventId(deviceId, recNo, ev, occurredAt, index) {
  const dev = deviceId || 'unknown';
  if (recNo != null && String(recNo).trim() !== '') {
    return dev + '_' + String(recNo).trim();
  }
  // Sem RecNo: hash determinístico do conteúdo identificador do evento. Inclui
  // occurredAt (ms) + userId + método/status + índice no lote p/ distinguir
  // eventos do mesmo POST. NÃO depende de now() — re-entrega gera o mesmo id.
  const userId = firstDefined(ev, ['UserID', 'UserId', 'userId', 'user_id']);
  const status = firstDefined(ev, ['Status', 'status']);
  const methodV = firstDefined(ev, ['Method', 'method']);
  const card = firstDefined(ev, ['CardNo', 'cardNo', 'cardno']);
  const basis = [
    occurredAt instanceof Date && !isNaN(occurredAt.getTime()) ? occurredAt.getTime() : '',
    userId, status, methodV, card, index,
  ].join('|');
  return dev + '_h' + djb2Hex(basis);
}

// Hash determinístico simples (djb2) — evita dependência de crypto neste módulo
// puro; só precisa ser estável e bem-distribuído p/ doc-id de dedupe.
function djb2Hex(str) {
  let h = 5381;
  const s = String(str);
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.charCodeAt(i)) >>> 0; // h*33 + c, unsigned 32-bit
  }
  return h.toString(16).padStart(8, '0');
}

// ---------------------------------------------------------------------------
// raw recortado p/ auditoria. Remove blobs grandes (foto base64) se vierem no
// objeto, mantém os campos de evento + um trecho do texto cru p/ field-confirm.
// ---------------------------------------------------------------------------
function redactRaw(ev, rawText) {
  const HEAVY = new Set([
    'PhotoData', 'FaceData', 'Picture', 'Image', 'Snap', 'photo', 'image',
  ]);
  const slim = {};
  for (const key of Object.keys(ev || {})) {
    if (HEAVY.has(key)) {
      slim[key] = '<omitted>';
      continue;
    }
    const v = ev[key];
    if (typeof v === 'string' && v.length > 512) {
      slim[key] = v.slice(0, 512) + '…<truncated>';
    } else {
      slim[key] = v;
    }
  }
  // Amostra do texto cru (sem a parte de imagem) p/ confirmar shape em campo.
  if (typeof rawText === 'string') {
    slim._rawSample = rawText.length > 1024 ? rawText.slice(0, 1024) + '…' : rawText;
  }
  return slim;
}

// ---------------------------------------------------------------------------
// utils
// ---------------------------------------------------------------------------
function headerOf(headers, name) {
  if (!headers) return '';
  const lower = name.toLowerCase();
  if (headers[lower] != null) return String(headers[lower]);
  for (const k of Object.keys(headers)) {
    if (k.toLowerCase() === lower) return String(headers[k]);
  }
  return '';
}

// Primeiro valor definido (não null/undefined/'') entre uma lista de chaves
// candidatas (tolera chave curta e pontilhada graças a flattenObject).
function firstDefined(obj, keys) {
  if (!obj) return undefined;
  for (const k of keys) {
    if (obj[k] != null && obj[k] !== '') return obj[k];
  }
  return undefined;
}

module.exports = parse;
module.exports.parse = parse;
// expostos p/ teste/field-confirm (não usados pelo núcleo)
module.exports._internals = {
  extractEventText, extractEvents, parseOccurredAt, buildEventId,
  toAccessEvent, METHOD_TABLE, GRANTED_STATUS,
};
