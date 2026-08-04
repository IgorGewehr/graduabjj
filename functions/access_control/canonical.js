/**
 * access_control/canonical.js — FORMA CANÔNICA + CONTRATO DO ADAPTER
 * ============================================================================
 *
 * Módulo PURO (sem firebase-admin, sem I/O). Define:
 *   1. A forma do AccessEvent canônico (JSDoc typedef) que TODO adapter produz.
 *   2. Helpers de normalização (normalizeDirection / normalizeMethod).
 *   3. O CONTRATO documentado do adapter:  parse(req, device) -> AccessEvent[] | null
 *
 * Os adapters de fabricante (./adapters/controlid.js, ./adapters/zkteco.js,
 * ./adapters/intelbras.js) são os ÚNICOS lugares que conhecem o wire format de
 * cada device. O núcleo (./ingest.js) só conhece o AccessEvent canônico — assim
 * os fabricantes ficam isolados e plugáveis via REGISTRY estático.
 *
 * Arquitetura C (push-cloud): a catraca faz o match biométrico EMBARCADO e POSTa
 * o evento direto na Cloud Function. Este arquivo não toca rede nem Firestore.
 * ============================================================================
 */

'use strict';

// ---------------------------------------------------------------------------
// AccessEvent canônico
// ---------------------------------------------------------------------------
/**
 * Forma única que TODO adapter produz. O núcleo (`recordAccessEvent`) só conhece
 * esta forma. Um POST do device pode conter N eventos (Control iD
 * `object_changes[]`, ZKTeco rtlog multi-linha, Intelbras lote) → o adapter
 * SEMPRE retorna um array `AccessEvent[]` (pode ser vazio p/ heartbeat), nunca
 * um objeto único; ou `null` se o payload for irreconhecível.
 *
 * @typedef {Object} AccessEvent
 * @property {string}  deviceId        id do device NO NOSSO sistema (= doc id em
 *                                     academies/{academyId}/devices/{deviceId}).
 * @property {('controlid'|'zkteco'|'intelbras')} vendor  fabricante de origem.
 * @property {string}  externalUserId  id do usuário NO device (Control iD
 *                                     values.user_id, ZKTeco pin, Intelbras
 *                                     UserID). '0'/'' => não identificado: o
 *                                     adapter pode emitir com granted=false p/
 *                                     auditoria, mas o núcleo NÃO grava presença
 *                                     sem studentId resolvido.
 * @property {string}  eventId         id ESTÁVEL do evento p/ idempotência. Deve
 *                                     ser determinístico e repetir-se igual em
 *                                     re-entregas do MESMO evento (ex.:
 *                                     `${deviceId}_${seqIdNoDevice}`). Sem id
 *                                     nativo estável → hash do conteúdo. O núcleo
 *                                     deduplica por accessEvents/{deviceId}_{eventId}.
 * @property {Date}    occurredAt      timestamp ORIGINAL do evento (NUNCA now()).
 *                                     Control iD/Intelbras: epoch em SEGUNDOS
 *                                     (×1000). ZKTeco rtlog: string local SEM tz
 *                                     → aplicar device.tzOffsetMinutes antes de
 *                                     virar UTC.
 * @property {('in'|'out'|'unknown')}  direction  sentido do acesso.
 * @property {('face'|'finger'|'card'|'pin'|'unknown')} method  método de
 *                                     identificação (auditoria; não gateia
 *                                     presença).
 * @property {boolean} granted         TRUE só quando o código de evento do
 *                                     fabricante = ACESSO CONCEDIDO. Decide se há
 *                                     presença. O adapter preenche consultando
 *                                     sua tabela GRANTED_EVENT_CODES (field-confirm).
 * @property {(string|number)} eventCode  código bruto do fabricante (auditoria +
 *                                     base da regra `granted`).
 * @property {Object}  raw             payload bruto recortado p/ auditoria e
 *                                     field-confirm (gravado em accessEvents.raw).
 */

// ---------------------------------------------------------------------------
// Vocabulário canônico (valores válidos dos enums acima)
// ---------------------------------------------------------------------------
const VENDORS = Object.freeze(['controlid', 'zkteco', 'intelbras']);
const DIRECTIONS = Object.freeze(['in', 'out', 'unknown']);
const METHODS = Object.freeze(['face', 'finger', 'card', 'pin', 'unknown']);

// ---------------------------------------------------------------------------
// Helpers de normalização — usados pelos adapters p/ aterrar valores de
// fabricante no vocabulário canônico. Tolerantes a entrada suja (string/number/
// null) e SEMPRE retornam um valor canônico válido (default 'unknown').
// ---------------------------------------------------------------------------

/**
 * Normaliza o sentido do acesso p/ 'in' | 'out' | 'unknown'.
 * Aceita: 'in'/'out'/'entry'/'exit' (string, qualquer caixa) ou ZKTeco
 * inoutstatus numérico (0=in, 1=out). Qualquer outra coisa → 'unknown'.
 * ASSUMPTION: alguns firmwares ZKTeco usam 2/3 p/ leitoras auxiliares e podem
 * inverter 0/1 — confirmar no device-alvo (o adapter decide o mapeamento final).
 * @param {string|number|null} raw
 * @returns {('in'|'out'|'unknown')}
 */
function normalizeDirection(raw) {
  if (raw === null || raw === undefined) return 'unknown';
  if (typeof raw === 'number' || /^\d+$/.test(String(raw))) {
    const n = Number(raw);
    if (n === 0) return 'in';
    if (n === 1) return 'out';
    return 'unknown';
  }
  const s = String(raw).trim().toLowerCase();
  if (s === 'in' || s === 'entry' || s === 'entrada') return 'in';
  if (s === 'out' || s === 'exit' || s === 'saida' || s === 'saída') return 'out';
  return 'unknown';
}

/**
 * Normaliza o método de identificação p/ 'face'|'finger'|'card'|'pin'|'unknown'.
 * Aceita um rótulo string ('face', 'fingerprint', 'cartao'...) já mapeado pelo
 * adapter, OU um código numérico de fabricante via tabela opcional.
 *
 * IMPORTANTE: a numeração de método (verifytype ZKTeco, Method Intelbras,
 * identifier_id Control iD) VARIA por fabricante/firmware. Esta função NÃO
 * embute a tabela de nenhum vendor — ela só aterra rótulos canônicos. Cada
 * adapter deve traduzir seu código próprio p/ um destes rótulos (ou passar a
 * própria tabela em `vendorTable`) marcando ASSUMPTION/TODO de field-confirm.
 *
 * @param {string|number|null} raw  rótulo ou código de método.
 * @param {Object<string,string>} [vendorTable]  mapa opcional código→rótulo do
 *        adapter (ex.: { '15': 'face', '1': 'finger' }). Consultado se `raw`
 *        for numérico.
 * @returns {('face'|'finger'|'card'|'pin'|'unknown')}
 */
function normalizeMethod(raw, vendorTable) {
  if (raw === null || raw === undefined || raw === '') return 'unknown';
  // Código numérico → tenta a tabela do adapter primeiro.
  if (vendorTable && (typeof raw === 'number' || /^\d+$/.test(String(raw)))) {
    const mapped = vendorTable[String(raw)];
    if (mapped) return coerceMethodLabel(mapped);
  }
  return coerceMethodLabel(raw);
}

/** Aterra um rótulo livre no enum canônico de método. */
function coerceMethodLabel(label) {
  const s = String(label).trim().toLowerCase();
  if (s.includes('face') || s.includes('facial') || s.includes('rosto')) return 'face';
  if (s.includes('finger') || s.includes('digital') || s.includes('fp') ||
      s.includes('biometr')) return 'finger';
  if (s.includes('card') || s.includes('cartao') || s.includes('cartão') ||
      s.includes('rfid')) return 'card';
  if (s.includes('pin') || s.includes('pass') || s.includes('senha')) return 'pin';
  if (METHODS.includes(s)) return s;
  return 'unknown';
}

// ---------------------------------------------------------------------------
// CONTRATO DO ADAPTER  (para os agentes que implementarem ./adapters/<vendor>.js)
// ---------------------------------------------------------------------------
/**
 * Cada adapter de fabricante exporta UMA função:
 *
 *     parse(req, device) -> AccessEvent[] | null
 *
 * ENTRADA
 * -------
 * @param req  Objeto recortado pelo NÚCLEO (já leu o corpo CRU; o adapter NÃO
 *             toca a rede). Forma:
 *               {
 *                 rawBody : string,   // corpo CRU (necessário p/ parsers não-JSON
 *                                     //   e p/ o núcleo já ter validado o HMAC)
 *                 query   : object,   // req.query (ex.: ?table=rtlog, ?acad=, SN)
 *                 headers : object,   // req.headers (lower-case keys)
 *                 method  : string,   // 'POST' | 'GET' (heartbeat/handshake)
 *                 path    : string,   // sub-path do evento: Control iD '/dao' |
 *                                     //   '/catra_event' | '/device_is_alive';
 *                                     //   ZKTeco '/iclock/cdata'. O adapter
 *                                     //   roteia internamente por aqui.
 *               }
 * @param device  O doc `academies/{academyId}/devices/{deviceId}` JÁ CARREGADO
 *                pelo núcleo. Dá ao adapter, sem novo read:
 *                  - vendor
 *                  - userMap            { [externalUserId]: studentId }  (info; o
 *                                       núcleo é quem resolve studentId — o
 *                                       adapter NÃO precisa)
 *                  - portalDirection    { [portalId]: 'in'|'out' }  (Control iD)
 *                  - tzOffsetMinutes    (ZKTeco: hora local sem tz)
 *                  - grantOn            'authorization'|'turn' (iDBlock)  [TODO]
 *
 * SAÍDA
 * -----
 * @returns {AccessEvent[]|null}
 *   - `AccessEvent[]`  um por evento de acesso reconhecido (pode ser VAZIO `[]`
 *     se o POST for heartbeat/giro irrelevante — o núcleo simplesmente ACKa).
 *   - `null`  se o payload for IRRECONHECÍVEL p/ este vendor (o núcleo loga e
 *     responde o ACK do fabricante mesmo assim, p/ não causar re-entrega).
 *
 * RESPONSABILIDADES do adapter (e SÓ estas)
 * -----------------------------------------
 *   - Rotear por `path`/`query` (sub-evento do fabricante).
 *   - Extrair externalUserId, eventId, occurredAt (ORIGINAL), eventCode.
 *   - Resolver `direction` e `method` (mapeando códigos do fabricante; pode usar
 *     normalizeDirection/normalizeMethod e device.portalDirection/tzOffsetMinutes).
 *   - Preencher `granted` consultando a SUA tabela GRANTED_EVENT_CODES (constante
 *     local do adapter, marcada TODO/field-confirm por vendor/firmware).
 *   - Recortar `raw` p/ auditoria.
 *
 * O adapter NÃO resolve studentId (isso é device.userMap[externalUserId], feito
 * pelo NÚCLEO), NÃO grava nada no Firestore, NÃO valida HMAC (já feito pelo
 * núcleo) e NÃO escreve a resposta HTTP (o contrato de resposta por fabricante —
 * "OK" texto p/ ZKTeco, JSON {auth} p/ Intelbras, 200 p/ Control iD — é do núcleo).
 *
 * @callback AccessAdapterParse
 * @param {{rawBody:string, query:object, headers:object, method:string, path:string}} req
 * @param {object} device
 * @returns {AccessEvent[]|null}
 */

module.exports = {
  // enums / vocabulário canônico
  VENDORS,
  DIRECTIONS,
  METHODS,
  // helpers de normalização (puros)
  normalizeDirection,
  normalizeMethod,
};
