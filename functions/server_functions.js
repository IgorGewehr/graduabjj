/**
 * Server-side Cloud Functions migrated from the (discontinued) ERP web repo.
 *
 * These were previously deployed from arpbjj-erp/functions/src/index.ts under
 * the same "default" codebase as this repo. Because both repos shared the
 * codebase, deploying from one wiped the other's functions — which is how the
 * payment functions got deleted. They now live here so the mobile repo is the
 * single source of truth for ALL Cloud Functions.
 *
 * Kept on the firebase-functions v1 (gen1) API to preserve the exact prior
 * behaviour. They coexist with the gen2 functions in index.js (no name
 * collisions). The default Admin app is initialized by index.js, which requires
 * this module AFTER initializeApp().
 *
 * Runtime env: ABACATEPAY_API_KEY (from functions/.env).
 */

const functions = require('firebase-functions/v1');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const crypto = require('crypto');

const db = admin.firestore();
const messaging = admin.messaging();

// Gen1 triggers/schedules that create stable links must opt in to the link
// secret explicitly. WhatsApp stays disabled until its provider credential is
// explicitly provisioned; an absent optional channel must not block a safe
// deployment of settlement, email and Pay Link code.
const MP_MKT_SECRETS = ['MP_OAUTH_CLIENT_ID', 'MP_OAUTH_CLIENT_SECRET'];
const BILLING_NOTIFICATION_SECRETS = [
  ...MP_MKT_SECRETS,
  'PUBLIC_PAY_TOKEN_SECRET',
];
const PUBLIC_PAY_SECRETS = [
  'MP_OAUTH_CLIENT_ID',
  'MP_OAUTH_CLIENT_SECRET',
  'PUBLIC_PAY_TOKEN_SECRET',
];

// ---- Catraca / ingestão de acesso (Arquitetura C) --------------------------
// A CF `ingestAccessEvent` é exportada por index.js a partir de
// ./access_control/ingest.js (implementação ÚNICA, com check-in por turma + gate
// de inadimplência, revisada). NÃO duplicar aqui (evita export conflitante).

// Definição CANÔNICA de "vencido" (BR wall-clock), compartilhada com o gate de
// inadimplência da catraca (access_control/financial_gate.js). Fonte ÚNICA da
// verdade: cron de cobrança e portão NUNCA discordam de quem está em atraso.
const { isOverdueBR, daysOverdueBR } = require('./access_control/overdue_util');
const {
  BillingPaymentMode,
  resolveBillingPaymentInstruction,
} = require('./billing_payment_resolver');
const {
  billingDateAtStartOfDay,
  datePartsInBillingTimeZone,
  findConflictingStudentIds,
  isMembershipEligibleForMonth,
} = require('./billing_tuition_rules');
const {
  buildBillingTemplatePayload,
  normalizeTemplateStage,
  templateNameFor,
} = require('./billing_whatsapp_templates');
const {
  ManualPixConfirmationDecision,
  classifyManualPixConfirmation,
  classifyMercadoPagoCancellation,
} = require('./manual_pix_confirmation');
const {
  CHECKOUT_TTL_MS,
  decryptPublicToken,
  encryptPublicToken,
  generatePublicToken,
  hashPublicToken,
  isReusableAttempt,
  isValidPublicToken,
  isValidRequestId,
  publicAvailableMethods,
  publicAttemptStatusFromProvider,
  publicChargeStatus,
} = require('./public_payment_link');

// ============================================
// Helper Functions
// ============================================

async function getUserTokens(userId) {
  const tokensSnapshot = await db
    .collection('users')
    .doc(userId)
    .collection('fcmTokens')
    .get();

  return tokensSnapshot.docs.map((doc) => doc.data().token);
}

// ---------------------------------------------------------------------------
// Gate de preferências do aluno (fix jul/2026: "prefs eram placebo" — nenhum
// sender deste arquivo consultava users/{uid}.notificationPrefs antes de
// mandar push). Mesma filosofia de push_functions.js:sendPushIfAllowed —
// mapa de categoria → chave PT-BR gravada por
// lib/screens/portal/notification_prefs_screen.dart —, MAS só entra em ação
// quando o chamador marca `data.category` explicitamente. A esmagadora
// maioria dos usos de sendToUser aqui é notificação a ADMIN/professor (sem
// toggle nenhum na UI) ou callables genéricas onde o admin decide o próprio
// conteúdo; sem category, o comportamento é IDÊNTICO ao de sempre (sempre
// envia) — cobre a exigência de não quebrar push de admin/professor sem
// precisar tocar em cada call site individualmente.
//
// 'financial' (cobrança) NÃO está no mapa de propósito: a tela mostra
// "Cobrancas e pagamentos sao sempre notificados" com switch fixo/desabilitado
// — cobrança nunca é filtrada por preferência, em nenhum dos dois canais de
// push (aqui ou push_functions.js). Os senders de cobrança abaixo marcam
// `category: 'financial'` mesmo assim, só para documentar a decisão no
// payload — o gate abaixo trata como não-gateável (equivalente a não marcar).
const CATEGORY_PREF_KEY = { social: 'social', training: 'treino', academy: 'academia' };

/**
 * true se o push da `category` deve ser DROPADO por preferência do aluno
 * (campo ausente = permitido — mesma semântica de push_functions.js).
 * Categorias fora do mapa (ex.: 'financial', ou nenhuma) nunca são
 * filtradas. Fail-open em erro de leitura: melhor 1 push a mais do que
 * quebrar um sender de cobrança por instabilidade transitória do Firestore.
 */
async function isOptedOutOfCategory(userId, category) {
  const prefKey = CATEGORY_PREF_KEY[category];
  if (!prefKey) return false;
  try {
    const snap = await db.collection('users').doc(userId).get();
    const prefs = (snap.exists && (snap.data() || {}).notificationPrefs) || {};
    return prefs[prefKey] === false;
  } catch (e) {
    console.warn(`[sendToUser] leitura de prefs falhou uid=${userId}:`, e.message);
    return false;
  }
}

async function sendToUser(userId, title, body, data) {
  const category = data && data.category;
  if (category && (await isOptedOutOfCategory(userId, category))) {
    console.log(`[push] drop (prefs opt-out categoria '${category}') uid=${userId}`);
    return false;
  }

  const tokens = await getUserTokens(userId);
  if (tokens.length === 0) {
    console.log(`No FCM tokens found for user: ${userId}`);
    return false;
  }

  const message = {
    notification: { title, body },
    data: data || {},
    tokens,
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
    console.log(
      `Push notification sent to ${response.successCount}/${tokens.length} devices for user ${userId}`
    );

    // Clean up invalid tokens
    if (response.failureCount > 0) {
      const deletePromises = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const errorCode = resp.error?.code;
          if (
            errorCode === 'messaging/invalid-registration-token' ||
            errorCode === 'messaging/registration-token-not-registered'
          ) {
            deletePromises.push(
              db
                .collection('users')
                .doc(userId)
                .collection('fcmTokens')
                .doc(tokens[idx])
                .delete()
                .then(() => {
                  console.log(`Removed invalid token ${tokens[idx]} for user ${userId}`);
                })
            );
          }
        }
      });
      await Promise.all(deletePromises);
    }

    return response.successCount > 0;
  } catch (error) {
    console.error('Error sending push notification:', error);
    return false;
  }
}

async function sendToTopic(topic, title, body, data) {
  const message = {
    notification: { title, body },
    data: data || {},
    topic,
  };

  try {
    const response = await messaging.send(message);
    console.log(`Push notification sent to topic ${topic}: ${response}`);
    return true;
  } catch (error) {
    console.error('Error sending push notification to topic:', error);
    return false;
  }
}

async function getStudentUserId(studentId, academyId) {
  // Auditoria (MED correctness/custo): antes esta função VARRIA a coleção
  // userAcademyMapping INTEIRA (uma leitura por usuário da plataforma toda) a
  // cada chamada — chamada N vezes por run de cron => O(usuarios × cobranças).
  // O ponteiro reverso aluno→usuário já existe no próprio doc do aluno
  // (linkedUserId), então lemos PRIMEIRO o doc do aluno (1 leitura direta).
  let student = null;
  try {
    const studentDoc = await db
      .collection('academies')
      .doc(academyId)
      .collection('students')
      .doc(studentId)
      .get();
    student = studentDoc.exists ? (studentDoc.data() || null) : null;
  } catch (_) {
    // segue sem quebrar — tenta o fallback abaixo
  }

  if (student && student.linkedUserId) return student.linkedUserId;

  // Fallback (dados legados sem linkedUserId no aluno): tenta o índice reverso
  // direto pela própria conta do aluno, se o doc do aluno apontar para um uid
  // candidato. Sem um índice reverso por studentId, evitamos a varredura da
  // coleção inteira e simplesmente seguimos sem uid (o cron faz null-guard e
  // não quebra a base toda por um aluno sem conta vinculada).
  return null;
}

// Billing recipient for a student's charges: the responsible adult (kids ->
// adult) when set on the student doc, otherwise the student's own linked user.
async function getBillingRecipientUid(studentId, academyId) {
  try {
    const stuSnap = await db
      .collection('academies').doc(academyId)
      .collection('students').doc(studentId)
      .get();
    const resp = stuSnap.exists ? stuSnap.data()?.responsibleUserId : null;
    if (resp) return resp;
  } catch (e) {
    // fall through to the student's own user
  }
  return getStudentUserId(studentId, academyId);
}

// ============================================
// S7 — Server-side autonomous WhatsApp + PIX billing reminders
// ============================================
//
// This whole block is INERT until the WHATSAPP_API_KEY secret/env var is set.
// The gate lives in sendWhatsAppTemplateServer(): with no key it returns immediately
// WITHOUT performing any network call, so wiring it into the crons is safe to
// ship disabled. The owner sets WHATSAPP_API_KEY later to turn it on.
//
// NOTE on env vars: these crons are firebase-functions v1 (functions.pubsub),
// so process.env.WHATSAPP_API_KEY is populated from functions config / the
// functions/.env file at runtime and reading it at call-time works. If these
// were migrated to v2 (onSchedule), the key would instead need to be declared
// via { secrets: ['WHATSAPP_API_KEY', ...] } on the function and injected by
// Secret Manager. For v1, WHATSAPP_API_KEY MUST be provided via functions
// config / .env (same mechanism as NOTIFICATION_API_KEY in index.js).

// ---- 1. Gated Meta-template sender (the inert switch) --------------------
// GATE: with no WHATSAPP_API_KEY, returns {sent:false, skipped:'no_key'}
// without calling anything. No academy-editable WhatsApp text crosses this
// boundary: billing copy is identified by templateName and variables.
async function sendWhatsAppTemplateServer(phone, academyId, templatePayload) {
  // The current Firebase project provides the shared notification-server key
  // through functions/.env. Keep a dedicated WhatsApp key as an optional
  // override, but do not require a second credential for the same provider.
  const key = process.env.WHATSAPP_API_KEY || process.env.NOTIFICATION_API_KEY;
  if (!key) {
    return { sent: false, skipped: 'no_key' };
  }
  const legacyUrl = process.env.WHATSAPP_API_URL ||
    'https://notification.tensorroot.com/api/send-whatsapp';
  const url = process.env.WHATSAPP_TEMPLATE_API_URL || legacyUrl.replace(
    /\/api\/send-whatsapp\/?$/,
    '/api/send-whatsapp-template'
  );
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': key,
      },
      body: JSON.stringify({
        appId: process.env.WHATSAPP_APP_ID || 'gestao-raiz',
        tenantId: academyId,
        phone,
        templateName: templatePayload.templateName,
        languageCode: process.env.WHATSAPP_TEMPLATE_LANG || 'pt_BR',
        variables: templatePayload.variables,
        ...(templatePayload.buttonUrl
          ? { buttonUrl: templatePayload.buttonUrl }
          : {}),
        type: 'billing_reminder',
      }),
    });
    // Auditoria (idempotência/precisão): só considera 'sent' com a CONFIRMAÇÃO
    // no corpo da resposta (body.success===true), não apenas res.ok — um proxy
    // pode devolver 200 com {success:false} (número inválido, fila cheia) e
    // marcar 'sent' indevidamente suprimiria o reenvio do lembrete de cobrança.
    if (!res.ok) return { sent: false };
    let body = null;
    try { body = await res.json(); } catch (_) { body = null; }
    if (body && body.success === true) {
      return {
        sent: true,
        provider: body.provider || 'unknown',
        wamid: body.wamid || null,
      };
    }
    return { sent: false, skipped: 'not_confirmed' };
  } catch (e) {
    console.error('[S7] sendWhatsAppTemplateServer failed:', e && e.message);
    return { sent: false };
  }
}

// ---- 1b. Phone normalization (port of Dart _normalizePhone) --------------
// Auditoria (LOW): o proxy de WhatsApp espera o número só com dígitos e prefixo
// 55 (Brasil). Normaliza no SERVIDOR antes de enviar (não confia no formato
// gravado no cadastro). Retorna '' quando não há dígitos.
function normalizePhoneServer(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits === '') return '';
  return digits.startsWith('55') ? digits : `55${digits}`;
}

// ---- 2. PIX block resolver (JS port of Dart injectPaymentInfo) -----------
// If pixCode present: substitute {pix}/{link} and strip the [[PIX]] markers.
// Else: remove the whole [[PIX]]..[[/PIX]] block. Always safety-strips leftover
// markers/placeholders, collapses 3+ newlines to 2, and trims.
function mpInjectPaymentInfo(text, pixCode, ticketUrl) {
  const has = pixCode != null && pixCode !== '';
  let out = String(text || '');
  if (has) {
    out = out
      .split('{pix}').join(pixCode)
      .split('{link}').join(ticketUrl || '')
      .split('[[PIX]]').join('')
      .split('[[/PIX]]').join('');
  } else {
    out = out.replace(/\[\[PIX\]\][\s\S]*?\[\[\/PIX\]\]/g, '');
  }
  // Safety net: never leak raw markers/placeholders.
  out = out
    .split('[[PIX]]').join('')
    .split('[[/PIX]]').join('')
    .split('{pix}').join('')
    .split('{link}').join('');
  // Tidy excess blank lines left by a removed block.
  out = out.replace(/\n{3,}/g, '\n\n').trim();
  return out;
}

// ---- 3. Default WhatsApp templates (ported from the Dart defaults) -------
// Includes the [[PIX]]..[[/PIX]] block resolved by mpInjectPaymentInfo.
// Placeholders: {nome}, {valor}, {vencimento}, {dias}, {academia}.
const DEFAULT_WHATSAPP_TEMPLATES = {
  'CREATED': 'Oi {nome}! Uma nova parcela de {valor} da {academia} ja esta disponivel, com vencimento em {vencimento}.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'UPCOMING': 'Oi {nome}! Sua parcela de {valor} da {academia} vence em {diasAteVencimento} dia(s), em {vencimento}.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+0': 'Oi {nome}! Passando rapidinho para lembrar que hoje, dia {vencimento}, vence sua mensalidade de {valor} com a {academia}. Contamos com voce! Qualquer duvida, estamos a disposicao.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+1': 'Ola {nome}! Aqui e a {academia}. Identificamos que sua mensalidade de {valor} venceu em {vencimento}. Caso ja tenha efetuado o pagamento, por favor desconsidere esta mensagem. Caso contrario, solicitamos a regularizacao. Obrigado![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+3': 'Ola {nome}! Sua mensalidade de {valor} da {academia} esta com 3 dias de atraso (vencimento: {vencimento}). Por favor, regularize sua situacao o mais breve possivel. Em caso de duvidas, estamos a disposicao![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+7': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Precisamos que regularize sua situacao para manter seus treinos em dia. Entre em contato conosco para combinar o pagamento.[[PIX]]\n\nPara facilitar, pague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+15': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Sua situacao precisa ser regularizada com urgencia para evitar a suspensao do acesso aos treinos. Por favor, entre em contato.[[PIX]]\n\nRegularize agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+30': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com mais de 30 dias de atraso. Caso a situacao nao seja regularizada, infelizmente precisaremos suspender seu acesso. Entre em contato urgente para negociarmos.[[PIX]]\n\nRegularize agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
};

// Auditoria (LOW ux): a régua de "mensalidade atrasada" (com ameaça de
// suspensão de acesso a partir de D+15/D+30) só faz sentido para
// type=='monthly_tuition'. Cobranças avulsas (aula particular, loja, etc.) usam
// um wording próprio, mais leve, SEM ameaça de suspensão — suspender o acesso
// por uma aula avulsa não paga não é a política. Mesmos placeholders.
const DEFAULT_WHATSAPP_TEMPLATES_GENERIC = {
  'CREATED': 'Oi {nome}! Uma nova cobranca de {valor} ({descricao}) da {academia} ja esta disponivel, com vencimento em {vencimento}.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'UPCOMING': 'Oi {nome}! Sua cobranca de {valor} ({descricao}) da {academia} vence em {diasAteVencimento} dia(s), em {vencimento}.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+0': 'Oi {nome}! Passando para lembrar que hoje, dia {vencimento}, vence sua cobranca de {valor} ({descricao}) com a {academia}. Qualquer duvida, estamos a disposicao.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+1': 'Ola {nome}! Aqui e a {academia}. Identificamos que sua cobranca de {valor} ({descricao}) venceu em {vencimento}. Caso ja tenha pago, desconsidere. Caso contrario, pedimos a regularizacao. Obrigado![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+3': 'Ola {nome}! Sua cobranca de {valor} ({descricao}) da {academia} esta com 3 dias de atraso (vencimento: {vencimento}). Quando puder, regularize. Em caso de duvidas, estamos a disposicao![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+7': 'Ola {nome}, sua cobranca de {valor} ({descricao}) da {academia} esta com {dias} dias de atraso. Quando possivel, entre em contato para combinar o pagamento.[[PIX]]\n\nPara facilitar, pague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+15': 'Ola {nome}, sua cobranca de {valor} ({descricao}) da {academia} esta com {dias} dias de atraso. Por favor, entre em contato para regularizarmos.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+30': 'Ola {nome}, sua cobranca de {valor} ({descricao}) da {academia} segue em aberto ha mais de 30 dias. Entre em contato para negociarmos.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
};

// Mirrors the Dart _applyTemplate replaceAll (all occurrences).
function applyBillingTemplate(tpl, {
  nome, valor, vencimento, dias, diasAteVencimento, academia, descricao
}) {
  return String(tpl || '')
    .split('{nome}').join(nome != null ? String(nome) : '')
    .split('{valor}').join(valor != null ? String(valor) : '')
    .split('{vencimento}').join(vencimento != null ? String(vencimento) : '')
    .split('{dias}').join(dias != null ? String(dias) : '')
    .split('{diasAteVencimento}').join(
      diasAteVencimento != null ? String(diasAteVencimento) : ''
    )
    .split('{academia}').join(academia != null ? String(academia) : '')
    // Auditoria: placeholder usado pelos templates genéricos (não-mensalidade).
    .split('{descricao}').join(descricao != null ? String(descricao) : '');
}

// ---- 4. Stage resolver (mirrors Dart _classifyStage thresholds) ----------
// 0->'D+0', 1-2->'D+1', 3-6->'D+3', 7-14->'D+7', 15-29->'D+15', >=30->'D+30'.
function resolveStage(daysOverdue) {
  if (daysOverdue >= 30) return 'D+30';
  if (daysOverdue >= 15) return 'D+15';
  if (daysOverdue >= 7) return 'D+7';
  if (daysOverdue >= 3) return 'D+3';
  if (daysOverdue >= 1) return 'D+1';
  return 'D+0';
}

// ---- formatting helpers (mirror Dart NumberFormat / DateFormat) ----------
// {valor}: R$ X,XX (pt-BR). amountReais is in REAIS.
function formatBrlAmount(amountReais) {
  const n = Number(amountReais) || 0;
  return 'R$ ' + n.toFixed(2).replace('.', ',');
}

// {vencimento}: dd/MM/yyyy.
function formatBrDate(date) {
  const d = date instanceof Date ? date : new Date(date);
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

// Detecção de vencido (isOverdueBR / daysOverdueBR) movida para o util
// compartilhado access_control/overdue_util.js — fonte ÚNICA da verdade com o
// gate de inadimplência da catraca. Importadas no topo deste arquivo.

// ---- 5. Stable MyDojo payment link ---------------------------------------
// Reminder delivery creates only this opaque URL. Mercado
// Pago is contacted exclusively by startPublicCheckout after a human click.
function publicPayBaseUrl() {
  return String(
    process.env.PUBLIC_PAY_BASE_URL ||
    process.env.APP_BASE_URL ||
    'https://arpjj-76350.web.app'
  ).replace(/\/$/, '');
}

function publicPaySecret() {
  const secret = process.env.PUBLIC_PAY_TOKEN_SECRET || '';
  if (secret.length < 32) {
    throw new HttpsError(
      'failed-precondition',
      'Pagamento publico nao configurado no backend.'
    );
  }
  return secret;
}

async function loadActivePublicPaymentToken(linkHash) {
  if (!/^[a-f0-9]{64}$/.test(String(linkHash || ''))) return null;
  const snapshot = await db.doc(`publicPaymentLinks/${linkHash}`).get();
  if (!snapshot.exists || snapshot.data()?.status !== 'active') return null;
  try {
    const rawToken = decryptPublicToken(snapshot.data(), publicPaySecret());
    if (!isValidPublicToken(rawToken) || hashPublicToken(rawToken) !== linkHash) {
      return null;
    }
    return { rawToken, record: snapshot.data() };
  } catch (_) {
    return null;
  }
}

async function getOrCreatePublicPaymentLink(academyId, financialId) {
  assertSafeDocumentId(academyId, 'academyId');
  assertSafeDocumentId(financialId, 'financialId');
  const financialRef = db.doc(
    `academies/${academyId}/financials/${financialId}`
  );
  const firstSnapshot = await financialRef.get();
  if (!firstSnapshot.exists) {
    throw new HttpsError('not-found', 'Cobranca nao encontrada.');
  }
  const first = firstSnapshot.data() || {};
  if (!['pending', 'overdue'].includes(first.status) ||
      first.publicPaymentEnabled === false) {
    throw new HttpsError(
      'failed-precondition',
      'Esta cobranca nao aceita pagamento publico.'
    );
  }

  const previousHash = String(first.publicPaymentLinkHash || '');
  const previous = await loadActivePublicPaymentToken(previousHash);
  if (previous && previous.record.academyId === academyId &&
      previous.record.targetId === financialId) {
    return {
      rawToken: previous.rawToken,
      linkHash: previousHash,
      url: `${publicPayBaseUrl()}/p/${previous.rawToken}`,
    };
  }

  const rawToken = generatePublicToken();
  const linkHash = hashPublicToken(rawToken);
  const encrypted = encryptPublicToken(rawToken, publicPaySecret());
  const linkRef = db.doc(`publicPaymentLinks/${linkHash}`);
  const selectedHash = await db.runTransaction(async (tx) => {
    const liveSnapshot = await tx.get(financialRef);
    if (!liveSnapshot.exists) {
      throw new HttpsError('not-found', 'Cobranca nao encontrada.');
    }
    const live = liveSnapshot.data() || {};
    if (!['pending', 'overdue'].includes(live.status) ||
        live.publicPaymentEnabled === false) {
      throw new HttpsError(
        'failed-precondition',
        'Esta cobranca nao aceita pagamento publico.'
      );
    }
    const concurrentHash = String(live.publicPaymentLinkHash || '');
    if (concurrentHash && concurrentHash !== previousHash) return concurrentHash;

    tx.create(linkRef, {
      academyId,
      targetType: 'financial',
      targetId: financialId,
      status: 'active',
      financialVersion: Number(live.financialVersion) || 1,
      ...encrypted,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(financialRef, {
      publicPaymentLinkHash: linkHash,
      publicPaymentEnabled: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (previous && previous.record.academyId === academyId &&
        previous.record.targetId === financialId &&
        previousHash !== linkHash) {
      tx.set(db.doc(`publicPaymentLinks/${previousHash}`), {
        status: 'revoked',
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    return linkHash;
  });

  if (selectedHash === linkHash) {
    return { rawToken, linkHash, url: `${publicPayBaseUrl()}/p/${rawToken}` };
  }
  const concurrent = await loadActivePublicPaymentToken(selectedHash);
  if (!concurrent || concurrent.record.academyId !== academyId ||
      concurrent.record.targetId !== financialId) {
    throw new HttpsError('aborted', 'Tente gerar o link novamente.');
  }
  return {
    rawToken: concurrent.rawToken,
    linkHash: selectedHash,
    url: `${publicPayBaseUrl()}/p/${concurrent.rawToken}`,
  };
}

function billingMercadoPagoFailureCode(error) {
  const message = String(error?.message || '').toLowerCase();
  if (message.includes('missing_valid_pix_payer')) {
    return 'missing_payer_data';
  }
  if (message.includes('reconect') || message.includes('expir')) {
    return 'reconnect_required';
  }
  if (message.includes('chave pix') || message.includes('pix without qr')) {
    return 'seller_pix_unavailable';
  }
  return 'mercado_pago_unavailable';
}

// Creates or reuses the Mercado Pago PIX that is embedded in the approved
// billing templates. This runs only at send time: opening a preview never
// creates a provider payment. The financial document remains the idempotency
// boundary, so repeated reminders reuse the same live PIX.
async function generateReminderMercadoPagoPix(
  academyId,
  financial,
  { payerFallbackUid = null } = {}
) {
  const financialId = String(financial?.id || '');
  if (!financialId || financial?.paymentMethodPolicy === 'card_only') {
    throw new Error('financial_not_eligible_for_pix');
  }

  const financialRef = db.doc(
    `academies/${academyId}/financials/${financialId}`
  );
  const financialSnapshot = await financialRef.get();
  if (!financialSnapshot.exists) throw new Error('financial_not_found');
  const live = { id: financialId, ...(financialSnapshot.data() || {}) };
  if (!['pending', 'overdue'].includes(live.status)) {
    throw new Error('financial_not_collectible');
  }

  const amount = Number(live.amount) || 0;
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error('invalid_financial_amount');
  }

  const existingExpiry = live.pixExpiresAt &&
    typeof live.pixExpiresAt.toMillis === 'function'
    ? live.pixExpiresAt.toMillis() : 0;
  const existingAmountMatches = typeof live.pixAmount !== 'number' ||
    Math.abs(amount - live.pixAmount) <= 0.01;
  if (live.gatewayPaymentId && live.pixCode &&
      existingExpiry > Date.now() && existingAmountMatches) {
    return {
      pixCode: live.pixCode,
      ticketUrl: live.pixTicketUrl || '',
    };
  }

  const studentSnapshot = await db.doc(
    `academies/${academyId}/students/${live.studentId}`
  ).get();
  const student = studentSnapshot.exists ? (studentSnapshot.data() || {}) : {};
  const kids = student.category === 'kids';
  const cpf = String(
    kids ? (student.guardian?.cpf || student.cpf) : student.cpf
  ).replace(/\D/g, '');
  const email = String(
    kids ? (student.guardian?.email || student.email) : student.email
  ).trim();
  let resolvedEmail = email;
  if (!isValidBillingEmail(resolvedEmail)) {
    try {
      const recipientUid = await getBillingRecipientUid(
        live.studentId,
        academyId
      );
      if (recipientUid) {
        const authUser = await admin.auth().getUser(recipientUid);
        resolvedEmail = String(authUser.email || '').trim();
      }
    } catch (_) {
      // The personal PIX resolver remains the safe fallback below.
    }
  }
  // Compatibility with the pre-migration manual flow: MercadoPagoService used
  // FirebaseAuth.currentUser.email, so the staff member sending the reminder
  // supplied the required payer e-mail implicitly. Preserve that behavior only
  // for an authenticated MANUAL dispatch. Scheduled sends never borrow a staff
  // e-mail and keep the configured personal-PIX/no-payment fallback instead.
  if (!isValidBillingEmail(resolvedEmail) && payerFallbackUid) {
    try {
      const authUser = await admin.auth().getUser(payerFallbackUid);
      resolvedEmail = String(authUser.email || '').trim();
    } catch (_) {
      // The personal PIX resolver remains the safe fallback below.
    }
  }
  if (!validateCPF(cpf) || !isValidBillingEmail(resolvedEmail)) {
    throw new Error('missing_valid_pix_payer');
  }

  // A live PIX minted for an old amount must not remain payable beside the
  // replacement. Cancel it before acquiring the new mint lock.
  if (typeof live.pixAmount === 'number' &&
      Math.abs(amount - live.pixAmount) > 0.01 &&
      live.gatewayPaymentId && live.pixCode) {
    await mpCancelPixPayment(academyId, live.gatewayPaymentId, {});
  }

  const mint = await mpAcquirePixMint(
    financialRef,
    'billing-reminder',
    amount
  );
  if (mint.reuse) {
    return {
      pixCode: mint.reuse.pixCode,
      ticketUrl: mint.reuse.pixTicketUrl || '',
    };
  }

  let pix;
  try {
    pix = await createMpPix({
      academyId,
      transactionAmount: amount,
      description: sanitizeString(live.description) || 'Mensalidade',
      externalReference: `${academyId}:fin:${financialId}`,
      payer: {
        email: resolvedEmail,
        cpf,
        name: student.fullName || live.studentName || 'Aluno',
      },
    });
  } catch (error) {
    await mpReleasePixMint(financialRef);
    throw error;
  }

  const expiresAt = admin.firestore.Timestamp.fromDate(pix.expiresAt);
  await financialRef.update({
    gatewayPaymentId: pix.paymentId,
    paymentGateway: 'mercadopago',
    pixCode: pix.pixCode,
    pixQrCode: pix.qrCodeBase64 || null,
    pixTicketUrl: pix.ticketUrl || null,
    pixExpiresAt: expiresAt,
    pixAmount: amount,
    pixMintAt: admin.firestore.FieldValue.delete(),
    pixMintBy: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {
    pixCode: pix.pixCode,
    ticketUrl: pix.ticketUrl || '',
  };
}

// ---- 6. Orchestrator: resolve + send one Meta billing template -----------
// GATES: billingSettings.whatsappEnabled !== false; recipient phone present
// (kids -> guardian.phone else phone, mirroring effectivePhone). Payment mode
// is resolved centrally: MP, personal PIX, or no payment instructions.
// NEVER throws.
//
// `stage` is 'D+0'..'D+30'. `daysOverdue` defaults to 0 for the due-soon cron.
async function sendBillingReminderWhatsApp(
  academyId,
  academyName,
  billingSettings,
  financial,
  stage,
  daysOverdue,
  options = {}
) {
  try {
    const settings = billingSettings || {};
    const manual = options.manual === true;
    // AUDITORIA (opt-in explícito): o gate era `=== false`, o que trata o
    // doc AUSENTE (settings/billingReminders nunca salvo) como LIGADO. O
    // cliente (BillingReminderService.getNotificationSettings) faz o oposto:
    // default whatsappEnabled=false quando o doc não existe. Enquanto
    // WHATSAPP_API_KEY estava vazia isso era inofensivo (sendWhatsAppTemplateServer
    // nunca disparava); assim que a chave for configurada, TODAS as
    // academias sem settings salvos passariam a receber WhatsApp automático
    // sem nunca terem optado. `!== true` alinha o server com o default do
    // cliente: só envia para quem opt-in explicitamente.
    if (!manual && settings.whatsappEnabled !== true) {
      return { sent: false, skipped: 'automation_disabled' };
    }

    // Resolve recipient phone from the student doc (effectivePhone semantics).
    // Auditoria (LGPD): respeita o opt-out POR ALUNO (whatsappOptOut===true) —
    // o gate por academia (settings.whatsappEnabled) continua acima; este é o
    // consentimento individual do aluno. Quando o aluno pediu para não receber
    // WhatsApp, não envia (o push/notificação interna continua no cron).
    let phone = options.phoneOverride || '';
    try {
      if (!phone) {
        const stuSnap = await db
          .collection('academies').doc(academyId)
          .collection('students').doc(financial.studentId)
          .get();
        if (stuSnap.exists) {
          const stu = stuSnap.data() || {};
          if (stu.whatsappOptOut === true) {
            return { sent: false, skipped: 'recipient_opt_out' };
          }
          phone = stu.category === 'kids' ? stu.guardian?.phone : stu.phone;
        }
      }
    } catch (_) {
      // no phone -> gate below
    }
    // Auditoria (LOW): normaliza no servidor (dígitos + prefixo 55) antes de
    // mandar ao proxy, em vez de confiar no formato gravado no cadastro.
    phone = normalizePhoneServer(phone);
    if (!phone) return { sent: false, skipped: 'missing_phone' };

    // Stage-level dedup: each reminder stage (D+0, D+1, D+3, ...) goes out at
    // most once per charge, so a charge sitting overdue (or due-soon) for days
    // doesn't WhatsApp the student every single day the cron runs. Only an
    // actual send marks the stage as covered (below), so an INERT run with no
    // WHATSAPP_API_KEY still delivers once the key is later configured.
    if (!manual && financial.lastReminderStage === stage) {
      return { sent: false, skipped: 'already_sent' };
    }

    // Monthly tuition has approved templates only for D+0..D+30. One-time
    // charges additionally support creation/upcoming through their generic
    // open/pending template families.
    const chargeType = financial.type || 'monthly_tuition';
    if (!templateNameFor(stage, BillingPaymentMode.NONE, chargeType)) {
      console.log(`[S7] WhatsApp skipped: no approved Meta template for stage=${stage}`);
      return { sent: false, skipped: 'template_unavailable' };
    }

    const dueDate = financial.dueDate && typeof financial.dueDate.toDate === 'function'
      ? financial.dueDate.toDate()
      : new Date();
    const valor = formatBrlAmount(Number(financial.amount) || 0);
    const vencimento = formatBrDate(dueDate);
    let academy = {};
    try {
      const academySnap = await db.doc(`academies/${academyId}`).get();
      academy = academySnap.exists ? (academySnap.data() || {}) : {};
    } catch (_) {
      // Missing academy payment data safely resolves to `none` below.
    }

    let paymentInstruction = { mode: BillingPaymentMode.NONE };
    let paymentFallbackReason = null;
    if (settings.includePaymentLink !== false &&
        financial.paymentMethodPolicy !== 'card_only') {
      paymentInstruction = await resolveBillingPaymentInstruction({
        academy,
        generateMercadoPagoPix: async () => {
          try {
            return await generateReminderMercadoPagoPix(
              academyId,
              financial,
              {
                payerFallbackUid: manual
                  ? options.payerFallbackUid || null
                  : null,
              }
            );
          } catch (error) {
            paymentFallbackReason = billingMercadoPagoFailureCode(error);
            console.warn(
              '[billing] Mercado Pago unavailable; trying personal PIX',
              financial.id,
              paymentFallbackReason
            );
            throw error;
          }
        },
      });
    }

    // The approved Meta template matrix is selected only by stage and payment
    // mode. Academy-editable WhatsApp copy is intentionally ignored here.
    const templatePayload = buildBillingTemplatePayload({
      stage,
      paymentInstruction,
      studentName: financial.studentName || '',
      academyName: academyName || academy.name || academy.academyName || '',
      amountFormatted: valor,
      dueDateFormatted: vencimento,
      chargeType,
      description: financial.description,
    });
    if (!templatePayload) {
      return { sent: false, skipped: 'template_unavailable' };
    }

    console.log(
      `[S7] WhatsApp billing mode=${templatePayload.paymentMode} ` +
      `template=${templatePayload.templateName} stage=${stage}`
    );
    const result = await sendWhatsAppTemplateServer(
      phone,
      academyId,
      templatePayload
    );
    // Persist the dedup marker ONLY when the message actually went out (not on
    // the INERT no_key path), so re-enabling WhatsApp later still delivers.
    if (result && result.sent && financial.id) {
      try {
        await db.doc(`academies/${academyId}/financials/${financial.id}`).update({
          lastReminderStage: stage,
          lastReminderAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // best-effort: the dedup marker is non-critical.
      }
    }
    return {
      ...(result || { sent: false, skipped: 'unknown' }),
      paymentMode: templatePayload.paymentMode,
      templateName: templatePayload.templateName,
      paymentFallbackReason: paymentInstruction.mode === BillingPaymentMode.MERCADO_PAGO
        ? null : paymentFallbackReason,
    };
  } catch (e) {
    console.error('[S7] sendBillingReminderWhatsApp failed:', e && e.message);
    return { sent: false, skipped: 'internal' };
  }
}

function isValidBillingEmail(email) {
  const clean = String(email || '').trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clean)) return false;
  const domain = clean.split('@').pop().toLowerCase();
  return !['email.com', 'teste.com', 'test.com', 'exemplo.com', 'example.com']
    .includes(domain);
}

function buildBillingEmailContent(
  stage,
  financial,
  academyName,
  daysOverdue,
  paymentUrl = ''
) {
  const studentName = String(financial.studentName || 'Aluno');
  const amount = formatBrlAmount(Number(financial.amount) || 0);
  const dueDate = financial.dueDate &&
    typeof financial.dueDate.toDate === 'function'
    ? financial.dueDate.toDate() : new Date();
  const due = formatBrDate(dueDate);
  const subjects = {
    'CREATED': `Nova cobranca disponivel - ${academyName}`,
    'UPCOMING': `Sua cobranca vence em breve - ${academyName}`,
    'D+0': `Lembrete: sua cobranca vence hoje - ${academyName}`,
    'D+1': `Lembrete de pagamento - ${academyName}`,
    'D+3': `Pagamento atrasado - ${academyName}`,
    'D+7': `Pagamento pendente - ${academyName}`,
    'D+15': `Aviso de pagamento pendente - ${academyName}`,
    'D+30': `Situacao de pagamento pendente - ${academyName}`,
  };
  const timing = stage === 'D+0'
    ? `vence hoje (${due})`
    : daysOverdue > 0
      ? `venceu em ${due} e esta ha ${daysOverdue} dia(s) em aberto`
      : `vence em ${due}`;
  return {
    subject: subjects[stage] || `Lembrete de pagamento - ${academyName}`,
    message: `Ola ${studentName},\n\nSua cobranca de ${amount} da ${academyName} ${timing}.\n\n` +
      (paymentUrl ? `Pague com seguranca: ${paymentUrl}\n\n` : '') +
      'Se o pagamento ja foi realizado, desconsidere esta mensagem.\n\n' +
      `Atenciosamente,\n${academyName}`,
  };
}

async function sendBillingEmailServer(email, academyId, payload) {
  const key = process.env.NOTIFICATION_API_KEY;
  if (!key) return { sent: false, skipped: 'no_key' };
  const url = process.env.NOTIFICATION_API_URL ||
    'https://notification.tensorroot.com/api/send-email';
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': key },
      body: JSON.stringify({
        appId: process.env.NOTIFICATION_APP_ID || 'gestao-raiz',
        tenantId: academyId,
        academyId,
        email,
        subject: payload.subject,
        message: payload.message,
        studentId: payload.studentId,
        financialId: payload.financialId,
        stage: payload.stage,
        type: 'billing_reminder',
      }),
      signal: AbortSignal.timeout(30 * 1000),
    });
    if (!response.ok) return { sent: false, skipped: 'provider_error' };
    const body = await response.json().catch(() => null);
    if (body && (body.success === true || body.sent === true || body.status === 'sent')) {
      return { sent: true, provider: body.provider || 'email' };
    }
    return { sent: false, skipped: 'not_confirmed' };
  } catch (error) {
    console.error('[billing] sendBillingEmailServer failed:', error && error.message);
    return { sent: false, skipped: 'provider_error' };
  }
}

async function sendBillingReminderEmail(
  academyId,
  academyName,
  financial,
  stage,
  daysOverdue
) {
  let email = '';
  try {
    const studentSnapshot = await db
      .collection('academies').doc(academyId)
      .collection('students').doc(financial.studentId)
      .get();
    if (studentSnapshot.exists) {
      const student = studentSnapshot.data() || {};
      email = student.category === 'kids'
        ? (student.guardian?.email || student.email)
        : student.email;
    }
  } catch (_) {
    // Missing recipient is handled below.
  }
  if (!isValidBillingEmail(email)) {
    return { sent: false, skipped: 'missing_email' };
  }
  let paymentUrl = '';
  let publicPayAvailable = false;
  try {
    const academySnapshot = await db.doc(`academies/${academyId}`).get();
    const academy = academySnapshot.exists ? (academySnapshot.data() || {}) : {};
    publicPayAvailable = academy.mpConnected === true &&
      academy.publicPaymentLinksEnabled === true &&
      academy.mpNeedsReauth !== true &&
      financial.paymentMethodPolicy !== 'card_only';
  } catch (_) {
    publicPayAvailable = false;
  }
  if (publicPayAvailable && financial.id &&
      ['pending', 'overdue'].includes(financial.status)) {
    try {
      const publicLink = await getOrCreatePublicPaymentLink(
        academyId,
        financial.id
      );
      paymentUrl = publicLink.url;
    } catch (error) {
      console.error(
        '[billing] email public link unavailable',
        financial.id,
        error && error.message
      );
    }
  }
  const content = buildBillingEmailContent(
    stage,
    financial,
    academyName,
    daysOverdue,
    paymentUrl
  );
  return sendBillingEmailServer(email, academyId, {
    ...content,
    studentId: financial.studentId,
    financialId: financial.id,
    stage,
  });
}

// Reads the per-academy billingReminders settings doc once. Returns {} when
// absent. Never throws.
async function getBillingReminderSettings(academyId) {
  try {
    const snap = await db
      .collection('academies').doc(academyId)
      .collection('settings').doc('billingReminders')
      .get();
    return snap.exists ? (snap.data() || {}) : {};
  } catch (_) {
    return {};
  }
}

// Manual billing dispatch. The client identifies the charge and channel only;
// recipient, amount, due date, template and payment instruction are resolved
// from authoritative server data. Notification credentials never reach Flutter.
exports.sendBillingReminder = onCall(
  {
    // Callable endpoints must be reachable by the Firebase client. Access to
    // academy data is still protected below by request.auth + isAcademyStaff.
    // Without this IAM binding Cloud Run rejects the request with 403 before
    // the callable SDK can validate the Firebase ID token.
    invoker: 'public',
    secrets: BILLING_NOTIFICATION_SECRETS,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Login required.');
    }
    const academyId = assertSafeDocumentId(request.data?.academyId, 'academyId');
    const financialId = assertSafeDocumentId(
      request.data?.financialId, 'financialId'
    );
    const channel = String(request.data?.channel || '').trim();
    if (!['whatsapp', 'email'].includes(channel)) {
      throw new HttpsError(
        'invalid-argument',
        'academyId, financialId e channel valido sao obrigatorios.'
      );
    }
    if (!(await isAcademyStaff(request.auth.uid, academyId))) {
      throw new HttpsError(
        'permission-denied',
        'Apenas a equipe da academia pode enviar cobrancas.'
      );
    }

    const financialRef = db.doc(
      `academies/${academyId}/financials/${financialId}`
    );
    const [financialSnapshot, academySnapshot] = await Promise.all([
      financialRef.get(),
      db.doc(`academies/${academyId}`).get(),
    ]);
    if (!financialSnapshot.exists) {
      throw new HttpsError('not-found', 'Cobranca nao encontrada.');
    }
    if (!academySnapshot.exists) {
      throw new HttpsError('not-found', 'Academia nao encontrada.');
    }

    const financial = { id: financialId, ...financialSnapshot.data() };
    if (financial.academyId && financial.academyId !== academyId) {
      throw new HttpsError('permission-denied', 'Cobranca de outro tenant.');
    }
    if (!['pending', 'overdue', 'test'].includes(financial.status)) {
      throw new HttpsError(
        'failed-precondition',
        'Somente cobrancas abertas podem ser enviadas.'
      );
    }

    const dueDate = financial.dueDate &&
      typeof financial.dueDate.toDate === 'function'
      ? financial.dueDate.toDate() : new Date();
    const now = new Date();
    const daysOverdue = daysOverdueBR(dueDate, now);
    const requestedStage = String(request.data?.stage || '');
    const dueDay = new Date(
      dueDate.getFullYear(), dueDate.getMonth(), dueDate.getDate()
    ).getTime();
    const today = new Date(
      now.getFullYear(), now.getMonth(), now.getDate()
    ).getTime();
    const liveStage = dueDay > today ? 'UPCOMING' : resolveStage(daysOverdue);
    const stage = financial.status === 'test' && normalizeTemplateStage(requestedStage)
      ? requestedStage
      : liveStage;
    const academy = academySnapshot.data() || {};
    const academyName = academy.name || academy.academyName || 'Academia';

    let result;
    if (channel === 'whatsapp') {
      let phoneOverride = '';
      if (request.data?.recipientOverride) {
        if (financial.status !== 'test') {
          throw new HttpsError(
            'invalid-argument',
            'Destinatario manual so e permitido para cobranca de teste.'
          );
        }
        await requireAdminOf(request, academyId);
        phoneOverride = String(request.data.recipientOverride);
      }
      const settings = await getBillingReminderSettings(academyId);
      result = await sendBillingReminderWhatsApp(
        academyId,
        academyName,
        settings,
        financial,
        stage,
        daysOverdue,
        {
          manual: true,
          phoneOverride,
          payerFallbackUid: request.auth.uid,
        }
      );
    } else {
      result = await sendBillingReminderEmail(
        academyId,
        academyName,
        financial,
        stage,
        daysOverdue
      );
    }

    if (!result || !result.sent) {
      const reason = result?.skipped || 'unknown';
      if (reason === 'no_key') {
        throw new HttpsError(
          'failed-precondition',
          'Canal de notificacao nao configurado no backend.'
        );
      }
      throw new HttpsError(
        'unavailable',
        `Nao foi possivel enviar a cobranca (${reason}).`
      );
    }
    return {
      success: true,
      channel,
      provider: result.provider || channel,
      stage,
      paymentMode: result.paymentMode || null,
      templateName: result.templateName || null,
      paymentFallbackReason: result.paymentFallbackReason || null,
    };
  }
);

// ============================================
// Internal Notification Helper
// ============================================

async function createInternalNotification(
  academyId,
  userId,
  type,
  priority,
  title,
  message,
  options
) {
  try {
    const data = {
      academyId,
      userId,
      type,
      priority,
      title,
      message,
      read: false,
      channels: ['in_app'],
      sentVia: ['in_app'],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (options?.actionUrl) data.actionUrl = options.actionUrl;
    if (options?.actionLabel) data.actionLabel = options.actionLabel;
    if (options?.financialId) data.financialId = options.financialId;
    if (options?.studentId) data.studentId = options.studentId;
    if (options?.competitionId) data.competitionId = options.competitionId;
    if (options?.expiresInDays) {
      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + options.expiresInDays);
      data.expiresAt = admin.firestore.Timestamp.fromDate(expiresAt);
    }

    await db.collection(`academies/${academyId}/notifications`).add(data);
  } catch (error) {
    console.error('Error creating internal notification:', error);
  }
}

async function notifyAdminCF(academyId, type, title, message, options) {
  try {
    const academySnap = await db.doc(`academies/${academyId}`).get();
    if (!academySnap.exists) return;
    const adminUserId = academySnap.data()?.ownerId || academySnap.data()?.adminUserId;
    if (!adminUserId) return;

    // Internal notification
    await createInternalNotification(academyId, adminUserId, type, 'high', title, message, {
      financialId: options?.financialId,
      studentId: options?.studentId,
      expiresInDays: 30,
    });

    // Push notification
    await sendToUser(adminUserId, title, message, { type, academyId });
  } catch (error) {
    console.error('Error notifying admin:', error);
  }
}
// Exportado (helper puro, não é Cloud Function) para reuso por index.js —
// ver `submitJoinRequest` (notifica a equipe da academia sobre solicitação
// nova, spec 2.1). index.js precisa stripar essa entrada do destructure de
// `require('./server_functions')` como já faz para os outros helpers-puros
// abaixo, senão o discovery de endpoints do Firebase tenta deployá-la.
exports.notifyAdminCF = notifyAdminCF;

// ============================================
// Cloud Functions - Firestore Triggers
// ============================================

/**
 * Trigger: New financial record created
 * Action: Notify student about new payment due
 */
exports.onFinancialCreated = functions
  .runWith({ secrets: BILLING_NOTIFICATION_SECRETS })
  .firestore
  .document('academies/{academyId}/financials/{financialId}')
  .onCreate(async (snapshot, context) => {
    const { academyId, financialId } = context.params;
    const financial = snapshot.data();

    console.log(`New financial created: ${financialId} in academy ${academyId}`);

    // Docs sintéticos/terminais não representam uma nova parcela disponível.
    if (financial.status !== 'pending' || !financial.dueDate ||
        typeof financial.dueDate.toDate !== 'function') return null;

    const dueDate = financial.dueDate.toDate();
    const formattedDate = dueDate.toLocaleDateString('pt-BR');
    const formattedAmount = (Number(financial.amount) || 0).toFixed(2);
    const isTuition = (financial.type || 'monthly_tuition') === 'monthly_tuition';
    const description = sanitizeString(financial.description) || 'Cobrança avulsa';
    const notificationTitle = isTuition
      ? 'Nova Mensalidade Disponível'
      : 'Nova Cobrança Disponível';
    const pushMessage = isTuition
      ? `Uma nova mensalidade de R$ ${formattedAmount} foi gerada. Vencimento: ${formattedDate}.`
      : `Uma nova cobrança de R$ ${formattedAmount}, referente a ${description}, foi gerada. Vencimento: ${formattedDate}.`;
    const internalMessage = isTuition
      ? `Sua mensalidade de R$ ${formattedAmount} vence em ${formattedDate}.`
      : `Sua cobrança de R$ ${formattedAmount}, referente a ${description}, vence em ${formattedDate}.`;

    // Push/interna continuam independentes do WhatsApp. Sem conta vinculada,
    // o aluno ainda pode receber a mensagem automática pelo telefone cadastrado.
    const userId = await getBillingRecipientUid(financial.studentId, academyId);
    if (userId) {
      await sendToUser(
        userId,
        notificationTitle,
        pushMessage,
        {
          type: 'financial',
          id: financialId,
          academyId,
          category: 'financial',
          actionUrl: '/portal/financeiro',
        }
      );
      await createInternalNotification(academyId, userId, 'financial', 'normal',
        notificationTitle,
        internalMessage,
        { actionUrl: '/portal/financeiro', actionLabel: 'Ver detalhes', financialId, expiresInDays: 30 }
      );
    }

    // Aviso de criação é opt-in. Mensalidades continuam sem template CREATED;
    // cobranças únicas usam a família cobranca_avulsa_aberta.
    const billingSettings = await getBillingReminderSettings(academyId);
    if (billingSettings.notifyOnCreation === true) {
      const academySnap = await db.doc(`academies/${academyId}`).get();
      const academy = academySnap.exists ? (academySnap.data() || {}) : {};
      await sendBillingReminderWhatsApp(
        academyId,
        academy.name || academy.academyName || '',
        billingSettings,
        { ...financial, id: financialId },
        'CREATED',
        0
      );
    }

    console.log(`Creation notifications processed for financial ${financialId}`);
    return null;
  });

/**
 * Trigger: New competition created
 * Action: Notify all students in the academy
 */
exports.onCompetitionCreated = functions.firestore
  .document('academies/{academyId}/competitions/{competitionId}')
  .onCreate(async (snapshot, context) => {
    const { academyId, competitionId } = context.params;
    const competition = snapshot.data();

    console.log(`New competition created: ${competitionId} in academy ${academyId}`);

    // Send notification to all students via topic
    const competitionDate = competition.date.toDate();
    const formattedDate = competitionDate.toLocaleDateString('pt-BR');

    await sendToTopic(
      `academy_${academyId}`,
      'Novo Campeonato Criado',
      `${competition.name} foi adicionado! Data: ${formattedDate}. Faca sua inscricao.`,
      {
        type: 'competition',
        id: competitionId,
        academyId,
        actionUrl: `/portal/competicoes/${competitionId}`,
      }
    );

    // Create in-app notifications for all active students
    const studentsSnapshot = await db
      .collection('academies')
      .doc(academyId)
      .collection('students')
      .where('status', '==', 'active')
      .get();

    const notificationPromises = [];
    for (const studentDoc of studentsSnapshot.docs) {
      const student = studentDoc.data();
      if (student.userId) {
        notificationPromises.push(
          createInternalNotification(
            academyId,
            student.userId,
            'competition_reminder',
            'normal',
            'Novo Campeonato Criado',
            `${competition.name} foi adicionado! Data: ${formattedDate}. Faca sua inscricao.`,
            { competitionId, expiresInDays: 30 }
          )
        );
      }
    }
    await Promise.all(notificationPromises);

    console.log(`Notification sent to topic academy_${academyId} for competition ${competitionId}`);
  });

/**
 * Trigger: New timeline event (achievement) created
 * Action: Notify student about achievement
 */
exports.onTimelineEventCreated = functions.firestore
  .document('academies/{academyId}/students/{studentId}/timeline/{eventId}')
  .onCreate(async (snapshot, context) => {
    const { academyId, studentId, eventId } = context.params;
    const event = snapshot.data();

    // Only notify for achievements and graduations
    if (!['achievement', 'graduation', 'belt_promotion'].includes(event.type)) {
      console.log(`Timeline event ${eventId} is not a notifiable type: ${event.type}`);
      return;
    }

    console.log(`New timeline event created: ${eventId} for student ${studentId}`);

    // Get student's userId
    const userId = await getStudentUserId(studentId, academyId);
    if (!userId) {
      console.log(`No userId found for student: ${studentId}`);
      return;
    }

    // Determine notification content based on type
    let title = 'Nova Conquista!';
    let body = event.title;

    if (event.type === 'graduation' || event.type === 'belt_promotion') {
      title = 'Graduacao!';
      body = `Parabens! ${event.title}`;
    } else if (event.type === 'achievement') {
      title = 'Nova Conquista Desbloqueada!';
      body = `Parabens! Voce conquistou: ${event.title}`;
    }

    await sendToUser(userId, title, body, {
      type: event.type,
      id: eventId,
      academyId,
      studentId,
      actionUrl: '/portal/linha-do-tempo',
    });

    // Create in-app notification
    await createInternalNotification(
      academyId,
      userId,
      event.type,
      'normal',
      title,
      body,
      { studentId, expiresInDays: 30 }
    );

    console.log(`Notification sent to user ${userId} for timeline event ${eventId}`);
  });

/**
 * Trigger: a student doc is written.
 * Action: if a responsible adult became unavailable (their student doc was
 * deleted, their account was unlinked, or they were permanently removed —
 * status 'deleted'), clear the dangling responsibleUserId on every kid that
 * pointed at them. This is the safety net against orphan links: without it a
 * kid's charges would silently stop being payable in-app. A temporary
 * 'inactive' adult can still log in and pay, so it is intentionally NOT cleared.
 *
 * Note: clearing only touches responsible* fields, so the resulting writes on
 * the dependents do not re-trigger this cleanup (linkedUserId/status unchanged).
 */
exports.clearDependentsOnResponsibleGone = functions.firestore
  .document('academies/{academyId}/students/{studentId}')
  .onWrite(async (change, context) => {
    const { academyId } = context.params;
    const before = change.before.exists ? change.before.data() : null;
    if (!before) return null; // created — nothing to clean

    const oldUid = before.linkedUserId;
    if (!oldUid) return null; // never had an account → was never a responsible

    const after = change.after.exists ? change.after.data() : null;
    const deleted = after === null;
    const unlinked = after !== null && after.linkedUserId !== oldUid;
    const permanentlyRemoved = after !== null && after.status === 'deleted';
    if (!deleted && !unlinked && !permanentlyRemoved) return null;

    const deps = await db
      .collection(`academies/${academyId}/students`)
      .where('responsibleUserId', '==', oldUid)
      .get();
    if (deps.empty) return null;

    const batch = db.batch();
    deps.forEach((d) => {
      batch.update(d.ref, {
        responsibleUserId: admin.firestore.FieldValue.delete(),
        responsibleStudentId: admin.firestore.FieldValue.delete(),
        responsibleName: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    await batch.commit();
    console.log(
      `Cleared ${deps.size} orphan responsible link(s) for uid ${oldUid} in ${academyId}`
    );
    return null;
  });

// ============================================
// Sprint R — public profile mirror (privacy-correct social layer)
// ============================================
//
// The student doc bundles profile fields WITH sensitive PII (cpf, address,
// phone, health, financials, ...), and Firestore rules cannot filter fields on
// read. So peer/social reads (ranking, public fighter profile) must NOT read
// the student doc directly. Instead a Cloud Function keeps a slim mirror at
// academies/{academyId}/publicProfiles/{studentId} holding ONLY safe fields;
// the rules allow members (and the public when isProfilePublic) to read it.
//
// SAFE allowlist — mirrored fields (same field names as the student doc so the
// Flutter Student.fromFirestore parses the mirror unchanged; PII simply absent):
//   id (studentId via doc id), fullName, nickname, photoUrl,
//   currentBelt, currentStripes, sportData, sports, primarySport,
//   initialAttendanceCount, attendanceCount (feed totalAttendanceCount),
//   category (needed by getGrade kids/adult fallbacks; non-PII),
//   isProfilePublic, status, mirrorUpdatedAt.
//
// DENYLIST — NEVER mirrored: cpf, rg, address, phone, email, birthDate, sex,
// weight, targetWeightKg, targetBodyFatPct, bloodType, allergies, healthNotes,
// medicalCertificateUrl, medicalCertificateExpiry, emergencyContact, guardian,
// tuitionValue, tuitionDay, tuitionDueDay, planId, planIds, responsibleUserId,
// responsibleStudentId, responsibleName, responsibleTrainsHere, guardianCpf,
// linkedUserId, beltHistory, createdBy, and any payment/financial/health field.

// Explicit allowlist of student fields that are safe to expose publicly.
// Anything not in this list is treated as PII / sensitive and is dropped.
const PUBLIC_PROFILE_SAFE_FIELDS = [
  'fullName',
  'nickname',
  'photoUrl',
  'currentBelt',
  'currentStripes',
  'sportData',
  'sports',
  'primarySport',
  'initialAttendanceCount',
  'attendanceCount',
  'category',
  'isProfilePublic',
  'status',
  // Auth uid do aluno vinculado. NÃO é PII sensível — é o MESMO uid que já
  // vive em fighterProfiles (público). Necessário pro social intra-academia:
  // liga o COLEGA DE TURMA ao perfil/posts dele (studentId → linkedUserId → uid).
  'linkedUserId',
];

/**
 * Builds the SAFE projection of a student doc for the public mirror.
 * Allowlist-based (never denylist) so a newly-added PII field on the student
 * doc can NEVER leak into the mirror by default. Only keys present on the
 * source are copied; missing keys are simply absent (Flutter parser tolerant).
 *
 * @param {Object} student raw student doc data
 * @return {Object} safe projection (no PII), with mirrorUpdatedAt stamped
 */
function buildPublicProfileProjection(student) {
  const src = student || {};
  const out = {};
  for (const key of PUBLIC_PROFILE_SAFE_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(src, key) && src[key] !== undefined) {
      out[key] = src[key];
    }
  }
  // isProfilePublic must always be a concrete boolean — the mirror's read rule
  // keys off it for public access, and a missing field would deny by default.
  out.isProfilePublic = src.isProfilePublic === true;
  out.mirrorUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
  return out;
}

/**
 * Trigger: a student doc is written.
 * Action: keep the privacy-correct mirror at
 * academies/{academyId}/publicProfiles/{studentId} in sync.
 *   - create/update → write the SAFE projection (merge)
 *   - delete        → delete the mirror
 *
 * No infinite loop: this writes a DIFFERENT collection (publicProfiles), which
 * is not watched by any students-collection trigger.
 */
exports.mirrorStudentPublicProfile = functions.firestore
  .document('academies/{academyId}/students/{studentId}')
  .onWrite(async (change, context) => {
    const { academyId, studentId } = context.params;
    const mirrorRef = db.doc(
      `academies/${academyId}/publicProfiles/${studentId}`
    );

    // Deletion of the student → remove the mirror.
    if (!change.after.exists) {
      try {
        await mirrorRef.delete();
        console.log(`[mirror] deleted publicProfile ${academyId}/${studentId}`);
      } catch (e) {
        console.error('[mirror] delete failed', academyId, studentId, e && e.message);
      }
      return null;
    }

    // Create/update → write the SAFE projection (merge so we never clobber any
    // future server-only fields on the mirror).
    const projection = buildPublicProfileProjection(change.after.data());
    try {
      await mirrorRef.set(projection, { merge: true });
      console.log(`[mirror] synced publicProfile ${academyId}/${studentId}`);
    } catch (e) {
      console.error('[mirror] sync failed', academyId, studentId, e && e.message);
    }
    return null;
  });

// Exported for reuse by the one-shot backfill script (scripts/).
exports.buildPublicProfileProjection = buildPublicProfileProjection;
exports.PUBLIC_PROFILE_SAFE_FIELDS = PUBLIC_PROFILE_SAFE_FIELDS;

// ============================================
// Cloud Functions - Scheduled (Cron Jobs)
// ============================================

/**
 * Scheduled: Daily at 9:00 AM (Brasilia Time)
 * Action: Check for overdue payments and notify admins
 */
exports.scheduledOverdueCheck = functions
  .runWith({ secrets: BILLING_NOTIFICATION_SECRETS })
  .pubsub
  .schedule('0 9 * * *')
  .timeZone('America/Sao_Paulo')
  .onRun(async () => {
    console.log('Running scheduled overdue payment check');

    const now = new Date();
    const academiesSnapshot = await db.collection('academies').get();

    for (const academyDoc of academiesSnapshot.docs) {
      const academyId = academyDoc.id;
      const academy = academyDoc.data();

      // Auditoria (HIGH correctness): try/catch POR ACADEMIA (espelha o cron de
      // gamificação) — um doc malformado / falha de leitura de UMA academia não
      // pode abortar o run de cobrança de toda a base.
      try {
        // Skip if no admin user
        if (!academy.adminUserId) {
          console.log(`Academy ${academyId} has no admin user`);
          continue;
        }

        // Auditoria (HIGH product): consulta status in ['pending','overdue'].
        // Antes lia só 'pending' e virava o doc para 'overdue' no MESMO run, de
        // modo que nas execuções seguintes o doc 'overdue' não era mais
        // varrido => a escada de lembretes D+3/D+7/D+15/D+30 NUNCA disparava.
        const financialsSnapshot = await db
          .collection('academies')
          .doc(academyId)
          .collection('financials')
          .where('status', 'in', ['pending', 'overdue'])
          .get();

        let overdueCount = 0;
        let totalOverdueAmount = 0;

        // S7: read the per-academy WhatsApp/PIX reminder settings once.
        const billingSettings = await getBillingReminderSettings(academyId);
        const academyName = academy.name || academy.academyName || '';

        for (const financialDoc of financialsSnapshot.docs) {
          const financial = financialDoc.data();

          // Auditoria (HIGH correctness): null-guard em dueDate. Um doc sem
          // dueDate (ou com tipo inesperado) não pode derrubar o loop inteiro.
          if (!financial.dueDate || typeof financial.dueDate.toDate !== 'function') {
            continue;
          }
          const dueDate = financial.dueDate.toDate();

          // Auditoria (LOW): vencido = passou do FIM do dia do vencimento (BRT),
          // evitando "atrasada há 0 dias" no próprio dia às 09:00.
          if (!isOverdueBR(dueDate, now)) continue;

          overdueCount++;
          totalOverdueAmount += (Number(financial.amount) || 0);

          // Update status to overdue if not already
          if (financial.status !== 'overdue') {
            await financialDoc.ref.update({ status: 'overdue' });
          }

          // Dias de atraso por dia-calendário BR (sem off-by-one).
          const daysOverdue = daysOverdueBR(dueDate, now);
          const stage = resolveStage(daysOverdue);

          // Auditoria (HIGH product): deduplicação POR ESTÁGIO em TODOS os
          // canais (push + interna + WhatsApp). Só dispara o lembrete quando o
          // estágio MUDA (D+1 → D+3 → D+7 ...). Sem isso, com status 'overdue'
          // agora varrido todo dia, o aluno receberia push/notificação TODA
          // execução. O mesmo estágio nunca é reenviado.
          if (financial.lastReminderStage === stage) continue;

          // Auditoria (LOW ux): copy diferente para não-mensalidade (aula
          // avulsa/particular) — sem o wording de "mensalidade atrasada".
          const isTuition = (financial.type || 'monthly_tuition') === 'monthly_tuition';
          const valorFmt = (Number(financial.amount) || 0).toFixed(2);
          const noun = isTuition ? 'Sua mensalidade' : `Sua cobranca (${financial.description || 'avulsa'})`;
          const nounAcc = isTuition ? 'Sua mensalidade' : `Sua cobrança (${financial.description || 'avulsa'})`;

          // Notify the billing recipient (responsible adult for kids, else
          // the student) about the overdue payment (push + internal)
          const userId = await getBillingRecipientUid(financial.studentId, academyId);
          if (userId) {
            await sendToUser(
              userId,
              isTuition ? 'Pagamento Atrasado' : 'Cobranca em aberto',
              `${noun} de R$ ${valorFmt} esta em aberto ha ${daysOverdue} dia(s).`,
              {
                type: 'financial',
                id: financialDoc.id,
                academyId,
                category: 'financial', // sempre notificado — ver comentário no gate acima
                actionUrl: '/portal/financeiro',
              }
            );
            await createInternalNotification(academyId, userId, 'financial', 'high',
              isTuition ? 'Pagamento Atrasado' : 'Cobrança em aberto',
              `${nounAcc} de R$ ${valorFmt} está em aberto há ${daysOverdue} dia(s).`,
              { actionUrl: '/portal/financeiro', actionLabel: 'Regularizar',
                financialId: financialDoc.id, expiresInDays: 30 }
            );
          }

          // S7: additionally send the autonomous WhatsApp + PIX reminder.
          // INERT until WHATSAPP_API_KEY is set (template sender gate).
          await sendBillingReminderWhatsApp(
            academyId,
            academyName,
            billingSettings,
            { ...financial, id: financialDoc.id },
            stage,
            daysOverdue
          );

          // Auditoria (HIGH product): persiste o estágio coberto para TODOS os
          // canais (não só WhatsApp), garantindo que push/interna também não
          // reenviem o mesmo estágio na próxima execução. Best-effort.
          try {
            await financialDoc.ref.update({
              lastReminderStage: stage,
              lastReminderAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          } catch (_) {
            // dedup marker é não-crítico
          }
        }

        // Notify admin about overdue summary (push + internal)
        if (overdueCount > 0) {
          const adminId = academy.ownerId || academy.adminUserId;
          const totalFormatted = (Number(totalOverdueAmount) || 0).toFixed(2);
          const summaryMsg = `Voce tem ${overdueCount} pagamento(s) atrasado(s) totalizando R$ ${totalFormatted}.`;
          await sendToUser(
            adminId,
            'Resumo de Pagamentos Atrasados',
            summaryMsg,
            {
              type: 'overdue_summary',
              academyId,
            }
          );
          await createInternalNotification(academyId, adminId, 'financial', 'high',
            'Resumo de Pagamentos Atrasados',
            summaryMsg,
            { actionUrl: '/financeiro', actionLabel: 'Ver financeiro', expiresInDays: 7 }
          );
          console.log(`Notified admin of academy ${academyId} about ${overdueCount} overdue payments`);
        }
      } catch (e) {
        // Auditoria (HIGH correctness): isola a falha à academia atual.
        console.error(`[overdueCheck] academy ${academyId} failed`, e && e.message);
      }
    }

    console.log('Overdue payment check completed');
    return null;
  });

/**
 * Scheduled: Daily at 8:00 AM (Brasilia Time)
 * Action: Check for payments due soon (3 days before) and notify students
 */
exports.scheduledDueSoonReminder = functions
  .runWith({ secrets: BILLING_NOTIFICATION_SECRETS })
  .pubsub
  .schedule('0 8 * * *')
  .timeZone('America/Sao_Paulo')
  .onRun(async () => {
    console.log('Running scheduled due soon reminder');

    const now = new Date();
    const startNow = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const academiesSnapshot = await db.collection('academies').get();

    for (const academyDoc of academiesSnapshot.docs) {
      const academyId = academyDoc.id;
      const academy = academyDoc.data();

      // Auditoria (HIGH correctness): try/catch POR ACADEMIA — falha de uma
      // academia não aborta o run a-vencer de toda a base.
      try {
        // S7: read the per-academy WhatsApp/PIX reminder settings once.
        const billingSettings = await getBillingReminderSettings(academyId);
        const academyName = academy.name || academy.academyName || '';

        // Auditoria (LOW): antecedência configurável por academia. Default D-7 e
        // D-2 (avisa uma semana antes e na reta final). Sanitiza para inteiros
        // positivos e ordena desc para deduplicar pelo MAIOR offset elegível.
        const rawOffsets = Array.isArray(billingSettings.dueSoonOffsets)
          ? billingSettings.dueSoonOffsets
          : [7, 3, 2, 1, 0];
        const offsets = Array.from(new Set(
          rawOffsets.map((n) => Math.trunc(Number(n))).filter((n) => n >= 0)
        )).sort((a, b) => b - a);
        const maxOffset = offsets.length ? offsets[0] : 0;
        if (offsets.length === 0) continue;

        // Find pending financials due within the largest configured window.
        const financialsSnapshot = await db
          .collection('academies')
          .doc(academyId)
          .collection('financials')
          .where('status', '==', 'pending')
          .get();

        for (const financialDoc of financialsSnapshot.docs) {
          const financial = financialDoc.data();

          // Auditoria (HIGH correctness): null-guard em dueDate.
          if (!financial.dueDate || typeof financial.dueDate.toDate !== 'function') {
            continue;
          }
          const dueDate = financial.dueDate.toDate();
          const startDue = new Date(dueDate.getFullYear(), dueDate.getMonth(), dueDate.getDate());
          const daysUntilDue = Math.round(
            (startDue.getTime() - startNow.getTime()) / (1000 * 60 * 60 * 24)
          );

          // Só a-vencer (futuro). Vencido é tratado pelo scheduledOverdueCheck.
          if (daysUntilDue < 0 || daysUntilDue > maxOffset) continue;

          // Auditoria (LOW): só dispara num offset CONFIGURADO (ex.: 7 ou 2),
          // não em todo dia da janela. O estágio (ex.: 'due-7') deduplica para
          // não reenviar o mesmo aviso a-vencer. Campo separado do overdue
          // (lastDueSoonStage) para as duas réguas não colidirem.
          if (!offsets.includes(daysUntilDue)) continue;
          const dueStage = daysUntilDue === 0 ? 'D+0' : `due-${daysUntilDue}`;
          if (financial.lastDueSoonStage === dueStage) continue;

          const isTuition = (financial.type || 'monthly_tuition') === 'monthly_tuition';
          const noun = isTuition ? 'Sua mensalidade' : `Sua cobranca (${financial.description || 'avulsa'})`;
          const nounAcc = isTuition ? 'Sua mensalidade' : `Sua cobrança (${financial.description || 'avulsa'})`;

          const userId = await getBillingRecipientUid(financial.studentId, academyId);
          if (userId) {
            const amtFormatted = (Number(financial.amount) || 0).toFixed(2);
            await sendToUser(
              userId,
              'Lembrete de Pagamento',
              `${noun} de R$ ${amtFormatted} vence em ${daysUntilDue} dia(s).`,
              {
                type: 'financial',
                id: financialDoc.id,
                academyId,
                category: 'financial', // sempre notificado — ver comentário no gate acima
                actionUrl: '/portal/financeiro',
              }
            );
            await createInternalNotification(academyId, userId, 'financial', 'normal',
              'Lembrete de Pagamento',
              `${nounAcc} de R$ ${amtFormatted} vence em ${daysUntilDue} dia(s).`,
              { actionUrl: '/portal/financeiro', actionLabel: 'Ver detalhes',
                financialId: financialDoc.id, expiresInDays: 7 }
            );
            console.log(`Sent due soon reminder to user ${userId} for financial ${financialDoc.id}`);
          }

          // WhatsApp a vencer em todos os dias escolhidos pelo professor. O
          // stage dinâmico deduplica cada marco; o conteúdo usa o template
          // único UPCOMING, com {diasAteVencimento} preenchido.
          await sendBillingReminderWhatsApp(
            academyId,
            academyName,
            billingSettings,
            { ...financial, id: financialDoc.id },
            dueStage,
            -daysUntilDue
          );

          // Persist o estágio a-vencer coberto (best-effort) p/ deduplicar.
          try {
            await financialDoc.ref.update({
              lastDueSoonStage: dueStage,
              lastDueSoonAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          } catch (_) {
            // marcador de dedup é não-crítico
          }
        }
      } catch (e) {
        console.error(`[dueSoonReminder] academy ${academyId} failed`, e && e.message);
      }
    }

    console.log('Due soon reminder completed');
    return null;
  });

// ============================================================
// Auditoria (HIGH product / FEATURE): geração AGENDADA de mensalidades
// ============================================================
//
// Hoje a geração mensal (lib/services/payment_service.dart generateMonthlyTuitions)
// é 100% MANUAL — depende do dono clicar o botão. Alunos PIX/dinheiro que não
// recebem a mensalidade gerada simplesmente "evaporam" sem nunca virar
// 'inadimplentes', furando toda a régua de cobrança acima.
//
// Esta CF espelha a lógica do cliente no servidor, é IDEMPOTENTE por
// (academyId, studentId, referenceMonth), independentemente do plano. A chave
// transacional tambem protege a corrida entre botao manual e job agendado.
// pegar a virada do mês em qualquer fuso/horário.
//
// SEGURO POR PADRÃO: só gera para academias com settings.billing.autoTuitionEnabled
// === true (FALSE por padrão). Sem a flag, NÃO cria nenhuma cobrança — para não
// começar a faturar em produção sem o dono habilitar explicitamente. O botão
// manual continua existindo. REVISAR MODELO DE COBRANÇA ANTES DE HABILITAR.

// Mapeia o número de meses de cada período (espelha BillingPeriod.months).
function tuitionGenerationGuardRef(academyId, referenceMonth, studentId) {
  return db.doc(
    `academies/${academyId}/billingGenerationGuards/` +
    `${referenceMonth}_${studentId}`
  );
}

async function createTuitionWithGuard({
  academyId,
  referenceMonth,
  studentId,
  financialRef,
  payload,
}) {
  const guardRef = tuitionGenerationGuardRef(
    academyId, referenceMonth, studentId
  );
  return db.runTransaction(async (tx) => {
    const guard = await tx.get(guardRef);
    if (guard.exists) return false;
    tx.create(financialRef, payload);
    tx.create(guardRef, {
      academyId,
      studentId,
      referenceMonth,
      financialId: financialRef.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
}

function billingPeriodMonths(value) {
  switch (value) {
    case 'quarterly': return 3;
    case 'semiannual': return 6;
    case 'annual': return 12;
    default: return 1; // monthly + legados
  }
}

// referenceMonth canônico 'YYYY-MM' a partir de um Date (wall-clock BR).
function referenceMonthKey(d) {
  const parts = datePartsInBillingTimeZone(d);
  const y = parts.year;
  const m = String(parts.month).padStart(2, '0');
  return `${y}-${m}`;
}

// Gera as mensalidades de UMA academia para o mês de referência. Idempotente:
// não cria se já existe uma cobrança não-cancelada para o mesmo (studentId,
// planId, referenceMonth). Para planos não-mensais, respeita o período (só
// cobra quando passou o intervalo desde o último vencimento). Retorna nº criado.
async function generateAcademyTuitions(academyId, refDate) {
  const acadRef = db.collection('academies').doc(academyId);
  const referenceMonth = referenceMonthKey(refDate);
  const referenceParts = datePartsInBillingTimeZone(refDate);
  const refYear = referenceParts.year;
  const refMonth = referenceParts.month; // 1-12 in America/Sao_Paulo
  let created = 0;

  // Planos ativos da academia.
  let plansSnap;
  try {
    plansSnap = await acadRef.collection('plans').where('isActive', '==', true).get();
  } catch (e) {
    console.error(`[autoTuition] plans read failed ${academyId}`, e && e.message);
    return 0;
  }
  if (plansSnap.empty) return 0;

  // Alunos ativos (para nome + filtro de status, espelhando o cliente).
  const activeStudents = new Map(); // studentId -> data
  try {
    const stuSnap = await acadRef.collection('students').where('status', '==', 'active').get();
    for (const s of stuSnap.docs) activeStudents.set(s.id, s.data() || {});
  } catch (e) {
    console.error(`[autoTuition] students read failed ${academyId}`, e && e.message);
    return 0;
  }

  // Cobranças do mês de referência (dedup mensal) — uma leitura, não N+1.
  const monthCharges = [];
  try {
    const fSnap = await acadRef.collection('financials')
      .where('referenceMonth', '==', referenceMonth)
      .get();
    for (const f of fSnap.docs) {
      const d = f.data() || {};
      monthCharges.push({
        studentId: d.studentId,
        planId: d.planId || null,
        type: d.type || 'monthly_tuition',
        status: d.status,
      });
    }
  } catch (e) {
    console.error(`[autoTuition] financials(month) read failed ${academyId}`, e && e.message);
    return 0;
  }

  // Fail closed when a student is billable by more than one monthly plan.
  // Choosing whichever Firestore document appears first would be arbitrary.
  const monthlyCandidates = [];
  for (const planDoc of plansSnap.docs) {
    const plan = planDoc.data() || {};
    const planId = planDoc.id;
    const periodValue = plan.billingPeriod || 'monthly';
    // Card-only recurring plans also participate in conflict detection. They
    // are not invoiced here, but another monthly plan must not create a second
    // charge alongside their subscription.
    if (periodValue !== 'monthly') continue;
    const customValues = plan.customValues || {};
    const customDueDays = plan.customDueDays || {};
    const studentAddedAt = plan.studentAddedAt || {};
    const effectiveValue = (plan.periodValue != null ? plan.periodValue : plan.monthlyValue) || 0;
    const defaultDueDay = plan.defaultDueDay != null ? plan.defaultDueDay : 10;
    const studentIds = Array.isArray(plan.studentIds) ? plan.studentIds : [];
    for (const studentId of studentIds) {
      const stu = activeStudents.get(studentId);
      if (!stu) continue;
      const value = customValues[studentId] != null ? customValues[studentId] : effectiveValue;
      if (!(Number(value) > 0)) continue;
      const dueDay = stu.tuitionDay != null
        ? stu.tuitionDay
        : (customDueDays[studentId] != null ? customDueDays[studentId] : defaultDueDay);
      if (!isMembershipEligibleForMonth({
        planCreatedAt: plan.createdAt,
        studentAddedAt: studentAddedAt[studentId],
        referenceYear: refYear,
        referenceMonth: refMonth,
        dueDay,
      })) continue;
      monthlyCandidates.push({ studentId, planId });
    }
  }
  const conflictingStudentIds = findConflictingStudentIds(monthlyCandidates);
  if (conflictingStudentIds.size > 0) {
    console.warn(
      `[autoTuition] academy ${academyId}: ${conflictingStudentIds.size} student(s) ` +
      'in multiple monthly plans; automatic generation blocked for them'
    );
  }

  for (const planDoc of plansSnap.docs) {
    const plan = planDoc.data() || {};
    const planId = planDoc.id;
    const periodValue = plan.billingPeriod || 'monthly';
    const months = billingPeriodMonths(periodValue);
    // Planos cartão+mensal são assinatura recorrente automática no MP (decisão
    // de produto): NÃO geramos mensalidade avulsa para eles aqui — o débito sai
    // pela assinatura. Espelha Plan.isRecurring no cliente.
    const policy = plan.paymentMethodPolicy || 'both';
    if (periodValue === 'monthly' && policy === 'cardOnly') continue;

    const customValues = plan.customValues || {};
    const customDueDays = plan.customDueDays || {};
    const studentAddedAt = plan.studentAddedAt || {};
    const effectiveValue = (plan.periodValue != null ? plan.periodValue : plan.monthlyValue) || 0;
    const defaultDueDay = plan.defaultDueDay != null ? plan.defaultDueDay : 10;
    const studentIds = Array.isArray(plan.studentIds) ? plan.studentIds : [];

    for (const studentId of studentIds) {
      const stu = activeStudents.get(studentId);
      if (!stu) continue; // só alunos ativos

      const value = customValues[studentId] != null ? customValues[studentId] : effectiveValue;
      const rawDueDay = (stu.tuitionDay != null ? stu.tuitionDay
        : (customDueDays[studentId] != null ? customDueDays[studentId] : defaultDueDay));
      if (!isMembershipEligibleForMonth({
        planCreatedAt: plan.createdAt,
        studentAddedAt: studentAddedAt[studentId],
        referenceYear: refYear,
        referenceMonth: refMonth,
        dueDay: rawDueDay,
      })) continue;
      if (!(Number(value) > 0)) continue; // espelha .where((s) => s.value > 0)

      // Dedup / elegibilidade do período.
      const alreadyThisMonth = monthCharges.some((c) =>
        c.studentId === studentId && c.type === 'monthly_tuition');
      if (alreadyThisMonth) continue;
      if (periodValue === 'monthly') {
        if (conflictingStudentIds.has(studentId)) continue;
      } else {
        // Não-mensal: só cobra se passou o intervalo desde o último vencimento.
        let due = true;
        try {
          const histSnap = await acadRef.collection('financials')
            .where('studentId', '==', studentId)
            .where('planId', '==', planId)
            .where('type', '==', 'monthly_tuition')
            .get();
          const actives = histSnap.docs
            .map((d) => d.data() || {})
            .filter((d) => d.status !== 'cancelled' && d.dueDate && typeof d.dueDate.toDate === 'function');
          if (actives.length > 0) {
            actives.sort((a, b) => b.dueDate.toDate().getTime() - a.dueDate.toDate().getTime());
            const lastDue = actives[0].dueDate.toDate();
            const nextBilling = new Date(lastDue.getFullYear(), lastDue.getMonth() + months, lastDue.getDate());
            const ny = nextBilling.getFullYear();
            const nm = nextBilling.getMonth() + 1;
            due = ny < refYear || (ny === refYear && nm <= refMonth);
          }
        } catch (e) {
          // Em caso de falha de leitura, NÃO gera (seguro por padrão: evita
          // cobrança duplicada). Loga e segue.
          console.error(`[autoTuition] period check failed ${academyId}/${studentId}`, e && e.message);
          due = false;
        }
        if (!due) continue;
      }

      // Vencimento: dia do aluno (tuitionDay > custom > default), clampado ao
      // último dia do mês de referência (espelha o cliente).
      const lastDayOfMonth = new Date(refYear, refMonth, 0).getDate();
      const clampedDay = rawDueDay > lastDayOfMonth ? lastDayOfMonth : rawDueDay;
      const dueDate = billingDateAtStartOfDay(refYear, refMonth, clampedDay);

      const description = periodValue === 'monthly'
        ? 'Mensalidade'
        : (plan.name || 'Plano');

      try {
        // financials.amount é REAIS (canônico). Espelha PaymentService.create.
        const financialRef = acadRef.collection('financials').doc();
        const wasCreated = await createTuitionWithGuard({
          academyId,
          referenceMonth,
          studentId,
          financialRef,
          payload: {
            academyId,
            studentId,
            studentName: stu.fullName || stu.name || '',
            amount: Number(value),
            type: 'monthly_tuition',
            dueDate: admin.firestore.Timestamp.fromDate(dueDate),
            status: 'pending',
            description,
            referenceMonth,
            planId,
            paymentMethodPolicy: policy,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: 'system:autoTuition',
          },
        });
        if (!wasCreated) continue;
        // Atualiza o cache em memória para não duplicar dentro do mesmo run se
        // o aluno aparecer em mais de um plano (defensivo).
        monthCharges.push({ studentId, planId, type: 'monthly_tuition' });
        created++;
      } catch (e) {
        console.error(`[autoTuition] create failed ${academyId}/${studentId}`, e && e.message);
      }
    }
  }

  return created;
}

exports.generateAcademyTuitions = generateAcademyTuitions;

/**
 * Scheduled: Daily at 6:00 AM (Brasilia Time).
 * Action: per academy COM A FLAG LIGADA (settings.billing.autoTuitionEnabled),
 * gera as mensalidades do mês corrente de forma idempotente. SEGURO POR PADRÃO:
 * flag FALSE por padrão => nenhuma cobrança criada sem o dono habilitar.
 * REVISAR MODELO DE COBRANÇA ANTES DE HABILITAR.
 */
exports.scheduledMonthlyTuitionGeneration = functions.pubsub
  .schedule('0 6 * * *')
  .timeZone('America/Sao_Paulo')
  .onRun(async () => {
    console.log('Running scheduled monthly tuition generation');
    const now = new Date();
    const academiesSnapshot = await db.collection('academies').get();
    let totalCreated = 0;

    for (const academyDoc of academiesSnapshot.docs) {
      const academyId = academyDoc.id;
      try {
        // Gate por academia (FALSE por padrão). Lê settings/billing.
        let enabled = false;
        try {
          const billingSnap = await db
            .collection('academies').doc(academyId)
            .collection('settings').doc('billing')
            .get();
          enabled = billingSnap.exists && billingSnap.data()?.autoTuitionEnabled === true;
        } catch (_) {
          enabled = false; // sem settings => desligado
        }
        if (!enabled) continue;

        const created = await generateAcademyTuitions(academyId, now);
        totalCreated += created;
        if (created > 0) {
          console.log(`[autoTuition] academy ${academyId}: ${created} cobranca(s) gerada(s)`);
        }
      } catch (e) {
        // Falha de uma academia não aborta a base toda.
        console.error(`[autoTuition] academy ${academyId} failed`, e && e.message);
      }
    }

    console.log(`Monthly tuition generation completed (${totalCreated} created)`);
    return null;
  });

// ============================================================
// Gamification — server-authoritative milestones (streak + ranking)
// ============================================================
//
// A daily scheduled job that, PER ACADEMY, recomputes from REAL attendance:
//   1) the student's current consecutive-day attendance streak, and
//   2) the student's monthly attendance-ranking position per scope
//      (geral / adulto / kids),
// then writes `attendanceStreak` / `rankingPosition` achievements into the
// canonical `achievements` collection.
//
// SECURITY / PRIVACY (owner decision in /tmp/seguranca.txt):
//   - Values are ALWAYS recomputed server-side from the academy's own
//     attendance docs — NEVER trusted from any client counter.
//   - Streak and ranking milestones are PII-free counters/labels and are born
//     isPublic:true (visible among academy members).
//   - These NEVER touch the publicProfiles mirror (PUBLIC_PROFILE_SAFE_FIELDS
//     is unchanged); they live only in `achievements`.
//   - Idempotency: each auto-created milestone carries a deterministic
//     `autoKey`; we query-before-create by (studentId + autoKey) so a second
//     run (or the on-demand recompute callable in task 17) never duplicates.
//     Requires the composite index achievements(studentId ASC, autoKey ASC).
//   - The per-attendance "treinos totais" milestone already exists in the
//     client (attendance_service.dart) and is intentionally NOT duplicated
//     here (different autoKey namespace + different type).

// Attendance-streak thresholds (consecutive calendar days with a check-in)
// worth a milestone. Mirrors the spirit of the client's totals milestones but
// for *consecutive days* rather than lifetime totals.
const STREAK_DAY_THRESHOLDS = [3, 5, 7, 14, 21, 30, 60, 90, 180, 365];

// How many top positions of each monthly ranking scope earn a milestone.
const RANKING_TOP_N = 3;

// Local-time YYYY-MM-DD for a JS Date (process.env.TZ is pinned to Brazil in
// index.js, so getFullYear/getMonth/getDate are Brazil wall-clock).
function localDayKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

// Local-time YYYY-MM for a JS Date (the monthly ranking autoKey period).
// Same wall-clock 'YYYY-MM' format as referenceMonthKey above — delegates to
// it so the two call sites (ranking) and the billing reference-month logic
// can never drift apart.
function localMonthKey(d) {
  return referenceMonthKey(d);
}

// Pure: current consecutive-day streak ending at the most recent attendance
// day, given a set of distinct local day-keys (YYYY-MM-DD) and "today"/
// "yesterday" keys. The streak is only "current" if the latest attendance is
// today or yesterday (a gap of >1 day breaks it). Exposed (no Firestore) for
// reuse and testing. Mirrors the client's day-based notion of attendance.
function computeCurrentStreak(dayKeySet, todayKey, yesterdayKey) {
  if (!dayKeySet || dayKeySet.size === 0) return 0;
  const sorted = Array.from(dayKeySet).sort(); // lexicographic == chronological
  const latest = sorted[sorted.length - 1];
  // Stale streak: last check-in is older than yesterday → not current.
  if (latest !== todayKey && latest !== yesterdayKey) return 0;

  // Walk backwards day-by-day from `latest` while each previous calendar day is
  // also present.
  let streak = 0;
  let cursor = new Date(`${latest}T12:00:00`); // noon avoids DST edge issues
  // Guard the loop to a sane maximum (e.g. 2 years) to never spin forever.
  for (let i = 0; i < 800; i++) {
    const key = localDayKey(cursor);
    if (dayKeySet.has(key)) {
      streak++;
      cursor.setDate(cursor.getDate() - 1);
    } else {
      break;
    }
  }
  return streak;
}

// Pure: rank students by attendance-record count, highest first, ties broken by
// most-recent attendance (desc). Mirrors RankingService.rankFromPairs in the
// Flutter client so the server agrees with what the app shows. `pairs` is a list
// of { studentId, dateMs }. Returns [{ studentId, count, rank }] (1-based).
function rankFromPairs(pairs) {
  const counts = new Map();
  const mostRecent = new Map();
  for (const p of pairs) {
    counts.set(p.studentId, (counts.get(p.studentId) || 0) + 1);
    const cur = mostRecent.get(p.studentId);
    if (cur == null || p.dateMs > cur) mostRecent.set(p.studentId, p.dateMs);
  }
  const entries = Array.from(counts.keys()).map((id) => ({
    studentId: id,
    count: counts.get(id),
    mostRecentMs: mostRecent.get(id) || 0,
  }));
  entries.sort((a, b) => {
    if (b.count !== a.count) return b.count - a.count;
    return b.mostRecentMs - a.mostRecentMs;
  });
  return entries.map((e, i) => ({ studentId: e.studentId, count: e.count, rank: i + 1 }));
}

// Atomic idempotent write of an auto milestone, keyed by (studentId + autoKey).
// Returns true when a new doc was created, false when one already existed
// (no-op). NEVER touches publicProfiles.
//
// Uses a DETERMINISTIC doc-id (`${studentId}_${autoKey}`) plus `.create()`,
// which fails with ALREADY_EXISTS when the doc is present. This makes the
// creation atomic and closes the concurrency race between the daily cron
// (scheduledGamificationMilestones) and the on-demand callable
// (recomputeStudentMilestones) that could otherwise both observe "no existing
// doc" and both write, producing a duplicate milestone.
async function upsertAutoAchievement(academyId, fields) {
  const { studentId, autoKey } = fields;
  if (!studentId || !autoKey) return false;

  // Deterministic, collision-proof id. studentId is a Firestore uid and autoKey
  // is a system-generated slug, so neither contains '/' (the only char illegal
  // in a doc id), making this safe as a document path segment.
  const docId = `${studentId}_${autoKey}`;
  const docRef = db
    .collection('academies').doc(academyId)
    .collection('achievements')
    .doc(docId);

  try {
    // .create() is atomic: it fails if the doc already exists, so two concurrent
    // executions for the same (studentId, autoKey) cannot both succeed.
    await docRef.create({
      studentId,
      studentName: fields.studentName || 'Aluno',
      type: fields.type, // 'attendanceStreak' | 'rankingPosition'
      title: fields.title,
      description: fields.description || null,
      date: admin.firestore.Timestamp.fromDate(fields.date || new Date()),
      // Gamification PII-free fields (subset; the rest stay null for back-compat).
      streakDays: fields.streakDays != null ? fields.streakDays : null,
      rankingScope: fields.rankingScope || null,
      rankingRank: fields.rankingRank != null ? fields.rankingRank : null,
      iconKey: fields.iconKey || null,
      autoKey,
      // Owner decision: streak + ranking milestones are born public.
      isPublic: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: 'system:gamification',
    });

    // Auditoria (MED retention): marco NOVO de streak/ranking — avisa o aluno
    // (push + notificação interna). Idempotente: só chega aqui quando .create()
    // teve sucesso (marco inédito); se já existia (ALREADY_EXISTS) cai no catch
    // e NÃO re-notifica. Best-effort: falha de notificação não desfaz o marco.
    try {
      const uid = await getStudentUserId(studentId, academyId);
      if (uid) {
        const title = fields.type === 'rankingPosition'
          ? 'Novo marco no ranking!'
          : 'Nova conquista de sequência!';
        const body = fields.title || 'Voce desbloqueou uma nova conquista.';
        await sendToUser(uid, title, body, {
          type: 'achievement',
          achievementType: fields.type || '',
          academyId,
          actionUrl: '/portal/perfil',
        });
        await createInternalNotification(
          academyId, uid, 'achievement', 'normal',
          title, fields.description || body,
          { actionUrl: '/portal/perfil', actionLabel: 'Ver conquistas', expiresInDays: 30 }
        );
      }
    } catch (notifyErr) {
      console.error('[gamification] milestone notify failed', notifyErr && notifyErr.message);
    }

    return true;
  } catch (err) {
    // ALREADY_EXISTS (gRPC code 6) -> the milestone is already present: no-op.
    if (err && err.code === 6) return false;
    throw err;
  }
}

// Core worker: recompute streak + monthly ranking milestones for ONE academy.
// `onlyStudentId` (optional) restricts the streak pass to a single student —
// used by the on-demand recompute callable (task 17). Ranking is always
// computed academy-wide (you cannot rank one student in isolation) but only the
// requested student's position is written when `onlyStudentId` is set.
// Returns the number of NEW milestones created.
async function processAcademyGamification(academyId, onlyStudentId = null) {
  const now = new Date();
  const todayKey = localDayKey(now);
  const yesterdayKey = localDayKey(new Date(now.getTime() - 24 * 60 * 60 * 1000));
  const monthKey = localMonthKey(now);

  const acadRef = db.collection('academies').doc(academyId);

  // Denormalized student names (PII-free label fallback for the milestone).
  const studentNames = new Map();
  try {
    const studentsSnap = await acadRef.collection('students').get();
    for (const s of studentsSnap.docs) {
      const d = s.data() || {};
      studentNames.set(s.id, d.fullName || d.name || 'Aluno');
    }
  } catch (e) {
    console.error(`[gamification] students read failed ${academyId}`, e && e.message);
  }

  // Class → category map, to scope the ranking (kids vs adult). Matches the
  // client's _classIdsForCategory: kids = explicitly tagged kids; adult bucket =
  // adult-tagged PLUS untagged/legacy classes.
  const kidsClassIds = new Set();
  const adultClassIds = new Set();
  try {
    const classesSnap = await acadRef.collection('classes').get();
    for (const c of classesSnap.docs) {
      const cat = (c.data() || {}).category;
      if (cat === 'kids') kidsClassIds.add(c.id);
      else adultClassIds.add(c.id); // adult-tagged + untagged default to adult
    }
  } catch (e) {
    console.error(`[gamification] classes read failed ${academyId}`, e && e.message);
  }

  let created = 0;

  // -------- 1) Attendance STREAK (consecutive days) --------
  // Read a bounded recent window of attendance (last ~400 days) so the streak
  // computation has the days it needs without scanning all history. Grouped per
  // student into a set of distinct local day-keys.
  const streakWindowStart = new Date(now.getTime() - 400 * 24 * 60 * 60 * 1000);
  const perStudentDays = new Map(); // studentId -> Set<dayKey>
  try {
    let q = acadRef
      .collection('attendance')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(streakWindowStart));
    if (onlyStudentId) q = q.where('studentId', '==', onlyStudentId);
    const attSnap = await q.get();
    for (const doc of attSnap.docs) {
      const d = doc.data() || {};
      const sid = d.studentId;
      const ts = d.date;
      if (!sid || !ts || typeof ts.toDate !== 'function') continue;
      const dayKey = localDayKey(ts.toDate());
      let set = perStudentDays.get(sid);
      if (!set) { set = new Set(); perStudentDays.set(sid, set); }
      set.add(dayKey);
    }
  } catch (e) {
    console.error(`[gamification] attendance(streak) read failed ${academyId}`, e && e.message);
  }

  for (const [sid, daySet] of perStudentDays.entries()) {
    if (onlyStudentId && sid !== onlyStudentId) continue;
    const streak = computeCurrentStreak(daySet, todayKey, yesterdayKey);
    if (streak <= 0) continue;
    // Award every threshold the student has currently reached. autoKey is keyed
    // on the threshold (not the live count) so it is stable and idempotent: the
    // milestone "atingiu 7 dias" is created once, ever.
    for (const threshold of STREAK_DAY_THRESHOLDS) {
      if (streak < threshold) break;
      const ok = await upsertAutoAchievement(academyId, {
        studentId: sid,
        studentName: studentNames.get(sid),
        type: 'attendanceStreak',
        title: `Sequência de ${threshold} dias`,
        description: `${threshold} dias consecutivos de presença. Mantenha o ritmo!`,
        streakDays: threshold,
        iconKey: 'streak',
        autoKey: `streak_${threshold}`,
        date: now,
      });
      if (ok) created++;
    }
  }

  // -------- 2) Monthly RANKING position (geral / adulto / kids) --------
  // Recompute the current-month ranking server-side from real attendance and
  // award a milestone to the top N of each scope. autoKey is monthly, e.g.
  // rank_geral_2026-06, so it is idempotent within the month and a fresh
  // milestone is minted each new month.
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthAttendance = [];
  try {
    const monthSnap = await acadRef
      .collection('attendance')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(monthStart))
      .get();
    for (const doc of monthSnap.docs) {
      const d = doc.data() || {};
      if (!d.studentId || !d.date || typeof d.date.toDate !== 'function') continue;
      monthAttendance.push({
        studentId: d.studentId,
        classId: d.classId || null,
        dateMs: d.date.toDate().getTime(),
      });
    }
  } catch (e) {
    console.error(`[gamification] attendance(ranking) read failed ${academyId}`, e && e.message);
  }

  const scopes = [
    { id: 'geral', label: 'Geral', filter: null },
    { id: 'adulto', label: 'Adulto', filter: (a) => a.classId && adultClassIds.has(a.classId) },
    { id: 'kids', label: 'Kids', filter: (a) => a.classId && kidsClassIds.has(a.classId) },
  ];

  for (const scope of scopes) {
    const pairs = scope.filter
      ? monthAttendance.filter(scope.filter)
      : monthAttendance;
    if (pairs.length === 0) continue;
    const ranked = rankFromPairs(pairs);
    const autoKey = `rank_${scope.id}_${monthKey}`;
    for (const entry of ranked) {
      if (entry.rank > RANKING_TOP_N) break;
      if (onlyStudentId && entry.studentId !== onlyStudentId) continue;
      const ok = await upsertAutoAchievement(academyId, {
        studentId: entry.studentId,
        studentName: studentNames.get(entry.studentId),
        type: 'rankingPosition',
        title: `${entry.rank}º lugar no ranking ${scope.label}`,
        description: `Top ${entry.rank} de presença no ranking ${scope.label} de ${monthKey}.`,
        rankingScope: scope.id,
        rankingRank: entry.rank,
        iconKey: 'ranking',
        autoKey, // monthly idempotency key (per studentId via query-before-create)
        date: now,
      });
      if (ok) created++;
    }
  }

  return created;
}

// Exported for reuse by the on-demand recompute callable (task 17) and tests.
exports.processAcademyGamification = processAcademyGamification;
exports.computeCurrentStreak = computeCurrentStreak;
exports.rankFromGamificationPairs = rankFromPairs;

/**
 * Scheduled: Daily at 7:30 AM (Brasilia Time).
 * Action: per academy, recompute attendance streak + monthly ranking position
 * and write idempotent attendanceStreak/rankingPosition milestones.
 * Mirrors scheduledOverdueCheck's per-academy iteration shape.
 */
exports.scheduledGamificationMilestones = functions.pubsub
  .schedule('30 7 * * *')
  .timeZone('America/Sao_Paulo')
  .onRun(async () => {
    console.log('Running scheduled gamification milestones (streak + ranking)');

    const academiesSnapshot = await db.collection('academies').get();
    let totalCreated = 0;

    for (const academyDoc of academiesSnapshot.docs) {
      const academyId = academyDoc.id;
      try {
        const created = await processAcademyGamification(academyId);
        totalCreated += created;
        if (created > 0) {
          console.log(`[gamification] academy ${academyId}: ${created} new milestone(s)`);
        }
      } catch (e) {
        // Never let one academy's failure abort the whole cron.
        console.error(`[gamification] academy ${academyId} failed`, e && e.message);
      }
    }

    console.log(`Gamification milestones completed (${totalCreated} created)`);
    return null;
  });

/**
 * Returns true when `uid` is staff (admin OR instructor) of `academyId`,
 * read from userAcademyMapping. Mirrors the `isStaff` helper in index.js — kept
 * local here because that helper is not exported across modules.
 */
async function isAcademyStaff(uid, academyId) {
  const membership = await getUserAcademyMembership(uid, academyId);
  return !!(
    membership &&
    (membership.role === 'admin' || membership.role === 'instructor')
  );
}

/**
 * Returns true when `uid` has the grantable extra `permission` in `academyId`.
 * Mirrors the Firestore-rules helper hasExtraPermission(academyId, permission):
 * reads ONLY userAcademyMapping.academyDetails[academyId].extraPermissions
 * (the same single source the rules trust), so CF authorization can't diverge
 * from the client-write authorization. Returns the membership role alongside so
 * callers can express "admin always; instructor needs <permission>" in one read.
 *
 * Used to close the gap where a demand action (e.g. granting attendance) runs
 * server-side via the Admin SDK — which bypasses Firestore rules — and would
 * otherwise let any instructor act despite the rules requiring the extra
 * permission for the equivalent client write.
 */
async function getMembershipWithExtraPerms(uid, academyId) {
  if (!uid || !academyId) return { role: null, extraPermissions: [] };
  const snap = await db.collection('userAcademyMapping').doc(uid).get();
  if (!snap.exists) return { role: null, extraPermissions: [] };
  const entry = ((snap.data() || {}).academyDetails || {})[academyId] || {};
  const perms = Array.isArray(entry.extraPermissions) ? entry.extraPermissions : [];
  return { role: entry.role || null, extraPermissions: perms };
}

/**
 * "admin always; instructor only with `permission`" gate, matching the rules
 * pattern isAcademyAdmin || (isAcademyInstructor && hasExtraPermission(...)).
 * Admins are unconditionally allowed; instructors must carry the permission;
 * everyone else is denied.
 */
async function staffCanWithPermission(uid, academyId, permission) {
  const { role, extraPermissions } =
    await getMembershipWithExtraPerms(uid, academyId);
  if (role === 'admin') return true;
  if (role === 'instructor') return extraPermissions.includes(permission);
  return false;
}

/**
 * HTTP Callable: on-demand recompute of streak + ranking milestones for ONE
 * student (task 17). Used by the professor's per-student / bulk "recalcular
 * marcos" action.
 *
 * Body: { academyId: string, studentId: string }
 *
 * SECURITY / PRIVACY (owner decision in /tmp/seguranca.txt):
 *   - Gated to STAFF (admin OR instructor) of the academy via the auth context.
 *     A non-staff caller gets permission-denied.
 *   - Values are recomputed SERVER-SIDE from real attendance — the client only
 *     names the student, never a counter.
 *   - Fully idempotent: delegates to processAcademyGamification(academyId,
 *     studentId), whose upsertAutoAchievement query-before-creates by
 *     (studentId + autoKey). A second call is a no-op (0 created).
 *   - Streak/ranking milestones are born isPublic:true and NEVER touch the
 *     publicProfiles mirror (PUBLIC_PROFILE_SAFE_FIELDS is unchanged).
 */
exports.recomputeStudentMilestones = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError('unauthenticated', 'Login required.');
  }

  const data = request.data || {};
  const academyId = (data.academyId || '').toString();
  const studentId = (data.studentId || '').toString();
  if (!academyId || !studentId) {
    throw new HttpsError(
      'invalid-argument',
      'academyId e studentId são obrigatórios.'
    );
  }

  // Staff gate: only admin/instructor of THIS academy may recompute.
  if (!(await isAcademyStaff(auth.uid, academyId))) {
    throw new HttpsError(
      'permission-denied',
      'Apenas a equipe da academia pode recalcular marcos.'
    );
  }

  // Server-authoritative, idempotent recompute for the single student.
  const created = await processAcademyGamification(academyId, studentId);
  console.log(
    `[gamification] on-demand recompute academy=${academyId} student=${studentId}: ${created} new milestone(s)`
  );
  return { created };
});

// ============================================
// Cloud Functions - HTTP Callable (notifications)
// ============================================

/**
 * HTTP Callable: Send custom notification to academy students
 * Used by admin to send broadcast messages
 */
exports.sendAcademyNotification = onCall(async (request) => {
  const data = request.data || {};
  const context = { auth: request.auth };
  // Verify authentication
  if (!context.auth) {
    throw new HttpsError(
      'unauthenticated',
      'User must be authenticated'
    );
  }

  const { academyId, title, body, notificationData } = data;

  if (!academyId || !title || !body) {
    throw new HttpsError(
      'invalid-argument',
      'academyId, title, and body are required'
    );
  }

  // Verify user is admin of the academy
  const academyDoc = await db.collection('academies').doc(academyId).get();
  if (!academyDoc.exists) {
    throw new HttpsError('not-found', 'Academy not found');
  }

  const academy = academyDoc.data();
  if (academy.adminUserId !== context.auth.uid) {
    throw new HttpsError(
      'permission-denied',
      'User is not admin of this academy'
    );
  }

  // Send notification to all academy students
  const success = await sendToTopic(
    `academy_${academyId}`,
    title,
    body,
    notificationData || {}
  );

  return { success };
});

/**
 * HTTP Callable: Send notification to specific user
 * Used for testing or targeted notifications
 */
exports.sendUserNotification = onCall(async (request) => {
  const data = request.data || {};
  const context = { auth: request.auth };
  // Verify authentication
  if (!context.auth) {
    throw new HttpsError(
      'unauthenticated',
      'User must be authenticated'
    );
  }

  const { targetUserId, title, body, notificationData, academyId } = data;

  if (!targetUserId || !title || !body || !academyId) {
    throw new HttpsError(
      'invalid-argument',
      'targetUserId, title, body, and academyId are required'
    );
  }

  // Verify user is admin of the academy
  const academyDoc = await db.collection('academies').doc(academyId).get();
  if (!academyDoc.exists) {
    throw new HttpsError('not-found', 'Academy not found');
  }

  const academy = academyDoc.data();
  if (academy.adminUserId !== context.auth.uid) {
    throw new HttpsError(
      'permission-denied',
      'User is not admin of this academy'
    );
  }

  // Send notification to specific user
  const success = await sendToUser(
    targetUserId,
    title,
    body,
    notificationData || {}
  );

  return { success };
});

// ============================================
// Payment Helper Functions
// ============================================

const ABACATEPAY_API_URL = 'https://api.abacatepay.com/v1';
const MIN_WITHDRAWAL_AMOUNT = 1000; // R$ 10.00

function getAbacatePayApiKey() {
  return process.env.ABACATEPAY_API_KEY || null;
}

function sanitizeString(value) {
  if (typeof value !== 'string') return null;
  return value.replace(/[<>"']/g, '').trim().substring(0, 500);
}

function validateAmount(amount) {
  if (typeof amount !== 'number') {
    return { valid: false, error: 'Amount must be a number' };
  }
  if (amount <= 0) {
    return { valid: false, error: 'Amount must be positive' };
  }
  if (amount > 100000000) {
    return { valid: false, error: 'Amount exceeds maximum allowed' };
  }
  if (!Number.isInteger(amount)) {
    return { valid: false, error: 'Amount must be an integer (in centavos)' };
  }
  return { valid: true };
}

function validateCPF(cpf) {
  const cleaned = cpf.replace(/\D/g, '');
  if (cleaned.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(cleaned)) return false;

  let sum = 0;
  for (let i = 0; i < 9; i++) {
    sum += parseInt(cleaned[i]) * (10 - i);
  }
  let remainder = (sum * 10) % 11;
  if (remainder === 10 || remainder === 11) remainder = 0;
  if (remainder !== parseInt(cleaned[9])) return false;

  sum = 0;
  for (let i = 0; i < 10; i++) {
    sum += parseInt(cleaned[i]) * (11 - i);
  }
  remainder = (sum * 10) % 11;
  if (remainder === 10 || remainder === 11) remainder = 0;
  if (remainder !== parseInt(cleaned[10])) return false;

  return true;
}

function validateCardNumber(cardNumber) {
  const cleaned = cardNumber.replace(/\D/g, '');
  if (cleaned.length < 13 || cleaned.length > 19) return false;

  let sum = 0;
  let isEven = false;
  for (let i = cleaned.length - 1; i >= 0; i--) {
    let digit = parseInt(cleaned[i]);
    if (isEven) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
    isEven = !isEven;
  }
  return sum % 10 === 0;
}

function isValidPixKeyType(type) {
  return ['cpf', 'cnpj', 'email', 'phone', 'random'].includes(type);
}

async function getUserAcademyInfo(uid) {
  const mappingDoc = await db.collection('userAcademyMapping').doc(uid).get();
  const mappingData = mappingDoc.data();

  const academyId = mappingData?.primaryAcademyId || mappingData?.academyIds?.[0];

  // Primary: get role and studentId from userAcademyMapping.academyDetails
  const academyDetails = academyId && mappingData?.academyDetails?.[academyId];
  if (academyDetails?.role) {
    return {
      academyId,
      role: academyDetails.role,
      studentId: academyDetails.studentId,
    };
  }

  // Fallback: get role and studentId from academy-scoped user doc
  if (academyId) {
    const academyUserDoc = await db.collection('academies').doc(academyId).collection('users').doc(uid).get();
    const academyUserData = academyUserDoc.data();
    if (academyUserData?.role) {
      return {
        academyId,
        role: academyUserData.role,
        studentId: academyUserData.studentId,
      };
    }
  }

  return { academyId };
}

/**
 * Multi-academy aware variant of getUserAcademyInfo: resolves the caller's
 * membership in ONE SPECIFIC academy instead of only the primary one, so
 * users of a second academy aren't wrongly denied. Membership evidence comes
 * from userAcademyMapping (primaryAcademyId / academyIds / academyDetails
 * entry); role/studentId for THAT academy come from academyDetails[academyId]
 * with the academy-scoped user doc as fallback (same sources as
 * getUserAcademyInfo and index.js resolveRole).
 * Returns { academyId, role, studentId } or null when uid does NOT belong to
 * that academy. For single-academy users the result is identical to
 * getUserAcademyInfo.
 */
async function getUserAcademyMembership(uid, academyId) {
  if (!uid || !academyId) return null;
  const mappingDoc = await db.collection('userAcademyMapping').doc(uid).get();
  const mappingData = mappingDoc.data();

  const details = mappingData?.academyDetails?.[academyId];
  const belongs =
    mappingData?.primaryAcademyId === academyId ||
    (Array.isArray(mappingData?.academyIds) &&
      mappingData.academyIds.includes(academyId)) ||
    details !== undefined;
  if (!belongs) return null;

  if (details?.role) {
    return { academyId, role: details.role, studentId: details.studentId };
  }

  // Fallback: legacy academies often have academyIds set but no academyDetails
  // entry — the role/studentId live only in the academy-scoped user doc.
  const academyUserDoc = await db.collection('academies').doc(academyId)
    .collection('users').doc(uid).get();
  const academyUserData = academyUserDoc.data();
  if (academyUserData?.role) {
    return {
      academyId,
      role: academyUserData.role,
      studentId: academyUserData.studentId,
    };
  }

  return { academyId };
}

// ============================================
// Cloud Functions - Payment Callable Functions
// ============================================

/**
 * HTTP Callable: Create PIX payment for a financial record (tuition)
 * Called from Flutter app via FirebaseFunctions.instance.httpsCallable
 */
exports.createPixPayment = onCall(async (request) => {
  const data = request.data || {};
  const context = { auth: request.auth };
  // 1. Authenticate
  if (!context.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { academyId, amount, description, financialId, studentId, studentName } = data;

  // 2. Validate required fields
  if (!academyId || !amount || !financialId || !studentId) {
    throw new HttpsError(
      'invalid-argument',
      'Missing required fields: academyId, amount, financialId, studentId'
    );
  }

  // 3. Validate user belongs to THIS academy (multi-academy aware)
  const userInfo = await getUserAcademyMembership(context.auth.uid, academyId);
  if (!userInfo) {
    throw new HttpsError('permission-denied', 'Access denied: Invalid academy');
  }

  // 4. Validate user is paying for themselves, is staff, or is the responsible
  // adult for this (kids) student.
  const isStaff = userInfo.role === 'admin' || userInfo.role === 'instructor';
  if (!isStaff && userInfo.studentId !== studentId) {
    const stuSnap = await db.doc(`academies/${academyId}/students/${studentId}`).get();
    if (!stuSnap.exists || stuSnap.data()?.responsibleUserId !== context.auth.uid) {
      throw new HttpsError('permission-denied', 'Access denied: Cannot pay for another student');
    }
  }

  // 5. Validate amount
  const amountValidation = validateAmount(amount);
  if (!amountValidation.valid) {
    throw new HttpsError('invalid-argument', amountValidation.error || 'Invalid amount');
  }

  // 6. Check AbacatePay enabled
  const academySnap = await db.doc(`academies/${academyId}`).get();
  if (!academySnap.exists) {
    throw new HttpsError('not-found', 'Academy not found');
  }
  if (!academySnap.data()?.abacatePayEnabled) {
    throw new HttpsError('failed-precondition', 'Payment processing not enabled for this academy');
  }

  // 7. Verify financial record
  const financialSnap = await db.doc(`academies/${academyId}/financials/${financialId}`).get();
  if (!financialSnap.exists) {
    throw new HttpsError('not-found', 'Financial record not found');
  }
  const financialData = financialSnap.data();
  if (financialData.studentId !== studentId) {
    throw new HttpsError('permission-denied', 'Financial record does not belong to this student');
  }
  if (financialData.status === 'paid') {
    throw new HttpsError('already-exists', 'This payment has already been completed');
  }

  // 7b. Idempotency: if a still-valid PIX already exists for this charge, return
  // it instead of creating a SECOND gateway charge. The kid (own login) and the
  // responsible adult can both open the same charge — both must get the SAME PIX.
  const existingPixExpiry =
    financialData.pixExpiresAt && typeof financialData.pixExpiresAt.toMillis === 'function'
      ? financialData.pixExpiresAt.toMillis()
      : 0;
  if (financialData.externalId && financialData.pixCode && existingPixExpiry > Date.now()) {
    return {
      pixCode: financialData.pixCode,
      qrCodeUrl: financialData.pixQrCode || '',
      abacatePayId: financialData.externalId,
      expiresAt: financialData.pixExpiresAt.toDate().toISOString(),
    };
  }

  // 8. Get API key
  const apiKey = getAbacatePayApiKey();
  if (!apiKey) {
    console.error('ABACATEPAY_API_KEY not configured');
    throw new HttpsError('internal', 'Payment service not configured');
  }

  // 9. Call AbacatePay API - pixQrCode/create
  const response = await fetch(`${ABACATEPAY_API_URL}/pixQrCode/create`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      amount,
      description: sanitizeString(description) || 'Mensalidade',
      externalReference: `${academyId}_${financialId}`,
      expiresIn: 86400,
    }),
  });

  if (!response.ok) {
    const errorData = await response.json();
    console.error('AbacatePay API error:', errorData);
    throw new HttpsError('internal', 'Failed to create PIX payment');
  }

  const responseData = await response.json();
  const pixData = responseData.data || responseData;
  const abacatePayId = pixData.id;

  if (!abacatePayId) {
    console.error('No PIX ID in AbacatePay response:', JSON.stringify(responseData));
    throw new HttpsError('internal', 'Payment service returned invalid response');
  }

  // 10. Update financial record with PIX info (pixExpiresAt drives idempotency
  // above so a second request within the window reuses this same charge).
  await db.doc(`academies/${academyId}/financials/${financialId}`).update({
    pixCode: pixData.brCode || null,
    pixQrCode: pixData.brCodeBase64 || null,
    externalId: abacatePayId,
    pixExpiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 11. Create walletTransaction record
  await db.collection(`academies/${academyId}/walletTransactions`).add({
    academyId,
    type: 'payment',
    amount,
    status: 'pending',
    financialId,
    studentId,
    studentName: sanitizeString(studentName) || 'Aluno',
    abacatePayTransactionId: abacatePayId,
    pixCode: pixData.brCode || null,
    qrCodeUrl: pixData.brCodeBase64 || null,
    description: sanitizeString(description) || 'Mensalidade',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    pixCode: pixData.brCode || '',
    qrCodeUrl: pixData.brCodeBase64 || '',
    abacatePayId,
    expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
  };
});

/**
 * HTTP Callable: Create PIX payment for a store order
 */
exports.createOrderPixPayment = onCall(async (request) => {
  const data = request.data || {};
  const context = { auth: request.auth };
  // 1. Authenticate
  if (!context.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { academyId, amount, description, orderId, studentId, studentName } = data;

  // 2. Validate required fields
  if (!academyId || !amount || !orderId || !studentId) {
    throw new HttpsError(
      'invalid-argument',
      'Missing required fields: academyId, amount, orderId, studentId'
    );
  }

  // 3. Validate user belongs to THIS academy (multi-academy aware)
  const userInfo = await getUserAcademyMembership(context.auth.uid, academyId);
  if (!userInfo) {
    throw new HttpsError('permission-denied', 'Access denied: Invalid academy');
  }

  // 4. Validate user is paying for themselves, is staff, or is the responsible
  // adult for this (kids) student.
  const isStaff = userInfo.role === 'admin' || userInfo.role === 'instructor';
  if (!isStaff && userInfo.studentId !== studentId) {
    const stuSnap = await db.doc(`academies/${academyId}/students/${studentId}`).get();
    if (!stuSnap.exists || stuSnap.data()?.responsibleUserId !== context.auth.uid) {
      throw new HttpsError('permission-denied', 'Access denied: Cannot pay for another student');
    }
  }

  // 5. Validate amount
  const amountValidation = validateAmount(amount);
  if (!amountValidation.valid) {
    throw new HttpsError('invalid-argument', amountValidation.error || 'Invalid amount');
  }

  // 6. Check AbacatePay enabled
  const academySnap = await db.doc(`academies/${academyId}`).get();
  if (!academySnap.exists) {
    throw new HttpsError('not-found', 'Academy not found');
  }
  if (!academySnap.data()?.abacatePayEnabled) {
    throw new HttpsError('failed-precondition', 'Payment processing not enabled for this academy');
  }

  // 7. Verify order
  const orderRef = db.doc(`academies/${academyId}/storeOrders/${orderId}`);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  const orderData = orderSnap.data();
  if (orderData.studentId !== studentId) {
    throw new HttpsError('permission-denied', 'Order does not belong to this student');
  }
  if (orderData.status !== 'pending_payment') {
    throw new HttpsError('failed-precondition', 'This order is not pending payment');
  }

  // 8. SECURITY (preco autoritativo da LOJA): o pedido e criado client-side,
  // entao items[].price/total NAO sao confiaveis. Recomputa o total em REAIS
  // a partir de storeProducts e cobra ESSE valor — o amount do cliente vira
  // apenas cross-check.
  const orderTotal = await orderAuthoritativeTotalReais(academyId, orderData);
  if (Math.abs(orderTotal - amount) > 1) {
    throw new HttpsError(
      'invalid-argument',
      `Amount (${amount}) does not match order total (${orderTotal})`
    );
  }
  // Grava o total autoritativo de volta no pedido (validacao de valor do
  // settle compara contra o numero correto).
  if (Math.abs((Number(orderData.total ?? orderData.totalAmount) || 0) -
      orderTotal) > 0.005) {
    await orderRef.update({
      total: orderTotal,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // 9. Get API key
  const apiKey = getAbacatePayApiKey();
  if (!apiKey) {
    console.error('ABACATEPAY_API_KEY not configured');
    throw new HttpsError('internal', 'Payment service not configured');
  }

  // 10. Call AbacatePay API - pixQrCode/create
  const response = await fetch(`${ABACATEPAY_API_URL}/pixQrCode/create`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      // Cobra o total AUTORITATIVO (reais -> cents), nunca o amount do cliente.
      amount: Math.round(orderTotal * 100),
      description: sanitizeString(description) || 'Pedido da Loja',
      externalReference: `${academyId}_order_${orderId}`,
      expiresIn: 86400,
    }),
  });

  if (!response.ok) {
    const errorData = await response.json();
    console.error('AbacatePay API error:', errorData);
    throw new HttpsError('internal', 'Failed to create PIX payment');
  }

  const responseData = await response.json();
  const pixData = responseData.data || responseData;
  const abacatePayId = pixData.id;

  if (!abacatePayId) {
    console.error('No PIX ID in AbacatePay response:', JSON.stringify(responseData));
    throw new HttpsError('internal', 'Payment service returned invalid response');
  }

  // 11. Create walletTransaction record
  await db.collection(`academies/${academyId}/walletTransactions`).add({
    academyId,
    type: 'payment',
    amount: Math.round(orderTotal * 100), // cents (autoritativo; wallet display)
    status: 'pending',
    financialId: `order_${orderId}`,
    studentId,
    studentName: sanitizeString(studentName) || 'Aluno',
    abacatePayTransactionId: abacatePayId,
    pixCode: pixData.brCode || null,
    qrCodeUrl: pixData.brCodeBase64 || null,
    description: sanitizeString(description) || 'Pedido da Loja',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 12. Update order with payment info
  await orderRef.update({
    abacatePayTransactionId: abacatePayId,
    externalPaymentId: abacatePayId,
    pixCode: pixData.brCode,
    qrCodeUrl: pixData.brCodeBase64,
    paymentMethod: 'pix',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    pixCode: pixData.brCode || '',
    qrCodeUrl: pixData.brCodeBase64 || '',
    abacatePayId,
    expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
  };
});

/**
 * HTTP Callable: Create card payment for financial or order
 */
exports.createCardPayment = onCall(async (request) => {
  const data = request.data || {};
  const context = { auth: request.auth };
  // 1. Authenticate
  if (!context.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const {
    academyId, amount, description, financialId, studentId, studentName,
    cardNumber, cardHolder, expirationMonth, expirationYear, cvv, cpf,
  } = data;

  // 2. Validate required fields
  if (!academyId || !amount || !financialId || !studentId) {
    throw new HttpsError(
      'invalid-argument',
      'Missing required fields: academyId, amount, financialId, studentId'
    );
  }

  // 3. Validate user belongs to THIS academy (multi-academy aware)
  const userInfo = await getUserAcademyMembership(context.auth.uid, academyId);
  if (!userInfo) {
    throw new HttpsError('permission-denied', 'Access denied: Invalid academy');
  }

  // 4. Validate user is paying for themselves, is staff, or is the responsible
  // adult for this (kids) student.
  const isStaff = userInfo.role === 'admin' || userInfo.role === 'instructor';
  if (!isStaff && userInfo.studentId !== studentId) {
    const stuSnap = await db.doc(`academies/${academyId}/students/${studentId}`).get();
    if (!stuSnap.exists || stuSnap.data()?.responsibleUserId !== context.auth.uid) {
      throw new HttpsError('permission-denied', 'Access denied: Cannot pay for another student');
    }
  }

  // 5. Validate amount
  const amountValidation = validateAmount(amount);
  if (!amountValidation.valid) {
    throw new HttpsError('invalid-argument', amountValidation.error || 'Invalid amount');
  }

  // 6. Validate card data
  if (!cardNumber || !cardHolder || !expirationMonth || !expirationYear || !cvv || !cpf) {
    throw new HttpsError(
      'invalid-argument',
      'Missing card data: cardNumber, cardHolder, expirationMonth, expirationYear, cvv, cpf'
    );
  }

  const cleanedCardNumber = cardNumber.toString().replace(/\D/g, '');
  if (!validateCardNumber(cleanedCardNumber)) {
    throw new HttpsError('invalid-argument', 'Invalid card number');
  }

  if (!validateCPF(cpf)) {
    throw new HttpsError('invalid-argument', 'Invalid CPF');
  }

  const month = parseInt(expirationMonth, 10);
  const year = parseInt(expirationYear, 10);
  if (isNaN(month) || month < 1 || month > 12) {
    throw new HttpsError('invalid-argument', 'Invalid expiration month');
  }

  const currentDate = new Date();
  const currentYear = currentDate.getFullYear() % 100;
  const currentMonth = currentDate.getMonth() + 1;
  if (year < currentYear || (year === currentYear && month < currentMonth)) {
    throw new HttpsError('invalid-argument', 'Card has expired');
  }

  const cleanedCvv = cvv.toString().replace(/\D/g, '');
  if (cleanedCvv.length < 3 || cleanedCvv.length > 4) {
    throw new HttpsError('invalid-argument', 'Invalid CVV');
  }

  // 7. Check AbacatePay enabled
  const academySnap = await db.doc(`academies/${academyId}`).get();
  if (!academySnap.exists) {
    throw new HttpsError('not-found', 'Academy not found');
  }
  if (!academySnap.data()?.abacatePayEnabled) {
    throw new HttpsError('failed-precondition', 'Payment processing not enabled for this academy');
  }

  // 8. Verify financial record (if not a store order)
  if (!financialId.startsWith('order_')) {
    const financialSnap = await db.doc(`academies/${academyId}/financials/${financialId}`).get();
    if (!financialSnap.exists) {
      throw new HttpsError('not-found', 'Financial record not found');
    }
    const financialData = financialSnap.data();
    if (financialData.studentId !== studentId) {
      throw new HttpsError('permission-denied', 'Financial record does not belong to this student');
    }
    if (financialData.status === 'paid') {
      throw new HttpsError('already-exists', 'This payment has already been completed');
    }
  }

  // 9. Get API key
  const apiKey = getAbacatePayApiKey();
  if (!apiKey) {
    console.error('ABACATEPAY_API_KEY not configured');
    throw new HttpsError('internal', 'Payment service not configured');
  }

  // 10. Call AbacatePay card endpoint
  const response = await fetch(`${ABACATEPAY_API_URL}/card/charge`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      amount,
      description: sanitizeString(description) || 'Pagamento',
      card: {
        number: cleanedCardNumber,
        holderName: sanitizeString(cardHolder) || '',
        expirationMonth: expirationMonth.toString().padStart(2, '0'),
        expirationYear: year.toString(),
        cvv: cleanedCvv,
      },
      customer: {
        document: cpf.replace(/\D/g, ''),
      },
      metadata: {
        academyId,
        financialId,
        studentId,
      },
    }),
  });

  const responseData = await response.json();

  if (!response.ok || responseData.status === 'declined' || responseData.status === 'error') {
    console.warn(`Card payment failed for user ${context.auth.uid}: ${responseData.message}`);
    throw new HttpsError(
      'aborted',
      responseData.message || 'Pagamento recusado'
    );
  }

  // 11. Create transaction record
  const isApproved = responseData.status === 'approved';
  await db.collection(`academies/${academyId}/walletTransactions`).add({
    academyId,
    type: 'payment',
    amount,
    status: isApproved ? 'completed' : 'pending',
    financialId,
    studentId,
    studentName: sanitizeString(studentName) || 'Aluno',
    abacatePayTransactionId: responseData.id,
    paymentMethod: 'card',
    description: sanitizeString(description) || 'Pagamento',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    completedAt: isApproved ? admin.firestore.FieldValue.serverTimestamp() : null,
  });

  // 12. If approved, update financial record and wallet
  if (isApproved) {
    // Update wallet balance (deduct gateway fee - R$0.80 = 80 centavos)
    const gatewayFee = 80;
    const netAmount = Math.max(amount - gatewayFee, 0);
    const walletRef = db.doc(`academies/${academyId}/wallet/balance`);
    const walletSnap = await walletRef.get();

    if (!walletSnap.exists) {
      await walletRef.set({
        academyId,
        availableBalance: netAmount,
        pendingBalance: 0,
        totalReceived: amount,
        totalFees: gatewayFee,
        totalWithdrawn: 0,
        transactionCount: 1,
        lastTransactionAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      await walletRef.update({
        availableBalance: admin.firestore.FieldValue.increment(netAmount),
        totalReceived: admin.firestore.FieldValue.increment(amount),
        totalFees: admin.firestore.FieldValue.increment(gatewayFee),
        transactionCount: admin.firestore.FieldValue.increment(1),
        lastTransactionAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Update financial record or store order
    if (financialId.startsWith('order_')) {
      // Store order: update status + decrement stock
      const orderId = financialId.replace('order_', '');
      const orderRef = db.doc(`academies/${academyId}/storeOrders/${orderId}`);
      const orderSnap = await orderRef.get();
      if (orderSnap.exists && orderSnap.data()?.status === 'pending_payment') {
        await orderRef.update({
          status: 'paid',
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
          paymentMethod: 'card',
          externalPaymentId: responseData.id,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Decrement stock for in_stock products
        const items = orderSnap.data()?.items;
        if (items) {
          for (const item of items) {
            const productRef = db.doc(
              `academies/${academyId}/storeProducts/${item.productId}`
            );
            const productSnap = await productRef.get();
            if (productSnap.exists &&
                productSnap.data()?.stockType === 'in_stock') {
              await productRef.update({
                stockQuantity: admin.firestore.FieldValue.increment(
                  -item.quantity
                ),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }
    } else {
      await db.doc(`academies/${academyId}/financials/${financialId}`).update({
        status: 'paid',
        paymentDate: admin.firestore.FieldValue.serverTimestamp(),
        method: 'card',
        // Canonical gateway fields (read by the Dart Payment model), alongside
        // the legacy AbacatePay-specific fields kept for back-compat.
        paymentGateway: 'abacatepay',
        gatewayPaymentId: responseData.id,
        paidViaAbacatePay: true,
        abacatePayTransactionId: responseData.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  // Notify admin about payment received
  if (isApproved) {
    const isOrder = financialId.startsWith('order_');
    const notifTitle = isOrder ? 'Pedido Pago' : 'Pagamento Recebido';
    const amtFmt = (amount / 100).toFixed(2);
    const sName = sanitizeString(studentName) || 'Aluno';
    const orderCode = financialId.replace('order_', '').slice(-6).toUpperCase();
    const notifMessage = isOrder ?
      `${sName} pagou o pedido #${orderCode} - R$ ${amtFmt} via cartão.` :
      `${sName} pagou R$ ${amtFmt} via cartão.`;

    await notifyAdminCF(academyId, isOrder ? 'order_paid' : 'payment_received', notifTitle, notifMessage, {
      financialId,
      studentId,
    });
  }

  return {
    success: isApproved,
    transactionId: responseData.id,
    message: isApproved ? 'Pagamento aprovado!' : 'Aguardando confirmacao',
  };
});

/**
 * HTTP Callable: Request withdrawal to PIX key
 * Only academy owner can request withdrawals
 */
exports.requestWithdrawal = onCall(async (request) => {
  const data = request.data || {};
  const context = { auth: request.auth };
  // 1. Authenticate
  if (!context.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { academyId, amount, pixKey, pixKeyType } = data;

  // 2. Validate required fields
  if (!academyId || !amount || !pixKey || !pixKeyType) {
    throw new HttpsError(
      'invalid-argument',
      'Missing required fields: academyId, amount, pixKey, pixKeyType'
    );
  }

  // 3. Validate user belongs to THIS academy (multi-academy aware)
  const userInfo = await getUserAcademyMembership(context.auth.uid, academyId);
  if (!userInfo) {
    throw new HttpsError('permission-denied', 'Access denied: Invalid academy');
  }

  // 4. Validate user is academy owner
  const academySnap = await db.doc(`academies/${academyId}`).get();
  if (!academySnap.exists) {
    throw new HttpsError('not-found', 'Academy not found');
  }
  const academyData = academySnap.data();
  if (academyData.ownerId !== context.auth.uid) {
    throw new HttpsError(
      'permission-denied',
      'Only the academy owner can request withdrawals'
    );
  }

  // 4b. Gate barato de defesa em profundidade (auditoria — fluxo LATENTE):
  // saque é parte do AbacatePay, que está DESLIGADO em prod (só Mercado Pago).
  // Exige abacatePayEnabled===true antes de qualquer chamada externa, igual aos
  // demais endpoints AbacatePay deste arquivo. NÃO refatora o resto do fluxo.
  if (academyData.abacatePayEnabled !== true) {
    throw new HttpsError('failed-precondition',
      'Saque não está disponível para esta academia.');
  }

  // 5. Validate amount
  const amountValidation = validateAmount(amount);
  if (!amountValidation.valid) {
    throw new HttpsError('invalid-argument', amountValidation.error || 'Invalid amount');
  }
  if (amount < MIN_WITHDRAWAL_AMOUNT) {
    throw new HttpsError(
      'invalid-argument',
      `Minimum withdrawal amount is R$ ${(MIN_WITHDRAWAL_AMOUNT / 100).toFixed(2)}`
    );
  }

  // 6. Validate PIX key
  if (!isValidPixKeyType(pixKeyType)) {
    throw new HttpsError('invalid-argument', 'Invalid PIX key type');
  }
  const sanitizedPixKey = sanitizeString(pixKey);
  if (!sanitizedPixKey) {
    throw new HttpsError('invalid-argument', 'Invalid PIX key');
  }

  // 7. Check wallet balance
  const walletRef = db.doc(`academies/${academyId}/wallet/balance`);
  const walletSnap = await walletRef.get();
  if (!walletSnap.exists) {
    throw new HttpsError(
      'failed-precondition',
      'No wallet found. You need to receive payments first.'
    );
  }
  const walletData = walletSnap.data();
  const availableBalance = walletData.availableBalance || 0;
  if (availableBalance < amount) {
    throw new HttpsError(
      'failed-precondition',
      `Insufficient balance. Available: R$ ${(availableBalance / 100).toFixed(2)}`
    );
  }

  // 8. Get API key
  const apiKey = getAbacatePayApiKey();
  if (!apiKey) {
    throw new HttpsError('internal', 'Payment processing not configured');
  }

  // 9. Call AbacatePay withdraw endpoint
  let abacatePayResponse;
  try {
    const response = await fetch(`${ABACATEPAY_API_URL}/pix/withdraw`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount,
        pixKey: sanitizedPixKey,
        pixKeyType,
        metadata: {
          academyId,
          requestedBy: context.auth.uid,
        },
      }),
    });

    if (!response.ok) {
      const errorData = await response.json();
      console.error('AbacatePay withdrawal error:', errorData);
      throw new HttpsError(
        'internal',
        errorData.message || 'Failed to process withdrawal'
      );
    }

    abacatePayResponse = await response.json();
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error('AbacatePay API error:', error);
    throw new HttpsError('internal', 'Failed to connect to payment provider');
  }

  // 10. Atomic wallet update + transaction record
  try {
    await db.runTransaction(async (transaction) => {
      const freshWalletSnap = await transaction.get(walletRef);
      if (!freshWalletSnap.exists) {
        throw new Error('Wallet not found');
      }
      const freshBalance = freshWalletSnap.data().availableBalance || 0;
      if (freshBalance < amount) {
        throw new Error('Insufficient balance');
      }

      transaction.update(walletRef, {
        availableBalance: admin.firestore.FieldValue.increment(-amount),
        totalWithdrawn: admin.firestore.FieldValue.increment(amount),
        transactionCount: admin.firestore.FieldValue.increment(1),
        lastTransactionAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    // Create transaction record
    await db.collection(`academies/${academyId}/walletTransactions`).add({
      academyId,
      type: 'withdrawal',
      amount,
      status: abacatePayResponse.status === 'completed' ? 'completed' : 'pending',
      abacatePayTransactionId: abacatePayResponse.id,
      withdrawalPixKey: sanitizedPixKey,
      withdrawalPixKeyType: pixKeyType,
      requestedBy: context.auth.uid,
      description: `Saque via PIX - ${pixKeyType.toUpperCase()}`,
      fee: abacatePayResponse.fee || 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      completedAt: abacatePayResponse.status === 'completed' ?
        admin.firestore.FieldValue.serverTimestamp() :
        null,
    });
  } catch (error) {
    console.error('Transaction error:', error);
    throw new HttpsError(
      'internal',
      'Failed to update wallet. Please contact support.'
    );
  }

  // Notify admin about the withdrawal request
  const amtFormatted = (amount / 100).toFixed(2);
  await notifyAdminCF(
    academyId,
    'withdrawal_requested',
    'Saque Solicitado',
    `Saque de R$ ${amtFormatted} via PIX (${pixKeyType.toUpperCase()}) foi solicitado.`,
  );

  return {
    success: true,
    transactionId: abacatePayResponse.id,
    status: abacatePayResponse.status,
    amount,
    message: 'Withdrawal request submitted successfully',
  };
});

// ============================================
// Check PIX Payment Status
// ============================================
exports.checkPixStatus = onCall(async (request) => {
  const data = request.data || {};
  const context = { auth: request.auth };
  if (!context.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { abacatePayId } = data;
  if (!abacatePayId) {
    throw new HttpsError('invalid-argument', 'Missing abacatePayId');
  }

  const apiKey = getAbacatePayApiKey();
  if (!apiKey) {
    throw new HttpsError('internal', 'Payment service not configured');
  }

  const response = await fetch(`${ABACATEPAY_API_URL}/pixQrCode/check?id=${abacatePayId}`, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
    },
  });

  if (!response.ok) {
    const errorData = await response.json();
    console.error('AbacatePay check status error:', errorData);
    throw new HttpsError('internal', 'Failed to check payment status');
  }

  const responseData = await response.json();
  const statusData = responseData.data || responseData;

  return {
    status: statusData.status || 'PENDING',
  };
});

// ============================================================
// Mercado Pago — Marketplace / Split (student -> admin receivables)
//
// Each academy connects its OWN Mercado Pago account via OAuth. Charges are
// created on the admin's access_token with application_fee=0, so money settles
// DIRECTLY into the admin's MP account (0% platform fee, no wallet/float).
//
// DISTINCT from the platform paywall MP integration in index.js
// (createMercadoPagoCheckout / mercadoPagoWebhook = academy -> platform). Do
// not mix the secrets or webhook names.
//
// Required secrets (firebase functions:secrets:set ...):
//   MP_OAUTH_CLIENT_ID      — the marketplace app's client id (App ID)
//   MP_OAUTH_CLIENT_SECRET  — the marketplace app's client secret
//   MP_MKT_WEBHOOK_SECRET   — webhook signature secret for the marketplace app
// Optional env: MP_OAUTH_REDIRECT — must match the redirect registered in MP
//   and the deployed mercadoPagoOAuthCallback URL.
// ============================================================
const MP_API_BASE = 'https://api.mercadopago.com';
const MP_MKT_WEBHOOK_SECRETS = [...MP_MKT_SECRETS, 'MP_MKT_WEBHOOK_SECRET'];

function mpOAuthRedirect() {
  return process.env.MP_OAUTH_REDIRECT ||
    'https://us-central1-arpjj-76350.cloudfunctions.net/mercadoPagoOAuthCallback';
}

function mpMktWebhookUrl() {
  return process.env.MP_MKT_WEBHOOK_URL ||
    'https://us-central1-arpjj-76350.cloudfunctions.net/mercadoPagoMarketplaceWebhook';
}

/** HTTP helper for the MP REST API. Throws with .status/.data on non-2xx. */
async function mpRequest(method, path, { body, token, idempotencyKey } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (idempotencyKey) headers['X-Idempotency-Key'] = idempotencyKey;
  // Auditoria MP (refresh OAuth concorrente): timeout < LOCK_STALE_MS (30s) para
  // que um holder do mpTokenLock travado num /oauth/token lento ABORTE e libere
  // o lock ANTES de outra invocação reivindicá-lo como stale — fechando a janela
  // do double-refresh que rotacionaria o refresh_token 2x e quebraria a conexão.
  const r = await fetch(`${MP_API_BASE}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(20 * 1000),
  });
  const json = await r.json().catch(() => ({}));
  if (!r.ok) {
    const e = new Error(`MP ${method} ${path} -> ${r.status}`);
    e.status = r.status;
    e.data = json;
    throw e;
  }
  return json;
}

/**
 * Returns a valid access_token for the academy's connected MP account,
 * refreshing (and PERSISTING the rotated refresh_token — MP rotates it on every
 * refresh) when the current token is within 5 min of expiry.
 */
async function getMpAccessToken(academyId) {
  const ref = db.doc(`academies/${academyId}/private/mpAuth`);
  const lockRef = db.doc(`academies/${academyId}/private/mpTokenLock`);
  const academyRef = db.doc(`academies/${academyId}`);
  const bufferMs = 5 * 60 * 1000;
  const LOCK_STALE_MS = 30 * 1000;

  const readTokens = async () => {
    const s = await ref.get();
    if (!s.exists || !s.data().refreshToken) {
      throw new HttpsError('failed-precondition', 'Academia não conectou o Mercado Pago.');
    }
    return s.data();
  };
  const exp = (x) => (x && typeof x.toMillis === 'function') ? x.toMillis() : 0;
  const isFresh = (data) =>
    data && data.accessToken && Date.now() < exp(data.expiresAt) - bufferMs;

  const d = await readTokens();
  if (isFresh(d)) {
    // Um token válido prova que a conexão está saudável — limpa uma flag
    // mpNeedsReauth espúria deixada por uma falha transitória de refresh
    // (best-effort, fire-and-forget, fora do caminho crítico do pagamento).
    academyRef.get()
      .then((a) => {
        if (a.exists && a.data().mpNeedsReauth) {
          return academyRef.set(
            { mpNeedsReauth: admin.firestore.FieldValue.delete() },
            { merge: true });
        }
      })
      .catch(() => {});
    return d.accessToken;
  }

  // Token expired/near expiry. Acquire a lock so concurrent calls don't both
  // refresh — MP ROTATES the refresh_token on every refresh, so a double
  // refresh would invalidate the connection.
  const acquireLock = async () => {
    try {
      await lockRef.create({ at: admin.firestore.FieldValue.serverTimestamp() });
      return true;
    } catch (_) {
      // Lock exists. If it's stale (an orphaned lock from a crashed/timed-out
      // call), reclaim it so an academy can't be permanently degraded.
      const ls = await lockRef.get().catch(() => null);
      const at = ls && ls.exists ? ls.data().at : null;
      if (!ls || !ls.exists || (exp(at) && Date.now() - exp(at) > LOCK_STALE_MS)) {
        await lockRef.delete().catch(() => {});
        try {
          await lockRef.create({ at: admin.firestore.FieldValue.serverTimestamp() });
          return true;
        } catch (_) {
          return false; // someone else reclaimed it first
        }
      }
      return false;
    }
  };

  if (!(await acquireLock())) {
    // Another call is refreshing. Re-read the token + expiry in a bounded loop
    // (30×300ms ≈ 9s — um refresh OAuth lento não pode derrubar cobranças
    // legítimas com deadline-exceeded) instead of a single blind read, so we
    // never return a stale token. If the holder never finishes, fall through
    // to retry the lock once.
    for (let i = 0; i < 30; i++) {
      await new Promise((r) => setTimeout(r, 300));
      const cur = await readTokens();
      if (isFresh(cur)) {
        return cur.accessToken;
      }
    }
    // Holder appears stuck; attempt to take over (acquireLock reclaims if stale).
    if (!(await acquireLock())) {
      // Última chance: relê o doc de auth — o holder pode ter renovado entre
      // a última iteração e agora — antes de falhar de vez.
      const cur = await readTokens();
      if (isFresh(cur)) return cur.accessToken;
      throw new HttpsError('deadline-exceeded',
        'Não foi possível atualizar o token do Mercado Pago. Tente novamente.');
    }
  }

  try {
    const fresh = await readTokens();
    if (isFresh(fresh)) {
      return fresh.accessToken; // someone else refreshed before we locked
    }
    let tok;
    try {
      tok = await mpRequest('POST', '/oauth/token', {
        body: {
          client_id: process.env.MP_OAUTH_CLIENT_ID,
          client_secret: process.env.MP_OAUTH_CLIENT_SECRET,
          grant_type: 'refresh_token',
          refresh_token: fresh.refreshToken,
        },
      });
    } catch (err) {
      // refresh_token exchange failed — connection is broken and the admin must
      // reconnect. Flag it (best-effort) so the admin UI can prompt a reconnect.
      await academyRef.set({ mpNeedsReauth: true }, { merge: true }).catch(() => {});
      throw new HttpsError('failed-precondition',
        'A conexão com o Mercado Pago expirou. Reconecte a conta nas configurações.');
    }
    // Auditoria MP (rotação de refresh_token perdida): o MP ROTACIONA o
    // refresh_token a cada refresh — se a gravação local falhar APÓS o sucesso no
    // MP, o refresh_token rotacionado se perde e o próximo ciclo falha. Persiste
    // persistência-primeiro com 1 retry; se ainda falhar, sinaliza mpNeedsReauth
    // (como o catch de falha do refresh) para o admin reconectar em vez de
    // descobrir via cobranças falhando, e lança um erro recuperável.
    const tokenWrite = {
      accessToken: tok.access_token,
      refreshToken: tok.refresh_token || fresh.refreshToken,
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + (Number(tok.expires_in) || 0) * 1000),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    try {
      await ref.set(tokenWrite, { merge: true });
    } catch (writeErr) {
      await new Promise((r) => setTimeout(r, 300));
      try {
        await ref.set(tokenWrite, { merge: true });
      } catch (writeErr2) {
        await academyRef.set({ mpNeedsReauth: true }, { merge: true }).catch(() => {});
        throw new HttpsError('unavailable',
          'Falha ao salvar o token do Mercado Pago. Tente novamente.');
      }
    }
    // Successful refresh — clear any stale reconnect flag (best-effort).
    await academyRef.set(
      { mpNeedsReauth: admin.firestore.FieldValue.delete() }, { merge: true }
    ).catch(() => {});
    return tok.access_token;
  } finally {
    await lockRef.delete().catch(() => {});
  }
}

/** Ensures the caller is the admin of academyId. Returns userInfo. */
async function requireAdminOf(request, academyId) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }
  const info = await getUserAcademyMembership(request.auth.uid, academyId);
  if (!info || info.role !== 'admin') {
    throw new HttpsError('permission-denied',
      'Apenas o administrador da academia pode realizar esta acao.');
  }
  return info;
}

// ---- OAuth: start connect (admin) ----------------------------------------
exports.startMercadoPagoConnect = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const academyId = String(request.data?.academyId || '');
  if (!academyId) throw new HttpsError('invalid-argument', 'academyId é obrigatório.');
  await requireAdminOf(request, academyId);

  // Auditoria MP (hardening do state OAuth): nonce de 16 bytes (128 bits) em vez
  // de 8 — margem ampla contra adivinhação mesmo sendo single-use/TTL 10min. E
  // persiste o uid do admin que INICIOU o connect (oauthAdminUid) para auditoria
  // forense de quem disparou o fluxo (o callback é sem-auth por exigência do
  // OAuth2 — redirect batido pelo browser). A fronteira de segurança real segue
  // sendo a academia, já amarrada no state.
  const nonce = crypto.randomBytes(16).toString('hex');
  await db.doc(`academies/${academyId}/private/mpAuth`).set({
    oauthNonce: nonce,
    oauthAdminUid: request.auth?.uid || '',
    oauthStartedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  const state = `${academyId}:${nonce}`;
  const url = 'https://auth.mercadopago.com/authorization' +
    `?client_id=${encodeURIComponent(process.env.MP_OAUTH_CLIENT_ID)}` +
    '&response_type=code&platform_id=mp' +
    `&state=${encodeURIComponent(state)}` +
    `&redirect_uri=${encodeURIComponent(mpOAuthRedirect())}`;
  return { url };
});

// ---- OAuth: callback (exchanges code, stores tokens server-side) ----------
exports.mercadoPagoOAuthCallback = onRequest({ invoker: 'public', secrets: MP_MKT_SECRETS }, async (req, res) => {
  const code = req.query.code;
  const state = String(req.query.state || '');
  const [academyId, nonce] = state.split(':');
  if (!code || !academyId || !nonce) {
    return res.status(400).send('Parâmetros de conexão inválidos.');
  }
  const ref = db.doc(`academies/${academyId}/private/mpAuth`);
  const snap = await ref.get();
  if (!snap.exists || snap.data().oauthNonce !== nonce) {
    return res.status(403).send('Sessão de conexão inválida ou expirada.');
  }
  // Anti-replay: the state is good for 10 min only.
  const startedAt = snap.data().oauthStartedAt;
  if (startedAt && typeof startedAt.toMillis === 'function' &&
      Date.now() - startedAt.toMillis() > 10 * 60 * 1000) {
    await ref.update({ oauthNonce: admin.firestore.FieldValue.delete() }).catch(() => {});
    return res.status(403).send('Autorização expirada. Volte ao app e tente novamente.');
  }
  try {
    const tok = await mpRequest('POST', '/oauth/token', {
      body: {
        client_id: process.env.MP_OAUTH_CLIENT_ID,
        client_secret: process.env.MP_OAUTH_CLIENT_SECRET,
        grant_type: 'authorization_code',
        code,
        redirect_uri: mpOAuthRedirect(),
      },
    });
    // Auditoria MP (troca de conta órfã): se já existe um mpAuth de uma conta MP
    // DIFERENTE (mpUserId distinto do tok.user_id que está chegando) e há
    // assinaturas recorrentes ATIVAS, sobrescrever o token agora deixaria os
    // preapprovals da conta antiga ÓRFÃOS — o MP seguiria cobrando os cartões
    // dos alunos numa conta que o app não gerencia mais. Antes de sobrescrever,
    // cancela esses preapprovals usando AINDA o token ANTIGO (best-effort); o
    // que não der para cancelar vira órfão registrado + alerta ao admin. O
    // reconnect MAIS COMUM (reauth da MESMA conta via mpNeedsReauth) tem o MESMO
    // mpUserId e NÃO entra aqui — nenhum cancelamento indevido. Retrocompat: se
    // não havia conta anterior (primeiro connect), oldMpUserId é vazio e pula.
    const oldMpUserId = snap.exists ? String(snap.data().mpUserId || '') : '';
    const newMpUserId = String(tok.user_id || '');
    if (oldMpUserId && newMpUserId && oldMpUserId !== newMpUserId) {
      try {
        const oldToken = snap.data().accessToken;
        const activeSubs = await db
          .collection(`academies/${academyId}/subscriptions`)
          .where('status', 'in', ['pending', 'authorized', 'paused'])
          .get();
        const switchOrphans = [];
        for (const subDoc of activeSubs.docs) {
          const sub = subDoc.data();
          if (!sub.mpPreapprovalId) continue;
          let cancelled = false;
          try {
            if (oldToken) {
              await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
                { token: oldToken, body: { status: 'cancelled' } });
              cancelled = true;
            }
          } catch (err) {
            // PUT pode falhar com o preapproval já cancelado — confirma via GET.
            try {
              const pa = await mpRequest('GET',
                `/preapproval/${sub.mpPreapprovalId}`, { token: oldToken });
              cancelled = !!pa && pa.status === 'cancelled';
            } catch (_) { cancelled = false; }
          }
          if (cancelled) {
            await subDoc.ref.update({
              status: 'cancelled',
              lastEvent: 'cancelled_by_account_switch',
              updatedAt: FV.serverTimestamp(),
            }).catch(() => {});
          } else {
            switchOrphans.push(String(sub.mpPreapprovalId));
            await subDoc.ref.update({
              cancelPendingAtMp: true,
              lastEvent: 'account_switch_orphan',
              updatedAt: FV.serverTimestamp(),
            }).catch(() => {});
          }
        }
        if (switchOrphans.length) {
          await db.doc(`academies/${academyId}`).set({
            mpHasOrphanPreapprovals: true,
            mpOrphanPreapprovalIds: switchOrphans,
          }, { merge: true }).catch(() => {});
          await notifyAdminCF(academyId, 'payment_overdue',
            'Assinaturas da conta antiga para cancelar no Mercado Pago',
            'Voce conectou uma conta diferente do Mercado Pago e algumas ' +
            'assinaturas recorrentes da conta anterior NAO puderam ser ' +
            'canceladas pelo app. Cancele-as manualmente no painel da conta ' +
            'ANTIGA para os cartoes dos alunos nao continuarem sendo cobrados.' +
            ` IDs: ${switchOrphans.join(', ')}.`, {}).catch(() => {});
        }
      } catch (e) {
        console.error('[mpOAuthCallback] cancelamento na troca de conta falhou',
          e && e.message);
      }
    }
    // Auditoria MP (atomicidade do connect): grava tokens + flag mpConnected num
    // ÚNICO batch atômico. Antes eram duas escritas separadas — uma falha entre
    // elas deixava a academia com token vivo mas mpConnected ausente e o nonce
    // já consumido. set(merge) no doc da academia (em vez de update) evita
    // lançar caso o doc não exista e preserva o resto dos campos.
    const batch = db.batch();
    batch.set(ref, {
      accessToken: tok.access_token,
      refreshToken: tok.refresh_token,
      mpUserId: String(tok.user_id || ''),
      publicKey: tok.public_key || '',
      liveMode: tok.live_mode === true,
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + (Number(tok.expires_in) || 0) * 1000),
      connectedAt: admin.firestore.FieldValue.serverTimestamp(),
      oauthNonce: admin.firestore.FieldValue.delete(),
    }, { merge: true });
    // Public flags on the academy doc + per-academy opt-in: switch off the
    // legacy gateways so NEW charges route to MP.
    batch.set(db.doc(`academies/${academyId}`), {
      mpConnected: true,
      mpUserId: String(tok.user_id || ''),
      mpPublicKey: tok.public_key || '',
      mpLiveMode: tok.live_mode === true,
      mpConnectedAt: admin.firestore.FieldValue.serverTimestamp(),
      abacatePayEnabled: false,
      asaasEnabled: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();
    return res.status(200).send(mpCallbackHtml(
      'Mercado Pago conectado!',
      'Sua conta foi conectada. Volte ao app para continuar.', false));
  } catch (e) {
    console.error('[mpOAuthCallback] erro', e.message, e.data);
    // Auditoria MP (nonce single-use): consome o nonce TAMBÉM na falha da troca
    // code->token, garantindo que cada state seja invalidado em qualquer desfecho
    // (sucesso, expiração ou erro) — não sobrevive por até 10 min para reuso.
    await ref.update({ oauthNonce: admin.firestore.FieldValue.delete() }).catch(() => {});
    return res.status(500).send(mpCallbackHtml(
      'Falha ao conectar',
      'Ocorreu um erro. Volte ao app e tente novamente.', true));
  }
});

/**
 * Mobile-friendly callback page that also deep-links back into the app
 * (graduabjj://mp-oauth-callback?status=...) so the connect screen reacts
 * instantly; the visible page is the fallback if the deep link doesn't fire.
 */
function mpCallbackHtml(title, message, isError) {
  const color = isError ? '#E53935' : '#00A650';
  const icon = isError ? '&#10007;' : '&#10003;';
  const status = isError ? 'error' : 'success';
  return `<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width, initial-scale=1">` +
    `<title>${title}</title><style>body{font-family:-apple-system,Roboto,sans-serif;` +
    `text-align:center;padding:60px 24px;background:#fafafa;margin:0}.i{font-size:64px;` +
    `color:${color}}h1{font-size:22px;color:#1a1a1a;margin:16px 0 8px}p{font-size:16px;` +
    `color:#666;max-width:320px;margin:0 auto}</style></head><body>` +
    `<div class="i">${icon}</div><h1>${title}</h1><p>${message}</p>` +
    `<p class="hint" style="margin-top:32px;color:#999">Voce pode fechar esta janela.</p>` +
    `<script>window.location.href="graduabjj://mp-oauth-callback?status=${status}";</script>` +
    `</body></html>`;
}

// ---- OAuth: disconnect (admin) -------------------------------------------
exports.disconnectMercadoPago = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const academyId = String(request.data?.academyId || '');
  if (!academyId) throw new HttpsError('invalid-argument', 'academyId é obrigatório.');
  await requireAdminOf(request, academyId);

  // Sem assinaturas órfãs: o preapproval vive no LADO DO MP, independente do
  // nosso token OAuth — apagar os tokens sem cancelá-lo deixaria o MP cobrando
  // o cartão do aluno todo mês sem que ninguém (aluno, app ou crons) consiga
  // mais gerenciar. Cancela tudo no MP enquanto o token ainda é válido; se
  // QUALQUER cancel falhar, aborta o disconnect (tokens ficam p/ re-tentativa).
  const activeSubs = await db.collection(`academies/${academyId}/subscriptions`)
    .where('status', 'in', ['pending', 'authorized', 'paused'])
    .get();
  // Auditoria MP (observabilidade): IDs dos preapprovals que ficaram órfãos
  // (token irrecuperável) — persistidos no doc da academia para a UI exibir um
  // aviso destacado e persistente até o admin cancelá-los no painel do MP.
  const orphanPreapprovalIds = [];
  if (!activeSubs.empty) {
    let token = null;
    let failed = 0;
    // Token IRRECUPERÁVEL (refresh revogado no painel do MP / conta encerrada):
    // getMpAccessToken lança failed-precondition determinístico — abortar aqui
    // bloquearia o disconnect PARA SEMPRE. Nesse caso liberamos o disconnect
    // marcando as subs como pendentes de cancelamento MANUAL no painel do MP.
    let tokenIrrecoverable = false;
    for (const subDoc of activeSubs.docs) {
      const sub = subDoc.data();
      if (!sub.mpPreapprovalId) continue; // nunca chegou ao MP: nada a cancelar
      if (tokenIrrecoverable) break;
      try {
        if (!token) token = await getMpAccessToken(academyId);
        let mpCancelled = false;
        try {
          await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
            { token, body: { status: 'cancelled' } });
          mpCancelled = true;
        } catch (e) {
          // PUT pode falhar com o preapproval JÁ cancelado no MP — confirma via GET.
          const pa = await mpRequest('GET',
            `/preapproval/${sub.mpPreapprovalId}`, { token });
          mpCancelled = !!pa && pa.status === 'cancelled';
          if (!mpCancelled) throw e;
        }
        await subDoc.ref.update({
          status: 'cancelled',
          lastEvent: 'cancelled_by_disconnect',
          updatedAt: FV.serverTimestamp(),
        });
        await notifySubscriptionStudent(academyId, sub, 'subscription_cancelled',
          'Assinatura encerrada',
          'Sua assinatura recorrente foi encerrada pela academia. ' +
          'Nenhuma nova cobrança será feita no seu cartão.',
          { actionLabel: 'Ver financeiro' });
      } catch (e) {
        console.error('[disconnectMercadoPago] cancel preapproval falhou',
          subDoc.id, e.message);
        // failed-precondition de getMpAccessToken = refresh token recusado
        // pelo MP (invalid_grant): determinístico, nunca vai melhorar com
        // retry. Falhas TRANSITÓRIAS (timeout/5xx) seguem abortando.
        if (!token && e instanceof HttpsError &&
            e.code === 'failed-precondition') {
          tokenIrrecoverable = true;
        } else {
          failed += 1;
        }
      }
    }
    if (tokenIrrecoverable) {
      // Não dá para cancelar no MP sem token — mas manter a academia presa a
      // um disconnect impossível também não resolve o preapproval. Marca as
      // subs (preservando o status: NÃO são 'cancelled' — podem seguir vivas
      // no MP) e avisa o admin para cancelá-las manualmente no painel.
      for (const subDoc of activeSubs.docs) {
        const pid = subDoc.data().mpPreapprovalId;
        if (!pid) continue;
        orphanPreapprovalIds.push(String(pid));
        await subDoc.ref.update({
          cancelPendingAtMp: true,
          lastEvent: 'disconnect_token_revoked',
          updatedAt: FV.serverTimestamp(),
        }).catch(() => { /* best-effort: não bloqueia o disconnect */ });
      }
      try {
        await notifyAdminCF(academyId, 'payment_overdue',
          'Assinaturas para cancelar no Mercado Pago',
          'A conexao com o Mercado Pago foi revogada e as assinaturas ' +
          'recorrentes NAO puderam ser canceladas pelo app. Cancele-as ' +
          'manualmente no painel do Mercado Pago para os cartoes dos alunos ' +
          'nao continuarem sendo cobrados.' +
          (orphanPreapprovalIds.length
            ? ` IDs: ${orphanPreapprovalIds.join(', ')}.` : ''), {});
      } catch (_) { /* best-effort */ }
    } else if (failed > 0) {
      throw new HttpsError('unavailable',
        `${failed} assinatura(s) ativa(s) não puderam ser canceladas no ` +
        'Mercado Pago. A conta NÃO foi desconectada — tente novamente em ' +
        'alguns minutos.');
    }
  }

  // Auditoria MP (revoke OAuth no disconnect): antes de apagar localmente,
  // enquanto o token ainda é válido, tenta DESAUTORIZAR a aplicação na conta do
  // lojista no MP — honra plenamente a intenção do admin e encurta a janela de
  // um refresh_token longo eventualmente vazado. Best-effort: NUNCA bloqueia o
  // disconnect se a revogação falhar (retrocompat — o disconnect já cancelou os
  // preapprovals acima, que é o risco financeiro real). Lê o doc de auth antes
  // do delete; não loga o token em texto plano.
  try {
    const authSnap = await db.doc(`academies/${academyId}/private/mpAuth`).get();
    const auth = authSnap.exists ? authSnap.data() : null;
    const mpUserId = auth && auth.mpUserId ? String(auth.mpUserId) : '';
    if (auth && auth.accessToken && mpUserId) {
      // Endpoint de desautorização do MP: remove a aplicação (client_id) das
      // aplicações autorizadas do usuário/lojista, invalidando os tokens OAuth.
      await mpRequest('DELETE',
        `/users/${mpUserId}/applications/${process.env.MP_OAUTH_CLIENT_ID}`,
        { token: auth.accessToken });
    }
  } catch (e) {
    console.error('[disconnectMercadoPago] revoke OAuth falhou (non-fatal)',
      e && e.message);
  }

  await db.doc(`academies/${academyId}/private/mpAuth`).delete().catch(() => {});
  await db.doc(`academies/${academyId}`).update({
    mpConnected: false,
    mpUserId: admin.firestore.FieldValue.delete(),
    mpPublicKey: admin.firestore.FieldValue.delete(),
    mpLiveMode: admin.firestore.FieldValue.delete(),
    // Auditoria MP (observabilidade): se sobraram preapprovals órfãos (token
    // irrecuperável), persiste a lista para a UI alertar de forma destacada;
    // senão limpa qualquer flag de um disconnect anterior.
    mpHasOrphanPreapprovals: orphanPreapprovalIds.length > 0,
    mpOrphanPreapprovalIds: orphanPreapprovalIds.length
      ? orphanPreapprovalIds
      : admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { success: true };
});

/** Shared payer-permission check (self / staff / responsible adult). */
async function assertCanPayFor(request, academyId, studentId) {
  const userInfo = await getUserAcademyMembership(request.auth.uid, academyId);
  if (!userInfo) {
    throw new HttpsError('permission-denied', 'Access denied: Invalid academy');
  }
  const isStaff = userInfo.role === 'admin' || userInfo.role === 'instructor';
  if (!isStaff && userInfo.studentId !== studentId) {
    const stuSnap = await db.doc(`academies/${academyId}/students/${studentId}`).get();
    if (!stuSnap.exists || stuSnap.data()?.responsibleUserId !== request.auth.uid) {
      throw new HttpsError('permission-denied', 'Access denied: Cannot pay for another student');
    }
  }
}

/** Maps an MP error to a friendly message — notably the seller-has-no-PIX-key case. */
function mapMpPixError(e) {
  // Log the RAW Mercado Pago rejection so production failures are diagnosable —
  // the user only ever sees the mapped, friendly message below.
  console.error('[createMpPix] MP rejeitou a cobranca PIX:',
    'status=', e && e.status,
    'data=', e && e.data ? JSON.stringify(e.data) : (e && e.message));
  const text = `${e && e.data ? JSON.stringify(e.data) : ''} ${e && e.message ? e.message : ''}`
    .toLowerCase();
  if (text.includes('without key enabled for qr') || text.includes('qr render')) {
    return new HttpsError('failed-precondition',
      'A conta Mercado Pago da academia ainda nao tem uma chave PIX habilitada. ' +
      'Ative o PIX no app do Mercado Pago e tente novamente.');
  }
  if (text.includes('email')) {
    return new HttpsError('failed-precondition',
      'E-mail do pagador invalido para o Mercado Pago. Verifique o e-mail da sua conta.');
  }
  if (text.includes('identification') || text.includes('cpf') ||
      text.includes('payer')) {
    return new HttpsError('failed-precondition',
      'Dados do pagador invalidos (CPF/e-mail). Confira seu CPF e tente novamente.');
  }
  return new HttpsError('internal', 'Falha ao gerar a cobranca PIX.');
}

/** Auditoria (UX): mapeia a recusa de CARTÃO do Mercado Pago em mensagens
 * pt-BR acionáveis (espelha o mapMpPixError). Sem isso o aluno só via um
 * 'internal' opaco ("Falha ao processar o cartao.") e não sabia se era saldo,
 * CVV, limite, dados etc. Usa o status_detail do MP (campo canônico de motivo)
 * e, como fallback, o texto bruto de e.data/e.message. Retorna sempre um
 * HttpsError; o RAW já foi logado pelo chamador. */
function mapMpCardError(e, statusDetail) {
  const detail = String(statusDetail || '').toLowerCase();
  const text = `${detail} ${e && e.data ? JSON.stringify(e.data) : ''} ` +
    `${e && e.message ? e.message : ''}`.toLowerCase();
  const fp = (msg) => new HttpsError('failed-precondition', msg);
  // status_detail típicos do MP (cc_rejected_*) → mensagem acionável.
  if (text.includes('insufficient_amount') || text.includes('insufficient')) {
    return fp('Cartao recusado por saldo/limite insuficiente. Use outro cartao.');
  }
  if (text.includes('call_for_authorize') || text.includes('authorize')) {
    return fp('O banco pediu autorizacao para esta compra. Ligue para o seu ' +
      'banco e autorize, ou use outro cartao.');
  }
  if (text.includes('security_code') || text.includes('cvv')) {
    return fp('Codigo de seguranca (CVV) invalido. Confira e tente novamente.');
  }
  if (text.includes('expiration') || text.includes('expired') ||
      text.includes('card_expired')) {
    return fp('Cartao vencido ou data de validade invalida. Use outro cartao.');
  }
  if (text.includes('card_number') || text.includes('invalid_card')) {
    return fp('Numero do cartao invalido. Confira os dados e tente novamente.');
  }
  if (text.includes('card_disabled') || text.includes('blacklist') ||
      text.includes('blocked')) {
    return fp('Cartao bloqueado ou desabilitado. Use outro cartao ou fale com o banco.');
  }
  if (text.includes('high_risk') || text.includes('fraud') ||
      text.includes('rejected_by_bank')) {
    return fp('Pagamento recusado pelo banco emissor. Tente outro cartao ou ' +
      'fale com o seu banco.');
  }
  if (text.includes('max_attempts') || text.includes('duplicated_payment')) {
    return fp('Muitas tentativas seguidas. Aguarde alguns minutos e tente novamente.');
  }
  if (text.includes('identification') || text.includes('cpf') ||
      text.includes('docnumber')) {
    return fp('CPF do pagador invalido. Confira o CPF e tente novamente.');
  }
  if (text.includes('email')) {
    return fp('E-mail do pagador invalido. Confira o e-mail da sua conta.');
  }
  return new HttpsError('internal', 'Falha ao processar o cartao.');
}

/**
 * Server-side authoritative store-order total in REAIS. Recomputes from the
 * line items (each item carries the server-validated `price`), falling back to
 * the persisted `total`/`totalAmount` when items are unavailable. Used to DERIVE
 * the MP charge so the client-supplied amount is never trusted.
 */
function orderExpectedTotalReais(order) {
  const items = order && order.items;
  if (Array.isArray(items) && items.length > 0) {
    let sum = 0;
    let ok = true;
    for (const it of items) {
      const price = Number((it && (it.price ?? it.unitPrice)));
      const qty = Number(it && it.quantity);
      if (!Number.isFinite(price) || !Number.isFinite(qty)) { ok = false; break; }
      sum += price * qty;
    }
    if (ok) return sum;
  }
  return Number((order && (order.total ?? order.totalAmount)) || 0);
}

/**
 * SECURITY (preco autoritativo da LOJA): pedidos de loja sao criados DIRETO
 * pelo cliente no Firestore (sem CF de criacao), entao `items[].price` e
 * `total` NAO sao confiaveis — recomputar a partir dos proprios items
 * (orderExpectedTotalReais) e defesa CIRCULAR contra um cliente malicioso.
 * Este helper recomputa o total em REAIS buscando cada item em storeProducts
 * (preco unico por produto; sizes/colors sao atributos sem modificador de
 * preco). Se um produto nao existir mais, estiver sem preco valido, ou o preco
 * atual divergir do gravado no item (tolerancia de 1 centavo), lanca
 * failed-precondition — NUNCA cobramos o valor escrito pelo cliente.
 * Usado pelas CFs de cobranca de pedido (PIX/cartao, MP e AbacatePay).
 */
async function orderAuthoritativeTotalReais(academyId, order) {
  const stale = () => new HttpsError('failed-precondition',
    'Os preços deste pedido mudaram. Refaça o pedido.');
  const items = (order && order.items) || [];
  if (!Array.isArray(items) || items.length === 0) throw stale();
  let sum = 0;
  for (const it of items) {
    const productId = it && it.productId;
    const qty = Number(it && it.quantity);
    if (!productId || !Number.isInteger(qty) || qty <= 0) throw stale();
    const p = await db.doc(
      `academies/${academyId}/storeProducts/${productId}`).get();
    if (!p.exists) throw stale();
    const authoritative = Number(p.data()?.price);
    if (!Number.isFinite(authoritative) || authoritative <= 0) throw stale();
    const written = Number(it.price ?? it.unitPrice);
    if (!Number.isFinite(written) ||
        Math.abs(authoritative - written) > 0.01) {
      throw stale();
    }
    sum += authoritative * qty;
  }
  return Number(sum.toFixed(2));
}

/**
 * SECURITY: derive the order's effective payment-method policy SERVER-SIDE from
 * the products, never from the client-controlled `order.paymentMethodPolicy`
 * snapshot. Store orders are created directly by the client (no creation CF), so
 * the persisted policy field is not a trustworthy boundary — a malicious client
 * could write `'both'` for a `pix_only`/`card_only` product. This mirrors the
 * `orderExpectedTotalReais` mold (recompute the boundary from authoritative data).
 *
 * The effective policy is the MOST-RESTRICTIVE across all line items: PIX is
 * allowed only when EVERY product allows PIX; card only when EVERY product allows
 * card. A product whose `paymentMethodPolicy` is missing ⇒ `'both'` (compat).
 * Returns `{ allowsPix, allowsCard, value }` where `value` is the canonical
 * `'both' | 'pix_only' | 'card_only'`.
 */
async function orderEffectivePolicy(academyId, order) {
  let allowsPix = true;
  let allowsCard = true;
  const items = (order && order.items) || [];
  if (Array.isArray(items)) {
    for (const it of items) {
      const productId = it && it.productId;
      if (!productId) continue; // can't resolve → leave as 'both' for this item
      let policy = 'both';
      try {
        const p = await db.doc(
          `academies/${academyId}/storeProducts/${productId}`).get();
        if (p.exists) policy = p.data()?.paymentMethodPolicy || 'both';
      } catch (_) { /* product unreadable → conservative default 'both' */ }
      if (policy === 'pix_only') allowsCard = false;
      else if (policy === 'card_only') allowsPix = false;
    }
  }
  let value = 'both';
  if (allowsPix && !allowsCard) value = 'pix_only';
  else if (allowsCard && !allowsPix) value = 'card_only';
  return { allowsPix, allowsCard, value };
}

/**
 * Creates a PIX payment on the academy's MP account. transactionAmount in REAIS.
 * MP requires the payer identification (CPF) for PIX — pass it when available.
 */
async function createMpPix({ academyId, transactionAmount, description, externalReference, payer }) {
  const token = await getMpAccessToken(academyId);
  // O PIX legado precisa sobreviver a previews/reenvios e ao prazo minimo
  // recomendado pelo Checkout Pro. O link publico futuro sera duradouro; ate
  // la, mantemos a tentativa direta valida por tres dias.
  const expiresAt = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000);
  const cpf = ((payer && payer.cpf) || '').replace(/\D/g, '');
  const nameParts = ((payer && payer.name) || '').trim().split(/\s+/);
  // Idempotency key must be UNIQUE per minted PIX: external_reference is FIXED
  // per financial/order (the webhook parses it), so reusing it as the
  // idempotency key would make MP return the SAME (possibly expired) payment on
  // a regeneration after the 24h expiry. Append a fresh epoch-millis suffix so
  // each mint creates a fresh, payable PIX.
  const idempotencyKey =
    `${externalReference}:${admin.firestore.Timestamp.now().toMillis()}`;

  // Auditoria MP (PIX órfão / self-heal por external_reference): como a key de
  // idempotência é ÚNICA por mint e o external_reference é FIXO, um crash entre
  // o 200 do MP e o finRef.update perderia o id/QR de um PIX já criado, sem a
  // adoção de órfão que a assinatura tem. Antes de cunhar um novo, busca no MP um
  // PIX pending/in_process VIVO com este external_reference e, se o valor bater,
  // ADOTA-O (reusa id/QR) em vez de criar uma 2ª cobrança pagável. Best-effort:
  // se a busca falhar, segue para o mint normal.
  try {
    const found = await mpRequest('GET',
      `/v1/payments/search?external_reference=${encodeURIComponent(externalReference)}` +
      '&sort=date_created&criteria=desc',
      { token });
    const results = (found && (found.results || found.elements)) || [];
    const wanted = Number(transactionAmount.toFixed(2));
    const orphan = results.find((p) =>
      p && (p.status === 'pending' || p.status === 'in_process') &&
      p.payment_method_id === 'pix' &&
      Math.abs((Number(p.transaction_amount) || 0) - wanted) <= 0.01 &&
      p.point_of_interaction && p.point_of_interaction.transaction_data &&
      p.point_of_interaction.transaction_data.qr_code &&
      // só adota se ainda não expirou (date_of_expiration no futuro, quando há)
      (!p.date_of_expiration || new Date(p.date_of_expiration).getTime() > Date.now()));
    if (orphan) {
      const otx = orphan.point_of_interaction.transaction_data;
      console.warn('[createMpPix] PIX órfão adotado', orphan.id, externalReference);
      return {
        paymentId: String(orphan.id),
        pixCode: otx.qr_code,
        qrCodeBase64: otx.qr_code_base64 || '',
        ticketUrl: otx.ticket_url || '',
        expiresAt: orphan.date_of_expiration
          ? new Date(orphan.date_of_expiration) : expiresAt,
      };
    }
  } catch (searchErr) {
    console.error('[createMpPix] busca de PIX órfão falhou',
      searchErr && searchErr.message);
  }

  let payment;
  try {
    payment = await mpRequest('POST', '/v1/payments', {
      token,
      idempotencyKey,
      body: {
        transaction_amount: Number(transactionAmount.toFixed(2)),
        description: description || 'Pagamento',
        payment_method_id: 'pix',
        date_of_expiration: expiresAt.toISOString(),
        external_reference: externalReference,
        notification_url: `${mpMktWebhookUrl()}?acad=${encodeURIComponent(academyId)}`,
        // NÃO enviar application_fee: o MP rejeita `0` ("must be positive").
        // A academia recebe direto na própria conta (0% de taxa), então o
        // atributo deve ser OMITIDO — só se inclui quando há split positivo.
        payer: {
          // Never send a fake placeholder domain — Mercado Pago rejects it.
          // A real email is enforced by the callers (createMpPixPayment).
          email: (payer && payer.email) || undefined,
          first_name: nameParts[0] || undefined,
          last_name: nameParts.length > 1 ? nameParts.slice(1).join(' ') : undefined,
          identification: cpf.length >= 11 ? { type: 'CPF', number: cpf } : undefined,
        },
      },
    });
  } catch (e) {
    throw mapMpPixError(e);
  }
  const tx = payment.point_of_interaction &&
    payment.point_of_interaction.transaction_data;
  // Auditoria (UX): o MP pode devolver 200 com o pagamento criado mas SEM
  // transaction_data (qr_code vazio) — tipicamente conta sem chave PIX. NÃO
  // persistir gatewayPaymentId + QR vazio (geraria um PIX impagável gravado no
  // doc, bloqueando regeneração até expirar): trata como falha e lança o mesmo
  // erro acionável do MP rejeitar a cobrança.
  if (!tx || !tx.qr_code) {
    throw mapMpPixError({
      status: payment.status,
      data: { message: 'pix without qr render: transaction_data ausente' },
      message: 'PIX sem QR (transaction_data ausente)',
    });
  }
  return {
    paymentId: String(payment.id),
    pixCode: tx.qr_code,
    qrCodeBase64: tx.qr_code_base64 || '',
    ticketUrl: tx.ticket_url || '',
    expiresAt,
  };
}

// ---- Lock de geração de PIX (anti-race, achado #24) ------------------------
// createMpPixPayment/createMpOrderPixPayment faziam check-then-act sem
// transação: dois aparelhos abrindo a mesma cobrança mintavam DOIS PIX
// pagáveis (idempotency key tem epoch-millis) e a família podia pagar 2x.
// Serializa o mint com uma transação que grava pixMintAt/pixMintBy no doc
// ANTES de chamar o MP (padrão do mpTokenLock): quem perde a corrida espera
// e reusa o PIX do vencedor. Quem adquire o lock DEVE limpá-lo ao terminar
// (sucesso: no próprio update dos campos do PIX; falha no MP: no catch) —
// um lock órfão (crash) expira sozinho após PIX_MINT_STALE_MS.
const PIX_MINT_STALE_MS = 60 * 1000;

/** Resposta de reuso de um PIX ainda válido gravado no doc. */
function mpPixReuseResponse(d) {
  return {
    pixCode: d.pixCode,
    qrCodeUrl: d.pixQrCode || '',
    ticketUrl: d.pixTicketUrl || '',
    paymentId: d.gatewayPaymentId,
    expiresAt: d.pixExpiresAt.toDate().toISOString(),
  };
}

/** Adquire o lock de mint de PIX para um financial/pedido. Retorna
 * { acquired:true } (chame o MP e depois limpe pixMintAt/pixMintBy) ou
 * { reuse: data } (outro mint concorrente já produziu um PIX válido). */
async function mpAcquirePixMint(docRef, uid, expectedAmount) {
  const pixExpMs = (d) =>
    (d.pixExpiresAt && typeof d.pixExpiresAt.toMillis === 'function')
      ? d.pixExpiresAt.toMillis() : 0;
  const mintAtMs = (d) =>
    (d.pixMintAt && typeof d.pixMintAt.toMillis === 'function')
      ? d.pixMintAt.toMillis() : 0;
  // Auditoria MP: além de vivo, o PIX só é "fresco" para reuso se o valor cunhado
  // (pixAmount) ainda bate com o valor esperado atual (quando informado).
  // Retrocompat: sem expectedAmount ou sem pixAmount (PIX legado), não bloqueia.
  const amountOk = (d) =>
    typeof expectedAmount !== 'number' || typeof d.pixAmount !== 'number' ||
    Math.abs(expectedAmount - d.pixAmount) <= 0.01;
  const hasFreshPix = (d) =>
    d.gatewayPaymentId && d.pixCode && pixExpMs(d) > Date.now() && amountOk(d);

  const tryAcquire = () => db.runTransaction(async (tx) => {
    const s = await tx.get(docRef);
    if (!s.exists) {
      throw new HttpsError('not-found', 'Registro de cobranca nao encontrado.');
    }
    const d = s.data();
    if (d.status === 'paid') {
      throw new HttpsError('already-exists', 'Este pagamento ja foi concluido.');
    }
    if (hasFreshPix(d)) return { reuse: d };
    const mintAt = mintAtMs(d);
    if (mintAt && Date.now() - mintAt < PIX_MINT_STALE_MS) {
      return { wait: true }; // outro mint em andamento
    }
    tx.update(docRef, {
      pixMintAt: admin.firestore.Timestamp.now(),
      pixMintBy: uid || null,
    });
    return { acquired: true };
  });

  let r = await tryAcquire();
  if (r.wait) {
    // Outro aparelho está mintando: espera curto e reusa o PIX do vencedor
    // (molde do loop de espera do mpTokenLock em getMpAccessToken).
    for (let i = 0; i < 10; i++) {
      await new Promise((res) => setTimeout(res, 500));
      const s = await docRef.get();
      if (!s.exists) break;
      const d = s.data();
      if (hasFreshPix(d)) return { reuse: d };
      const mintAt = mintAtMs(d);
      // Vencedor falhou no MP (limpou o lock) ou travou (lock stale):
      // sai do loop e tenta assumir o mint.
      if (!mintAt || Date.now() - mintAt >= PIX_MINT_STALE_MS) break;
    }
    r = await tryAcquire();
    if (r.wait) {
      throw new HttpsError('deadline-exceeded',
        'Outro dispositivo esta gerando o PIX desta cobranca. Tente novamente em instantes.');
    }
  }
  return r;
}

/** Solta o lock de mint após falha na chamada ao MP (best-effort). */
async function mpReleasePixMint(docRef) {
  await docRef.update({
    pixMintAt: admin.firestore.FieldValue.delete(),
    pixMintBy: admin.firestore.FieldValue.delete(),
  }).catch(() => {});
}

// ---- PIX: mensalidade (amount in CENTAVOS, matching createPixPayment) -----
exports.createMpPixPayment = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const { academyId, amount, description, financialId, studentId, studentName,
    payerCpf, payerEmail } = request.data || {};
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
  if (!academyId || !amount || !financialId || !studentId) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }
  await assertCanPayFor(request, academyId, studentId);
  const amountValidation = validateAmount(amount);
  if (!amountValidation.valid) {
    throw new HttpsError('invalid-argument', amountValidation.error || 'Invalid amount');
  }

  const finRef = db.doc(`academies/${academyId}/financials/${financialId}`);
  const finSnap = await finRef.get();
  if (!finSnap.exists) throw new HttpsError('not-found', 'Financial record not found');
  const fin = finSnap.data();
  if (fin.studentId !== studentId) {
    throw new HttpsError('permission-denied', 'Financial record does not belong to this student');
  }
  if (fin.status === 'paid') {
    throw new HttpsError('already-exists', 'This payment has already been completed');
  }

  // Payment-method policy (defesa em profundidade — a UI ja esconde, mas o
  // enforcement real e aqui): cobranca marcada como "somente cartao" nao pode
  // ser paga via PIX.
  if (fin.paymentMethodPolicy === 'card_only') {
    throw new HttpsError('failed-precondition',
      'Esta cobranca aceita apenas cartao.');
  }

  // SECURITY: never trust the client amount. The charge is DERIVED from the
  // stored financial amount (REAIS, canonical). The client sends CENTAVOS, so
  // compare in centavos within a 1-centavo tolerance, else reject.
  const expectedCentavos = Math.round((Number(fin.amount) || 0) * 100);
  if (Math.abs(expectedCentavos - amount) > 1) {
    throw new HttpsError('invalid-argument',
      `Amount (${amount}) does not match financial amount (${expectedCentavos})`);
  }

  // Idempotency: reuse a still-valid PIX so the kid and the responsible adult
  // opening the same charge get the SAME code (no double charge).
  const existingExpiry = fin.pixExpiresAt && typeof fin.pixExpiresAt.toMillis === 'function'
    ? fin.pixExpiresAt.toMillis() : 0;
  // Auditoria MP: só reusa o PIX vivo se o valor cunhado (pixAmount) ainda bater
  // com o valor atual da cobrança (1-centavo). Se o admin editou o valor, o QR
  // antigo serviria um valor obsoleto — cai fora e cunha novo. Retrocompat: PIX
  // legado sem pixAmount (app antigo) é reusado normalmente.
  const finPixAmountOk = typeof fin.pixAmount !== 'number' ||
    Math.abs((Number(fin.amount) || 0) - fin.pixAmount) <= 0.01;
  if (fin.gatewayPaymentId && fin.pixCode && existingExpiry > Date.now() &&
      finPixAmountOk) {
    return {
      pixCode: fin.pixCode,
      qrCodeUrl: fin.pixQrCode || '',
      ticketUrl: fin.pixTicketUrl || '',
      paymentId: fin.gatewayPaymentId,
      expiresAt: fin.pixExpiresAt.toDate().toISOString(),
    };
  }

  // PIX requires a valid payer CPF (Brazilian regulation) AND a real e-mail.
  // Mirror the marketplace reference: fail fast with a clear message instead of
  // letting Mercado Pago reject an incomplete payer (which surfaced to students
  // as a generic "falha na cobranca PIX").
  // Auditoria (correção): valida o CPF pelo CHECKSUM (validateCPF), não só pelo
  // comprimento — um CPF de 11 dígitos com dígitos verificadores errados era
  // aceito e o MP recusava depois com erro genérico.
  const cpfDigits = String(payerCpf || '').replace(/\D/g, '');
  if (!validateCPF(cpfDigits)) {
    throw new HttpsError('failed-precondition',
      'Para pagar via PIX e necessario um CPF valido. Informe seu CPF e tente novamente.');
  }
  let resolvedEmail = String(payerEmail || '').trim();
  if (!resolvedEmail || !resolvedEmail.includes('@') ||
      resolvedEmail.endsWith('@bjjeasy.com.br')) {
    try {
      const authUser = await admin.auth().getUser(request.auth.uid);
      resolvedEmail = (authUser.email || '').trim();
    } catch (_) { /* keep whatever we had */ }
  }
  if (!resolvedEmail || !resolvedEmail.includes('@')) {
    throw new HttpsError('failed-precondition',
      'E necessario um e-mail valido na sua conta para gerar a cobranca PIX.');
  }

  // Auditoria MP (anti double-charge bidirecional): se este MESMO doc tem um
  // CARTÃO pendente vivo (in_process/3DS — gravado por createMpCardPayment),
  // cunhar o PIX agora deixaria as DUAS cobranças pagáveis. Cancela o cartão
  // pendente ANTES de mintar (mpCancelPixPayment cancela qualquer pagamento
  // pending/in_process, serve para cartão também). Espelha o guard cartão→PIX.
  await mpCancelLivePendingCard(academyId, finRef);

  // Auditoria MP (PIX com valor antigo): se há um PIX vivo cunhado com um valor
  // DIVERGENTE do atual (admin editou o valor), cancela-o no MP antes de cunhar
  // o novo — senão o QR antigo continuaria pagável com o valor obsoleto e o
  // settle recusaria o crédito (dinheiro preso). Retrocompat: sem pixAmount não age.
  if (typeof fin.pixAmount === 'number' &&
      Math.abs((Number(fin.amount) || 0) - fin.pixAmount) > 0.01 &&
      fin.gatewayPaymentId && fin.pixCode) {
    await mpCancelPixPayment(academyId, fin.gatewayPaymentId, {});
  }

  // Anti-race (achado #24): serializa o mint via lock transacional no doc —
  // dois aparelhos concorrentes geram UM PIX só (o perdedor reusa o do vencedor).
  const mint = await mpAcquirePixMint(finRef, request.auth.uid, Number(fin.amount) || 0);
  if (mint.reuse) return mpPixReuseResponse(mint.reuse);

  let pix;
  try {
    pix = await createMpPix({
      academyId,
      transactionAmount: Number(fin.amount) || 0, // server-derived REAIS
      description: sanitizeString(description) || 'Mensalidade',
      externalReference: `${academyId}:fin:${financialId}`,
      payer: { email: resolvedEmail, cpf: cpfDigits, name: studentName },
    });
  } catch (e) {
    await mpReleasePixMint(finRef); // solta o lock p/ um retry imediato
    throw e;
  }

  const expiresAt = admin.firestore.Timestamp.fromDate(pix.expiresAt);
  await finRef.update({
    pixCode: pix.pixCode || null,
    pixQrCode: pix.qrCodeBase64 || null,
    pixTicketUrl: pix.ticketUrl || null,
    gatewayPaymentId: pix.paymentId,
    paymentGateway: 'mercadopago',
    pixExpiresAt: expiresAt,
    // Auditoria MP (PIX reaproveitado com valor antigo): persiste o valor (REAIS)
    // com que o QR foi cunhado para o reuse guard revalidar contra fin.amount —
    // se o valor da cobrança mudar, NÃO reusa o QR velho (cunha novo).
    pixAmount: Number(fin.amount) || 0,
    pixMintAt: admin.firestore.FieldValue.delete(),
    pixMintBy: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    pixCode: pix.pixCode,
    qrCodeUrl: pix.qrCodeBase64,
    ticketUrl: pix.ticketUrl || '',
    paymentId: pix.paymentId,
    expiresAt: expiresAt.toDate().toISOString(),
  };
});

// ---- PIX: loja (amount em CENTAVOS; cross-check — a cobrança é derivada
// server-side de orderAuthoritativeTotalReais, o cliente envia (reais*100)) ----
exports.createMpOrderPixPayment = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const { academyId, amount, description, orderId, studentId, studentName,
    payerCpf, payerEmail } = request.data || {};
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
  if (!academyId || !amount || !orderId || !studentId) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }
  await assertCanPayFor(request, academyId, studentId);
  const amountValidation = validateAmount(amount);
  if (!amountValidation.valid) {
    throw new HttpsError('invalid-argument', amountValidation.error || 'Invalid amount');
  }

  const orderRef = db.doc(`academies/${academyId}/storeOrders/${orderId}`);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) throw new HttpsError('not-found', 'Order not found');
  const order = orderSnap.data();
  if (order.studentId !== studentId) {
    throw new HttpsError('permission-denied', 'Order does not belong to this student');
  }
  if (order.status === 'paid') {
    throw new HttpsError('already-exists', 'This order has already been paid');
  }

  // Enforcement de política de método de pagamento da LOJA. SECURITY: o pedido
  // é criado client-side, então NÃO confiamos em `order.paymentMethodPolicy`.
  // Recomputamos a política efetiva a partir dos PRODUTOS (server-side), do
  // mesmo jeito que o total é recomputado via orderAuthoritativeTotalReais. Pedido
  // com algum item "somente cartao" não aceita PIX. Espelha o erro de :3161.
  const orderPolicy = await orderEffectivePolicy(academyId, order);
  if (!orderPolicy.allowsPix) {
    throw new HttpsError('failed-precondition',
      'Este pedido aceita apenas cartao.');
  }

  // SECURITY: never trust the client amount. Derive the charge server-side
  // recomputando o total a partir de storeProducts (preco autoritativo —
  // items[].price/total do pedido sao escritos pelo cliente e NAO valem como
  // fronteira). O cliente envia CENTAVOS (H1); e so cross-check (1 centavo).
  const expectedReais = await orderAuthoritativeTotalReais(academyId, order);
  const expectedCentavos = Math.round(expectedReais * 100);
  if (Math.abs(expectedCentavos - amount) > 1) {
    throw new HttpsError('invalid-argument',
      `Amount (${amount}) does not match order total (${expectedCentavos})`);
  }
  // Grava o total autoritativo de volta no pedido para o guard de valor do
  // settle (mpMktSettle) comparar contra o numero correto.
  if (Math.abs((Number(order.total ?? order.totalAmount) || 0) - expectedReais) > 0.005) {
    await orderRef.update({
      total: expectedReais,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  const existingExpiry = order.pixExpiresAt && typeof order.pixExpiresAt.toMillis === 'function'
    ? order.pixExpiresAt.toMillis() : 0;
  // Auditoria MP: só reusa se o valor cunhado (pixAmount) ainda bate com o total
  // autoritativo recomputado (1-centavo). Retrocompat: PIX legado sem pixAmount
  // é reusado normalmente (espelha o caminho da mensalidade).
  const orderPixAmountOk = typeof order.pixAmount !== 'number' ||
    Math.abs(expectedReais - order.pixAmount) <= 0.01;
  if (order.gatewayPaymentId && order.pixCode && existingExpiry > Date.now() &&
      orderPixAmountOk) {
    return {
      pixCode: order.pixCode,
      qrCodeUrl: order.pixQrCode || '',
      ticketUrl: order.pixTicketUrl || '',
      paymentId: order.gatewayPaymentId,
      expiresAt: order.pixExpiresAt.toDate().toISOString(),
    };
  }

  // PIX requires a valid payer CPF (Brazilian regulation) AND a real e-mail.
  // Mirror the mensalidade path: fail fast with a clear message instead of
  // letting Mercado Pago reject an incomplete payer (which surfaced to users
  // as a generic "falha na cobranca PIX").
  // Auditoria (correção): valida o CPF pelo CHECKSUM (validateCPF), não só pelo
  // comprimento — espelha o caminho da mensalidade.
  const cpfDigits = String(payerCpf || '').replace(/\D/g, '');
  if (!validateCPF(cpfDigits)) {
    throw new HttpsError('failed-precondition',
      'Para pagar via PIX e necessario um CPF valido. Informe seu CPF e tente novamente.');
  }
  let resolvedEmail = String(payerEmail || '').trim();
  if (!resolvedEmail || !resolvedEmail.includes('@') ||
      resolvedEmail.endsWith('@bjjeasy.com.br')) {
    try {
      const authUser = await admin.auth().getUser(request.auth.uid);
      resolvedEmail = (authUser.email || '').trim();
    } catch (_) { /* keep whatever we had */ }
  }
  if (!resolvedEmail || !resolvedEmail.includes('@')) {
    throw new HttpsError('failed-precondition',
      'E necessario um e-mail valido na sua conta para gerar a cobranca PIX.');
  }

  // Auditoria MP (anti double-charge bidirecional): cancela um CARTÃO pendente
  // vivo deste pedido antes de cunhar o PIX (espelha o guard da mensalidade).
  await mpCancelLivePendingCard(academyId, orderRef);

  // Auditoria MP (PIX com valor antigo): cancela um PIX vivo cunhado com valor
  // divergente do total atual antes de cunhar o novo (espelha a mensalidade).
  if (typeof order.pixAmount === 'number' &&
      Math.abs(expectedReais - order.pixAmount) > 0.01 &&
      order.gatewayPaymentId && order.pixCode) {
    await mpCancelPixPayment(academyId, order.gatewayPaymentId, {});
  }

  // Anti-race (achado #24): serializa o mint via lock transacional no doc —
  // dois aparelhos concorrentes geram UM PIX só (o perdedor reusa o do vencedor).
  const mint = await mpAcquirePixMint(orderRef, request.auth.uid, expectedReais);
  if (mint.reuse) return mpPixReuseResponse(mint.reuse);

  let pix;
  try {
    pix = await createMpPix({
      academyId,
      transactionAmount: expectedReais, // server-derived reais
      description: sanitizeString(description) || 'Pedido da Loja',
      externalReference: `${academyId}:order:${orderId}`,
      payer: { email: resolvedEmail, cpf: cpfDigits, name: studentName },
    });
  } catch (e) {
    await mpReleasePixMint(orderRef); // solta o lock p/ um retry imediato
    throw e;
  }

  const expiresAt = admin.firestore.Timestamp.fromDate(pix.expiresAt);
  await orderRef.update({
    pixCode: pix.pixCode || null,
    pixQrCode: pix.qrCodeBase64 || null,
    pixTicketUrl: pix.ticketUrl || null,
    gatewayPaymentId: pix.paymentId,
    paymentGateway: 'mercadopago',
    pixExpiresAt: expiresAt,
    // Auditoria MP (PIX reaproveitado com valor antigo): valor (REAIS) com que o
    // QR foi cunhado, para o reuse guard revalidar contra o total autoritativo.
    pixAmount: expectedReais,
    pixMintAt: admin.firestore.FieldValue.delete(),
    pixMintBy: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    pixCode: pix.pixCode,
    qrCodeUrl: pix.qrCodeBase64,
    ticketUrl: pix.ticketUrl || '',
    paymentId: pix.paymentId,
    expiresAt: expiresAt.toDate().toISOString(),
  };
});

// ---- Card (token tokenized client-side with the admin's public_key) -------
// Handles BOTH mensalidade (financialId) and loja (orderId). Em AMBOS o cliente
// envia `amount` em CENTAVOS (cross-check; o valor real é derivado server-side).
// Card is synchronous: settle inline when approved;
// the webhook is the backup for async/3DS confirmations.
exports.createMpCardPayment = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const { academyId, amount, description, financialId, orderId, studentId,
    studentName, cardToken, installments, payerCpf, payerEmail } = request.data || {};
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
  if (!academyId || !amount || !studentId || !cardToken || (!financialId && !orderId)) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }
  await assertCanPayFor(request, academyId, studentId);
  const amountValidation = validateAmount(amount);
  if (!amountValidation.valid) {
    throw new HttpsError('invalid-argument', amountValidation.error || 'Invalid amount');
  }

  const isOrder = !!orderId;
  const docId = isOrder ? orderId : financialId;
  const ref = isOrder
    ? db.doc(`academies/${academyId}/storeOrders/${orderId}`)
    : db.doc(`academies/${academyId}/financials/${financialId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Record not found');
  const recData = snap.data();
  if (recData.status === 'paid') {
    throw new HttpsError('already-exists', 'Already paid');
  }
  // Ownership: both financial and storeOrder docs carry studentId; require it to
  // match the authenticated payer for BOTH (orders were previously unchecked).
  if (recData.studentId !== studentId) {
    throw new HttpsError('permission-denied', 'Record does not belong to this student');
  }

  // SECURITY (defesa em profundidade): cartao de credito na LOJA so quando a
  // academia habilitou storeCreditCardEnabled. O gate da UI nao basta — reforco
  // server-side aqui. Mensalidade (nao-order) nao e afetada.
  if (isOrder) {
    // Enforcement de política de método de pagamento da LOJA. SECURITY: o pedido
    // é criado client-side, então NÃO confiamos em `recData.paymentMethodPolicy`.
    // Recomputamos a política efetiva a partir dos PRODUTOS (server-side), do
    // mesmo jeito que o total é recomputado via orderAuthoritativeTotalReais. Cartão
    // permitido SSE policy.allowsCard && storeCreditCardEnabled.
    const orderPolicy = await orderEffectivePolicy(academyId, recData);
    if (!orderPolicy.allowsCard) {
      throw new HttpsError('failed-precondition',
        'Este pedido aceita apenas PIX.');
    }
    const acadSnap = await db.doc(`academies/${academyId}`).get();
    if (acadSnap.data()?.storeCreditCardEnabled !== true) {
      throw new HttpsError('failed-precondition',
        'Pagamento com cartao nao esta habilitado para a loja desta academia.');
    }
  } else if (recData.paymentMethodPolicy === 'pix_only') {
    // Payment-method policy: cobranca/mensalidade marcada como "somente PIX"
    // nao aceita cartao (enforcement server-side, alem do gate da UI).
    throw new HttpsError('failed-precondition',
      'Esta cobranca aceita apenas PIX.');
  }

  // SECURITY: never trust the client amount. DERIVE the charge server-side.
  // Mensalidade: financial.amount e REAIS (canonico). Loja: o pedido e criado
  // client-side, entao o total e recomputado de storeProducts (preco
  // autoritativo) — items[].price/total NAO valem como fronteira. O cliente
  // envia CENTAVOS; o valor dele e so cross-check (1-centavo tolerance).
  let expectedCentavos;
  if (isOrder) {
    const authoritativeReais =
      await orderAuthoritativeTotalReais(academyId, recData);
    expectedCentavos = Math.round(authoritativeReais * 100);
    // Grava o total autoritativo de volta no pedido para o guard de valor do
    // settle (mpMktSettle) comparar contra o numero correto.
    if (Math.abs((Number(recData.total ?? recData.totalAmount) || 0) -
        authoritativeReais) > 0.005) {
      await ref.update({
        total: authoritativeReais,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  } else {
    expectedCentavos = Math.round((Number(recData.amount) || 0) * 100);
  }
  if (Math.abs(expectedCentavos - amount) > 1) {
    throw new HttpsError('invalid-argument',
      `Amount (${amount}) does not match expected amount (${expectedCentavos})`);
  }
  // transaction_amount is always REAIS for MP.
  const transactionAmount = expectedCentavos / 100;
  const token = await getMpAccessToken(academyId);

  // Auditoria MP (anti double-charge cartão→cartão): se este MESMO doc já tem um
  // CARTÃO pendente vivo (in_process/3DS — cardPendingPaymentId gravado abaixo),
  // cobrar OUTRO cartão agora deixaria as DUAS cobranças pagáveis. Mata o cartão
  // pendente ANTES de tokenizar a nova cobrança (espelha o guard PIX→cartão e o
  // simétrico cartão→PIX em createMpPixPayment).
  {
    const cardGuard = await mpCancelLivePendingCard(academyId, ref);
    // Auditoria MP (cartão pendente JÁ APROVADO porém não liquidado): se no
    // intervalo o cartão anterior foi aprovado, NÃO cobramos de novo — o
    // doc ainda não virou 'paid' inline (aprovação assíncrona só liquida pelo
    // webhook), então o guard de status='paid' (acima) ainda não barra. Espelha
    // exatamente o branch PIX→cartão (alreadyApproved / !cancelled).
    if (cardGuard.alreadyApproved) {
      throw new HttpsError('failed-precondition',
        'Este pagamento ja foi aprovado, aguarde a confirmacao.');
    }
    if (!cardGuard.cancelled) {
      // Não foi possível garantir que o cartão pendente foi cancelado no MP →
      // recusa a 2ª cobrança para não arriscar a dupla. O aluno re-tenta.
      throw new HttpsError('failed-precondition',
        'Ha um pagamento com cartao em andamento para esta cobranca. ' +
        'Aguarde alguns segundos e tente novamente.');
    }
  }

  // Auditoria (anti double-charge): se este MESMO doc já tem um PIX VIVO não
  // pago (gatewayPaymentId + pixCode + pixExpiresAt no futuro), cobrar o cartão
  // agora deixaria as DUAS cobranças pagáveis ao mesmo tempo — a família podia
  // pagar o cartão e o PIX. Cancela o PIX em aberto ANTES de cobrar o cartão
  // (reusa o mesmo cancelamento do callable cancelMpPix). Se o PIX já estiver
  // aprovado, NÃO cobramos o cartão: o doc já foi/serásettleado pelo webhook.
  {
    const pixExpMs = recData.pixExpiresAt &&
      typeof recData.pixExpiresAt.toMillis === 'function'
      ? recData.pixExpiresAt.toMillis() : 0;
    const hasLivePix = recData.paymentGateway === 'mercadopago' &&
      recData.gatewayPaymentId && recData.pixCode && pixExpMs > Date.now();
    if (hasLivePix) {
      const cancel = await mpCancelPixPayment(academyId, recData.gatewayPaymentId,
        { token });
      if (cancel.alreadyApproved) {
        throw new HttpsError('failed-precondition',
          'Esta cobranca ja foi paga via PIX. Atualize a tela.');
      }
      if (!cancel.cancelled) {
        // Não conseguimos garantir que o PIX foi morto → recusa o cartão para
        // não arriscar a cobrança dupla. O aluno re-tenta em instantes.
        throw new HttpsError('failed-precondition',
          'Ha um PIX em aberto para esta cobranca. Aguarde alguns segundos e ' +
          'tente o cartao novamente, ou pague pelo PIX ja gerado.');
      }
      // Auditoria MP (PIX órfão no doc → cartão bloqueado por até 24h): o PIX
      // foi cancelado no MP acima, mas os campos pix* seguiam no doc. Numa 2ª
      // tentativa de cartão o guard hasLivePix os relia (pixExpiresAt ainda no
      // futuro) e recusava o cartão por um PIX que já está MORTO. Apaga os
      // campos pix* e o gatewayPaymentId — espelha o que o settle já faz — para
      // que hasLivePix volte a ser FALSE. Retrocompat: doc sem esses campos só
      // recebe deletes no-op. Best-effort: não trava a cobrança do cartão.
      await ref.update({
        pixCode: admin.firestore.FieldValue.delete(),
        pixQrCode: admin.firestore.FieldValue.delete(),
        pixTicketUrl: admin.firestore.FieldValue.delete(),
        pixExpiresAt: admin.firestore.FieldValue.delete(),
        pixAmount: admin.firestore.FieldValue.delete(),
        gatewayPaymentId: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch((e) => console.error(
        '[createMpCardPayment] limpeza pix órfão falhou', docId, e.message));
    }
  }

  const cpf = String(payerCpf || '').replace(/\D/g, '');
  const nameParts = String(studentName || '').trim().split(/\s+/);
  const externalReference = `${academyId}:${isOrder ? 'order' : 'fin'}:${docId}`;

  // Valida/resolve o e-mail do pagador (achado #25 — assimetria com o PIX):
  // espelha o bloco dos caminhos PIX. Um payer.email vazio ou placeholder
  // '@bjjeasy.com.br' faz o MP recusar o pagamento e o aluno só via o erro
  // genérico 'Falha ao processar o cartao.' sem saber o que corrigir.
  let resolvedEmail = String(payerEmail || '').trim();
  if (!resolvedEmail || !resolvedEmail.includes('@') ||
      resolvedEmail.endsWith('@bjjeasy.com.br')) {
    try {
      const authUser = await admin.auth().getUser(request.auth.uid);
      resolvedEmail = (authUser.email || '').trim();
    } catch (_) { /* keep whatever we had */ }
  }
  if (!resolvedEmail || !resolvedEmail.includes('@')) {
    throw new HttpsError('failed-precondition',
      'E necessario um e-mail valido na sua conta para pagar com cartao.');
  }

  // Auditoria (correção): exige CPF VÁLIDO por checksum também no cartão (antes
  // o CPF era opcional e só ia no payer.identification quando tinha 11 dígitos).
  // O MP usa o CPF do pagador na análise antifraude; sem ele a recusa era comum
  // e o aluno via erro genérico. Simetria com o caminho PIX (validateCPF).
  if (!validateCPF(cpf)) {
    throw new HttpsError('failed-precondition',
      'Para pagar com cartao e necessario um CPF valido. Informe seu CPF e tente novamente.');
  }

  let payment;
  try {
    payment = await mpRequest('POST', '/v1/payments', {
      token,
      // Idempotency key inclui o token do cartao: estavel num retry de
      // transporte do MESMO submit, mas NOVA a cada nova tokenizacao — uma
      // recusa (CVV errado/sem saldo) nao congela a resposta para sempre.
      // Espelha o racional do PIX em createMpPix (key unica por mint).
      idempotencyKey: `${externalReference}:card:${cardToken}`,
      body: {
        transaction_amount: Number(transactionAmount.toFixed(2)),
        description: sanitizeString(description) ||
          (isOrder ? 'Pedido da Loja' : 'Mensalidade'),
        token: cardToken,
        installments: Number(installments) > 0 ? Number(installments) : 1,
        three_d_secure_mode: 'optional',
        binary_mode: false,
        external_reference: externalReference,
        notification_url: `${mpMktWebhookUrl()}?acad=${encodeURIComponent(academyId)}`,
        // NÃO enviar application_fee: o MP rejeita `0` ("must be positive").
        // Liquidação direta na conta da academia (0% de taxa) → omitir.
        payer: {
          email: resolvedEmail,
          first_name: nameParts[0] || undefined,
          last_name: nameParts.length > 1 ? nameParts.slice(1).join(' ') : undefined,
          identification: cpf.length >= 11 ? { type: 'CPF', number: cpf } : undefined,
        },
      },
    });
  } catch (e) {
    console.error('[createMpCardPayment] erro', e.message, e.data);
    // Auditoria (UX): mapeia a recusa do MP (status_detail / e.data.cause) em
    // mensagem pt-BR acionável em vez de um 'internal' opaco. O detalhe pode vir
    // no corpo do erro do MP (e.data.status_detail) ou na causa.
    const detail = (e && e.data && (e.data.status_detail ||
      (Array.isArray(e.data.cause) && e.data.cause[0] &&
        (e.data.cause[0].description || e.data.cause[0].code)))) || '';
    throw mapMpCardError(e, detail);
  }

  // Synchronous approval → settle now; webhook covers async/3DS later.
  if (payment.status === 'approved') {
    await mpMktSettle({ academyId, type: isOrder ? 'order' : 'fin', docId }, payment);
  } else if (payment.status === 'in_process' || payment.status === 'pending') {
    // Auditoria MP (anti double-charge bidirecional): cartão em análise/3DS NÃO
    // grava estado no doc, então o guard PIX (createMpPixPayment) não sabia que
    // havia um cartão vivo e gerava um PIX pagável em paralelo → cobrança dupla
    // na direção inversa. Persiste o paymentId do cartão pendente + validade,
    // para o guard simétrico do PIX cancelá-lo antes de cunhar (espelha o
    // finRef.update do PIX vivo). Best-effort: não bloqueia a resposta do cartão.
    await ref.update({
      cardPendingPaymentId: String(payment.id),
      cardPendingStatus: payment.status,
      cardPendingExpiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + 60 * 60 * 1000), // ~1h: 3DS/análise costuma resolver antes
      paymentGateway: 'mercadopago',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch((e) => console.error(
      '[createMpCardPayment] cardPending persist falhou', docId, e.message));
  }

  return {
    success: payment.status === 'approved',
    status: payment.status,
    statusDetail: payment.status_detail || '',
    transactionId: String(payment.id),
    threeDsUrl: (payment.three_ds_info &&
      payment.three_ds_info.external_resource_url) || null,
  };
});

// ============================================================
// Recurring subscriptions (Assinaturas / Mercado Pago Preapproval)
// ============================================================
// A monthly + card-only plan is billed as a true subscription: after the
// student subscribes once (card tokenized client-side), MP auto-charges the
// card every month on `billing_day`, with no further action. We enforce the
// fixed N-month term ourselves (MP /preapproval has no native end): each
// approved charge mints one paid `financials` doc and bumps `chargesPaid`;
// when it reaches `months` we cancel the preapproval.

const FV = admin.firestore.FieldValue;

// ---- Dunning policy constants (resiliência de recorrência) -----------------
// Máximo de retentativas automáticas de uma assinatura `paused`/needsReauth e
// o backoff (em dias) a partir da falha. Após esgotar, mantém `paused` e
// notifica admin + aluno (NÃO cancela).
const MAX_DUNNING_RETRIES = 3;
const DUNNING_BACKOFF_DAYS = [1, 3, 7];
// Folga do backstop por DATA do term guard: ~1 ciclo de billing além do termo.
// Evita cancelar/completar antes da última cobrança quando o billing_day adiou a
// 1ª cobrança cheia (billing_day_proportional:false). A conclusão primária é por
// contagem (chargesPaid>=months); a data só age como rede de segurança tardia.
const TERM_GUARD_SLACK_MS = 35 * 24 * 60 * 60 * 1000;

/**
 * Extrai do retorno do Mercado Pago (preapproval POST ou payment) os dados
 * NÃO-PCI do cartão para espelhar em Firestore: últimos 4 dígitos + validade.
 * Defensivo: o payload do /preapproval pode trazer o cartão em `card` ou
 * aninhado; só retorna os campos que conseguir extrair (resto fica null).
 * Retorna { cardLast4, cardExpMonth, cardExpYear } com valores ou null.
 */
function extractMpCardInfo(mpPayload) {
  const card = mpPayload && (mpPayload.card ||
    (mpPayload.summarized && mpPayload.summarized.card) ||
    // authorized_payment / payment payloads aninham o cartão em `payment.card`.
    (mpPayload.payment && mpPayload.payment.card) || null);
  const toInt = (v) => {
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : null;
  };
  const last4Raw = card && (card.last_four_digits != null
    ? card.last_four_digits
    : card.lastFourDigits);
  const expMonth = card ? (card.expiration_month != null
    ? card.expiration_month : card.expirationMonth) : null;
  const expYear = card ? (card.expiration_year != null
    ? card.expiration_year : card.expirationYear) : null;
  // Normaliza ano de 2 dígitos (ex.: 27 → 2027). O MP pode devolver YY em alguns
  // payloads; sem isso o filtro expYear<2000 do scheduledCardExpiryWarning
  // descartaria o cartão silenciosamente. (00..99 → 2000..2099.)
  let expYearNorm = toInt(expYear);
  if (expYearNorm != null && expYearNorm >= 0 && expYearNorm < 100) {
    expYearNorm += 2000;
  }
  return {
    cardLast4: last4Raw != null ? String(last4Raw) : null,
    cardExpMonth: toInt(expMonth),
    cardExpYear: expYearNorm,
  };
}

/** Calcula o Timestamp do fim do termo (createdAt + months meses). `base` é um
 * Date/Timestamp; retorna admin Timestamp ou null se months<=0. */
function computeTermEndsAt(base, months) {
  const m = Number(months) || 0;
  if (m <= 0) return null;
  const baseDate = base && typeof base.toDate === 'function'
    ? base.toDate()
    : (base instanceof Date ? base : new Date());
  // Soma `m` meses clampando o dia ao último dia do mês alvo (mesma filosofia do
  // clamp de billing_day em 28): 31/Jan +1 → 28/Fev, e NÃO transborda p/ Março.
  const end = new Date(baseDate.getTime());
  const day = end.getDate();
  end.setDate(1); // evita overflow ao trocar o mês
  end.setMonth(end.getMonth() + m);
  // Último dia do mês alvo (dia 0 do mês seguinte).
  const lastDay = new Date(end.getFullYear(), end.getMonth() + 1, 0).getDate();
  end.setDate(Math.min(day, lastDay));
  return admin.firestore.Timestamp.fromDate(end);
}

/** Settle ONE approved subscription charge: mint a paid financial for the cycle
 * (idempotent by deterministic id), bump chargesPaid, and cancel the
 * preapproval once the N-month term is reached. */
async function mpSubSettleCycle(academyId, subscriptionId, token,
  { paymentId, amount, mpPayload, chargeDate } = {}) {
  const subRef = db.doc(`academies/${academyId}/subscriptions/${subscriptionId}`);
  // Deterministic financial id → the same MP payment never settles twice.
  const finId = `sub_${subscriptionId}_${paymentId}`;
  const finRef = db.doc(`academies/${academyId}/financials/${finId}`);

  // Data REAL da cobrança (payload do MP, passada pelo chamador): o
  // referenceMonth/dueDate do financial devem refletir o mês civil do CICLO
  // cobrado em America/Sao_Paulo (TZ pinada no index.js → localMonthKey é
  // wall-clock Brasil), NÃO o momento do settle — a drenagem atrasada do
  // reconcile/termGuard contabilizaria o ciclo no mês errado. Fallback para
  // `now` apenas quando o chamador não tem a data (ou ela é inválida).
  let chargedAt = chargeDate ? new Date(chargeDate) : null;
  if (!(chargedAt instanceof Date) || isNaN(chargedAt.getTime())) {
    chargedAt = new Date();
  }

  const result = await db.runTransaction(async (tx) => {
    const [subDoc, finDoc] = await Promise.all([tx.get(subRef), tx.get(finRef)]);
    if (!subDoc.exists) return { ok: false };
    if (finDoc.exists) return { ok: false }; // already settled this charge
    const sub = subDoc.data();
    const cycle = (sub.chargesPaid || 0) + 1;
    const referenceMonth = localMonthKey(chargedAt);
    const months = Number(sub.months) || 0;
    // GUARDA DE ESTADO TERMINAL / ALÉM DO TERMO: se a assinatura já está
    // 'cancelled'/'completed' ou já quitou todos os ciclos, o MP cobrou ALÉM
    // do contratado. O dinheiro entrou de fato, então o financial determinístico
    // É criado (idempotência preservada), mas sinalizado como cobrança indevida
    // (NÃO conta como mensalidade) e o estado da assinatura NÃO é ressuscitado.
    const isTerminal = sub.status === 'cancelled' || sub.status === 'completed';
    const beyondTerm = months > 0 && (sub.chargesPaid || 0) >= months;
    if (isTerminal || beyondTerm) {
      tx.set(finRef, {
        academyId,
        studentId: sub.studentId,
        studentName: sub.studentName || '',
        amount: amount > 0 ? amount : (Number(sub.recurringValue) || 0),
        type: 'subscription_overcharge',
        status: 'paid',
        overcharge: true,
        // Alinhamento com o financial_gate: ele exclui "dinheiro devido ao
        // aluno" por `isOvercharge === true`. Escreve os dois nomes para o
        // escritor e o leitor concordarem (nunca prender um pagante por isso).
        isOvercharge: true,
        needsRefund: true,
        description:
          'Cobrança indevida de assinatura (além do termo/cancelamento) — reembolsar',
        referenceMonth,
        planId: sub.planId || null,
        subscriptionId,
        paymentMethodPolicy: 'card_only',
        paymentGateway: 'mercadopago',
        method: 'card',
        gatewayPaymentId: paymentId,
        dueDate: admin.firestore.Timestamp.fromDate(chargedAt),
        paymentDate: FV.serverTimestamp(),
        createdAt: FV.serverTimestamp(),
        updatedAt: FV.serverTimestamp(),
      });
      // Preserva status/chargesPaid (não reabre 'completed'/'cancelled').
      tx.update(subRef, {
        lastPaymentId: paymentId,
        lastEvent: 'overcharge_detected',
        updatedAt: FV.serverTimestamp(),
      });
      return { ok: true, overcharge: true,
        preapprovalId: sub.mpPreapprovalId };
    }
    const settledAmount = amount > 0 ? amount : (Number(sub.recurringValue) || 0);
    // Auditoria MP (espelha o settleMismatch do avulso): se o valor cobrado pelo
    // MP divergir do recurringValue esperado da assinatura (> ~1 centavo),
    // sinaliza amountMismatch no financial e alerta o admin pós-tx — o `amount`
    // gravado é SEMPRE o efetivamente cobrado (não há perda), mas a divergência
    // (ex.: admin mudou o preço do plano e o preapproval segue no valor antigo)
    // fica visível em vez de passar silenciosa.
    const expectedRecurring = Number(sub.recurringValue) || 0;
    const amountMismatch = expectedRecurring > 0 && amount > 0 &&
      Math.abs(settledAmount - expectedRecurring) > 0.01;
    const finData = {
      academyId,
      studentId: sub.studentId,
      studentName: sub.studentName || '',
      amount: settledAmount,
      type: 'monthly_tuition',
      status: 'paid',
      description: 'Mensalidade (assinatura)',
      referenceMonth,
      planId: sub.planId || null,
      subscriptionId,
      recurringCycle: cycle,
      paymentMethodPolicy: 'card_only',
      paymentGateway: 'mercadopago',
      method: 'card',
      gatewayPaymentId: paymentId,
      dueDate: admin.firestore.Timestamp.fromDate(chargedAt),
      paymentDate: FV.serverTimestamp(),
      createdAt: FV.serverTimestamp(),
      updatedAt: FV.serverTimestamp(),
    };
    if (amountMismatch) {
      finData.amountMismatch = {
        expected: expectedRecurring,
        charged: settledAmount,
        at: admin.firestore.Timestamp.now(),
      };
    }
    tx.set(finRef, finData);
    const subUpdate = {
      chargesPaid: cycle,
      lastPaymentId: paymentId,
      needsReauth: false,
      // Voltou a cobrar com sucesso → zera o estado de dunning.
      failedAttempts: 0,
      nextRetryAt: null,
      dunningExhaustedNotifiedAt: null,
      lastEvent: 'payment_approved',
      updatedAt: FV.serverTimestamp(),
    };
    // Um ciclo em trânsito aprovado NÃO desfaz uma pausa intencional do aluno:
    // mantém 'paused'/pausedBy. Nos demais casos, pagamento aprovado ⇒ ativa.
    if (!(sub.status === 'paused' && sub.pausedBy === 'user')) {
      subUpdate.status = 'authorized';
    }
    // Fallback do espelho NÃO-PCI do cartão: o POST /preapproval normalmente NÃO
    // traz o cartão, mas o authorized_payment/payment aprovado costuma trazê-lo.
    // Preenche só o que ainda estiver ausente na assinatura (defensivo).
    if (mpPayload) {
      const cardInfo = extractMpCardInfo(mpPayload);
      if (cardInfo.cardLast4 != null && sub.cardLast4 == null) {
        subUpdate.cardLast4 = cardInfo.cardLast4;
      }
      if (cardInfo.cardExpMonth != null && sub.cardExpMonth == null) {
        subUpdate.cardExpMonth = cardInfo.cardExpMonth;
      }
      if (cardInfo.cardExpYear != null && sub.cardExpYear == null) {
        subUpdate.cardExpYear = cardInfo.cardExpYear;
      }
    }
    tx.update(subRef, subUpdate);
    return { ok: true, cycle, months: Number(sub.months) || 0,
      preapprovalId: sub.mpPreapprovalId,
      mismatch: amountMismatch
        ? { expected: expectedRecurring, charged: settledAmount } : null };
  });

  if (!result.ok) return;
  // Cobrança indevida (estado terminal / além do termo): tenta matar o
  // preapproval que ainda cobra (best-effort, o próximo ciclo re-tenta) e
  // alerta o admin para reembolso MANUAL. Não notifica como mensalidade.
  if (result.overcharge) {
    if (result.preapprovalId) {
      try {
        await mpRequest('PUT', `/preapproval/${result.preapprovalId}`,
          { token, body: { status: 'cancelled' } });
      } catch (e) {
        console.error('[mpSubSettleCycle] overcharge cancel failed', e.message);
      }
    }
    try {
      await notifyAdminCF(academyId, 'payment_overdue',
        'Cobranca indevida de assinatura',
        `Assinatura cobrou R$ ${(amount || 0).toFixed(2)} alem do termo/` +
        'cancelamento. Reembolse o aluno manualmente no Mercado Pago.',
        { subscriptionId });
    } catch (_) { /* notify is best-effort */ }
    return;
  }
  // Term reached → cancel the preapproval so MP stops charging. Só marca
  // 'completed' quando o MP CONFIRMAR o cancel (PUT ok, ou GET = cancelled);
  // senão o doc sumiria das queries dos crons com o preapproval vivo cobrando.
  if (result.months > 0 && result.cycle >= result.months && result.preapprovalId) {
    let mpCancelled = false;
    try {
      await mpRequest('PUT', `/preapproval/${result.preapprovalId}`,
        { token, body: { status: 'cancelled' } });
      mpCancelled = true;
    } catch (e) {
      console.error('[mpSubSettleCycle] term cancel failed', e.message);
      // PUT pode falhar com o preapproval JÁ cancelado no MP — confirma via GET.
      try {
        const pa = await mpRequest('GET',
          `/preapproval/${result.preapprovalId}`, { token });
        mpCancelled = !!pa && pa.status === 'cancelled';
      } catch (_) { /* mantém mpCancelled = false */ }
    }
    if (mpCancelled) {
      await subRef.update({
        status: 'completed',
        termCancelPending: FV.delete(),
        updatedAt: FV.serverTimestamp(),
      });
    } else {
      // Mantém o status atual (authorized/paused): o termGuard diário re-acha
      // a assinatura (chargesPaid >= months) e re-tenta o cancel até suceder.
      await subRef.update({
        termCancelPending: true,
        lastEvent: 'term_cancel_failed',
        updatedAt: FV.serverTimestamp(),
      });
    }
  }
  try {
    await notifyAdminCF(academyId, 'payment_received', 'Mensalidade recebida',
      `Assinatura: cobranca de R$ ${(amount || 0).toFixed(2)} recebida no cartao.`,
      { subscriptionId });
  } catch (_) { /* notify is best-effort */ }
  // Auditoria MP: alerta de divergência de valor (espelha o settleMismatch do
  // avulso). O ciclo FOI creditado (o dinheiro entrou), mas o valor diverge do
  // esperado do plano — admin confere/atualiza o preapproval.
  if (result.mismatch) {
    try {
      await notifyAdminCF(academyId, 'payment_overdue',
        'Assinatura com valor divergente',
        `A assinatura cobrou R$ ${result.mismatch.charged.toFixed(2)}, mas o ` +
        `valor esperado do plano e R$ ${result.mismatch.expected.toFixed(2)}. ` +
        'A cobranca foi registrada; confira o valor da assinatura no Mercado Pago.',
        { subscriptionId });
    } catch (_) { /* notify is best-effort */ }
  }
}

/** Webhook: an authorized_payment event for a subscription. */
async function mpSubHandleAuthorizedPayment(academyId, authPayId) {
  const token = await getMpAccessToken(academyId);
  const ap = await mpRequest('GET', `/authorized_payments/${authPayId}`, { token });
  const preapprovalId = ap && ap.preapproval_id;
  if (!preapprovalId) return;
  const subSnap = await db.collection(`academies/${academyId}/subscriptions`)
    .where('mpPreapprovalId', '==', String(preapprovalId)).limit(1).get();
  let subRef;
  if (!subSnap.empty) {
    subRef = subSnap.docs[0].ref;
  } else {
    // SELF-HEALING: doc órfão (crash entre POST /preapproval e o update do
    // doc). O external_reference costuma vir no próprio authorized_payment;
    // se ausente, busca no preapproval.
    let extRef = ap.external_reference;
    let paStatus = null;
    if (!extRef) {
      try {
        const pa = await mpRequest('GET',
          `/preapproval/${preapprovalId}`, { token });
        extRef = pa && pa.external_reference;
        paStatus = pa && pa.status;
      } catch (e) {
        console.error('[mpSubHandleAuthorizedPayment] GET preapproval falhou ' +
          'no self-healing', academyId, String(preapprovalId), e.message);
      }
    }
    const healed = await mpSubHealOrphanSubscription(
      academyId, String(preapprovalId), extRef, paStatus);
    if (!healed) return;
    subRef = healed.ref;
  }
  const payStatus = ap.payment && ap.payment.status;
  const paymentId = ap.payment && ap.payment.id ?
    String(ap.payment.id) : `ap_${authPayId}`;
  const amount = Number(ap.transaction_amount) || 0;
  if (payStatus === 'approved') {
    await mpSubSettleCycle(academyId, subRef.id, token, {
      paymentId, amount, mpPayload: ap,
      // Data real da cobrança → referenceMonth/dueDate do ciclo correto.
      chargeDate: (ap.payment && ap.payment.date_approved) ||
        ap.debit_date || ap.date_created,
    });
  } else if (MP_REVERSAL_STATUSES.includes(payStatus)) {
    // Auditoria MP (completude defensiva): refund/chargeback do MP chegam pelo
    // tópico `payment` (onde mpSubHandleReversal já trata) — mas se um
    // authorized_payment for entregue com o payment já estornado, reverte aqui
    // também pelo MESMO handler idempotente, evitando que chargesPaid/financial
    // fiquem 'paid' indevidamente. Passa ap.payment (objeto com .id/.status/
    // .transaction_amount), não ap. NÃO trata 'cancelled' como reversão de ciclo:
    // só refunded/charged_back (cancelled de ciclo é tentativa fracassada, abaixo).
    if (payStatus === 'refunded' || payStatus === 'charged_back') {
      await mpSubHandleReversal(academyId, subRef.id, ap.payment);
    } else {
      // 'cancelled' aqui = tentativa de cobrança cancelada (dunning), não estorno.
      await subRef.update({
        lastEvent: `payment_${payStatus}`,
        updatedAt: FV.serverTimestamp(),
      });
    }
  } else if (payStatus === 'rejected') {
    // Dunning: do NOT settle. The preapproval will move to paused; the sync
    // handler flags needsReauth. Record the failed attempt for visibility.
    await subRef.update({
      lastEvent: `payment_${payStatus}`,
      updatedAt: FV.serverTimestamp(),
    });
  }
}

/** Pausa intencional LEGADA: o pauseMpSubscription antigo (em produção) gravava
 * `status:'paused'` SEM `pausedBy`. Um doc local já 'paused' sem NENHUM estado
 * de dunning (needsReauth/failedAttempts/nextRetryAt) só pode ter vindo dessa
 * pausa intencional — uma pausa por cobrança recusada sempre chega com o doc
 * 'authorized' (webhook/reconcile é quem o pausa, já setando needsReauth).
 * Tratar como pausedBy:'user' (com backfill) impede que reconcile+dunning
 * reativem a cobrança desses dados legados sem consentimento. */
function isLegacyUserPause(sub) {
  return sub.status === 'paused' && sub.pausedBy == null &&
    sub.needsReauth !== true &&
    !(Number(sub.failedAttempts) > 0) &&
    sub.nextRetryAt == null;
}

/** SELF-HEALING de assinatura órfã: se a function morreu entre o POST
 * /preapproval e o update do doc (createMpSubscription), a assinatura fica
 * 'pending' SEM mpPreapprovalId e os lookups por mpPreapprovalId retornam
 * vazio — webhooks descartados em silêncio enquanto o MP cobra o cartão.
 * Recupera pelo external_reference do preapproval (`${academyId}:sub:${subId}`,
 * gerado em createMpSubscription e parseável por mpMktParseRef): grava o
 * mpPreapprovalId ausente (e o status do MP, se o doc ainda está 'pending') e
 * devolve { ref, data } para o chamador prosseguir o processamento. Retorna
 * null (com log destacado) quando irrecuperável. */
async function mpSubHealOrphanSubscription(academyId, preapprovalId,
  externalReference, mpStatus) {
  const parsed = mpMktParseRef(externalReference);
  if (!parsed || parsed.type !== 'sub' || parsed.academyId !== academyId) {
    console.error('[mpSubHealOrphan] ASSINATURA ÓRFÃ IRRECUPERÁVEL: nenhum doc ' +
      'com este mpPreapprovalId e external_reference não aponta para assinatura ' +
      'desta academia', academyId, preapprovalId, externalReference || '(vazio)');
    return null;
  }
  const ref = db.doc(`academies/${academyId}/subscriptions/${parsed.docId}`);
  const snap = await ref.get();
  if (!snap.exists) {
    console.error('[mpSubHealOrphan] ASSINATURA ÓRFÃ IRRECUPERÁVEL: doc ' +
      `subscriptions/${parsed.docId} não existe`, academyId, preapprovalId);
    return null;
  }
  const data = snap.data();
  if (data.mpPreapprovalId && data.mpPreapprovalId !== String(preapprovalId)) {
    console.error('[mpSubHealOrphan] doc aponta para OUTRO preapproval — ' +
      'possível preapproval duplicado, NÃO sobrescrevendo', academyId,
      parsed.docId, 'doc:', data.mpPreapprovalId,
      'webhook:', String(preapprovalId));
    return null;
  }
  const heal = {
    mpPreapprovalId: String(preapprovalId),
    lastEvent: 'orphan_preapproval_healed',
    updatedAt: FV.serverTimestamp(),
  };
  const map = { authorized: 'authorized', paused: 'paused',
    cancelled: 'cancelled', pending: 'pending' };
  if (data.status === 'pending' && map[mpStatus]) heal.status = map[mpStatus];
  await ref.update(heal);
  console.log('[mpSubHealOrphan] assinatura órfã recuperada', academyId,
    parsed.docId, '→ mpPreapprovalId', String(preapprovalId));
  return {
    ref,
    data: Object.assign({}, data, { mpPreapprovalId: String(preapprovalId) },
      heal.status ? { status: heal.status } : {}),
  };
}

/** Webhook: a preapproval status change (authorized/paused/cancelled). */
async function mpSubSyncPreapproval(academyId, preapprovalId) {
  const token = await getMpAccessToken(academyId);
  const pa = await mpRequest('GET', `/preapproval/${preapprovalId}`, { token });
  const subSnap = await db.collection(`academies/${academyId}/subscriptions`)
    .where('mpPreapprovalId', '==', String(preapprovalId)).limit(1).get();
  let subRef; let current;
  if (!subSnap.empty) {
    subRef = subSnap.docs[0].ref;
    current = subSnap.docs[0].data();
  } else {
    // SELF-HEALING: doc órfão (crash entre POST /preapproval e o update do
    // doc em createMpSubscription) — sem isso o webhook seria descartado em
    // silêncio com o preapproval vivo cobrando o cartão.
    const healed = await mpSubHealOrphanSubscription(
      academyId, String(preapprovalId), pa && pa.external_reference,
      pa && pa.status);
    if (!healed) return;
    subRef = healed.ref;
    current = healed.data;
  }
  // Never downgrade a term-completed subscription back to cancelled.
  if (current.status === 'completed') return;

  const map = { authorized: 'authorized', paused: 'paused',
    cancelled: 'cancelled', pending: 'pending' };
  const newStatus = map[pa.status] || pa.status;
  const update = {
    status: newStatus,
    lastEvent: `preapproval_${pa.status}`,
    updatedAt: FV.serverTimestamp(),
  };
  if (pa.next_payment_date) {
    update.nextBillingDate =
      admin.firestore.Timestamp.fromDate(new Date(pa.next_payment_date));
  }
  // Pausa INTENCIONAL do aluno (pausedBy:'user') NÃO entra em dunning: nada de
  // needsReauth/nextRetryAt, senão o dunning reativa a cobrança sem consentimento.
  let startedDunning = false;
  if (pa.status === 'paused' && current.pausedBy !== 'user') {
    if (isLegacyUserPause(current)) {
      // Dados legados: pausa intencional gravada sem pausedBy — backfill.
      update.pausedBy = 'user';
    } else {
      startedDunning = true;
      update.needsReauth = true;
      // Início do ciclo de dunning: marca a falha e agenda o 1º retry se ainda
      // não houver um pendente (o cron scheduledSubscriptionDunning assume daqui).
      update.lastFailureAt = FV.serverTimestamp();
      if (current.nextRetryAt == null) {
        update.nextRetryAt = admin.firestore.Timestamp.fromMillis(
          Date.now() + DUNNING_BACKOFF_DAYS[0] * 24 * 60 * 60 * 1000);
      }
    }
  }
  if (pa.status === 'authorized') {
    update.needsReauth = false;
    // Reativou no MP → a pausa intencional (se havia) deixa de existir.
    update.pausedBy = FV.delete();
    // Recuperou sozinha → limpa o estado de dunning.
    update.failedAttempts = 0;
    update.nextRetryAt = null;
    update.dunningExhaustedNotifiedAt = null;
  }
  await subRef.update(update);

  if (startedDunning) {
    try {
      await notifyAdminCF(academyId, 'payment_overdue', 'Assinatura com falha',
        'A cobranca recorrente de um aluno falhou (cartao recusado/expirado).',
        { subscriptionId: subRef.id });
    } catch (_) { /* best-effort */ }
  }
}

// ---- createMpSubscription — start a recurring card subscription ------------
exports.createMpSubscription = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const { academyId, planId, studentId, studentName, cardToken, payerCpf,
    payerEmail } = request.data || {};
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
  if (!academyId || !planId || !studentId || !cardToken) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }
  await assertCanPayFor(request, academyId, studentId);

  // Guarda de duplicidade: um retry/duplo-toque do cliente criaria DOIS
  // preapprovals cobrando o mesmo cartão todo mês. Rejeita se já existe
  // assinatura viva deste aluno+plano (cobre o retry sequencial; o caso
  // CONCORRENTE é colapsado pela idempotencyKey determinística no POST
  // /preapproval abaixo). Exceção: docs 'pending' SEM mpPreapprovalId com
  // mais de 1h são lixo de tentativa abortada (crash antes do POST
  // /preapproval) — marca 'abandoned' e ignora.
  const dupSnap = await db.collection(`academies/${academyId}/subscriptions`)
    .where('studentId', '==', studentId)
    .where('planId', '==', planId)
    .where('status', 'in', ['pending', 'authorized', 'paused', 'error'])
    .get();
  const STALE_PENDING_MS = 60 * 60 * 1000; // 1h
  const ORPHAN_RISK_MS = 24 * 60 * 60 * 1000; // 24h
  let hasLiveSub = false;
  for (const dupDoc of dupSnap.docs) {
    const dup = dupDoc.data();
    const createdMs = dup.createdAt && typeof dup.createdAt.toMillis === 'function'
      ? dup.createdAt.toMillis() : 0;
    const ageMs = createdMs > 0 ? (Date.now() - createdMs) : Infinity;
    const isStaleAbort = dup.status === 'pending' && !dup.mpPreapprovalId &&
      createdMs > 0 && ageMs > STALE_PENDING_MS;
    if (isStaleAbort) {
      await dupDoc.ref.update({
        status: 'abandoned',
        lastEvent: 'abandoned_stale_pending',
        updatedAt: FV.serverTimestamp(),
      }).catch(() => { /* best-effort: não bloqueia a criação */ });
    } else if (dup.status === 'error') {
      // Uma criação que FALHOU só bloqueia um novo retry quando pode esconder um
      // preapproval órfão VIVO no MP — a busca no catch não confirmou o
      // cancelamento (possibleOrphan) ou um id já ficou gravado. Uma falha comum
      // (cartão recusado, sem órfão) NÃO bloqueia o aluno de tentar de novo.
      if (ageMs < ORPHAN_RISK_MS && (dup.mpPreapprovalId || dup.possibleOrphan === true)) {
        hasLiveSub = true;
      }
    } else {
      hasLiveSub = true;
    }
  }
  if (hasLiveSub) {
    throw new HttpsError('failed-precondition',
      'Já existe uma assinatura ativa (ou em verificação) deste plano para este aluno.');
  }

  const planSnap = await db.doc(`academies/${academyId}/plans/${planId}`).get();
  if (!planSnap.exists) throw new HttpsError('not-found', 'Plano não encontrado.');
  const plan = planSnap.data();
  const isMonthly = (plan.billingPeriod || 'monthly') === 'monthly';
  if (!isMonthly || plan.paymentMethodPolicy !== 'card_only') {
    throw new HttpsError('failed-precondition',
      'Este plano não é uma assinatura recorrente (mensal + somente cartão).');
  }
  // Derive the monthly amount SERVER-SIDE (custom value per student wins). Never
  // trust a client-sent value.
  const custom = plan.customValues && plan.customValues[studentId];
  const monthlyValue = Number(custom != null ? custom : plan.monthlyValue) || 0;
  if (monthlyValue <= 0) {
    throw new HttpsError('failed-precondition', 'Valor do plano inválido.');
  }
  const months = Number(plan.recurringMonths) > 0 ? Number(plan.recurringMonths) : 0;
  let billingDay = Number(plan.billingDay || plan.defaultDueDay || 5);
  if (!(billingDay >= 1)) billingDay = 1;
  if (billingDay > 28) billingDay = 28; // avoid short-month drift

  // MP /preapproval REQUIRES a valid payer_email. Resolve robustly (client may
  // send null/placeholder): fall back to the auth account, then the student doc.
  let resolvedEmail = String(payerEmail || '').trim();
  const emailOk = (e) => e && e.includes('@') && !e.endsWith('@bjjeasy.com.br');
  if (!emailOk(resolvedEmail)) {
    try {
      const authUser = await admin.auth().getUser(request.auth.uid);
      if (emailOk((authUser.email || '').trim())) {
        resolvedEmail = authUser.email.trim();
      }
    } catch (_) { /* keep trying below */ }
  }
  if (!emailOk(resolvedEmail)) {
    const stuSnap = await db.doc(`academies/${academyId}/students/${studentId}`).get();
    const stuEmail = String((stuSnap.data() || {}).email || '').trim();
    if (emailOk(stuEmail)) resolvedEmail = stuEmail;
  }
  if (!resolvedEmail || !resolvedEmail.includes('@')) {
    throw new HttpsError('failed-precondition',
      'É necessário um e-mail válido para criar a assinatura. Atualize o e-mail do aluno.');
  }

  const token = await getMpAccessToken(academyId);
  const subRef = db.collection(`academies/${academyId}/subscriptions`).doc();
  const subId = subRef.id;
  const externalReference = `${academyId}:sub:${subId}`;

  await subRef.set({
    studentId,
    studentName: studentName || '',
    planId,
    status: 'pending',
    recurringValue: monthlyValue,
    billingDay,
    months,
    chargesPaid: 0,
    needsReauth: false,
    // Resiliência de recorrência: estado de dunning começa zerado.
    failedAttempts: 0,
    createdAt: FV.serverTimestamp(),
    updatedAt: FV.serverTimestamp(),
  });

  // Idempotência DETERMINÍSTICA por alvo (academia+aluno+plano) numa janela de
  // 15 min: duas invocações SIMULTÂNEAS (ex.: responsável e aluno com a mesma
  // cobrança aberta em dois aparelhos) passam ambas pela guarda de duplicidade
  // acima, mas colapsam no MP em UM único preapproval — em vez de dois
  // cobrando o mesmo cartão todo mês. A janela curta evita que uma
  // re-assinatura legítima (cancelou e assinou de novo mais tarde) colida com
  // a key da criação anterior.
  const idemWindow = Math.floor(Date.now() / (15 * 60 * 1000));
  let pa;
  try {
    pa = await mpRequest('POST', '/preapproval', {
      token,
      idempotencyKey: `sub:${academyId}:${studentId}:${planId}:${idemWindow}`,
      body: {
        reason: sanitizeString(plan.name ? `Mensalidade ${plan.name}` : 'Mensalidade'),
        external_reference: externalReference,
        payer_email: resolvedEmail,
        card_token_id: cardToken,
        status: 'authorized', // auto-charge without a hosted page
        back_url: 'https://arpjj-76350.web.app',
        notification_url: `${mpMktWebhookUrl()}?acad=${encodeURIComponent(academyId)}`,
        auto_recurring: {
          frequency: 1,
          frequency_type: 'months',
          transaction_amount: Number(monthlyValue.toFixed(2)),
          currency_id: 'BRL',
          billing_day: billingDay,
          billing_day_proportional: false, // 1ª cobrança cheia no dia da assinatura
        },
      },
    });
  } catch (e) {
    console.error('[createMpSubscription] erro', e.message, e.data);
    // O POST pode ter CRIADO o preapproval no MP e falhado só na RESPOSTA
    // (timeout/erro parcial). Marcar 'error' sem mpPreapprovalId esconderia esse
    // preapproval ÓRFÃO da guarda de duplicidade -> um retry criaria um SEGUNDO
    // preapproval cobrando o mesmo cartão todo mês. Procura no MP pelo
    // external_reference (único deste sub) e, se o órfão existir, ADOTA-o
    // (segue para o pós-processamento de sucesso abaixo, reaproveitando-o).
    let recovered = null;
    let searchFailed = false;
    try {
      const found = await mpRequest('GET',
        `/preapproval/search?external_reference=${encodeURIComponent(externalReference)}`,
        { token });
      const results = (found && (found.results || found.elements)) || [];
      recovered = results.find((r) => r && r.id) || null;
    } catch (searchErr) {
      searchFailed = true;
      console.error('[createMpSubscription] busca de preapproval órfão falhou',
        searchErr.message);
    }
    if (recovered) {
      console.warn('[createMpSubscription] preapproval órfão adotado',
        recovered.id, 'sub', subId);
      pa = recovered; // cai no pós-processamento de sucesso abaixo
    } else {
      // Falha real (MP não criou preapproval) OU não confirmada. possibleOrphan=
      // true só quando a busca FALHOU: a guarda de duplicidade passa a bloquear
      // retries por 24h e o reconcile pode procurar/cancelar o órfão depois. Uma
      // falha comum (cartão recusado, sem órfão) deixa possibleOrphan=false e
      // permite o aluno tentar de novo.
      await subRef.update({
        status: 'error',
        lastEvent: 'create_failed',
        possibleOrphan: searchFailed,
        updatedAt: FV.serverTimestamp(),
      });
      const text = `${e.data ? JSON.stringify(e.data) : ''} ${e.message || ''}`
        .toLowerCase();
      if (text.includes('card_token') || text.includes('token')) {
        throw new HttpsError('failed-precondition',
          'Não foi possível usar este cartão. Digite os dados do cartão novamente.');
      }
      throw new HttpsError('internal', 'Falha ao criar a assinatura.');
    }
  }

  const status = pa.status === 'authorized' ? 'authorized' : (pa.status || 'pending');
  const update = {
    mpPreapprovalId: String(pa.id),
    status,
    updatedAt: FV.serverTimestamp(),
  };
  let firstBilling = null;
  if (pa.next_payment_date) {
    firstBilling = new Date(pa.next_payment_date);
    update.nextBillingDate = admin.firestore.Timestamp.fromDate(firstBilling);
  }
  // Fim do termo (rede de segurança do scheduledSubscriptionTermGuard caso o
  // webhook do último ciclo se perca). ANCORAR na 1ª data de cobrança retornada
  // pelo MP (next_payment_date), NÃO em createdAt: com billing_day +
  // billing_day_proportional:false, se a assinatura é criada APÓS o billing_day a
  // 1ª cobrança cheia é adiada para o próximo ciclo, então a N-ésima cobrança cai
  // depois de (createdAt + N meses). Ancorar no 1º billing evita que o term guard
  // cancele por data antes do último ciclo. Fallback p/ now se o MP não devolveu
  // a data (mesma tolerância de meses de antes).
  const termEndsAt = computeTermEndsAt(firstBilling || new Date(), months);
  if (termEndsAt) update.termEndsAt = termEndsAt;
  // Espelho NÃO-PCI do cartão (últimos 4 + validade) extraído do retorno do MP.
  const cardInfo = extractMpCardInfo(pa);
  if (cardInfo.cardLast4 != null) update.cardLast4 = cardInfo.cardLast4;
  if (cardInfo.cardExpMonth != null) update.cardExpMonth = cardInfo.cardExpMonth;
  if (cardInfo.cardExpYear != null) update.cardExpYear = cardInfo.cardExpYear;
  await subRef.update(update);

  return {
    subscriptionId: subId,
    status,
    nextPaymentDate: pa.next_payment_date || null,
  };
});

// ---- cancel / pause / update-card -----------------------------------------
async function _loadOwnedSubscription(request, academyId, subscriptionId) {
  const subRef = db.doc(`academies/${academyId}/subscriptions/${subscriptionId}`);
  const snap = await subRef.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Assinatura não encontrada.');
  await assertCanPayFor(request, academyId, snap.data().studentId);
  return { subRef, sub: snap.data() };
}

/** Recusa operações que RE-AUTORIZARIAM uma cobrança no MP (resume / troca de
 * cartão) quando o termo da assinatura já acabou (auditoria — achado LOW):
 * reativar um preapproval cujo termo de N meses já foi quitado faria o MP
 * cobrar ALÉM do contratado. Espelha o `beyondTerm` do mpSubSettleCycle:
 * termo esgotado por contagem (months>0 && chargesPaid>=months) OU pela data
 * (now>=termEndsAt). Estado terminal (cancelled/completed) também é rejeitado.
 * NÃO altera o doc — só lança failed-precondition. Retrocompatível: assinaturas
 * sem `months`/`termEndsAt` (months<=0 = sem fim) nunca são bloqueadas. */
function assertSubscriptionStillBillable(sub) {
  const status = sub && sub.status;
  if (status === 'cancelled' || status === 'completed') {
    throw new HttpsError('failed-precondition', status === 'completed'
      ? 'Esta assinatura já foi concluída.'
      : 'Esta assinatura já está cancelada.');
  }
  const months = Number(sub && sub.months) || 0;
  const chargesPaid = Number(sub && sub.chargesPaid) || 0;
  const byCount = months > 0 && chargesPaid >= months;
  const termEndsMs = sub && sub.termEndsAt &&
    typeof sub.termEndsAt.toMillis === 'function' ? sub.termEndsAt.toMillis() : 0;
  const byDate = termEndsMs > 0 && Date.now() >= termEndsMs;
  if (byCount || byDate) {
    throw new HttpsError('failed-precondition',
      'O período contratado desta assinatura já foi concluído.');
  }
}

exports.cancelMpSubscription = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const { academyId, subscriptionId } = request.data || {};
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
  if (!academyId || !subscriptionId) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }
  const { subRef, sub } = await _loadOwnedSubscription(request, academyId, subscriptionId);
  // Estado TERMINAL: não há o que cancelar — e protege contra um cliente com
  // snapshot stale rebaixando 'completed' para 'cancelled'.
  if (sub.status === 'cancelled' || sub.status === 'completed') {
    throw new HttpsError('failed-precondition', sub.status === 'completed'
      ? 'Esta assinatura já foi concluída e não pode ser cancelada.'
      : 'Esta assinatura já está cancelada.');
  }
  if (sub.mpPreapprovalId) {
    // NÃO é best-effort: se o cancel no MP falhar, o preapproval continua
    // cobrando o cartão — não podemos marcar 'cancelled' local e dizer ao
    // aluno que deu certo. Propaga o erro para o aluno re-tentar.
    try {
      const token = await getMpAccessToken(academyId);
      try {
        await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
          { token, body: { status: 'cancelled' } });
      } catch (e) {
        // PUT pode falhar com o preapproval JÁ cancelado no MP (ex.: retry
        // após a function morrer pós-PUT, ou cancel pelo painel do MP) —
        // confirma via GET; só propaga quando o MP não confirmar o cancel.
        const pa = await mpRequest('GET',
          `/preapproval/${sub.mpPreapprovalId}`, { token });
        if (!pa || pa.status !== 'cancelled') throw e;
      }
    } catch (e) {
      console.error('[cancelMpSubscription] erro', e.message, e.data);
      if (e instanceof HttpsError) throw e;
      throw new HttpsError('internal',
        'Não foi possível cancelar a assinatura agora. Tente novamente.');
    }
  }
  await subRef.update({ status: 'cancelled', updatedAt: FV.serverTimestamp() });
  return { success: true };
});

exports.pauseMpSubscription = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const { academyId, subscriptionId } = request.data || {};
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
  if (!academyId || !subscriptionId) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }
  const { subRef, sub } = await _loadOwnedSubscription(request, academyId, subscriptionId);
  // Estado TERMINAL: não há o que pausar — e protege contra um cliente com
  // snapshot stale sobrescrevendo 'completed'/'cancelled' com 'paused'.
  if (sub.status === 'cancelled' || sub.status === 'completed') {
    throw new HttpsError('failed-precondition', sub.status === 'completed'
      ? 'Esta assinatura já foi concluída e não pode ser pausada.'
      : 'Esta assinatura já foi cancelada e não pode ser pausada.');
  }
  if (sub.mpPreapprovalId) {
    // Marca a intenção ANTES do PUT: o webhook subscription_preapproval que o
    // próprio PUT dispara pode ler o doc antes do update final — sem o
    // marcador, mpSubSyncPreapproval trataria a pausa como falha de cobrança
    // (needsReauth:true), escondendo o "Retomar assinatura" no app.
    await subRef.update({ pausedBy: 'user', updatedAt: FV.serverTimestamp() });
    try {
      const token = await getMpAccessToken(academyId);
      await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
        { token, body: { status: 'paused' } });
    } catch (e) {
      // A pausa NÃO aconteceu no MP: desfaz o marcador (best-effort) e propaga.
      await subRef.update({
        pausedBy: FV.delete(), updatedAt: FV.serverTimestamp(),
      }).catch(() => {});
      throw e;
    }
  }
  await subRef.update({
    status: 'paused',
    // Pausa INTENCIONAL do aluno: não é falha de cobrança. O flag impede que
    // sync/reconcile/dunning tratem como dunning e reativem sem consentimento.
    pausedBy: 'user',
    needsReauth: false,
    nextRetryAt: null,
    failedAttempts: 0,
    updatedAt: FV.serverTimestamp(),
  });
  return { success: true };
});

// ---- resumeMpSubscription — student resumes a user-paused subscription -----
exports.resumeMpSubscription = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const { academyId, subscriptionId } = request.data || {};
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
  if (!academyId || !subscriptionId) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }
  const { subRef, sub } = await _loadOwnedSubscription(request, academyId, subscriptionId);
  if (sub.status !== 'paused') {
    throw new HttpsError('failed-precondition', 'A assinatura não está pausada.');
  }
  // Auditoria: revalida o termo antes de reautorizar no MP — retomar uma
  // assinatura cujo período já acabou faria o MP cobrar além do contratado.
  assertSubscriptionStillBillable(sub);
  if (sub.mpPreapprovalId) {
    // Sem try/catch: se o PUT falhar, propaga SEM tocar no doc — o aluno
    // re-tenta e o estado local segue refletindo o MP ('paused').
    const token = await getMpAccessToken(academyId);
    await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
      { token, body: { status: 'authorized' } });
  }
  await subRef.update({
    status: 'authorized',
    pausedBy: FV.delete(),
    needsReauth: FV.delete(),
    nextRetryAt: FV.delete(),
    failedAttempts: 0,
    lastEvent: 'resumed_by_user',
    updatedAt: FV.serverTimestamp(),
  });
  return { success: true };
});

exports.updateSubscriptionCard = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const { academyId, subscriptionId, cardToken } = request.data || {};
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
  if (!academyId || !subscriptionId || !cardToken) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }
  const { subRef, sub } = await _loadOwnedSubscription(request, academyId, subscriptionId);
  if (!sub.mpPreapprovalId) {
    throw new HttpsError('failed-precondition', 'Assinatura sem preapproval.');
  }
  // Auditoria: revalida o termo antes de reautorizar com o cartão novo — trocar
  // o cartão de uma assinatura cujo período já acabou (status 'authorized' no
  // body) reativaria cobranças além do contratado.
  assertSubscriptionStillBillable(sub);
  const token = await getMpAccessToken(academyId);
  let pa;
  try {
    pa = await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
      { token, body: { card_token_id: cardToken, status: 'authorized' } });
  } catch (e) {
    console.error('[updateSubscriptionCard] erro', e.message, e.data);
    throw new HttpsError('failed-precondition',
      'Não foi possível atualizar o cartão. Tente novamente.');
  }
  const update = {
    needsReauth: false,
    status: 'authorized',
    // Reativou no MP → uma pausa intencional do aluno deixa de existir.
    pausedBy: FV.delete(),
    // Cartão novo → zera o estado de dunning e o aviso de expiração.
    failedAttempts: 0,
    nextRetryAt: null,
    dunningExhaustedNotifiedAt: null,
    expiryNotifiedAt: null,
    updatedAt: FV.serverTimestamp(),
  };
  // Re-espelha os dados NÃO-PCI do novo cartão (se o retorno do MP trouxer).
  const cardInfo = extractMpCardInfo(pa);
  if (cardInfo.cardLast4 != null) update.cardLast4 = cardInfo.cardLast4;
  if (cardInfo.cardExpMonth != null) update.cardExpMonth = cardInfo.cardExpMonth;
  if (cardInfo.cardExpYear != null) update.cardExpYear = cardInfo.cardExpYear;
  await subRef.update(update);
  return { success: true };
});

// ---- Cancel an open MP PIX (H4) -------------------------------------------
// When an admin marks a charge paid offline, the already-sent PIX must be
// killed so it stays unpayable (no double payment). Best-effort: the client
// calls this after the local mark-paid; failure here never blocks mark-paid.
// Requires the academy admin. Only cancels payments still in a cancellable
// state (pending/in_process) — never touches an already-approved one.
/** Cancela no MP um pagamento PIX ainda cancelável (pending/in_process).
 * Núcleo reutilizável do callable cancelMpPix — usado também ao cobrar o
 * cartão de um doc que ainda tem PIX vivo (auditoria, anti double-charge).
 * Best-effort por padrão: nunca lança a menos que throwOnError=true.
 * Retorna { cancelled, status }. */
async function mpCancelPixPayment(academyId, paymentId, { token, throwOnError } = {}) {
  try {
    const tok = token || await getMpAccessToken(academyId);
    const current = await mpRequest('GET', `/v1/payments/${paymentId}`, { token: tok });
    if (current.status !== 'pending' && current.status !== 'in_process') {
      // Já aprovado → NÃO cancela (seria estorno, fora de escopo). Se já estava
      // aprovado, sinaliza para o chamador via flag dedicada.
      return { cancelled: false, status: current.status,
        alreadyApproved: current.status === 'approved' };
    }
    const updated = await mpRequest('POST', `/v1/payments/${paymentId}`, {
      token: tok,
      body: { status: 'cancelled' },
    });
    return { cancelled: updated.status === 'cancelled', status: updated.status };
  } catch (e) {
    console.error('[mpCancelPixPayment] erro', e && e.message);
    if (throwOnError) throw e;
    return { cancelled: false, status: 'error' };
  }
}

/**
 * Auditoria MP (anti double-charge bidirecional): cancela no MP um CARTÃO
 * pendente vivo gravado no doc por createMpCardPayment (cardPendingPaymentId +
 * cardPendingExpiresAt no futuro), para que ele não fique pagável em paralelo a
 * um PIX recém-cunhado. Reusa mpCancelPixPayment (cancela qualquer pagamento
 * pending/in_process — vale para cartão). Limpa os marcadores no doc.
 * Best-effort: nunca lança (não trava a geração do PIX).
 * Retorna o resultado de mpCancelPixPayment ({ cancelled, status, alreadyApproved })
 * ou { cancelled: true, noop: true } quando não havia cartão pendente vivo —
 * para o chamador cartão→cartão poder RECUSAR a nova cobrança se o cartão
 * pendente já foi APROVADO (mas ainda não liquidado) ou não pôde ser cancelado.
 */
async function mpCancelLivePendingCard(academyId, docRef) {
  try {
    const snap = await docRef.get();
    if (!snap.exists) return { cancelled: true, noop: true };
    const d = snap.data();
    if (!d.cardPendingPaymentId) {
      return { cancelled: true, noop: true };
    }
    // Auditoria MP (TTL local não é autoridade): o cardPendingExpiresAt (~1h) é
    // só um palpite. Decidir liberar uma 2ª cobrança apenas pelo relógio local
    // arriscava a dupla quando o 3DS/análise demora mais que 1h e o cartão segue
    // pagável. Sempre consulta o ESTADO REAL no MP (mpCancelPixPayment faz GET e
    // no-op em status terminal); o TTL vira apenas uma dica suave: marcadores
    // muito velhos ainda são checados no MP antes de liberar a nova cobrança.
    const result = await mpCancelPixPayment(academyId, d.cardPendingPaymentId, {});
    // O cartão pendente está NÃO-PAGÁVEL quando foi cancelado agora OU já estava
    // num estado terminal não-aprovado (rejected/cancelled/refunded) — em ambos
    // os casos uma nova cobrança de cartão é segura. APROVADO é o único terminal
    // que ainda pode liquidar: NÃO é seguro e preserva os marcadores.
    const terminalNotPayable = result.cancelled ||
      (!result.alreadyApproved && result.status &&
        result.status !== 'pending' && result.status !== 'in_process' &&
        result.status !== 'error');
    // Auditoria MP (cartão→cartão com cartão JÁ APROVADO porém não liquidado):
    // só limpa os marcadores quando o pagamento ficou terminal não-pagável. Se
    // foi APROVADO (alreadyApproved), PRESERVA os marcadores — o webhook/settle
    // ainda vai liquidá-lo — e devolve o estado para o chamador recusar a 2ª
    // cobrança em vez de duplicar.
    if (terminalNotPayable) {
      await docRef.update({
        cardPendingPaymentId: admin.firestore.FieldValue.delete(),
        cardPendingStatus: admin.firestore.FieldValue.delete(),
        cardPendingExpiresAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => { /* best-effort */ });
    }
    // Normaliza `cancelled` para o chamador cartão→cartão: terminal-não-pagável
    // libera a nova cobrança; só alreadyApproved/erro/pendente-não-cancelável a barram.
    return { ...result, cancelled: result.cancelled || terminalNotPayable };
  } catch (e) {
    console.error('[mpCancelLivePendingCard] erro', e && e.message);
    // Falha indeterminada: não afirma que cancelou. O chamador cartão→cartão
    // trata como "não foi possível garantir o cancelamento" e recusa a cobrança.
    return { cancelled: false, status: 'error' };
  }
}

/**
 * Auditoria MP (cardPending* obsoleto): quando o webhook processa um cartão em
 * estado terminal não-aprovado (rejected/cancelled), apaga os marcadores
 * cardPending* do doc — mas SÓ se o cardPendingPaymentId gravado for exatamente
 * este pagamento (não apaga marcadores de outra tentativa). Best-effort; nunca
 * lança. parsed = { type:'fin'|'order', docId }.
 */
async function mpClearCardPendingIfMatches(academyId, parsed, paymentId) {
  try {
    if (!parsed || (parsed.type !== 'fin' && parsed.type !== 'order')) return;
    const docRef = parsed.type === 'order'
      ? db.doc(`academies/${academyId}/storeOrders/${parsed.docId}`)
      : db.doc(`academies/${academyId}/financials/${parsed.docId}`);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(docRef);
      if (!snap.exists) return;
      if (String(snap.data().cardPendingPaymentId || '') !== paymentId) return;
      tx.update(docRef, {
        cardPendingPaymentId: admin.firestore.FieldValue.delete(),
        cardPendingStatus: admin.firestore.FieldValue.delete(),
        cardPendingExpiresAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  } catch (e) {
    console.error('[mpClearCardPendingIfMatches] erro', e && e.message);
  }
}

exports.cancelMpPix = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const { academyId, paymentId } = request.data || {};
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
  if (!academyId || !paymentId) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }
  await requireAdminOf(request, academyId);

  const token = await getMpAccessToken(academyId);
  try {
    const current = await mpRequest('GET', `/v1/payments/${paymentId}`, { token });
    // Only pending/in_process payments can be cancelled. If it already settled
    // we must NOT cancel (that would be a refund path, out of scope).
    if (current.status !== 'pending' && current.status !== 'in_process') {
      return { cancelled: false, status: current.status };
    }
    const updated = await mpRequest('POST', `/v1/payments/${paymentId}`, {
      token,
      body: { status: 'cancelled' },
    });
    return { cancelled: updated.status === 'cancelled', status: updated.status };
  } catch (e) {
    console.error('[cancelMpPix] erro', e.message);
    throw new HttpsError('internal', 'Falha ao cancelar a cobranca PIX.');
  }
});

/**
 * Confirma o recebimento de uma cobranca paga na chave PIX pessoal da
 * academia. A baixa e exclusivamente server-side e admin-only: o aluno nao
 * consegue quitar a propria cobranca e o cliente nao escolhe valor, aluno,
 * data ou identidade do confirmador.
 *
 * Se existir um PIX/cartao Mercado Pago concorrente, ele precisa estar
 * comprovadamente cancelado ou terminal antes da baixa. Falhas e estados
 * intermediarios bloqueiam a operacao (fail closed) para evitar pagamento
 * duplicado. A transacao final revalida o status para cobrir a corrida com o
 * webhook do Mercado Pago.
 */
exports.confirmManualPixPayment = onCall(
  { secrets: MP_MKT_SECRETS }, async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Login obrigatorio.');
    }
    const academyId = String(request.data?.academyId || '').trim();
    const financialId = String(request.data?.financialId || '').trim();
    if (!academyId || !financialId || academyId.includes('/') ||
        financialId.includes('/')) {
      throw new HttpsError('invalid-argument',
        'academyId e financialId validos sao obrigatorios.');
    }
    await requireAdminOf(request, academyId);

    const finRef = db.doc(`academies/${academyId}/financials/${financialId}`);
    const initialSnap = await finRef.get();
    if (!initialSnap.exists) {
      throw new HttpsError('not-found', 'Cobranca nao encontrada.');
    }
    const initialFin = initialSnap.data();
    const initialDecision = classifyManualPixConfirmation(initialFin);
    if (initialDecision === ManualPixConfirmationDecision.PAID_BY_OTHER_METHOD) {
      throw new HttpsError('failed-precondition',
        'Esta cobranca ja foi paga por outro meio. Atualize a tela.');
    }
    if (initialDecision === ManualPixConfirmationDecision.INVALID_STATUS) {
      throw new HttpsError('failed-precondition',
        'Somente cobrancas pendentes ou vencidas podem receber baixa de PIX manual.');
    }

    // Idempotencia: uma repeticao da mesma baixa nao volta a consultar/cancelar
    // o MP nem altera a data original. O grant de aula particular, se pendente,
    // ainda e tentado depois da transacao abaixo.
    const verifiedCompetingPaymentIds = new Set();
    if (initialDecision !== ManualPixConfirmationDecision.ALREADY_CONFIRMED) {
      const competingPaymentIds = new Set();
      if (initialFin.gatewayPaymentId &&
          (initialFin.paymentGateway === 'mercadopago' || initialFin.pixCode)) {
        competingPaymentIds.add(String(initialFin.gatewayPaymentId));
      }
      if (initialFin.cardPendingPaymentId) {
        competingPaymentIds.add(String(initialFin.cardPendingPaymentId));
      }

      if (competingPaymentIds.size > 0) {
        const token = await getMpAccessToken(academyId);
        for (const paymentId of competingPaymentIds) {
          const cancelResult = await mpCancelPixPayment(
            academyId, paymentId, { token }
          );
          const safety = classifyMercadoPagoCancellation(cancelResult);
          if (!safety.safe && safety.reason === 'approved') {
            throw new HttpsError('failed-precondition',
              'O Mercado Pago ja aprovou este pagamento. Aguarde a baixa automatica e atualize a tela.');
          }
          if (!safety.safe) {
            console.error('[confirmManualPixPayment] cancelamento MP inconclusivo',
              { academyId, financialId, status: safety.reason });
            throw new HttpsError('unavailable',
              'Nao foi possivel cancelar a cobranca concorrente do Mercado Pago. Tente novamente antes de confirmar o PIX manual.');
          }
          verifiedCompetingPaymentIds.add(paymentId);
        }
      }
    }

    let confirmedByName = '';
    try {
      const userSnap = await db.doc(`users/${request.auth.uid}`).get();
      const user = userSnap.exists ? userSnap.data() : {};
      confirmedByName = String(user.displayName || user.name || '').trim();
    } catch (e) {
      console.error('[confirmManualPixPayment] perfil do confirmador indisponivel',
        e && e.message);
    }
    confirmedByName = confirmedByName ||
      String(request.auth.token?.name || request.auth.token?.email || '').trim() ||
      'Administrador';

    const auditRef = db.doc(
      `academies/${academyId}/paymentAuditLogs/manual_pix_${financialId}`
    );
    const result = await db.runTransaction(async (tx) => {
      const liveSnap = await tx.get(finRef);
      if (!liveSnap.exists) {
        throw new HttpsError('not-found', 'Cobranca nao encontrada.');
      }
      const live = liveSnap.data();
      const decision = classifyManualPixConfirmation(live);
      if (decision === ManualPixConfirmationDecision.ALREADY_CONFIRMED) {
        return { alreadyConfirmed: true, finData: live };
      }
      if (decision === ManualPixConfirmationDecision.PAID_BY_OTHER_METHOD) {
        throw new HttpsError('failed-precondition',
          'O pagamento foi confirmado por outro meio enquanto esta tela estava aberta. Atualize a tela.');
      }
      if (decision !== ManualPixConfirmationDecision.CONFIRM) {
        throw new HttpsError('failed-precondition',
          'A cobranca nao esta mais disponivel para baixa manual. Atualize a tela.');
      }

      // Uma nova geracao MP pode ter ocorrido entre a leitura inicial e esta
      // transacao. Nunca apague/quite um pagamento que nao foi verificado e
      // cancelado acima. Como o financial e lido dentro da tx, qualquer mint
      // concorrente tambem faz a transacao repetir e passar por este guard.
      const liveCompetingPaymentIds = [];
      if (live.gatewayPaymentId &&
          (live.paymentGateway === 'mercadopago' || live.pixCode)) {
        liveCompetingPaymentIds.push(String(live.gatewayPaymentId));
      }
      if (live.cardPendingPaymentId) {
        liveCompetingPaymentIds.push(String(live.cardPendingPaymentId));
      }
      if (liveCompetingPaymentIds.some(
        (paymentId) => !verifiedCompetingPaymentIds.has(paymentId)
      )) {
        throw new HttpsError('aborted',
          'Uma nova cobranca do Mercado Pago foi criada durante a confirmacao. Tente novamente para cancela-la com seguranca.');
      }

      const confirmedAt = admin.firestore.Timestamp.now();
      const manualPaymentAudit = {
        type: 'personal_pix',
        source: 'admin_app',
        confirmedByName,
        confirmedAt,
      };
      tx.update(finRef, {
        status: 'paid',
        method: 'pix',
        paymentGateway: 'manual',
        paymentDate: confirmedAt,
        manualPaymentAudit,
        gatewayPaymentId: admin.firestore.FieldValue.delete(),
        pixCode: admin.firestore.FieldValue.delete(),
        pixQrCode: admin.firestore.FieldValue.delete(),
        pixTicketUrl: admin.firestore.FieldValue.delete(),
        pixExpiresAt: admin.firestore.FieldValue.delete(),
        pixAmount: admin.firestore.FieldValue.delete(),
        pixMintAt: admin.firestore.FieldValue.delete(),
        pixMintBy: admin.firestore.FieldValue.delete(),
        cardPendingPaymentId: admin.firestore.FieldValue.delete(),
        cardPendingStatus: admin.firestore.FieldValue.delete(),
        cardPendingExpiresAt: admin.firestore.FieldValue.delete(),
        updatedAt: confirmedAt,
      });
      tx.set(auditRef, {
        event: 'manual_pix_confirmed',
        academyId,
        financialId,
        studentId: live.studentId || '',
        studentName: live.studentName || '',
        amount: Number(live.amount) || 0,
        method: 'pix',
        paymentGateway: 'manual',
        confirmedBy: request.auth.uid,
        confirmedByName,
        confirmedAt,
      });
      return { alreadyConfirmed: false, finData: live };
    });

    let attendanceGranted = result.finData?.attendanceGranted === true;
    if (result.finData?.type === 'private_lesson' && !attendanceGranted) {
      try {
        await grantPrivateLessonAttendance(
          academyId, financialId, result.finData, {
            verifiedBy: request.auth.uid,
            verifiedByName: confirmedByName,
          }
        );
        attendanceGranted = true;
      } catch (e) {
        // A baixa do dinheiro ja foi confirmada. O callable e idempotente: uma
        // nova tentativa completa apenas a presenca, sem duplicar pagamento.
        console.error('[confirmManualPixPayment] grant aula particular falhou',
          financialId, e && e.message);
      }
    }

    return {
      success: true,
      alreadyConfirmed: result.alreadyConfirmed,
      attendanceGranted,
    };
  }
);

// ---------------------------------------------------------------------------
// Public MyDojo Pay API. Resolving a stable link is read-only. Mercado Pago is
// contacted only by startPublicCheckout after an explicit user action.
// ---------------------------------------------------------------------------
function publicPayAllowedOrigins() {
  const configured = String(process.env.PUBLIC_PAY_ALLOWED_ORIGINS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  const defaults = [new URL(publicPayBaseUrl()).origin];
  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    defaults.push('http://localhost:8888', 'http://localhost:5000');
  }
  return new Set([...defaults, ...configured]);
}

function preparePublicPayResponse(req, res) {
  const origin = String(req.get('origin') || '');
  if (origin && publicPayAllowedOrigins().has(origin)) {
    res.set('Access-Control-Allow-Origin', origin);
    res.set('Vary', 'Origin');
  }
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  res.set('Cache-Control', 'no-store, max-age=0');
  res.set('Pragma', 'no-cache');
  res.set('Referrer-Policy', 'no-referrer');
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('X-Frame-Options', 'DENY');
  return !origin || publicPayAllowedOrigins().has(origin);
}

function publicPayRequestBody(req) {
  if (!String(req.get('content-type') || '').toLowerCase()
    .startsWith('application/json')) {
    throw new HttpsError('invalid-argument', 'Conteudo invalido.');
  }
  const serializedLength = Buffer.byteLength(JSON.stringify(req.body || {}));
  if (serializedLength > 4096 || !req.body || typeof req.body !== 'object') {
    throw new HttpsError('invalid-argument', 'Conteudo invalido.');
  }
  return req.body;
}

async function enforcePublicPayRateLimit(req, linkHash, action, maximum) {
  const forwarded = String(req.get('x-forwarded-for') || '').split(',')[0].trim();
  const ip = forwarded || String(req.ip || 'unknown');
  const ipHash = crypto.createHmac('sha256', publicPaySecret())
    .update(ip).digest('hex').substring(0, 24);
  const bucket = Math.floor(Date.now() / 60000);
  const counterId = crypto.createHash('sha256')
    .update(`${linkHash}:${action}:${bucket}:${ipHash}`)
    .digest('hex');
  const ref = db.doc(`publicPaymentRateLimits/${counterId}`);
  const allowed = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const count = snapshot.exists ? Number(snapshot.data()?.count || 0) : 0;
    if (count >= maximum) return false;
    tx.set(ref, {
      linkHash,
      action,
      count: count + 1,
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + 10 * 60 * 1000
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
  });
  if (!allowed) {
    throw new HttpsError('resource-exhausted', 'Muitas tentativas. Aguarde.');
  }
}

async function resolvePublicPaymentContext(rawToken) {
  if (!isValidPublicToken(rawToken)) return null;
  const linkHash = hashPublicToken(rawToken);
  const linkSnapshot = await db.doc(`publicPaymentLinks/${linkHash}`).get();
  if (!linkSnapshot.exists) return null;
  const link = linkSnapshot.data() || {};
  if (link.status !== 'active' || link.targetType !== 'financial') return null;
  const academyId = String(link.academyId || '');
  const financialId = String(link.targetId || '');
  if (!academyId || academyId.includes('/') ||
      !financialId || financialId.includes('/')) return null;
  const [financialSnapshot, academySnapshot] = await Promise.all([
    db.doc(`academies/${academyId}/financials/${financialId}`).get(),
    db.doc(`academies/${academyId}`).get(),
  ]);
  if (!financialSnapshot.exists || !academySnapshot.exists) return null;
  const financial = financialSnapshot.data() || {};
  if (financial.academyId && financial.academyId !== academyId) return null;
  return {
    rawToken,
    linkHash,
    linkRef: linkSnapshot.ref,
    link,
    academyId,
    financialId,
    financialRef: financialSnapshot.ref,
    financial,
    academy: academySnapshot.data() || {},
  };
}

function publicStudentDisplayName(value) {
  const first = String(value || 'Aluno').trim().split(/\s+/)[0] || 'Aluno';
  return first.substring(0, 60);
}

function publicDueDate(value) {
  const date = value && typeof value.toDate === 'function'
    ? value.toDate() : null;
  if (!date) return null;
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-` +
    String(date.getDate()).padStart(2, '0');
}

function safePublicLogoUrl(value) {
  try {
    const url = new URL(String(value || ''));
    return url.protocol === 'https:' ? url.toString() : null;
  } catch (_) {
    return null;
  }
}

function publicChargePayload(context) {
  const { financial, academy } = context;
  const amount = Number(financial.amount) || 0;
  const status = amount > 0 && academy.publicPaymentLinksEnabled === true
    ? publicChargeStatus(financial) : 'unavailable';
  return {
    status,
    academy: {
      displayName: sanitizeString(
        academy.name || academy.academyName || 'Academia'
      ).substring(0, 120),
      logoUrl: safePublicLogoUrl(academy.logoUrl || academy.logo),
    },
    charge: {
      description: sanitizeString(financial.description || 'Mensalidade')
        .substring(0, 160),
      amount: Math.round(amount * 100) / 100,
      currency: 'BRL',
      dueDate: publicDueDate(financial.dueDate),
      studentDisplayName: publicStudentDisplayName(financial.studentName),
    },
    availableMethods: publicAvailableMethods(financial, academy),
    version: Number(financial.financialVersion) || 1,
  };
}

function publicPayHttpError(res, error) {
  const code = error instanceof HttpsError ? error.code : 'internal';
  const status = {
    'invalid-argument': 400,
    'failed-precondition': 412,
    'resource-exhausted': 429,
    'aborted': 409,
  }[code] || 500;
  if (status >= 500) {
    console.error('[public-pay] request failed', error && error.message);
  }
  return res.status(status).json({
    status: 'error',
    code,
    message: status >= 500
      ? 'Nao foi possivel processar o pagamento.'
      : String(error.message || 'Nao foi possivel processar o pagamento.'),
  });
}

exports.resolvePublicCharge = onRequest(
  { cors: false, invoker: 'public', secrets: ['PUBLIC_PAY_TOKEN_SECRET'] },
  async (req, res) => {
    const originAllowed = preparePublicPayResponse(req, res);
    if (req.method === 'OPTIONS') return res.status(originAllowed ? 204 : 403).send('');
    if (req.method !== 'POST' || !originAllowed) {
      return res.status(405).json({ status: 'unavailable' });
    }
    try {
      const body = publicPayRequestBody(req);
      const rawToken = String(body.token || '');
      if (!isValidPublicToken(rawToken)) {
        return res.status(200).json({ status: 'unavailable' });
      }
      const linkHash = hashPublicToken(rawToken);
      await enforcePublicPayRateLimit(req, linkHash, 'resolve', 60);
      const context = await resolvePublicPaymentContext(rawToken);
      if (!context) return res.status(200).json({ status: 'unavailable' });
      const lastResolvedMs = context.link.lastResolvedAt &&
        typeof context.link.lastResolvedAt.toMillis === 'function'
        ? context.link.lastResolvedAt.toMillis() : 0;
      if (Date.now() - lastResolvedMs > 60 * 60 * 1000) {
        context.linkRef.update({
          lastResolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        }).catch(() => {});
      }
      const payload = publicChargePayload(context);
      return res.status(200).json(
        payload.status === 'unavailable' ? { status: 'unavailable' } : payload
      );
    } catch (error) {
      return publicPayHttpError(res, error);
    }
  }
);

function publicAttemptResponse(attemptId, attempt) {
  const common = {
    status: 'ready',
    attemptId,
    checkoutMode: attempt.mode,
    expiresAt: attempt.expiresAt && typeof attempt.expiresAt.toDate === 'function'
      ? attempt.expiresAt.toDate().toISOString()
      : new Date(Number(attempt.expiresAtMs || 0)).toISOString(),
  };
  if (attempt.mode === 'pix') {
    return {
      ...common,
      pixCode: attempt.pixCode,
      qrCodeBase64: attempt.pixQrCode || '',
      ticketUrl: attempt.pixTicketUrl || '',
    };
  }
  return { ...common, redirectUrl: attempt.providerRedirectUrl };
}

async function createPublicCheckoutPreference(context, attemptId, expiresAt) {
  const token = await getMpAccessToken(context.academyId);
  const backUrl = `${publicPayBaseUrl()}/p/${context.rawToken}`;
  const now = new Date();
  const preference = await mpRequest('POST', '/checkout/preferences', {
    token,
    idempotencyKey: attemptId,
    body: {
      items: [{
        id: 'financial',
        title: sanitizeString(context.financial.description || 'Mensalidade')
          .substring(0, 120),
        currency_id: 'BRL',
        quantity: 1,
        unit_price: Number(Number(context.financial.amount).toFixed(2)),
      }],
      external_reference: `${context.academyId}:fin:${context.financialId}`,
      notification_url: `${mpMktWebhookUrl()}?acad=` +
        encodeURIComponent(context.academyId),
      back_urls: { success: backUrl, pending: backUrl, failure: backUrl },
      auto_return: 'approved',
      expires: true,
      expiration_date_from: now.toISOString(),
      expiration_date_to: expiresAt.toISOString(),
      date_of_expiration: expiresAt.toISOString(),
      payment_methods: {
        excluded_payment_types: [{ id: 'ticket' }, { id: 'atm' }],
      },
      metadata: { attempt_id: attemptId },
    },
  });
  const redirectUrl = String(preference.init_point || preference.sandbox_init_point || '');
  let redirectHost = '';
  try { redirectHost = new URL(redirectUrl).hostname; } catch (_) { /* invalid */ }
  if (!redirectUrl ||
      (!redirectHost.endsWith('.mercadopago.com.br') &&
       redirectHost !== 'mercadopago.com.br')) {
    throw new Error('Mercado Pago returned an invalid checkout URL');
  }
  return {
    providerPreferenceId: String(preference.id || ''),
    providerRedirectUrl: redirectUrl,
  };
}

async function publicPixPayer(context) {
  const snapshot = await db.doc(
    `academies/${context.academyId}/students/${context.financial.studentId}`
  ).get();
  const student = snapshot.exists ? (snapshot.data() || {}) : {};
  const kids = student.category === 'kids';
  const cpf = String(kids ? (student.guardian?.cpf || student.cpf) : student.cpf)
    .replace(/\D/g, '');
  const email = String(kids ? (student.guardian?.email || student.email) : student.email)
    .trim();
  if (!validateCPF(cpf) || !isValidBillingEmail(email)) {
    throw new HttpsError(
      'failed-precondition',
      'CPF e e-mail validos sao necessarios para gerar o PIX.'
    );
  }
  return {
    cpf,
    email,
    name: student.fullName || context.financial.studentName || 'Aluno',
  };
}

async function expirePublicPreferenceBestEffort(academyId, preferenceId) {
  if (!preferenceId) return;
  try {
    const token = await getMpAccessToken(academyId);
    const expiry = new Date(Date.now() + 60 * 1000).toISOString();
    await mpRequest('PUT', `/checkout/preferences/${preferenceId}`, {
      token,
      body: {
        expires: true,
        expiration_date_to: expiry,
        date_of_expiration: expiry,
      },
    });
  } catch (error) {
    console.error('[public-pay] preference expiration failed', preferenceId);
  }
}

exports.startPublicCheckout = onRequest(
  { cors: false, invoker: 'public', secrets: PUBLIC_PAY_SECRETS },
  async (req, res) => {
    const originAllowed = preparePublicPayResponse(req, res);
    if (req.method === 'OPTIONS') return res.status(originAllowed ? 204 : 403).send('');
    if (req.method !== 'POST' || !originAllowed) {
      return res.status(405).json({ status: 'unavailable' });
    }
    let attemptRef;
    let attemptId = '';
    let context;
    let ownsAttempt = false;
    try {
      const body = publicPayRequestBody(req);
      const rawToken = String(body.token || '');
      const requestId = String(body.requestId || '');
      const expectedVersion = Number(body.expectedVersion);
      if (!isValidPublicToken(rawToken) || !isValidRequestId(requestId) ||
          !Number.isInteger(expectedVersion) || expectedVersion < 1) {
        throw new HttpsError('invalid-argument', 'Solicitacao invalida.');
      }
      context = await resolvePublicPaymentContext(rawToken);
      if (!context) {
        return res.status(404).json({ status: 'unavailable' });
      }
      await enforcePublicPayRateLimit(req, context.linkHash, 'start', 10);
      const status = publicChargeStatus(context.financial);
      const methods = publicAvailableMethods(context.financial, context.academy);
      if (status !== 'open' || methods.length === 0) {
        throw new HttpsError(
          'failed-precondition',
          status === 'open'
            ? 'Este metodo ainda nao esta disponivel no pagamento publico.'
            : 'Esta cobranca nao esta disponivel para pagamento.'
        );
      }
      const amount = Number(context.financial.amount);
      if (!Number.isFinite(amount) || amount <= 0 || amount > 1000000) {
        throw new HttpsError('failed-precondition', 'Valor da cobranca invalido.');
      }
      const mode = context.financial.paymentMethodPolicy === 'pix_only'
        ? 'pix' : 'checkout_pro';
      const requestIdHash = crypto.createHash('sha256').update(requestId).digest('hex');
      attemptId = `attempt_${crypto.createHash('sha256')
        .update(`${context.linkHash}:${requestId}`).digest('hex').substring(0, 40)}`;
      attemptRef = db.doc(
        `academies/${context.academyId}/paymentAttempts/${attemptId}`
      );
      const now = admin.firestore.Timestamp.now();
      const expiresAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + CHECKOUT_TTL_MS
      );
      const expected = {
        publicLinkHash: context.linkHash,
        financialVersion: expectedVersion,
        amount,
        mode,
        nowMs: Date.now(),
      };
      const lock = await db.runTransaction(async (tx) => {
        const liveSnapshot = await tx.get(context.financialRef);
        const requestSnapshot = await tx.get(attemptRef);
        if (!liveSnapshot.exists) {
          throw new HttpsError('failed-precondition', 'Cobranca indisponivel.');
        }
        const live = liveSnapshot.data() || {};
        const liveVersion = Number(live.financialVersion) || 1;
        if (!['pending', 'overdue'].includes(live.status) ||
            liveVersion !== expectedVersion ||
            Math.abs(Number(live.amount) - amount) > 0.01) {
          throw new HttpsError(
            'aborted',
            'A cobranca mudou. Atualize os dados antes de pagar.'
          );
        }
        const requested = requestSnapshot.exists ? requestSnapshot.data() : null;
        if (isReusableAttempt(requested, expected)) {
          return { reuse: requested, attemptId };
        }
        const creatingAtMs = requested?.updatedAt &&
          typeof requested.updatedAt.toMillis === 'function'
          ? requested.updatedAt.toMillis() : 0;
        if (requested?.status === 'creating' &&
            Date.now() - creatingAtMs < 60 * 1000) {
          return { processing: true };
        }

        const lastAttemptId = String(live.lastCheckoutAttemptId || '');
        if (lastAttemptId && lastAttemptId !== attemptId) {
          const lastRef = db.doc(
            `academies/${context.academyId}/paymentAttempts/${lastAttemptId}`
          );
          const lastSnapshot = await tx.get(lastRef);
          const last = lastSnapshot.exists ? lastSnapshot.data() : null;
          if (isReusableAttempt(last, expected)) {
            return { reuse: last, attemptId: lastAttemptId };
          }
          const lastCreatingAtMs = last?.updatedAt &&
            typeof last.updatedAt.toMillis === 'function'
            ? last.updatedAt.toMillis() : 0;
          if (last?.status === 'creating' &&
              Date.now() - lastCreatingAtMs < 60 * 1000) {
            return { processing: true };
          }
        }

        tx.set(attemptRef, {
          targetType: 'financial',
          targetId: context.financialId,
          publicLinkHash: context.linkHash,
          financialVersion: expectedVersion,
          provider: 'mercadopago',
          mode,
          requestIdHash,
          amount: Math.round(amount * 100) / 100,
          currency: 'BRL',
          status: 'creating',
          createdAt: requestSnapshot.exists
            ? (requested.createdAt || now) : now,
          expiresAt,
          updatedAt: now,
          failureCode: admin.firestore.FieldValue.delete(),
        }, { merge: true });
        tx.update(context.financialRef, {
          lastCheckoutAttemptId: attemptId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { create: true, expiresAt };
      });

      if (lock.reuse) {
        return res.status(200).json(
          publicAttemptResponse(lock.attemptId, lock.reuse)
        );
      }
      if (lock.processing) {
        return res.status(409).json({ status: 'processing' });
      }
      ownsAttempt = true;

      let providerData;
      if (mode === 'pix') {
        const payer = await publicPixPayer(context);
        const pix = await createMpPix({
          academyId: context.academyId,
          transactionAmount: amount,
          description: sanitizeString(context.financial.description) || 'Mensalidade',
          externalReference: `${context.academyId}:fin:${context.financialId}`,
          payer,
        });
        providerData = {
          providerPaymentId: pix.paymentId,
          pixCode: pix.pixCode,
          pixQrCode: pix.qrCodeBase64 || '',
          pixTicketUrl: pix.ticketUrl || '',
        };
      } else {
        providerData = await createPublicCheckoutPreference(
          context,
          attemptId,
          lock.expiresAt.toDate()
        );
      }

      const finalized = await db.runTransaction(async (tx) => {
        const liveSnapshot = await tx.get(context.financialRef);
        if (!liveSnapshot.exists) return false;
        const live = liveSnapshot.data() || {};
        if (!['pending', 'overdue'].includes(live.status) ||
            (Number(live.financialVersion) || 1) !== expectedVersion ||
            String(live.lastCheckoutAttemptId || '') !== attemptId) {
          tx.update(attemptRef, {
            status: 'cancelled',
            failureCode: 'financial_changed',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return false;
        }
        tx.update(attemptRef, {
          ...providerData,
          status: 'ready',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        if (mode === 'pix') {
          tx.update(context.financialRef, {
            gatewayPaymentId: providerData.providerPaymentId,
            paymentGateway: 'mercadopago',
            pixCode: providerData.pixCode,
            pixQrCode: providerData.pixQrCode,
            pixTicketUrl: providerData.pixTicketUrl,
            pixExpiresAt: lock.expiresAt,
            pixAmount: Math.round(amount * 100) / 100,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        return true;
      });
      if (!finalized) {
        if (mode === 'pix') {
          await mpCancelPixPayment(
            context.academyId,
            providerData.providerPaymentId,
            {}
          ).catch(() => {});
        } else {
          await expirePublicPreferenceBestEffort(
            context.academyId,
            providerData.providerPreferenceId
          );
        }
        ownsAttempt = false;
        throw new HttpsError(
          'aborted',
          'A cobranca mudou. Atualize os dados antes de pagar.'
        );
      }
      ownsAttempt = false;
      const readySnapshot = await attemptRef.get();
      return res.status(200).json(
        publicAttemptResponse(attemptId, readySnapshot.data())
      );
    } catch (error) {
      if (attemptRef && ownsAttempt) {
        await attemptRef.set({
          status: 'failed',
          failureCode: error instanceof HttpsError ? error.code : 'provider_error',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }).catch(() => {});
      }
      return publicPayHttpError(res, error);
    }
  }
);

async function invalidatePublicCheckoutAttemptBestEffort(
  academyId,
  attemptId,
  reason
) {
  if (!attemptId) return;
  try {
    const ref = db.doc(`academies/${academyId}/paymentAttempts/${attemptId}`);
    const snapshot = await ref.get();
    if (!snapshot.exists) return;
    const attempt = snapshot.data() || {};
    if (!['creating', 'ready', 'pending'].includes(attempt.status)) return;
    await ref.set({
      status: 'cancelled',
      failureCode: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    if (attempt.mode === 'checkout_pro' && attempt.providerPreferenceId) {
      await expirePublicPreferenceBestEffort(
        academyId,
        attempt.providerPreferenceId
      );
    }
  } catch (error) {
    console.error('[public-pay] attempt invalidation failed', attemptId);
  }
}

// ---------------------------------------------------------------------------
// Server-authoritative financial actions. These callables are additive so old
// app versions keep working during rollout; Firestore Rules can become fully
// read-only only after the minimum compatible app version is enforced.
// ---------------------------------------------------------------------------
function assertSafeDocumentId(value, fieldName) {
  const clean = String(value || '').trim();
  if (!clean || clean.includes('/') || clean.length > 200) {
    throw new HttpsError('invalid-argument', `${fieldName} invalido.`);
  }
  return clean;
}

function parseFinancialDate(value, fieldName) {
  const parsed = new Date(String(value || ''));
  if (!Number.isFinite(parsed.getTime())) {
    throw new HttpsError('invalid-argument', `${fieldName} invalida.`);
  }
  return parsed;
}

function openStatusForDueDate(dueDate, now = new Date()) {
  return isOverdueBR(dueDate, now) ? 'overdue' : 'pending';
}

function financialGatewayCleanup() {
  const del = admin.firestore.FieldValue.delete();
  return {
    gatewayPaymentId: del,
    pixCode: del,
    pixQrCode: del,
    pixTicketUrl: del,
    pixExpiresAt: del,
    pixAmount: del,
    pixMintAt: del,
    pixMintBy: del,
    cardPendingPaymentId: del,
    cardPendingStatus: del,
    cardPendingExpiresAt: del,
  };
}

function competingProviderPaymentIds(financial) {
  const ids = new Set();
  if (financial.gatewayPaymentId &&
      (financial.paymentGateway === 'mercadopago' || financial.pixCode)) {
    ids.add(String(financial.gatewayPaymentId));
  }
  if (financial.cardPendingPaymentId) {
    ids.add(String(financial.cardPendingPaymentId));
  }
  return ids;
}

async function cancelCompetingPaymentsFailClosed(academyId, financial) {
  const ids = competingProviderPaymentIds(financial);
  const verified = new Set();
  if (ids.size === 0) return verified;
  const token = await getMpAccessToken(academyId);
  for (const paymentId of ids) {
    const cancelResult = await mpCancelPixPayment(
      academyId, paymentId, { token }
    );
    const safety = classifyMercadoPagoCancellation(cancelResult);
    if (!safety.safe && safety.reason === 'approved') {
      throw new HttpsError(
        'failed-precondition',
        'O Mercado Pago ja aprovou este pagamento. Aguarde a baixa automatica.'
      );
    }
    if (!safety.safe) {
      throw new HttpsError(
        'unavailable',
        'Nao foi possivel invalidar a tentativa concorrente. Tente novamente.'
      );
    }
    verified.add(paymentId);
  }
  return verified;
}

async function financialActorName(request) {
  try {
    const snapshot = await db.doc(`users/${request.auth.uid}`).get();
    const user = snapshot.exists ? snapshot.data() : {};
    const name = String(user.displayName || user.name || '').trim();
    if (name) return name;
  } catch (_) {
    // Fall back to the auth token below.
  }
  return String(
    request.auth.token?.name || request.auth.token?.email || 'Administrador'
  ).trim();
}

exports.createFinancialCharge = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Login obrigatorio.');
  const academyId = assertSafeDocumentId(request.data?.academyId, 'academyId');
  const studentId = assertSafeDocumentId(request.data?.studentId, 'studentId');
  if (!(await staffCanWithPermission(
    request.auth.uid, academyId, 'financial:create'
  ))) {
    throw new HttpsError(
      'permission-denied',
      'Sem permissao para criar cobrancas nesta academia.'
    );
  }
  const amount = Number(request.data?.amount);
  if (!Number.isFinite(amount) || amount <= 0 || amount > 1000000) {
    throw new HttpsError('invalid-argument', 'Valor da cobranca invalido.');
  }
  const dueDate = parseFinancialDate(request.data?.dueDate, 'dueDate');
  const type = String(request.data?.type || 'monthly_tuition');
  if (!['monthly_tuition', 'avulsa', 'private_lesson'].includes(type)) {
    throw new HttpsError('invalid-argument', 'Tipo de cobranca invalido.');
  }
  const policy = String(request.data?.paymentMethodPolicy || 'both');
  if (!['both', 'pix_only', 'card_only'].includes(policy)) {
    throw new HttpsError('invalid-argument', 'Politica de pagamento invalida.');
  }
  const studentSnapshot = await db.doc(
    `academies/${academyId}/students/${studentId}`
  ).get();
  if (!studentSnapshot.exists) {
    throw new HttpsError('not-found', 'Aluno nao encontrado nesta academia.');
  }
  const student = studentSnapshot.data() || {};
  const studentName = String(
    student.fullName || student.name || 'Aluno'
  ).trim().substring(0, 160);
  let authoritativeAmount = Math.round(amount * 100) / 100;
  let authoritativePolicy = policy;
  let planId = sanitizeString(request.data?.planId) || null;
  let referenceMonth = sanitizeString(request.data?.referenceMonth) || null;

  if (type === 'monthly_tuition') {
    if (!referenceMonth || !/^\d{4}-\d{2}$/.test(referenceMonth)) {
      throw new HttpsError(
        'invalid-argument', 'Mes de referencia da mensalidade invalido.'
      );
    }
    const [referenceYear, referenceMonthNumber] = referenceMonth
      .split('-').map(Number);
    if (referenceMonthNumber < 1 || referenceMonthNumber > 12) {
      throw new HttpsError(
        'invalid-argument', 'Mes de referencia da mensalidade invalido.'
      );
    }
    const dueParts = datePartsInBillingTimeZone(dueDate);
    if (dueParts.year !== referenceYear ||
        dueParts.month !== referenceMonthNumber) {
      throw new HttpsError(
        'invalid-argument',
        'O vencimento precisa estar no mesmo mes da mensalidade.'
      );
    }

    const existingSnapshot = await db
      .collection(`academies/${academyId}/financials`)
      .where('referenceMonth', '==', referenceMonth)
      .get();
    const existingTuition = existingSnapshot.docs.some((doc) => {
      const financial = doc.data() || {};
      return financial.studentId === studentId &&
        (financial.type || 'monthly_tuition') === 'monthly_tuition';
    });
    if (existingTuition) {
      throw new HttpsError(
        'already-exists',
        'Este aluno ja possui uma mensalidade neste mes, inclusive cancelada.'
      );
    }

    const activePlansSnapshot = await db
      .collection(`academies/${academyId}/plans`)
      .where('isActive', '==', true)
      .get();
    const memberships = activePlansSnapshot.docs.filter((doc) => {
      const plan = doc.data() || {};
      const studentIds = Array.isArray(plan.studentIds) ? plan.studentIds : [];
      const customValues = plan.customValues || {};
      const planValue = customValues[studentId] != null
        ? customValues[studentId]
        : (plan.periodValue != null ? plan.periodValue : plan.monthlyValue);
      return studentIds.includes(studentId) && Number(planValue) > 0;
    });
    if (memberships.length > 1) {
      throw new HttpsError(
        'failed-precondition',
        'Aluno vinculado a mais de um plano. Revise os planos antes de cobrar.'
      );
    }
    if (planId) {
      planId = assertSafeDocumentId(planId, 'planId');
      const planDocument = activePlansSnapshot.docs.find(
        (doc) => doc.id === planId
      );
      if (!planDocument) {
        throw new HttpsError('not-found', 'Plano ativo nao encontrado.');
      }
      const plan = planDocument.data() || {};
      if (!(Array.isArray(plan.studentIds) && plan.studentIds.includes(studentId))) {
        throw new HttpsError(
          'failed-precondition', 'Aluno nao esta vinculado ao plano informado.'
        );
      }
      const periodValue = plan.billingPeriod || 'monthly';
      const planPolicy = plan.paymentMethodPolicy || 'both';
      if (periodValue === 'monthly' && planPolicy === 'cardOnly') {
        throw new HttpsError(
          'failed-precondition',
          'Plano recorrente no cartao nao pode receber mensalidade avulsa.'
        );
      }
      const customValues = plan.customValues || {};
      const expectedAmount = Number(
        customValues[studentId] != null
          ? customValues[studentId]
          : (plan.periodValue != null ? plan.periodValue : plan.monthlyValue)
      );
      if (!Number.isFinite(expectedAmount) || expectedAmount <= 0) {
        throw new HttpsError('failed-precondition', 'Valor do plano invalido.');
      }
      if (Math.abs(expectedAmount - amount) > 0.005) {
        throw new HttpsError(
          'failed-precondition',
          `O valor correto deste aluno no plano e R$ ${expectedAmount.toFixed(2)}.`
        );
      }
      const customDueDays = plan.customDueDays || {};
      const effectiveDueDay = student.tuitionDay != null
        ? student.tuitionDay
        : (customDueDays[studentId] != null
          ? customDueDays[studentId]
          : (plan.defaultDueDay != null ? plan.defaultDueDay : 10));
      const studentAddedAt = plan.studentAddedAt || {};
      if (!isMembershipEligibleForMonth({
        planCreatedAt: plan.createdAt,
        studentAddedAt: studentAddedAt[studentId],
        referenceYear,
        referenceMonth: referenceMonthNumber,
        dueDay: effectiveDueDay,
      })) {
        throw new HttpsError(
          'failed-precondition',
          'Plano ou vinculo criado apos o vencimento; cobre a partir do proximo mes.'
        );
      }
      authoritativeAmount = Math.round(expectedAmount * 100) / 100;
      authoritativePolicy = planPolicy;
    } else if (memberships.length > 0) {
      throw new HttpsError(
        'failed-precondition', 'Selecione o plano desta mensalidade.'
      );
    }
  }
  // Financeiro is month-scoped for every charge type. Keep avulsas and
  // private lessons in the same canonical bucket as their due date even when
  // an older client omits (or sends a stale) referenceMonth.
  if (type !== 'monthly_tuition') {
    const dueParts = datePartsInBillingTimeZone(dueDate);
    referenceMonth = `${dueParts.year}-${String(dueParts.month).padStart(2, '0')}`;
    planId = null;
  }
  const now = admin.firestore.Timestamp.now();
  const financialRef = db.collection(
    `academies/${academyId}/financials`
  ).doc();
  const payload = {
    academyId,
    studentId,
    studentName,
    amount: authoritativeAmount,
    type,
    dueDate: admin.firestore.Timestamp.fromDate(dueDate),
    status: openStatusForDueDate(dueDate),
    description: sanitizeString(request.data?.description) || 'Mensalidade',
    referenceMonth,
    planId,
    paymentMethodPolicy: authoritativePolicy,
    financialVersion: 1,
    publicPaymentEnabled: true,
    createdAt: now,
    updatedAt: now,
    createdBy: request.auth.uid,
  };
  if (type === 'private_lesson') {
    const actorName = await financialActorName(request);
    const lessonDate = request.data?.lessonDate
      ? parseFinancialDate(request.data.lessonDate, 'lessonDate') : dueDate;
    const weight = Number(request.data?.lessonWeight ?? 1);
    payload.lessonDate = admin.firestore.Timestamp.fromDate(lessonDate);
    payload.lessonWeight = Number.isFinite(weight) && weight > 0 ? weight : 1;
    payload.lessonSport = sanitizeString(request.data?.lessonSport) || 'bjj';
    payload.instructorId = request.auth.uid;
    payload.instructorName = actorName;
    payload.attendanceGranted = false;
  }
  if (type === 'monthly_tuition') {
    const wasCreated = await createTuitionWithGuard({
      academyId,
      referenceMonth,
      studentId,
      financialRef,
      payload,
    });
    if (!wasCreated) {
      throw new HttpsError(
        'already-exists', 'Este aluno ja possui uma mensalidade neste mes.'
      );
    }
  } else {
    await financialRef.create(payload);
  }
  return { success: true, financialId: financialRef.id };
});

exports.updateFinancialTerms = onCall(
  { secrets: MP_MKT_SECRETS }, async (request) => {
    const academyId = assertSafeDocumentId(request.data?.academyId, 'academyId');
    const financialId = assertSafeDocumentId(
      request.data?.financialId, 'financialId'
    );
    await requireAdminOf(request, academyId);
    const amount = Number(request.data?.amount);
    if (!Number.isFinite(amount) || amount <= 0 || amount > 1000000) {
      throw new HttpsError('invalid-argument', 'Valor da cobranca invalido.');
    }
    const dueDate = parseFinancialDate(request.data?.dueDate, 'dueDate');
    const financialRef = db.doc(
      `academies/${academyId}/financials/${financialId}`
    );
    const initialSnapshot = await financialRef.get();
    if (!initialSnapshot.exists) {
      throw new HttpsError('not-found', 'Cobranca nao encontrada.');
    }
    const initial = initialSnapshot.data();
    if (!['pending', 'overdue'].includes(initial.status)) {
      throw new HttpsError(
        'failed-precondition',
        'Cobranca liquidada nao pode ser editada.'
      );
    }
    const verifiedIds = await cancelCompetingPaymentsFailClosed(
      academyId, initial
    );
    const invalidatedAttemptId = await db.runTransaction(async (tx) => {
      const liveSnapshot = await tx.get(financialRef);
      if (!liveSnapshot.exists) {
        throw new HttpsError('not-found', 'Cobranca nao encontrada.');
      }
      const live = liveSnapshot.data();
      if (!['pending', 'overdue'].includes(live.status)) {
        throw new HttpsError('aborted', 'A cobranca mudou. Atualize a tela.');
      }
      const liveIds = competingProviderPaymentIds(live);
      if ([...liveIds].some((id) => !verifiedIds.has(id))) {
        throw new HttpsError(
          'aborted',
          'Uma nova tentativa de pagamento surgiu. Tente novamente.'
        );
      }
      tx.update(financialRef, {
        amount: Math.round(amount * 100) / 100,
        dueDate: admin.firestore.Timestamp.fromDate(dueDate),
        status: openStatusForDueDate(dueDate),
        financialVersion: (Number(live.financialVersion) || 0) + 1,
        ...financialGatewayCleanup(),
        lastReminderStage: admin.firestore.FieldValue.delete(),
        lastReminderAt: admin.firestore.FieldValue.delete(),
        lastDueSoonStage: admin.firestore.FieldValue.delete(),
        lastDueSoonAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (live.publicPaymentLinkHash) {
        tx.set(db.doc(`publicPaymentLinks/${live.publicPaymentLinkHash}`), {
          financialVersion: (Number(live.financialVersion) || 0) + 1,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      return live.lastCheckoutAttemptId || '';
    });
    await invalidatePublicCheckoutAttemptBestEffort(
      academyId,
      invalidatedAttemptId,
      'financial_changed'
    );
    return { success: true };
  }
);

exports.markFinancialPaidManual = onCall(
  { secrets: MP_MKT_SECRETS }, async (request) => {
    const academyId = assertSafeDocumentId(request.data?.academyId, 'academyId');
    const financialId = assertSafeDocumentId(
      request.data?.financialId, 'financialId'
    );
    await requireAdminOf(request, academyId);
    const method = String(request.data?.method || 'pix');
    if (!['pix', 'credit_card', 'debit_card', 'cash', 'bank_transfer']
      .includes(method)) {
      throw new HttpsError('invalid-argument', 'Metodo de pagamento invalido.');
    }
    const paymentDate = request.data?.paymentDate
      ? parseFinancialDate(request.data.paymentDate, 'paymentDate') : new Date();
    const financialRef = db.doc(
      `academies/${academyId}/financials/${financialId}`
    );
    const initialSnapshot = await financialRef.get();
    if (!initialSnapshot.exists) {
      throw new HttpsError('not-found', 'Cobranca nao encontrada.');
    }
    const initial = initialSnapshot.data();
    if (!['pending', 'overdue'].includes(initial.status)) {
      throw new HttpsError(
        'failed-precondition',
        'Somente cobrancas abertas podem receber baixa manual.'
      );
    }
    const verifiedIds = await cancelCompetingPaymentsFailClosed(
      academyId, initial
    );
    const actorName = await financialActorName(request);
    const auditRef = db.collection(
      `academies/${academyId}/paymentAuditLogs`
    ).doc();
    const result = await db.runTransaction(async (tx) => {
      const liveSnapshot = await tx.get(financialRef);
      if (!liveSnapshot.exists) {
        throw new HttpsError('not-found', 'Cobranca nao encontrada.');
      }
      const live = liveSnapshot.data();
      if (!['pending', 'overdue'].includes(live.status)) {
        throw new HttpsError('aborted', 'A cobranca mudou. Atualize a tela.');
      }
      const liveIds = competingProviderPaymentIds(live);
      if ([...liveIds].some((id) => !verifiedIds.has(id))) {
        throw new HttpsError(
          'aborted',
          'Uma nova tentativa de pagamento surgiu. Tente novamente.'
        );
      }
      const paidAt = admin.firestore.Timestamp.fromDate(paymentDate);
      tx.update(financialRef, {
        status: 'paid',
        method,
        paymentGateway: 'manual',
        paymentDate: paidAt,
        manualPaymentAudit: {
          type: method,
          source: 'admin_app',
          confirmedByName: actorName,
          confirmedAt: paidAt,
        },
        ...financialGatewayCleanup(),
        updatedAt: paidAt,
      });
      tx.set(auditRef, {
        action: 'mark_paid_manual',
        academyId,
        financialId,
        studentId: live.studentId || '',
        studentName: live.studentName || '',
        amount: Number(live.amount) || 0,
        method,
        actorUid: request.auth.uid,
        actorDisplayName: actorName,
        beforeStatus: live.status,
        afterStatus: 'paid',
        createdAt: paidAt,
      });
      return live;
    });
    await invalidatePublicCheckoutAttemptBestEffort(
      academyId,
      result.lastCheckoutAttemptId,
      'financial_paid_manual'
    );
    let attendanceGranted = result.attendanceGranted === true;
    if (result.type === 'private_lesson' && !attendanceGranted) {
      await grantPrivateLessonAttendance(
        academyId, financialId, result,
        { verifiedBy: request.auth.uid, verifiedByName: actorName }
      );
      attendanceGranted = true;
    }
    return { success: true, attendanceGranted };
  }
);

exports.cancelFinancialCharge = onCall(
  { secrets: MP_MKT_SECRETS }, async (request) => {
    const academyId = assertSafeDocumentId(request.data?.academyId, 'academyId');
    const financialId = assertSafeDocumentId(
      request.data?.financialId, 'financialId'
    );
    await requireAdminOf(request, academyId);
    const financialRef = db.doc(
      `academies/${academyId}/financials/${financialId}`
    );
    const initialSnapshot = await financialRef.get();
    if (!initialSnapshot.exists) {
      throw new HttpsError('not-found', 'Cobranca nao encontrada.');
    }
    const initial = initialSnapshot.data();
    if (initial.status === 'cancelled') return { success: true, alreadyCancelled: true };
    if (!['pending', 'overdue'].includes(initial.status)) {
      throw new HttpsError('failed-precondition', 'Cobranca liquidada nao pode ser cancelada.');
    }
    const verifiedIds = await cancelCompetingPaymentsFailClosed(
      academyId, initial
    );
    const invalidatedAttemptId = await db.runTransaction(async (tx) => {
      const liveSnapshot = await tx.get(financialRef);
      if (!liveSnapshot.exists) {
        throw new HttpsError('not-found', 'Cobranca nao encontrada.');
      }
      const live = liveSnapshot.data();
      if (!['pending', 'overdue'].includes(live.status)) {
        throw new HttpsError('aborted', 'A cobranca mudou. Atualize a tela.');
      }
      const liveIds = competingProviderPaymentIds(live);
      if ([...liveIds].some((id) => !verifiedIds.has(id))) {
        throw new HttpsError('aborted', 'Nova tentativa detectada. Tente novamente.');
      }
      tx.update(financialRef, {
        status: 'cancelled',
        financialVersion: (Number(live.financialVersion) || 0) + 1,
        ...financialGatewayCleanup(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return live.lastCheckoutAttemptId || '';
    });
    await invalidatePublicCheckoutAttemptBestEffort(
      academyId,
      invalidatedAttemptId,
      'financial_cancelled'
    );
    return { success: true };
  }
);

exports.reactivateFinancialCharge = onCall(async (request) => {
  const academyId = assertSafeDocumentId(request.data?.academyId, 'academyId');
  const financialId = assertSafeDocumentId(
    request.data?.financialId, 'financialId'
  );
  await requireAdminOf(request, academyId);
  const financialRef = db.doc(
    `academies/${academyId}/financials/${financialId}`
  );
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(financialRef);
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'Cobranca nao encontrada.');
    }
    const financial = snapshot.data();
    if (financial.status !== 'cancelled') {
      throw new HttpsError('failed-precondition', 'A cobranca nao esta cancelada.');
    }
    const dueDate = financial.dueDate?.toDate?.();
    if (!dueDate) throw new HttpsError('failed-precondition', 'Vencimento invalido.');
    tx.update(financialRef, {
      status: openStatusForDueDate(dueDate),
      financialVersion: (Number(financial.financialVersion) || 0) + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { success: true };
});

exports.refreshOverdueFinancials = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Login obrigatorio.');
  const academyId = assertSafeDocumentId(request.data?.academyId, 'academyId');
  if (!(await isAcademyStaff(request.auth.uid, academyId))) {
    throw new HttpsError(
      'permission-denied',
      'Apenas a equipe da academia pode atualizar cobrancas vencidas.'
    );
  }
  const snapshot = await db.collection(
    `academies/${academyId}/financials`
  ).where('status', '==', 'pending').get();
  const now = new Date();
  // Firestore batches accept at most 500 writes. Academies with a larger
  // backlog must still be able to open Financeiro instead of failing the
  // callable (and consequently the whole screen load).
  let batch = db.batch();
  let writesInBatch = 0;
  let updated = 0;
  for (const document of snapshot.docs) {
    const financial = document.data() || {};
    const dueDate = financial.dueDate?.toDate?.();
    if (dueDate && isOverdueBR(dueDate, now)) {
      batch.update(document.ref, {
        status: 'overdue',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      updated++;
      writesInBatch++;
      if (writesInBatch === 500) {
        await batch.commit();
        batch = db.batch();
        writesInBatch = 0;
      }
    }
  }
  if (writesInBatch > 0) await batch.commit();
  return { success: true, updated };
});

exports.deleteFinancialCharge = onCall(async (request) => {
  const academyId = assertSafeDocumentId(request.data?.academyId, 'academyId');
  const financialId = assertSafeDocumentId(
    request.data?.financialId, 'financialId'
  );
  await requireAdminOf(request, academyId);
  const financialRef = db.doc(
    `academies/${academyId}/financials/${financialId}`
  );
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(financialRef);
    if (!snapshot.exists) return;
    const financial = snapshot.data();
    if (!['pending', 'overdue', 'cancelled', 'test'].includes(financial.status) ||
        competingProviderPaymentIds(financial).size > 0 ||
        financial.paymentDate || financial.manualPaymentAudit) {
      throw new HttpsError(
        'failed-precondition',
        'Cobranca com historico financeiro nao pode ser excluida.'
      );
    }
    if (financial.publicPaymentLinkHash) {
      tx.set(db.doc(`publicPaymentLinks/${financial.publicPaymentLinkHash}`), {
        status: 'revoked',
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    tx.delete(financialRef);
  });
  return { success: true };
});

/** Parses `${academyId}:fin:${id}` / `${academyId}:order:${id}`. */
function mpMktParseRef(ref) {
  const parts = String(ref || '').split(':');
  if (parts.length < 3) return null;
  return { academyId: parts[0], type: parts[1], docId: parts.slice(2).join(':') };
}

function publicAttemptIdFromPayment(payment) {
  const value = String(payment?.metadata?.attempt_id || '');
  return /^attempt_[a-f0-9]{40}$/i.test(value) ? value : '';
}

async function publicAttemptRefsForPayment(academyId, payment) {
  const refs = new Map();
  const metadataAttemptId = publicAttemptIdFromPayment(payment);
  if (metadataAttemptId) {
    const ref = db.doc(
      `academies/${academyId}/paymentAttempts/${metadataAttemptId}`
    );
    refs.set(ref.path, ref);
  }

  const paymentId = String(payment?.id || '');
  if (paymentId) {
    const matches = await db.collection(`academies/${academyId}/paymentAttempts`)
      .where('providerPaymentId', '==', paymentId)
      .limit(3)
      .get();
    matches.docs.forEach((snapshot) => refs.set(snapshot.ref.path, snapshot.ref));
  }
  return [...refs.values()];
}

/**
 * Mirrors provider state into the server-only attempt audit trail. The financial
 * remains the authoritative source: an approved provider payment is shown as
 * `paid` only after it settled the matching financial with the same payment id.
 */
async function projectPublicPaymentAttempt(academyId, payment) {
  const desiredStatus = publicAttemptStatusFromProvider(payment?.status);
  const paymentId = String(payment?.id || '');
  if (!desiredStatus || !paymentId) return;

  const refs = await publicAttemptRefsForPayment(academyId, payment);
  await Promise.all(refs.map(async (attemptRef) => {
    const attemptSnapshot = await attemptRef.get();
    if (!attemptSnapshot.exists) return;
    const attempt = attemptSnapshot.data() || {};
    if (attempt.targetType !== 'financial' || !attempt.targetId) return;

    const update = {
      providerPaymentId: paymentId,
      providerStatus: String(payment.status || '').toLowerCase(),
      providerStatusObservedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const currentStatus = String(attempt.status || '');

    if (desiredStatus === 'paid' || desiredStatus === 'reversed') {
      const financialSnapshot = await db.doc(
        `academies/${academyId}/financials/${attempt.targetId}`
      ).get();
      const financial = financialSnapshot.exists ? financialSnapshot.data() || {} : {};
      const settledByThisPayment = financial.status === 'paid' &&
        String(financial.gatewayPaymentId || '') === paymentId;
      if (desiredStatus === 'paid' && settledByThisPayment) {
        update.status = 'paid';
        update.paidAt = admin.firestore.FieldValue.serverTimestamp();
      } else if (desiredStatus === 'reversed' && currentStatus === 'paid') {
        update.status = 'reversed';
        update.reversedAt = admin.firestore.FieldValue.serverTimestamp();
      } else if (desiredStatus === 'paid' &&
          ['cancelled', 'failed', 'expired', 'reversed'].includes(currentStatus)) {
        // Preserve local invalidation, but surface a late provider approval for
        // staff reconciliation. Never revive an invalidated checkout.
        update.lateProviderApprovalAt = admin.firestore.FieldValue.serverTimestamp();
      }
    } else if (!['paid', 'cancelled', 'failed', 'expired', 'reversed'].includes(currentStatus)) {
      update.status = desiredStatus;
      if (desiredStatus === 'failed' || desiredStatus === 'cancelled') {
        update.failureCode = `provider_${String(payment.status || '').toLowerCase()}`;
      }
    }
    await attemptRef.set(update, { merge: true });
  }));
}

function publicAttemptTimestampMs(value) {
  return value && typeof value.toMillis === 'function' ? value.toMillis() : 0;
}

function publicAttemptPaymentCandidate(payment, attempt) {
  if (!payment || !MP_REVERSAL_STATUSES.includes(payment.status) &&
      !['approved', 'pending', 'in_process', 'rejected', 'cancelled'].includes(payment.status)) {
    return false;
  }
  if (Math.abs((Number(payment.transaction_amount) || 0) -
      (Number(attempt.amount) || 0)) > 0.01) return false;
  const createdAtMs = Date.parse(payment.date_created || payment.date_approved || '');
  const startMs = publicAttemptTimestampMs(attempt.createdAt);
  const endMs = publicAttemptTimestampMs(attempt.expiresAt);
  return !Number.isFinite(createdAtMs) || !startMs || !endMs ||
    (createdAtMs >= startMs - 5 * 60 * 1000 && createdAtMs <= endMs + 24 * 60 * 60 * 1000);
}

/**
 * Replays recent public attempts through MP so a lost webhook cannot strand a
 * paid financial. It is intentionally bounded per academy and idempotent:
 * `mpMktSettle` remains the only code that flips money state.
 */
exports.scheduledPublicPaymentAttemptReconcile = onSchedule(
  { schedule: '*/10 * * * *', timeZone: 'America/Sao_Paulo',
    timeoutSeconds: 540, secrets: MP_MKT_SECRETS },
  async () => {
    const staleCutoffMs = Date.now() - 7 * 24 * 60 * 60 * 1000;
    await forEachMpAcademy('public-attempt-reconcile', async (academyDoc) => {
      const academyId = academyDoc.id;
      const attempts = await db.collection(`academies/${academyId}/paymentAttempts`)
        .where('status', 'in', ['ready', 'pending'])
        .orderBy('updatedAt', 'asc')
        .limit(50)
        .get();
      if (attempts.empty) return 'skipped';

      let token;
      for (const attemptDoc of attempts.docs) {
        const attempt = attemptDoc.data() || {};
        if (attempt.targetType !== 'financial' || !attempt.targetId) continue;
        if (publicAttemptTimestampMs(attempt.expiresAt) < staleCutoffMs) {
          await attemptDoc.ref.set({
            status: 'expired',
            failureCode: 'reconcile_expired',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          continue;
        }
        try {
          if (!token) token = await getMpAccessToken(academyId);
          const externalReference = `${academyId}:fin:${attempt.targetId}`;
          let candidates = [];
          if (attempt.providerPaymentId) {
            candidates = [await mpRequest(
              'GET', `/v1/payments/${encodeURIComponent(attempt.providerPaymentId)}`, { token }
            )];
          } else {
            const search = await mpRequest('GET',
              `/v1/payments/search?external_reference=${encodeURIComponent(externalReference)}` +
              '&sort=date_created&criteria=desc&limit=20', { token });
            candidates = (search?.results || search?.elements || [])
              .filter((payment) => publicAttemptPaymentCandidate(payment, attempt));
          }
          for (const payment of candidates) {
            if (payment.status === 'approved') {
              await mpMktSettle({ academyId, type: 'fin', docId: attempt.targetId }, payment);
            } else if (MP_REVERSAL_STATUSES.includes(payment.status)) {
              await mpMktHandleReversal(
                { academyId, type: 'fin', docId: attempt.targetId }, payment
              );
            }
            await projectPublicPaymentAttempt(academyId, payment);
          }
        } catch (error) {
          console.error('[public-attempt-reconcile] attempt failed', academyId,
            attemptDoc.id, error && error.message);
        }
      }
      return null;
    });
    return null;
  }
);

// ---- Marketplace webhook (flips financials/storeOrders to paid) -----------
exports.mercadoPagoMarketplaceWebhook = onRequest(
  // The webhook fetches the payment using the academy OAuth token. Bind both
  // OAuth secrets as well as the HMAC secret: a token refresh must not fail just
  // because a gen2 instance was cold-started without process-wide env vars.
  { cors: false, invoker: 'public', secrets: MP_MKT_WEBHOOK_SECRETS },
  async (req, res) => {
    if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

    const acad = String(req.query.acad || '');
    const dataId = String(
      req.query['data.id'] || (req.query.data && req.query.data.id) ||
      req.query.id || (req.body && req.body.data && req.body.data.id) || '',
    );

    // x-signature HMAC validation (same scheme as the paywall webhook).
    // FAIL CLOSED: if the secret is not configured we cannot authenticate the
    // caller — refuse to process (do NOT settle on an unverified webhook).
    const secret = process.env.MP_MKT_WEBHOOK_SECRET;
    if (!secret) {
      console.error('[mpMktWebhook] MP_MKT_WEBHOOK_SECRET not configured — refusing');
      return res.status(401).json({ error: 'webhook secret not configured' });
    }
    {
      const xSignature = req.header('x-signature') || '';
      const xRequestId = req.header('x-request-id') || '';
      let ts = ''; let v1 = '';
      for (const part of xSignature.split(',')) {
        const [k, val] = part.split('=').map((s) => (s || '').trim());
        if (k === 'ts') ts = val;
        if (k === 'v1') v1 = val;
      }
      const manifest = `id:${dataId.toLowerCase()};request-id:${xRequestId};ts:${ts};`;
      const expected = crypto.createHmac('sha256', secret).update(manifest).digest('hex');
      const valid = v1.length === expected.length &&
        crypto.timingSafeEqual(Buffer.from(v1), Buffer.from(expected));
      if (!valid) {
        console.warn('[mpMktWebhook] assinatura inválida');
        return res.status(401).json({ error: 'invalid signature' });
      }
      // Frescor do ts (anti-replay, auditoria): rejeita assinaturas fora da
      // janela de ~5 min — espelha o mercadoPagoWebhook do index.js. O MP manda
      // o ts em segundos ou ms conforme a versão; normaliza pra ms antes de
      // comparar. Sem isso, uma assinatura válida capturada pode ser reenviada.
      const tsNum = Number(ts);
      const tsMs = tsNum < 1e12 ? tsNum * 1000 : tsNum;
      if (!Number.isFinite(tsNum) || tsNum <= 0 ||
          Math.abs(Date.now() - tsMs) > 5 * 60 * 1000) {
        console.warn('[mpMktWebhook] ts da assinatura fora da janela — possível replay', { ts });
        return res.status(401).json({ error: 'stale signature timestamp' });
      }
    }

    const type = String(req.query.type || req.query.topic ||
      (req.body && req.body.type) || '');
    if (!dataId || !acad) {
      return res.status(200).json({ received: true, skipped: 'no_id' });
    }

    try {
      // Recurring subscriptions (Assinaturas / Preapproval). These arrive on
      // their own topics — handle them BEFORE the one-off payment path.
      if (type === 'subscription_preapproval') {
        await mpSubSyncPreapproval(acad, dataId);
        return res.status(200).json({ success: true, kind: 'preapproval' });
      }
      if (type === 'subscription_authorized_payment') {
        await mpSubHandleAuthorizedPayment(acad, dataId);
        return res.status(200).json({ success: true, kind: 'authorized_payment' });
      }
      if (type && type !== 'payment') {
        return res.status(200).json({ received: true, skipped: type });
      }

      const token = await getMpAccessToken(acad);
      const payment = await mpRequest('GET', `/v1/payments/${dataId}`, { token });
      const parsed = mpMktParseRef(payment.external_reference);
      if (!parsed || parsed.academyId !== acad) {
        return res.status(200).json({ received: true, skipped: 'ref_mismatch' });
      }
      // A subscription payment that surfaces on the payment topic (defensive —
      // normally it arrives as subscription_authorized_payment).
      const isReversal = MP_REVERSAL_STATUSES.includes(payment.status);
      if (parsed.type === 'sub') {
        if (payment.status === 'approved') {
          await mpSubSettleCycle(acad, parsed.docId, token, {
            paymentId: String(payment.id),
            amount: Number(payment.transaction_amount) || 0,
            // Data real da cobrança → referenceMonth/dueDate do ciclo correto.
            chargeDate: payment.date_approved || payment.date_created,
          });
        } else if (isReversal) {
          // Estorno/chargeback de um ciclo já liquidado (achado #16).
          await mpSubHandleReversal(acad, parsed.docId, payment);
        }
        return res.status(200).json({ success: true, kind: 'sub_payment' });
      }
      if (payment.status !== 'approved') {
        if (isReversal) {
          // Estorno/chargeback de financial/pedido já 'paid' (achado #16).
          // No-op se o doc não estiver 'paid' com o mesmo paymentId (ex.: PIX
          // expirado chega como 'cancelled'). Sempre responde 200.
          await mpMktHandleReversal(parsed, payment);
          return res.status(200).json({ success: true, kind: 'reversal' });
        }
        // Auditoria MP (limpeza dos marcadores cardPending*): cartão em estado
        // terminal não-aprovado (rejected/cancelled) deve apagar os marcadores
        // cardPending* do doc para não deixarem estado obsoleto por ~1h até
        // expirar. Só limpa se cardPendingPaymentId === payment.id (não apaga
        // marcadores de outra tentativa em curso). Best-effort.
        if (payment.status === 'rejected' || payment.status === 'cancelled') {
          await mpClearCardPendingIfMatches(acad, parsed, String(payment.id));
        }
        // This is only an audit projection. It never changes the financial and
        // therefore must not make webhook acknowledgement depend on Firestore.
        if (parsed.type === 'fin') {
          await projectPublicPaymentAttempt(acad, payment).catch((error) =>
            console.error('[mpMktWebhook] attempt projection failed', error.message));
        }
        return res.status(200).json({ received: true, status: payment.status });
      }
      // Auditoria MP (estorno PARCIAL silencioso): o MP re-notifica o MESMO
      // paymentId ainda como status='approved' quando há um estorno PARCIAL
      // (transaction_amount_refunded > 0 e < transaction_amount). Sem tratamento,
      // o doc seguia 'paid' pelo valor cheio e o dinheiro devolvido sumia da
      // conciliação. Detecta ANTES do settle e registra um refundEvent parcial
      // idempotente + alerta o admin, SEM desfazer o pagamento integral.
      const refunded = Number(payment.transaction_amount_refunded) || 0;
      const total = Number(payment.transaction_amount) || 0;
      if (refunded > 0.005 && refunded < total - 0.005) {
        await mpMktHandlePartialRefund(parsed, payment, refunded);
        return res.status(200).json({ success: true, kind: 'partial_refund' });
      }
      await mpMktSettle(parsed, payment);
      if (parsed.type === 'fin') {
        // Project approved only after the authoritative settle has run. A value
        // mismatch or duplicate must stay visible as such instead of showing the
        // public attempt as paid.
        await projectPublicPaymentAttempt(acad, payment).catch((error) =>
          console.error('[mpMktWebhook] attempt projection failed', error.message));
      }
      return res.status(200).json({ success: true });
    } catch (e) {
      console.error('[mpMktWebhook] erro', e.message);
      // Auditoria MP (retry-storm de academia desconectada/sem token): o
      // getMpAccessToken lança 'failed-precondition' tanto p/ "nunca conectou"
      // (sem refreshToken) quanto p/ "refresh quebrado momentaneamente". Para o
      // 1º, retry NUNCA resolve → responde 200 (descarta). Para o 2º (transitório)
      // mantém 500/retry, pois o evento ainda pode liquidar após a reconexão.
      // Distingue lendo o mpAuth: ausência de refreshToken = nunca conectou.
      if (e instanceof HttpsError && e.code === 'failed-precondition') {
        try {
          const authSnap = await db.doc(`academies/${acad}/private/mpAuth`).get();
          if (!authSnap.exists || !authSnap.data().refreshToken) {
            return res.status(200).json({ received: true, skipped: 'no_token' });
          }
        } catch (_) { /* cai no 500/retry abaixo */ }
      }
      // Auditoria MP (tópico vazio / id não-payment): notificação genérica sem
      // type cujo dataId NÃO é um payment válido faz o GET /v1/payments dar 404.
      // Retry não vai materializar um payment inexistente → responde 200.
      if (e && e.status === 404) {
        return res.status(200).json({ received: true, skipped: 'not_a_payment' });
      }
      return res.status(500).json({ error: e.message }); // 500 => MP retries
    }
  });

/** Pagamento APROVADO que não casa com o estado do doc:
 * - reason 'missing_doc' (default): doc apagado/inexistente (ex.: professor
 *   apagou a cobrança/pedido com o PIX vivo e o aluno pagou depois) — sem
 *   registro, o dinheiro cai na conta MP da academia sem rastro no app.
 * - reason 'duplicate': SEGUNDO pagamento aprovado com paymentId diferente do
 *   gravado num doc já 'paid' (race da geração de PIX) — a família pagou 2x e
 *   o admin precisa reembolsar.
 * Grava um doc de conciliação (dedupe por paymentId via create(), p/ webhook
 * duplicado) e avisa o admin na 1ª vez. Best-effort: nunca lança. */
async function mpMktRecordUnmatchedPayment(academyId, type, docId, payment, opts) {
  const reason = (opts && opts.reason) || 'missing_doc';
  const chargeId = String(payment.id);
  const amount = Number(payment.transaction_amount) || 0;
  console.error('[mpMktSettle]', reason === 'duplicate'
    ? 'segundo pagamento aprovado p/ doc ja pago'
    : 'pagamento aprovado p/ doc inexistente',
  type, docId, chargeId);
  try {
    await db.doc(`academies/${academyId}/unmatchedPayments/${chargeId}`).create({
      type,
      docId,
      paymentId: chargeId,
      amount, // REAIS (canônico)
      reason,
      createdAt: FV.serverTimestamp(),
    });
  } catch (_) {
    return; // já registrado (webhook duplicado): não re-notifica
  }
  try {
    const what = type === 'order'
      ? `o pedido #${docId.slice(-6).toUpperCase()}` : 'uma cobranca';
    const notifType = type === 'order' ? 'order_paid' : 'payment_received';
    const target = type === 'order' ? { orderId: docId } : { financialId: docId };
    if (reason === 'duplicate') {
      await notifyAdminCF(academyId, notifType,
        'Pagamento duplicado — reembolso necessario',
        `Caiu um SEGUNDO pagamento de R$ ${amount.toFixed(2)} para ${what} ` +
        `que ja estava paga(o). O aluno pagou duas vezes — reembolse o ` +
        `pagamento ${chargeId} no Mercado Pago.`,
        target);
    } else {
      await notifyAdminCF(academyId, notifType,
        'Pagamento sem cobranca no app',
        `Caiu um pagamento de R$ ${amount.toFixed(2)} para ${what} que nao ` +
        `existe mais no app. O valor esta na sua conta Mercado Pago — confira ` +
        `manualmente (pagamento ${chargeId}).`,
        target);
    }
  } catch (_) { /* notify is best-effort */ }
}

/** Flips the financial/order to paid (idempotent) + stock + admin notify. */
// ---- Aula particular: concessão de presença ao liquidar a cobrança ---------
// Uma cobrança financial type='private_lesson' concede UMA presença real ao
// aluno (sem turma/plano) quando é paga. Espelha a semântica do markPresent do
// cliente (attendance_service.dart:362-427): cria o doc de attendance e
// incrementa student.attendanceCount na MESMA transação. É idempotente por
// FINANCIAL via dois mecanismos combinados: a flag fin.attendanceGranted e um
// id de presença determinístico que inclui o financialId — duas aulas
// particulares do mesmo aluno no mesmo dia geram presenças distintas (a regra
// padrão {studentId}_{classId}_{YYYYMMDD} colidiria e perderia uma presença
// paga). NOTA: a auto-promoção de faixa (graduationMode='auto') roda no cliente
// no check-in; aqui só incrementamos o contador (que alimenta ranking/streak/
// elegibilidade) — a promoção é reavaliada no próximo check-in ou manualmente.
function ymdCompact(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}${m}${day}`;
}

/** Concede (exactly-once) a presença de uma aula particular paga. `fin` é o
 * snapshot do doc financial; `actor` = { verifiedBy, verifiedByName }. Best-
 * effort no chamador: uma falha aqui nunca deve desfazer a liquidação. */
async function grantPrivateLessonAttendance(academyId, financialId, fin, actor) {
  const studentId = fin.studentId;
  if (!studentId) {
    console.error('[grantPrivateLesson] financial sem studentId', financialId);
    return;
  }
  const lessonDate = fin.lessonDate?.toDate?.() ||
    fin.dueDate?.toDate?.() || new Date();
  const weight = Number(fin.lessonWeight) > 0 ? Number(fin.lessonWeight) : 1;
  const sport = fin.lessonSport || 'bjj';
  const attendanceId =
    `${studentId}_aula_particular_${ymdCompact(lessonDate)}_${String(financialId).slice(-6)}`;

  const finRef = db.doc(`academies/${academyId}/financials/${financialId}`);
  const attRef = db.doc(`academies/${academyId}/attendance/${attendanceId}`);
  const studentRef = db.doc(`academies/${academyId}/students/${studentId}`);

  await db.runTransaction(async (tx) => {
    const finSnap = await tx.get(finRef);
    if (finSnap.exists && finSnap.data().attendanceGranted === true) {
      return; // já concedida (re-entrega do webhook / grant manual prévio)
    }
    const attSnap = await tx.get(attRef);
    const finUpdate = {
      attendanceGranted: true,
      attendanceId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (attSnap.exists) {
      // Presença já existe mas a flag não estava setada (reconciliação): só
      // marca a flag, sem re-incrementar o contador (evita duplo incremento).
      tx.update(finRef, finUpdate);
      return;
    }
    const payload = {
      studentId,
      studentName: fin.studentName || '',
      classId: 'aula_particular',
      className: 'Aula Particular',
      date: admin.firestore.Timestamp.fromDate(lessonDate),
      verifiedBy: actor.verifiedBy,
      verifiedByName: actor.verifiedByName,
      notes: `Aula particular — fin ${financialId}`,
      sport,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (weight !== 1) payload.weight = weight; // espelha markPresent (só != 1)
    tx.set(attRef, payload);
    tx.update(studentRef, {
      attendanceCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(finRef, finUpdate);
  });
}

async function mpMktSettle({ academyId, type, docId }, payment) {
  const chargeId = String(payment.id);
  const amtFmt = (Number(payment.transaction_amount) || 0).toFixed(2);
  const method = payment.payment_method_id === 'pix' ? 'pix' : 'card';
  const viaLabel = method === 'pix' ? 'via PIX' : 'via cartao';

  if (type === 'order') {
    const orderRef = db.doc(`academies/${academyId}/storeOrders/${docId}`);
    // Atomic status flip: read + guard + update inside a transaction so that
    // an inline (sync card) settle and the webhook settle for the SAME payment
    // cannot both pass the early-return and double-decrement stock / double-
    // notify. Only the execution that actually performed the flip proceeds.
    const settle = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(orderRef);
      if (!snap.exists) {
        // Doc apagado/inexistente NÃO é o caso idempotente de 'já pago' —
        // precisa virar registro de conciliação + aviso (fora da transação).
        return { didSettle: false, missingDoc: true };
      }
      if (snap.data().status === 'paid') {
        // SEGUNDO pagamento aprovado com OUTRO paymentId para um pedido já
        // pago (race da geração de PIX, achado #24): a família pagou 2x.
        // Registra para conciliação + alerta de reembolso (fora da tx).
        if (snap.data().gatewayPaymentId &&
            snap.data().gatewayPaymentId !== chargeId) {
          return { didSettle: false, duplicatePayment: true };
        }
        // Auditoria MP (double-pay silencioso): pedido já 'paid' SEM um
        // gatewayPaymentId do MP (marcado "pago"/cash manualmente) e agora chega
        // um pagamento MP aprovado para o MESMO pedido → o PIX em aberto foi pago
        // DEPOIS do cash. Espelha o branch financial (5585-5590): NÃO credita de
        // novo, mas sinaliza duplicidade alertável para o admin reembolsar.
        if (!snap.data().gatewayPaymentId) {
          return { didSettle: false, duplicatePayment: true };
        }
        // Auditoria MP (cash-then-PIX do MESMO QR): o mark-paid cash de pedido
        // (_killLivePixOnPaid) limpa os campos pix* mas NÃO apaga o
        // gatewayPaymentId do PIX vivo cunhado. Se o cancelMpPix best-effort
        // falhou e o cliente pagou aquele MESMO PIX, o webhook chega com
        // gatewayPaymentId === chargeId — escapando do guard acima (5745) e do
        // !gatewayPaymentId. Distingue do settle real do MP pela AUSÊNCIA de
        // `stockSettled` (campo só escrito por este mpMktSettle; cash-mark via
        // app nunca o grava): pedido 'paid' com o MESMO chargeId mas que NUNCA
        // passou pelo settle do MP = pagou cash e depois pagou o PIX → duplicata
        // alertável (espelha o branch financial 5916-5921). Retrocompat: settle
        // legítimo do MP sempre define stockSettled (false→true), então NÃO cai
        // aqui; pedido do app antigo sem PIX cunhado nunca tem gatewayPaymentId.
        if (snap.data().gatewayPaymentId === chargeId &&
            snap.data().stockSettled === undefined) {
          return { didSettle: false, duplicatePayment: true };
        }
        // Re-entrega do webhook com o decremento de estoque pendente (crash
        // entre o commit da tx e o loop de estoque, achado #30): completa o
        // efeito em vez de retornar direto.
        if (snap.data().stockSettled === false) {
          return { didSettle: false, completeStock: true,
            items: snap.data().items };
        }
        return { didSettle: false }; // idempotent
      }
      // SECURITY: refuse to settle if the paid amount differs from the order
      // total (reais, 1-centavo tolerance). Protects against a tampered or
      // mismatched MP payment flipping the order to paid for the wrong value.
      const expectedReais = orderExpectedTotalReais(snap.data());
      const paidReais = Number(payment.transaction_amount) || 0;
      if (Math.abs(expectedReais - paidReais) > 0.01) {
        console.error('[mpMktSettle] amount mismatch order', docId,
          'expected', expectedReais, 'paid', paidReais);
        // Mismatch VISIVEL: registra no doc (sem marcar paid) e avisa o admin
        // APOS a transacao — dinheiro caiu com valor divergente e precisa de
        // conferencia manual. Mesmo paymentId ja registrado => nao re-notifica
        // (settle inline + webhook para o mesmo pagamento).
        const already =
          snap.data().settleMismatch?.paymentId === chargeId;
        if (!already) {
          transaction.update(orderRef, {
            settleMismatch: {
              paymentId: chargeId,
              paidAmount: paidReais,
              expectedAmount: expectedReais,
              at: admin.firestore.Timestamp.now(),
            },
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        return { didSettle: false,
          mismatch: already ? null : { paid: paidReais, expected: expectedReais } };
      }
      transaction.update(orderRef, {
        status: 'paid',
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        paymentMethod: method,
        paymentGateway: 'mercadopago',
        gatewayPaymentId: chargeId,
        externalPaymentId: chargeId,
        // Decremento de estoque PENDENTE: vira true após o loop pós-tx. Uma
        // re-entrega do webhook com paid && stockSettled===false completa o
        // decremento perdido num crash (achado #30).
        stockSettled: false,
        pixCode: admin.firestore.FieldValue.delete(),
        pixQrCode: admin.firestore.FieldValue.delete(),
        pixTicketUrl: admin.firestore.FieldValue.delete(),
        pixExpiresAt: admin.firestore.FieldValue.delete(),
        // Auditoria MP (cardPending* obsoleto): cartão que passou por in_process/
        // 3DS e aprovou só via webhook deixava os marcadores cardPending* vivos
        // (mpClearCardPendingIfMatches só limpa em rejected/cancelled). Limpa-os
        // no settle de APROVADO — o doc já é 'paid' e os guards curto-circuitam,
        // mas o estado fica consistente. Retrocompat: delete no-op se ausentes.
        cardPendingPaymentId: admin.firestore.FieldValue.delete(),
        cardPendingStatus: admin.firestore.FieldValue.delete(),
        cardPendingExpiresAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { didSettle: true, items: snap.data().items };
    });
    if (!settle.didSettle && !settle.completeStock) {
      if (settle.missingDoc) {
        await mpMktRecordUnmatchedPayment(academyId, type, docId, payment);
      }
      if (settle.duplicatePayment) {
        await mpMktRecordUnmatchedPayment(academyId, type, docId, payment,
          { reason: 'duplicate' });
      }
      if (settle.mismatch) {
        const code = docId.slice(-6).toUpperCase();
        await notifyAdminCF(academyId, 'order_paid',
          'Pagamento com valor divergente',
          `Pedido #${code}: caiu um pagamento de R$ ${settle.mismatch.paid.toFixed(2)}, ` +
          `mas o esperado era R$ ${settle.mismatch.expected.toFixed(2)}. ` +
          `O pedido NAO foi marcado como pago — confira manualmente no Mercado Pago.`,
          { orderId: docId });
      }
      return; // already settled, missing doc, duplicate, or mismatch
    }
    const items = settle.items;
    const oversold = []; // produtos que esgotaram no settle (conciliação)
    if (Array.isArray(items)) {
      for (const item of items) {
        const productRef = db.doc(`academies/${academyId}/storeProducts/${item.productId}`);
        // Auditoria MP (oversell server-side): decrementa o estoque DENTRO de uma
        // transação com PISO em 0 — lê o estoque atual e nunca deixa negativo.
        // Dois pedidos concorrentes na última unidade não furam mais o piso; o
        // 2º registra `oversell` para conciliação (a academia recebeu 2x e pode
        // reembolsar). Só vale p/ stockType==='in_stock' com quantidade finita.
        const res = await db.runTransaction(async (tx) => {
          const p = await tx.get(productRef);
          if (!p.exists || p.data()?.stockType !== 'in_stock') return null;
          const cur = Number(p.data().stockQuantity);
          if (!Number.isFinite(cur)) return null; // estoque ilimitado/indefinido
          const qty = Number(item.quantity) || 0;
          const next = Math.max(0, cur - qty); // piso em 0 (sem estoque negativo)
          tx.update(productRef, {
            stockQuantity: next,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          // Faltou estoque para atender este item por inteiro → conciliação.
          return cur - qty < 0
            ? { productId: item.productId, requested: qty, available: cur }
            : null;
        }).catch((e) => {
          console.error('[mpMktSettle] stock decrement falhou', item.productId, e.message);
          return null;
        });
        if (res) oversold.push(res);
      }
    }
    if (oversold.length) {
      // Estoque esgotado no momento do pagamento: avisa o admin para conciliar
      // (reembolsar/repor). NÃO bloqueia o pedido — o dinheiro já entrou.
      const code = docId.slice(-6).toUpperCase();
      await notifyAdminCF(academyId, 'order_paid', 'Estoque esgotado no pedido pago',
        `Pedido #${code} foi pago, mas ${oversold.length} item(ns) ficaram sem ` +
        'estoque suficiente. Confira para repor o estoque ou reembolsar.',
        { orderId: docId }).catch(() => { /* best-effort */ });
    }
    // Decremento concluído — desarma o flag (achado #30). Best-effort: se
    // falhar, a re-entrega do webhook completa de novo (increment idempotente
    // por execução; janela de duplo decremento exige crash + duas re-entregas
    // simultâneas, aceito como risco residual).
    await orderRef.update({
      stockSettled: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch((e) =>
      console.error('[mpMktSettle] stockSettled update falhou', docId, e.message));
    if (!settle.didSettle) {
      return; // completeStock: efeito completado; não re-notifica o admin
    }
    const code = docId.slice(-6).toUpperCase();
    await notifyAdminCF(academyId, 'order_paid', 'Pedido Pago',
      `Pedido #${code} pago - R$ ${amtFmt} ${viaLabel}.`, { orderId: docId });
    return;
  }

  // mensalidade / financial
  const finRef = db.doc(`academies/${academyId}/financials/${docId}`);
  // Atomic status flip (see order branch above): guards against the inline +
  // webhook double-settle so the admin notify fires exactly once.
  const finSettle = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(finRef);
    if (!snap.exists) {
      // Doc apagado/inexistente NÃO é o caso idempotente de 'já pago' —
      // precisa virar registro de conciliação + aviso (fora da transação).
      return { didSettle: false, missingDoc: true };
    }
    if (snap.data().status === 'paid') {
      // SEGUNDO pagamento aprovado com OUTRO paymentId para cobrança já paga
      // (race da geração de PIX, achado #24): a família pagou 2x. Registra
      // para conciliação + alerta de reembolso (fora da tx).
      if (snap.data().gatewayPaymentId &&
          snap.data().gatewayPaymentId !== chargeId) {
        return { didSettle: false, duplicatePayment: true };
      }
      // Auditoria MP (double-charge silencioso): cobrança já 'paid' SEM um
      // gatewayPaymentId do MP — foi marcada paga FORA do MP (markAsPaid de
      // mensalidade → paymentGateway 'manual'; markPrivateLessonGiven cash →
      // 'cash'; legado/AbacatePay) e agora chega um pagamento MP aprovado para o
      // MESMO financial → o PIX em aberto foi pago DEPOIS. NÃO credita de novo,
      // mas sinaliza duplicidade alertável (admin reembolsa). INCONDICIONAL,
      // espelhando o branch order (5940): um settle MP legítimo SEMPRE grava
      // gatewayPaymentId, então 'paid' sem id NUNCA é o caminho normal do MP —
      // cobre 'manual', 'cash' e gateways legados (a versão anterior só checava
      // 'cash'/ausente e deixava o caso 'manual' cair no no-op silencioso).
      if (!snap.data().gatewayPaymentId) {
        return { didSettle: false, duplicatePayment: true };
      }
      // Aula particular já paga mas com a presença ainda não concedida (crash
      // entre o commit do dinheiro e o grant, espelho do completeStock/achado
      // #30): completa o grant na re-entrega do webhook em vez de no-op.
      if (snap.data().type === 'private_lesson' &&
          snap.data().attendanceGranted !== true) {
        return { didSettle: false, completeGrant: true, finData: snap.data() };
      }
      return { didSettle: false }; // idempotent
    }
    // SECURITY: refuse to settle if the paid amount differs from the stored
    // financial amount (REAIS, canonical; 1-centavo tolerance).
    const expectedFinReais = Number(snap.data().amount) || 0;
    const paidFinReais = Number(payment.transaction_amount) || 0;
    if (Math.abs(expectedFinReais - paidFinReais) > 0.01) {
      console.error('[mpMktSettle] amount mismatch fin', docId,
        'expected', expectedFinReais, 'paid', paidFinReais);
      // Mismatch VISIVEL (espelha o branch de order): registra no doc sem
      // marcar paid e avisa o admin apos a transacao para conferencia manual.
      const already = snap.data().settleMismatch?.paymentId === chargeId;
      if (!already) {
        transaction.update(finRef, {
          settleMismatch: {
            paymentId: chargeId,
            paidAmount: paidFinReais,
            expectedAmount: expectedFinReais,
            at: admin.firestore.Timestamp.now(),
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      return { didSettle: false,
        mismatch: already ? null : { paid: paidFinReais, expected: expectedFinReais } };
    }
    transaction.update(finRef, {
      status: 'paid',
      paymentDate: admin.firestore.FieldValue.serverTimestamp(),
      method: method,
      paymentGateway: 'mercadopago',
      gatewayPaymentId: chargeId,
      pixCode: admin.firestore.FieldValue.delete(),
      pixQrCode: admin.firestore.FieldValue.delete(),
      pixTicketUrl: admin.firestore.FieldValue.delete(),
      pixExpiresAt: admin.firestore.FieldValue.delete(),
      // Auditoria MP (cardPending* obsoleto): espelha o branch order — cartão
      // aprovado só via webhook (in_process/3DS) deixava cardPending* vivos.
      // Limpa no settle de APROVADO. Retrocompat: delete no-op se ausentes.
      cardPendingPaymentId: admin.firestore.FieldValue.delete(),
      cardPendingStatus: admin.firestore.FieldValue.delete(),
      cardPendingExpiresAt: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { didSettle: true, finData: snap.data() };
  });
  // Aula particular: completa só o grant da presença numa re-entrega tardia
  // (dinheiro já liquidado num processo anterior que crashou antes do grant).
  // Tx do dinheiro e tx do grant são separadas mas ambas idempotentes.
  if (finSettle.completeGrant) {
    await grantPrivateLessonAttendance(academyId, docId, finSettle.finData, {
      verifiedBy: 'mp-webhook', verifiedByName: 'Mercado Pago',
    }).catch((e) =>
      console.error('[mpMktSettle] grant aula particular falhou', docId, e.message));
    return; // efeito completado; não re-notifica o admin
  }
  if (!finSettle.didSettle) {
    if (finSettle.missingDoc) {
      await mpMktRecordUnmatchedPayment(academyId, type, docId, payment);
    }
    if (finSettle.duplicatePayment) {
      await mpMktRecordUnmatchedPayment(academyId, type, docId, payment,
        { reason: 'duplicate' });
    }
    if (finSettle.mismatch) {
      await notifyAdminCF(academyId, 'payment_received',
        'Pagamento com valor divergente',
        `Caiu um pagamento de R$ ${finSettle.mismatch.paid.toFixed(2)}, ` +
        `mas a cobranca esperava R$ ${finSettle.mismatch.expected.toFixed(2)}. ` +
        `A cobranca NAO foi marcada como paga — confira manualmente no Mercado Pago.`,
        { financialId: docId });
    }
    return; // already settled, missing doc, or mismatch
  }
  // Liquidação real: se for aula particular, concede a presença (best-effort,
  // após o commit do dinheiro — uma falha aqui não desfaz o pagamento).
  if (finSettle.finData?.type === 'private_lesson') {
    await grantPrivateLessonAttendance(academyId, docId, finSettle.finData, {
      verifiedBy: 'mp-webhook', verifiedByName: 'Mercado Pago',
    }).catch((e) =>
      console.error('[mpMktSettle] grant aula particular falhou', docId, e.message));
  }
  await notifyAdminCF(academyId, 'payment_received', 'Pagamento Recebido',
    `Pagamento de R$ ${amtFmt} recebido ${viaLabel}.`, { financialId: docId });
}

/** Concessão MANUAL da presença de uma aula particular — caminho offline:
 * dinheiro recebido em mãos (cash), aula cortesia, ou staff confirmando que a
 * aula aconteceu. Gated para staff (admin/instrutor). Opcionalmente marca a
 * cobrança como paga (method='cash') quando paga presencialmente. Reutiliza o
 * MESMO grantPrivateLessonAttendance idempotente do caminho do webhook, de modo
 * que conceder manual e depois receber o webhook (ou vice-versa) nunca duplica
 * a presença nem o contador. */
// Secrets MP_MKT_SECRETS: necessários para o cancelamento best-effort do PIX
// em aberto quando a aula é marcada "paga em dinheiro" (auditoria, achado de
// double-charge) — getMpAccessToken pode precisar renovar o token OAuth.
exports.markPrivateLessonGiven = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Login required.');
  const { academyId, financialId, markPaidCash, staffName } = request.data || {};
  if (!academyId || !financialId) {
    throw new HttpsError('invalid-argument',
      'academyId e financialId são obrigatórios.');
  }
  // Granting the private-lesson presence writes an attendance doc server-side
  // (grantPrivateLessonAttendance, via the Admin SDK — bypasses Firestore
  // rules). To stay consistent with the attendance-create rule (admins always;
  // instructors need the grantable 'attendance:take'), enforce the same gate
  // here. Without this, an instructor without 'attendance:take' — who is blocked
  // from manual attendance on the client — could still mark presence through
  // this callable. Admins are unaffected; instructors who already mark
  // attendance carry the permission, so existing flows keep working.
  if (!(await staffCanWithPermission(
    request.auth.uid, academyId, 'attendance:take'))) {
    throw new HttpsError('permission-denied',
      'Apenas admin, ou professor com permissão de presença, pode conceder a presença.');
  }

  const finRef = db.doc(`academies/${academyId}/financials/${financialId}`);
  const snap = await finRef.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Cobrança não encontrada.');
  }
  const fin = snap.data();
  if (fin.type !== 'private_lesson') {
    throw new HttpsError('failed-precondition',
      'A cobrança não é uma aula particular.');
  }

  // Pagamento presencial em dinheiro: marca a cobrança como paga (cash) antes
  // de conceder a presença. Idempotente — só marca se ainda não estava paga.
  if (markPaidCash === true && fin.status !== 'paid') {
    // Auditoria (anti double-charge): marcar "pago em dinheiro" precisa MATAR o
    // PIX MP em aberto e LIMPAR os campos pix* do financial — espelha o que o
    // PaymentService.markAsPaid faz no cliente. Sem isso o PIX já enviado
    // continuava pagável e a família podia pagar de novo (cobrança dupla
    // silenciosa). Best-effort: cancela ANTES de marcar paga e nunca bloqueia o
    // mark-paid se o cancelamento falhar (reusa o cancelMpPix via helper).
    const pixPaymentId = fin.paymentGateway === 'mercadopago' &&
      fin.gatewayPaymentId && fin.pixCode ? fin.gatewayPaymentId : null;
    if (pixPaymentId) {
      await mpCancelPixPayment(academyId, pixPaymentId).catch((e) =>
        console.error('[markPrivateLessonGiven] cancel PIX falhou', e && e.message));
    }
    await finRef.update({
      status: 'paid',
      method: 'cash',
      paymentGateway: 'cash',
      paymentDate: admin.firestore.FieldValue.serverTimestamp(),
      // Limpa o PIX em aberto para que não seja mais exibido/pagável.
      pixCode: admin.firestore.FieldValue.delete(),
      pixQrCode: admin.firestore.FieldValue.delete(),
      pixTicketUrl: admin.firestore.FieldValue.delete(),
      pixExpiresAt: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  await grantPrivateLessonAttendance(academyId, financialId, fin, {
    verifiedBy: request.auth.uid,
    verifiedByName: (staffName && String(staffName).trim()) || 'Professor',
  });
  return { success: true };
});

// ---- Estorno / chargeback no marketplace (achado #16) ----------------------
// O MP re-notifica o MESMO payment id com status refunded/charged_back/
// cancelled quando um pagamento já liquidado é devolvido. Antes, qualquer
// status != 'approved' era ignorado: o financial/pedido ficava 'paid' para
// sempre, o estoque continuava decrementado e o admin nem ficava sabendo do
// chargeback. Só age quando o doc está 'paid' com o MESMO gatewayPaymentId —
// um PIX expirado ('cancelled') de doc pendente continua sendo no-op.
const MP_REVERSAL_STATUSES = ['refunded', 'charged_back', 'cancelled'];

/** Estorno de pagamento avulso (financial ou pedido da loja). Marca o doc como
 * 'refunded'/'chargeback', restaura o estoque do pedido (atômico: o flip do
 * status e os increments de estoque comitam na MESMA transação — restauração
 * exatamente-uma-vez, sem over-restore) e notifica o admin. Nunca relança para
 * o webhook. */
async function mpMktHandleReversal({ academyId, type, docId }, payment) {
  const chargeId = String(payment.id);
  const newStatus = payment.status === 'charged_back' ? 'chargeback' : 'refunded';
  const amount = Number(payment.transaction_amount) || 0; // REAIS
  const verb = newStatus === 'chargeback'
    ? 'contestado (chargeback)' : 'estornado';
  const refundEvent = {
    paymentId: chargeId,
    mpStatus: payment.status,
    statusDetail: payment.status_detail || null,
    amount,
    at: admin.firestore.Timestamp.now(),
  };

  if (type === 'order') {
    const orderRef = db.doc(`academies/${academyId}/storeOrders/${docId}`);
    // Auditoria MP (over-restore): a restauração do estoque agora roda DENTRO da
    // MESMA transação que vira o pedido para refunded/chargeback. O flip do
    // status e os increments de estoque comitam atomicamente juntos — eliminando
    // a janela pendente em que duas re-entregas concorrentes do webhook
    // restauravam o estoque em dobro. Re-entregas viram no-op (status já não é
    // 'paid'). Firestore exige TODAS as leituras antes das escritas: lemos o
    // pedido e, se for restaurar, os produtos, antes de qualquer update.
    const r = await db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) return { handled: false };
      const d = snap.data();
      if (d.status !== 'paid' || d.gatewayPaymentId !== chargeId) {
        // Já estornado (idempotente), re-entrega ou outro pagamento — não mexe.
        return { handled: false };
      }
      const willRestock = d.stockSettled !== false; // settle decrementou?
      // Pré-lê os produtos a restaurar (todas as leituras ANTES das escritas).
      const items = Array.isArray(d.items) ? d.items : [];
      const restores = [];
      if (willRestock) {
        for (const item of items) {
          const productRef =
            db.doc(`academies/${academyId}/storeProducts/${item.productId}`);
          const p = await tx.get(productRef);
          if (p.exists && p.data()?.stockType === 'in_stock') {
            restores.push({ ref: productRef, qty: Number(item.quantity) || 0 });
          }
        }
      }
      const update = {
        status: newStatus,
        refundedAt: FV.serverTimestamp(),
        refundEvent,
        updatedAt: FV.serverTimestamp(),
      };
      if (!willRestock) {
        // O decremento do settle NUNCA rodou (crash antes do loop): apenas marca
        // settled — efeito líquido nulo no estoque, e a re-entrega do 'approved'
        // não decrementa mais (doc não está 'paid').
        update.stockSettled = true;
      }
      tx.update(orderRef, update);
      // Increments de estoque na MESMA transação → restauração exatamente-uma-vez.
      for (const rst of restores) {
        tx.update(rst.ref, {
          stockQuantity: FV.increment(rst.qty),
          updatedAt: FV.serverTimestamp(),
        });
      }
      return { handled: true, restock: willRestock && restores.length > 0 };
    });
    if (r.handled) {
      const code = docId.slice(-6).toUpperCase();
      await notifyAdminCF(academyId, 'order_paid',
        newStatus === 'chargeback' ? 'Chargeback em pedido' : 'Pedido estornado',
        `Pedido #${code}: o pagamento de R$ ${amount.toFixed(2)} foi ${verb} ` +
        `no Mercado Pago.` +
        (r.restock ? ' O estoque foi restaurado — confira o pedido.'
          : ' Confira o pedido.'),
        { orderId: docId });
    }
    return;
  }

  // financial (mensalidade/cobrança avulsa)
  const finRef = db.doc(`academies/${academyId}/financials/${docId}`);
  const r = await db.runTransaction(async (tx) => {
    const snap = await tx.get(finRef);
    if (!snap.exists) return { handled: false };
    const d = snap.data();
    if (d.status !== 'paid' || d.gatewayPaymentId !== chargeId) {
      return { handled: false }; // já estornado (idempotente) ou outro pagamento
    }
    tx.update(finRef, {
      status: newStatus,
      refundedAt: FV.serverTimestamp(),
      refundEvent,
      updatedAt: FV.serverTimestamp(),
    });
    return { handled: true };
  });
  if (r.handled) {
    await notifyAdminCF(academyId, 'payment_received',
      newStatus === 'chargeback' ? 'Chargeback recebido' : 'Pagamento estornado',
      `Um pagamento de R$ ${amount.toFixed(2)} foi ${verb} no Mercado Pago. ` +
      `A cobranca foi marcada como estornada — confira no app.`,
      { financialId: docId });
  }
}

/**
 * Auditoria MP (estorno PARCIAL silencioso): o MP devolveu PARTE do valor mas o
 * pagamento continua 'approved' (transaction_amount_refunded entre 0 e o total).
 * NÃO desfaz o pagamento integral — só registra um refundEvent parcial no doc
 * (idempotente por (paymentId, valor acumulado refunded) via partialRefundKey) e
 * alerta o admin para conciliação, já que o doc seguiria refletindo o valor
 * cheio e a receita ficaria superestimada até a conferência manual. O doc precisa
 * estar 'paid' com o MESMO gatewayPaymentId. Best-effort; nunca relança ao MP.
 */
async function mpMktHandlePartialRefund({ academyId, type, docId }, payment, refundedAmount) {
  const chargeId = String(payment.id);
  const refunded = Number(refundedAmount) || 0; // REAIS
  const total = Number(payment.transaction_amount) || 0; // REAIS
  const docRef = type === 'order'
    ? db.doc(`academies/${academyId}/storeOrders/${docId}`)
    : db.doc(`academies/${academyId}/financials/${docId}`);
  // Chave idempotente: paymentId + valor acumulado devolvido (2 casas). Estornos
  // parciais sucessivos (refunded cresce) geram chaves distintas → cada degrau é
  // registrado uma vez; re-entregas do webhook com o mesmo total são no-op.
  const partialRefundKey = `${chargeId}:${refunded.toFixed(2)}`;
  const r = await db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    if (!snap.exists) return { handled: false };
    const d = snap.data();
    if (d.status !== 'paid' || d.gatewayPaymentId !== chargeId) {
      return { handled: false }; // outro pagamento, doc não pago, ou estado mudou
    }
    if (d.partialRefundKey === partialRefundKey) {
      return { handled: false }; // já registrado este degrau (idempotente)
    }
    tx.update(docRef, {
      partialRefundKey,
      partialRefundEvent: {
        paymentId: chargeId,
        refundedAmount: refunded,
        totalAmount: total,
        at: admin.firestore.Timestamp.now(),
      },
      updatedAt: FV.serverTimestamp(),
    });
    return { handled: true };
  });
  if (r.handled) {
    const target = type === 'order' ? { orderId: docId } : { financialId: docId };
    const notifType = type === 'order' ? 'order_paid' : 'payment_received';
    await notifyAdminCF(academyId, notifType,
      'Estorno parcial no Mercado Pago',
      `Foram devolvidos R$ ${refunded.toFixed(2)} de um pagamento de ` +
      `R$ ${total.toFixed(2)} (pagamento ${chargeId}). A cobranca segue marcada ` +
      `como paga pelo valor cheio — confira e concilie manualmente no Mercado Pago.`,
      target).catch((e) =>
      console.error('[mpMktHandlePartialRefund] notify falhou', docId, e.message));
  }
}

/** Estorno de um CICLO de assinatura: marca o financial determinístico
 * sub_{subId}_{paymentId} como 'refunded'/'chargeback' e REGRIDE chargesPaid
 * em 1 dentro da mesma transação.
 * DECISÃO (documentada): chargesPaid regride porque reflete ciclos
 * efetivamente pagos — sem regredir, um ciclo estornado contaria para
 * completar o termo sem o professor ter recebido. A regressão é idempotente
 * via flag chargesPaidReversed no próprio financial (re-entrega do webhook
 * não regride 2x); 'subscription_overcharge' nunca incrementou chargesPaid,
 * então não regride. O status da assinatura NÃO muda aqui (um sub
 * 'completed'/'cancelled' não volta às queries dos crons). */
async function mpSubHandleReversal(academyId, subscriptionId, payment) {
  const chargeId = String(payment.id);
  const newStatus = payment.status === 'charged_back' ? 'chargeback' : 'refunded';
  const finRef =
    db.doc(`academies/${academyId}/financials/sub_${subscriptionId}_${chargeId}`);
  const subRef = db.doc(`academies/${academyId}/subscriptions/${subscriptionId}`);
  const r = await db.runTransaction(async (tx) => {
    const [finDoc, subDoc] = await Promise.all([tx.get(finRef), tx.get(subRef)]);
    if (!finDoc.exists) return { handled: false }; // ciclo nunca liquidado aqui
    const fin = finDoc.data();
    if (fin.status !== 'paid') return { handled: false }; // já estornado
    const finUpdate = {
      status: newStatus,
      refundedAt: FV.serverTimestamp(),
      refundEvent: {
        paymentId: chargeId,
        mpStatus: payment.status,
        statusDetail: payment.status_detail || null,
        amount: Number(payment.transaction_amount) || 0, // REAIS
        at: admin.firestore.Timestamp.now(),
      },
      updatedAt: FV.serverTimestamp(),
    };
    if (subDoc.exists && fin.type === 'monthly_tuition' &&
        fin.chargesPaidReversed !== true &&
        (Number(subDoc.data().chargesPaid) || 0) > 0) {
      finUpdate.chargesPaidReversed = true;
      tx.update(subRef, {
        chargesPaid: FV.increment(-1),
        lastEvent: 'cycle_refunded',
        updatedAt: FV.serverTimestamp(),
      });
    }
    tx.update(finRef, finUpdate);
    return { handled: true, amount: Number(fin.amount) || 0 };
  });
  if (!r.handled) return;
  try {
    await notifyAdminCF(academyId, 'payment_overdue',
      newStatus === 'chargeback'
        ? 'Chargeback em assinatura' : 'Ciclo de assinatura estornado',
      `Uma cobranca de assinatura de R$ ${r.amount.toFixed(2)} foi ` +
      `${newStatus === 'chargeback' ? 'contestada (chargeback)' : 'estornada'} ` +
      `no Mercado Pago. Confira a assinatura do aluno.`,
      { subscriptionId });
  } catch (_) { /* notify is best-effort */ }
}

// ============================================================
// Resiliência de Recorrência — Cloud Functions agendadas (crons)
// ============================================================
// Seguem o molde de iteração de scheduledOverdueCheck (:870): try/catch POR
// academia (uma falha NUNCA aborta o lote) e são idempotentes — seguras para
// re-rodar. Declaradas em v2 onSchedule({ schedule, timeZone, secrets }) —
// mesmo runtime/secrets das callables MP (v2), não o gen1 das demais crons.
//
// IMPORTANTE — credenciais do Mercado Pago: os secrets MP_OAUTH_CLIENT_ID/SECRET
// vivem no Secret Manager (MP_MKT_SECRETS) e SÓ são injetados em process.env
// quando declarados na própria função. As callables fazem isso via
// onCall({ secrets: MP_MKT_SECRETS }); estas crons fazem o equivalente via
// onSchedule({ ..., secrets: MP_MKT_SECRETS }). Sem esse bind, o branch de
// refresh de getMpAccessToken leria client_id/secret undefined, falharia o
// /oauth/token e marcaria a academia mpNeedsReauth indevidamente.

/** Notifica o ALUNO (ou o responsável, p/ menores) de uma assinatura — push +
 * notificação interna. Best-effort: nunca lança. */
async function notifySubscriptionStudent(academyId, sub, type, title, message, options) {
  try {
    const uid = await getBillingRecipientUid(sub.studentId, academyId);
    if (!uid) return;
    await sendToUser(uid, title, message, {
      type, academyId,
      category: 'financial', // sempre notificado — ver comentário no gate acima
      actionUrl: '/portal/financeiro',
    });
    await createInternalNotification(academyId, uid, type, 'high', title, message, {
      actionUrl: '/portal/financeiro', actionLabel: 'Atualizar cartão',
      studentId: sub.studentId, expiresInDays: 30,
      ...(options || {}),
    });
  } catch (e) {
    console.error('[notifySubscriptionStudent] erro', e.message);
  }
}

/** Resolve o fim do termo de uma assinatura com fallback legacy:
 * termEndsAt ?? (createdAt + months meses). Retorna Date ou null. */
function subscriptionTermEndDate(sub) {
  if (sub.termEndsAt && typeof sub.termEndsAt.toDate === 'function') {
    return sub.termEndsAt.toDate();
  }
  const months = Number(sub.months) || 0;
  if (months <= 0) return null;
  const ts = computeTermEndsAt(sub.createdAt, months);
  return ts ? ts.toDate() : null;
}

// ---- Escala das crons ------------------------------------------------------
// As 4 crons de assinatura faziam full-scan sequencial de `academies` com o
// timeout default do v2 (60s) — com crescimento, as MESMAS academias do fim do
// snapshot nunca rodariam. Mitigação pragmática (sem collectionGroup → sem
// índice novo): filtro por mpConnected==true (gravado pelo OAuth connect/
// disconnect), lotes concorrentes pequenos e timeoutSeconds:540 nas crons.
const CRON_ACADEMY_BATCH = 5;

/** Itera as academias com Mercado Pago conectado (mpConnected==true) em lotes
 * concorrentes de CRON_ACADEMY_BATCH via Promise.allSettled — uma academia que
 * falha não derruba o lote (mesma isolação do try/catch por academia). O
 * handler pode retornar 'skipped' quando não há nada a fazer. Ao final, loga o
 * placar processadas/puladas/falhas. */
async function forEachMpAcademy(label, handler) {
  const snap = await db.collection('academies')
    .where('mpConnected', '==', true)
    .get();
  let processed = 0;
  let skipped = 0;
  let failed = 0;
  for (let i = 0; i < snap.docs.length; i += CRON_ACADEMY_BATCH) {
    const batch = snap.docs.slice(i, i + CRON_ACADEMY_BATCH);
    const results = await Promise.allSettled(batch.map((d) => handler(d)));
    results.forEach((r, idx) => {
      if (r.status === 'fulfilled') {
        if (r.value === 'skipped') skipped += 1;
        else processed += 1;
      } else {
        failed += 1;
        console.error(`[${label}] academia falhou`, batch[idx].id,
          (r.reason && r.reason.message) || r.reason);
      }
    });
  }
  console.log(`[${label}] done — academias: ${processed} processadas, ` +
    `${skipped} puladas, ${failed} falhas`);
}

// Paginação do search de authorized_payments: o MP retorna só a primeira
// página por default — ciclos além dela nunca seriam liquidados (e o termGuard
// poderia 'completar' por data perdendo financials para sempre). Teto de
// segurança de MP_AP_SEARCH_MAX_PAGES páginas contra paging.total inconsistente.
const MP_AP_SEARCH_LIMIT = 50;
const MP_AP_SEARCH_MAX_PAGES = 20;

/** Busca TODOS os authorized_payments de um preapproval, paginando o search do
 * MP via limit/offset até cobrir paging.total. Retorna a lista concatenada. */
async function mpSearchAllAuthorizedPayments(token, preapprovalId) {
  const all = [];
  let offset = 0;
  for (let page = 0; page < MP_AP_SEARCH_MAX_PAGES; page += 1) {
    const search = await mpRequest('GET',
      `/authorized_payments/search?preapproval_id=${preapprovalId}` +
      `&limit=${MP_AP_SEARCH_LIMIT}&offset=${offset}`, { token });
    const results = (search && (search.results || search.elements)) || [];
    all.push(...results);
    offset += results.length;
    const total = search && search.paging ? Number(search.paging.total) : NaN;
    if (results.length === 0 || results.length < MP_AP_SEARCH_LIMIT ||
        (Number.isFinite(total) && offset >= total)) {
      break;
    }
  }
  return all;
}

// ---- 4. scheduledSubscriptionTermGuard ------------------------------------
// Rede de segurança: cancela o preapproval + marca `completed` quando a
// assinatura atingiu N meses, caso o webhook do último ciclo se perca.
// Idempotente: nunca rebaixa uma assinatura já `completed`.
exports.scheduledSubscriptionTermGuard = onSchedule(
  { schedule: '15 6 * * *', timeZone: 'America/Sao_Paulo',
    timeoutSeconds: 540, secrets: MP_MKT_SECRETS },
  async () => {
    console.log('[termGuard] start');
    const now = new Date();

    await forEachMpAcademy('termGuard', async (academyDoc) => {
      const academyId = academyDoc.id;
      let token = null; // lazy: só busca MP se houver algo a cancelar
      const subsSnap = await db
        .collection(`academies/${academyId}/subscriptions`)
        .where('status', 'in', ['authorized', 'paused'])
        .get();
      if (subsSnap.empty) return 'skipped';

      for (const subDoc of subsSnap.docs) {
        const sub = subDoc.data();
        if (sub.status === 'completed') continue; // nunca rebaixa
        const months = Number(sub.months) || 0;
        if (months <= 0) continue; // open-ended: sem termo

        const chargesPaid = Number(sub.chargesPaid) || 0;
        const termEnd = subscriptionTermEndDate(sub);
        const reachedByCharges = chargesPaid >= months;
        // Backstop por DATA com folga: só serve de rede de segurança quando o
        // webhook do último ciclo se perdeu. Damos ~1 ciclo de margem (35d) além
        // do termo para não cancelar antes da última cobrança quando o billing
        // foi adiado (billing_day + billing_day_proportional:false). A conclusão
        // real é por CONTAGEM (chargesPaid>=months); a data é só fallback.
        const dateBackstop = termEnd != null &&
          now.getTime() >= termEnd.getTime() + TERM_GUARD_SLACK_MS;
        // Entra no fluxo (drenar + possivelmente completar) se bateu a contagem
        // OU se passou do backstop por data. A decisão FINAL de 'completed' é
        // tomada depois da drenagem, sobre os dados re-lidos (freshSnap).
        if (!reachedByCharges && !dateBackstop) continue;

        // INTEGRIDADE FINANCEIRA: antes de cancelar o preapproval, DRENA os
        // authorized_payments aprovados ainda não liquidados. Sem isso, se o
        // webhook do último ciclo se perdeu (reachedByDate, chargesPaid<months)
        // e a janela do reconcile (>48h) ainda não passou, a academia perde o
        // financial 'paid' do último ciclo. mpSubSettleCycle é idempotente
        // (id determinístico sub_{}_{}), então re-rodar é seguro.
        if (sub.mpPreapprovalId) {
          try {
            if (!token) token = await getMpAccessToken(academyId);
            const results = await mpSearchAllAuthorizedPayments(
              token, sub.mpPreapprovalId).catch((e) => {
                console.error('[termGuard] search ap falhou', academyId,
                  subDoc.id, e.message);
                return [];
              });
            for (const ap of results) {
              const payStatus = ap.payment && ap.payment.status;
              if (payStatus !== 'approved') continue;
              const paymentId = ap.payment && ap.payment.id
                ? String(ap.payment.id) : `ap_${ap.id}`;
              const apAmount = Number(ap.transaction_amount) || 0;
              await mpSubSettleCycle(academyId, subDoc.id, token, {
                paymentId, amount: apAmount, mpPayload: ap,
                // Data real da cobrança: a drenagem roda DEPOIS do ciclo —
                // sem isso o financial cairia no mês do settle.
                chargeDate: (ap.payment && ap.payment.date_approved) ||
                  ap.debit_date || ap.date_created,
              });
            }
          } catch (e) {
            console.error('[termGuard] drenar ap falhou', academyId,
              subDoc.id, e.message);
          }
        }

        // Re-lê o estado APÓS a drenagem: mpSubSettleCycle pode ter liquidado o
        // último ciclo (e até completado/cancelado a assinatura), e bumpou
        // chargesPaid. Toda a decisão abaixo usa freshSnap (não o `sub` stale),
        // evitando re-cancelar/rebaixar e evitando clobber de uma transição
        // concorrente.
        const freshSnap = await subDoc.ref.get();
        if (!freshSnap.exists || freshSnap.data().status === 'completed') {
          continue;
        }
        const fresh = freshSnap.data();
        const freshCharges = Number(fresh.chargesPaid) || 0;
        const freshPreapprovalId = fresh.mpPreapprovalId;

        // CONCLUSÃO: primariamente por CONTAGEM. A data é só backstop tardio (já
        // com a folga TERM_GUARD_SLACK_MS aplicada na entrada). NUNCA completar
        // uma assinatura que não pagou NENHUM ciclo (freshCharges===0) apenas por
        // data — deixa o dunning seguir; só a contagem pode concluí-la. Isso
        // cobre assinaturas nunca-pagas (inclusive 'paused') que de outra forma
        // seriam marcadas 'completed' por mera passagem de tempo.
        const completeByCharges = freshCharges >= months;
        if (!completeByCharges && freshCharges === 0) {
          continue; // nunca-paga: não concluir por data, segue o dunning
        }

        // Atingiu o termo → cancela no MP e SÓ marca completed quando o MP
        // confirmar (PUT ok, ou GET = cancelled). Em falha, mantém o status
        // atual (authorized/paused) + termCancelPending: como a sub continua
        // nas queries deste cron e chargesPaid >= months, o próximo run
        // re-tenta o cancel até suceder.
        let mpCancelled = !freshPreapprovalId; // sem preapproval: nada a cancelar
        if (freshPreapprovalId) {
          try {
            if (!token) token = await getMpAccessToken(academyId);
            await mpRequest('PUT', `/preapproval/${freshPreapprovalId}`,
              { token, body: { status: 'cancelled' } });
            mpCancelled = true;
          } catch (e) {
            console.error('[termGuard] cancel preapproval falhou', academyId,
              subDoc.id, e.message);
            // PUT pode falhar com o preapproval JÁ cancelado — confirma via GET.
            try {
              if (token) {
                const pa = await mpRequest('GET',
                  `/preapproval/${freshPreapprovalId}`, { token });
                mpCancelled = !!pa && pa.status === 'cancelled';
              }
            } catch (_) { /* mantém mpCancelled = false */ }
          }
        }
        if (!mpCancelled) {
          await subDoc.ref.update({
            termCancelPending: true,
            lastEvent: 'term_cancel_failed',
            updatedAt: FV.serverTimestamp(),
          });
          console.log('[termGuard] cancel pendente (MP nao confirmou)',
            academyId, subDoc.id);
          continue;
        }
        // TÉRMINO COM INADIMPLÊNCIA VISÍVEL: se completou pelo backstop por
        // DATA com pagamento parcial (0 < freshCharges < months), mantém o
        // status 'completed' (compatível com as queries existentes) mas marca
        // termShortfall + lastEvent dedicado e avisa o admin — o professor não
        // perde a distinção entre "aluno quitou" e "pagou N de M e sumiu".
        const termShortfall = completeByCharges
          ? 0 : Math.max(0, months - freshCharges);
        const completedUpdate = {
          status: 'completed',
          termCancelPending: FV.delete(),
          lastEvent: termShortfall > 0
            ? 'term_expired_shortfall' : 'term_completed_guard',
          updatedAt: FV.serverTimestamp(),
        };
        if (termShortfall > 0) completedUpdate.termShortfall = termShortfall;
        await subDoc.ref.update(completedUpdate);
        if (termShortfall > 0) {
          try {
            await notifyAdminCF(academyId, 'payment_overdue',
              'Assinatura encerrada com ciclos em aberto',
              `A assinatura de ${fresh.studentName || 'um aluno'} chegou ao ` +
              `fim do prazo com ${termShortfall} de ${months} ciclo(s) sem ` +
              'pagamento. Avalie a cobranca dos valores em aberto.',
              { subscriptionId: subDoc.id });
          } catch (_) { /* best-effort */ }
        }
        console.log('[termGuard] completed', academyId, subDoc.id,
          'charges', freshCharges, 'byCharges', completeByCharges,
          'shortfall', termShortfall);
      }
    });
    return null;
  });

// ---- 5. scheduledSubscriptionReconcile ------------------------------------
// Recupera webhooks perdidos: para assinaturas `authorized` com nextBillingDate
// vencida há >48h e sem `financials` novo do ciclo, re-sincroniza via
// GET /preapproval e liquida os authorized_payments aprovados via
// mpSubSettleCycle (idempotente por id determinístico). A cada 6h.
exports.scheduledSubscriptionReconcile = onSchedule(
  { schedule: '0 */6 * * *', timeZone: 'America/Sao_Paulo',
    timeoutSeconds: 540, secrets: MP_MKT_SECRETS },
  async () => {
    console.log('[reconcile] start');
    const now = Date.now();
    const STALE_MS = 48 * 60 * 60 * 1000;

    await forEachMpAcademy('reconcile', async (academyDoc) => {
      const academyId = academyDoc.id;
      const subsSnap = await db
        .collection(`academies/${academyId}/subscriptions`)
        .where('status', 'in', ['authorized', 'paused'])
        .get();
      if (subsSnap.empty) return 'skipped';

      let token = null;
      for (const subDoc of subsSnap.docs) {
        const sub = subDoc.data();
        if (!sub.mpPreapprovalId) continue;
        const nextBilling = sub.nextBillingDate &&
          typeof sub.nextBillingDate.toDate === 'function'
          ? sub.nextBillingDate.toDate().getTime() : null;
        // `authorized` só reconcilia quando a cobrança já deveria ter ocorrido
        // há >48h. `paused` SEMPRE reconcilia (buraco de cobertura: uma
        // assinatura pausada no MP cujo webhook se perdeu pode nunca entrar em
        // dunning se nextBillingDate local ainda <48h vencida ou dessincronizada
        // — precisamos garantir needsReauth=true para o dunning pegar).
        if (sub.status === 'authorized' &&
            (nextBilling == null || now - nextBilling <= STALE_MS)) continue;

        try {
          if (!token) token = await getMpAccessToken(academyId);

          // 1) Re-sync do status + próxima cobrança a partir do preapproval.
          const pa = await mpRequest('GET',
            `/preapproval/${sub.mpPreapprovalId}`, { token });
          const map = { authorized: 'authorized', paused: 'paused',
            cancelled: 'cancelled', pending: 'pending' };
          const syncUpdate = {
            lastEvent: 'reconcile_resync',
            updatedAt: FV.serverTimestamp(),
          };
          if (sub.status !== 'completed' && map[pa.status]) {
            syncUpdate.status = map[pa.status];
            // Pausa INTENCIONAL do aluno (pausedBy:'user') NÃO entra em
            // dunning — sem needsReauth/nextRetryAt, senão o dunning
            // reativaria a cobrança sem consentimento.
            if (pa.status === 'paused' && sub.pausedBy !== 'user') {
              if (isLegacyUserPause(sub)) {
                // Dados legados: o pauseMpSubscription antigo não gravava
                // pausedBy — backfill em vez de iniciar dunning.
                syncUpdate.pausedBy = 'user';
              } else {
                syncUpdate.needsReauth = true;
                syncUpdate.lastFailureAt = FV.serverTimestamp();
                if (sub.nextRetryAt == null) {
                  syncUpdate.nextRetryAt = admin.firestore.Timestamp.fromMillis(
                    Date.now() + DUNNING_BACKOFF_DAYS[0] * 24 * 60 * 60 * 1000);
                }
              }
            }
            // MP cobrando de novo → a pausa intencional (se havia) acabou.
            if (pa.status === 'authorized') {
              syncUpdate.pausedBy = FV.delete();
            }
          }
          if (pa.next_payment_date) {
            syncUpdate.nextBillingDate = admin.firestore.Timestamp.fromDate(
              new Date(pa.next_payment_date));
          }
          await subDoc.ref.update(syncUpdate);

          // 2) Liquida authorized_payments aprovados ainda não liquidados.
          //    mpSubSettleCycle é idempotente (id determinístico sub_{}_{}).
          const results = await mpSearchAllAuthorizedPayments(
            token, sub.mpPreapprovalId).catch((e) => {
              console.error('[reconcile] search ap falhou', academyId,
                subDoc.id, e.message);
              return [];
            });
          for (const ap of results) {
            const payStatus = ap.payment && ap.payment.status;
            if (payStatus !== 'approved') continue;
            const paymentId = ap.payment && ap.payment.id
              ? String(ap.payment.id) : `ap_${ap.id}`;
            const amount = Number(ap.transaction_amount) || 0;
            await mpSubSettleCycle(academyId, subDoc.id, token, {
              paymentId, amount, mpPayload: ap,
              // Data real da cobrança: o reconcile age >48h após o ciclo —
              // sem isso o financial cairia no mês do settle.
              chargeDate: (ap.payment && ap.payment.date_approved) ||
                ap.debit_date || ap.date_created,
            });
          }
        } catch (e) {
          console.error('[reconcile] assinatura falhou', academyId,
            subDoc.id, e.message);
        }
      }
    });
    return null;
  });

// ---- 6. scheduledSubscriptionDunning --------------------------------------
// Retry automático de assinaturas `paused`/needsReauth: MAX 3 tentativas com
// backoff [1,3,7] dias a partir da falha. Após esgotar, mantém `paused` e
// notifica admin + aluno (NÃO cancela). Diário.
exports.scheduledSubscriptionDunning = onSchedule(
  { schedule: '30 6 * * *', timeZone: 'America/Sao_Paulo',
    timeoutSeconds: 540, secrets: MP_MKT_SECRETS },
  async () => {
    console.log('[dunning] start');
    const now = Date.now();

    await forEachMpAcademy('dunning', async (academyDoc) => {
      const academyId = academyDoc.id;
      const subsSnap = await db
        .collection(`academies/${academyId}/subscriptions`)
        .where('status', '==', 'paused')
        .get();
      if (subsSnap.empty) return 'skipped';

      let token = null;
      for (const subDoc of subsSnap.docs) {
        const sub = subDoc.data();
        // Pausa INTENCIONAL do aluno: NUNCA reativar o preapproval por cron —
        // só o próprio aluno retoma (resumeMpSubscription / troca de cartão).
        if (sub.pausedBy === 'user') continue;
        if (sub.needsReauth !== true) continue;
        if (!sub.mpPreapprovalId) continue;
        const failedAttempts = Number(sub.failedAttempts) || 0;

        // Esgotou as tentativas → para de tentar e notifica (uma vez).
        // Idempotência da notificação via campo DEDICADO
        // (dunningExhaustedNotifiedAt), desacoplada do gatilho nextRetryAt —
        // nextRetryAt cuida só do backoff, não de "já notifiquei a suspensão".
        if (failedAttempts >= MAX_DUNNING_RETRIES) {
          if (sub.dunningExhaustedNotifiedAt == null) {
            await subDoc.ref.update({
              nextRetryAt: null,
              dunningExhaustedNotifiedAt: FV.serverTimestamp(),
              lastEvent: 'dunning_exhausted',
              updatedAt: FV.serverTimestamp(),
            });
            try {
              await notifyAdminCF(academyId, 'payment_overdue',
                'Assinatura suspensa',
                `A cobranca recorrente de ${sub.studentName || 'um aluno'} ` +
                'falhou apos 3 tentativas. Peca a atualizacao do cartao.',
                { subscriptionId: subDoc.id });
            } catch (_) { /* best-effort */ }
            await notifySubscriptionStudent(academyId, sub, 'payment_overdue',
              'Atualize seu cartao',
              'Sua assinatura foi suspensa apos varias tentativas de cobranca. ' +
              'Atualize o cartao para reativar.',
              { subscriptionId: subDoc.id });
          }
          continue;
        }

        // Ainda há tentativas: respeita o backoff (nextRetryAt). Na 1ª
        // tentativa nextRetryAt pode ser nulo → tenta imediatamente.
        const retryAt = sub.nextRetryAt &&
          typeof sub.nextRetryAt.toDate === 'function'
          ? sub.nextRetryAt.toDate().getTime() : null;
        if (retryAt != null && now < retryAt) continue;

        const attemptN = failedAttempts + 1; // 1..3
        let reactivated = false;
        try {
          if (!token) token = await getMpAccessToken(academyId);
          await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
            { token, body: { status: 'authorized' } });
          reactivated = true;
        } catch (e) {
          console.error('[dunning] reativar falhou', academyId, subDoc.id,
            e.message);
        }

        if (!reactivated) {
          // Falha TRANSITÓRIA de chamada (throw/5xx/timeout no PUT, refresh de
          // token, etc.) — NÃO é um ciclo de cobrança recusado. Não consome a
          // tentativa nem avança o backoff: deixamos o estado intacto e o
          // próximo run (a isolação por academia segue valendo) tenta de novo.
          // Assim `failedAttempts` representa ciclos de cobrança falhos, não
          // falhas de API, e 3 indisponibilidades não suspendem quem paga.
          console.log('[dunning] reativacao falhou (transitorio), tentativa NAO ' +
            'consumida', academyId, subDoc.id, 'attempt', attemptN);
          continue;
        }

        // Reativação aceita pelo MP → conta como tentativa do ciclo. Backoff
        // para a PRÓXIMA tentativa: índice attemptN..MAX, cap no fim.
        const backoffIdx = Math.min(attemptN, DUNNING_BACKOFF_DAYS.length - 1);
        const nextRetry = admin.firestore.Timestamp.fromMillis(
          now + DUNNING_BACKOFF_DAYS[backoffIdx] * 24 * 60 * 60 * 1000);
        // TRANSAÇÃO, não update cego: entre o PUT authorized e este write o
        // MP pode disparar webhooks que já resetaram o estado (sync/settle →
        // 'authorized' + failedAttempts:0, ou pausa intencional do aluno).
        // Só grava o estado de dunning se a assinatura AINDA está no ciclo
        // esperado ('paused' + needsReauth, não pausada pelo aluno) — se o
        // webhook já reativou, não regride com contador fantasma.
        await db.runTransaction(async (txn) => {
          const freshSnap = await txn.get(subDoc.ref);
          if (!freshSnap.exists) return;
          const fresh = freshSnap.data();
          if (fresh.status !== 'paused' || fresh.needsReauth !== true ||
              fresh.pausedBy === 'user') {
            console.log('[dunning] estado mudou durante o retry — write de ' +
              'dunning ignorado', academyId, subDoc.id, fresh.status);
            return;
          }
          txn.update(subDoc.ref, {
            failedAttempts: attemptN,
            lastFailureAt: FV.serverTimestamp(),
            nextRetryAt: nextRetry,
            lastEvent: 'dunning_retry_sent',
            updatedAt: FV.serverTimestamp(),
          });
        });
        // A reativação foi aceita; o webhook do próximo authorized_payment
        // confirma (e mpSubSettleCycle zera failedAttempts ao aprovar).
        console.log('[dunning] retry', academyId, subDoc.id, 'attempt', attemptN,
          'reactivated', reactivated);
      }
    });
    return null;
  });

// ---- 7. scheduledCardExpiryWarning ----------------------------------------
// Avisa o aluno quando o cartão da assinatura expira no MÊS CORRENTE, ANTES do
// billing_day, uma única vez por mês (expiryNotifiedAt). Diário.
exports.scheduledCardExpiryWarning = onSchedule(
  { schedule: '45 6 * * *', timeZone: 'America/Sao_Paulo',
    timeoutSeconds: 540, secrets: MP_MKT_SECRETS },
  async () => {
    console.log('[cardExpiry] start');
    const now = new Date();
    const curYear = now.getFullYear();
    const curMonth = now.getMonth() + 1; // 1..12
    const curDay = now.getDate();

    await forEachMpAcademy('cardExpiry', async (academyDoc) => {
      const academyId = academyDoc.id;
      const subsSnap = await db
        .collection(`academies/${academyId}/subscriptions`)
        .where('status', '==', 'authorized')
        .get();
      if (subsSnap.empty) return 'skipped';

      for (const subDoc of subsSnap.docs) {
        const sub = subDoc.data();
        const expMonth = Number(sub.cardExpMonth) || 0;
        const expYear = Number(sub.cardExpYear) || 0;
        if (!(expMonth >= 1 && expMonth <= 12) || expYear < 2000) continue;

        // ANTECEDÊNCIA: o cartão é válido até o FIM do mês expMonth/expYear, então
        // avisar só no mês exato da expiração chega tarde (a cobrança do próprio
        // mês pode já ter sido recusada). Avisamos quando faltam <= ~40 dias para
        // o fim da validade — ou seja, quando estamos no mês da expiração OU no
        // mês anterior. Usamos índice ano*12+mês para comparar meses linearmente.
        const curIdx = curYear * 12 + curMonth;
        const expIdx = expYear * 12 + expMonth;
        const monthsUntilExpiry = expIdx - curIdx; // 0 = expira este mês
        // Já expirou (monthsUntilExpiry<0) → ainda assim avisa (cartão vencido).
        // Só pula quando ainda falta mais de 1 mês para o mês de expiração.
        if (monthsUntilExpiry > 1) continue;
        // Avisar ANTES do billing_day (depois disso a cobrança já tentou neste
        // ciclo); só relevante quando o aviso e a cobrança caem no mesmo mês.
        const billingDay = Number(sub.billingDay) || 1;
        if (monthsUntilExpiry <= 0 && curDay >= billingDay) continue;

        // Já avisamos NESTE mês? (expiryNotifiedAt no mesmo ano/mês).
        const notified = sub.expiryNotifiedAt &&
          typeof sub.expiryNotifiedAt.toDate === 'function'
          ? sub.expiryNotifiedAt.toDate() : null;
        if (notified && notified.getFullYear() === curYear &&
            notified.getMonth() + 1 === curMonth) continue;

        await notifySubscriptionStudent(academyId, sub, 'card_expiring',
          'Cartao prestes a expirar',
          'O cartao da sua assinatura expira este mes. Atualize-o antes da ' +
          'proxima cobranca para nao perder o acesso.',
          { subscriptionId: subDoc.id });
        await subDoc.ref.update({
          expiryNotifiedAt: FV.serverTimestamp(),
          updatedAt: FV.serverTimestamp(),
        });
        console.log('[cardExpiry] avisado', academyId, subDoc.id);
      }
    });
    return null;
  });

// ===========================================================================
// A1 — Reserva de aula com vaga + lista de espera (class booking)
// Capacity + waitlist are server-authoritative: ALL writes to classOccurrences
// and classBookings happen here (Firestore rules deny client writes), so the
// counter can never be tampered with. The client only reads them.
// ===========================================================================

const DAY_MS = 24 * 60 * 60 * 1000;
const BOOKING_DEFAULTS = {
  windowDays: 7,
  cancelCutoffMinutes: 60,
  maxActiveBookingsPerStudent: 3,
};

/// "HH:mm" -> minutes since midnight (0 on malformed). Mirrors the Dart helper.
function bk_hmToMinutes(hm) {
  const parts = String(hm || '').split(':');
  if (parts.length !== 2) return 0;
  return (parseInt(parts[0], 10) || 0) * 60 + (parseInt(parts[1], 10) || 0);
}

/// "HH:mm" -> "HHmm" normalized via minutes (so "9:5" -> "0905"). Mirrors Dart.
function bk_hmCompact(hm) {
  const mins = bk_hmToMinutes(hm);
  const h = String(Math.floor(mins / 60)).padStart(2, '0');
  const m = String(mins % 60).padStart(2, '0');
  return `${h}${m}`;
}

/// 0=Sun..6=Sat for a yyyyMMdd string, computed in UTC (date-only, TZ-safe).
function bk_weekdayFromDateStr(date) {
  const y = parseInt(date.slice(0, 4), 10);
  const mo = parseInt(date.slice(4, 6), 10);
  const d = parseInt(date.slice(6, 8), 10);
  return new Date(Date.UTC(y, mo - 1, d)).getUTCDay();
}

/// True when 2+ schedule slots fall on the same weekday (occ-id disambiguation).
function bk_hasMultiPerDay(schedule) {
  const seen = new Set();
  for (const s of schedule || []) {
    if (seen.has(s.dayOfWeek)) return true;
    seen.add(s.dayOfWeek);
  }
  return false;
}

/// Deterministic occurrence id — must match `class_occurrences.dart`.
function bk_occurrenceId(classId, date, startTime, multiPerDay) {
  const base = `${classId}_${date}`;
  return multiPerDay ? `${base}_${bk_hmCompact(startTime)}` : base;
}

/// Resolves the caller's relationship to the target student, or throws.
/// Uses getUserAcademyMembership(uid, academyId) — NOT getUserAcademyInfo — so
/// multi-academy members (cujo academyId selecionado != primário) não são
/// barrados ao reservar/cancelar na academia em que estão de fato matriculados.
async function bk_resolvePermission(uid, academyId, studentId) {
  const info = await getUserAcademyMembership(uid, academyId);
  if (!info) {
    throw new HttpsError('permission-denied', 'Access denied: invalid academy');
  }
  const isStaff = info.role === 'admin' || info.role === 'instructor';
  if (isStaff) return { isStaff: true, bookedBy: 'staff' };
  if (info.studentId && info.studentId === studentId) {
    return { isStaff: false, bookedBy: 'self' };
  }
  // Responsible adult booking for a dependent.
  const stuSnap = await db.doc(`academies/${academyId}/students/${studentId}`).get();
  if (stuSnap.exists && stuSnap.data()?.responsibleUserId === uid) {
    return { isStaff: false, bookedBy: 'responsible' };
  }
  throw new HttpsError('permission-denied', 'Access denied: cannot book for another student');
}

async function bk_loadBookingConfig(academyId) {
  const snap = await db.doc(`academies/${academyId}`).get();
  const d = snap.data() || {};
  return {
    enabled: d.bookingEnabled === true,
    windowDays: Number.isFinite(d.bookingWindowDays) ? d.bookingWindowDays : BOOKING_DEFAULTS.windowDays,
    cancelCutoffMinutes: Number.isFinite(d.bookingCancelCutoffMinutes)
      ? d.bookingCancelCutoffMinutes : BOOKING_DEFAULTS.cancelCutoffMinutes,
    maxActive: Number.isFinite(d.maxActiveBookingsPerStudent)
      ? d.maxActiveBookingsPerStudent : BOOKING_DEFAULTS.maxActiveBookingsPerStudent,
  };
}

exports.reserveClassSlot = onCall(async (request) => {
  const { auth } = request;
  if (!auth) throw new HttpsError('unauthenticated', 'Login required.');
  const data = request.data || {};
  const { academyId, classId, date, startTime, studentId, slotStartMillis } = data;
  if (!academyId || !classId || !date || !startTime || !studentId || !slotStartMillis) {
    throw new HttpsError('invalid-argument',
      'Missing required fields: academyId, classId, date, startTime, studentId, slotStartMillis');
  }

  const perm = await bk_resolvePermission(auth.uid, academyId, studentId);
  const cfg = await bk_loadBookingConfig(academyId);
  if (!cfg.enabled && !perm.isStaff) {
    throw new HttpsError('failed-precondition', 'Booking is disabled for this academy.');
  }

  const classRef = db.doc(`academies/${academyId}/classes/${classId}`);
  const classSnap = await classRef.get();
  if (!classSnap.exists) throw new HttpsError('not-found', 'Class not found.');
  const cls = classSnap.data();
  if (cls.isActive === false) {
    throw new HttpsError('failed-precondition', 'Class is not active.');
  }

  // The requested slot must exist in the weekly schedule.
  const dow = bk_weekdayFromDateStr(date);
  const schedule = Array.isArray(cls.schedule) ? cls.schedule : [];
  const slot = schedule.find((s) => s.dayOfWeek === dow && s.startTime === startTime);
  if (!slot) throw new HttpsError('invalid-argument', 'No class slot at that day/time.');

  const now = Date.now();
  const multiPerDay = bk_hasMultiPerDay(schedule);
  const occId = bk_occurrenceId(classId, date, startTime, multiPerDay);
  const occRef = db.doc(`academies/${academyId}/classOccurrences/${occId}`);
  const bookingRef = db.doc(`academies/${academyId}/classBookings/${occId}__${studentId}`);

  // Idempotency BEFORE the limit check: re-reserving an existing active booking
  // is a no-op and must never trip the per-student limit (the booking is one of
  // the counted ones). The transaction re-checks this authoritatively.
  const existing = await bookingRef.get();
  if (existing.exists && existing.data().status !== 'cancelled') {
    return { status: existing.data().status, position: 0 };
  }

  if (!perm.isStaff) {
    if (slotStartMillis <= now) {
      throw new HttpsError('failed-precondition', 'Class already started.');
    }
    if (slotStartMillis > now + (cfg.windowDays + 1) * DAY_MS) {
      throw new HttpsError('failed-precondition', `Booking window is ${cfg.windowDays} days.`);
    }
    // Eligibility mirrors the QR self-check-in rule: enrolled, explicitly open,
    // or no roster at all (empty/absent studentIds => open class).
    const roster = Array.isArray(cls.studentIds) ? cls.studentIds : [];
    const eligible = cls.isOpenClass === true || roster.length === 0 || roster.includes(studentId);
    if (!eligible) {
      throw new HttpsError('permission-denied', 'Student is not eligible for this class.');
    }
    // Per-student active future bookings limit.
    const activeSnap = await db.collection(`academies/${academyId}/classBookings`)
      .where('studentId', '==', studentId)
      .where('status', 'in', ['confirmed', 'waitlist'])
      .where('slotStart', '>=', admin.firestore.Timestamp.fromMillis(now))
      .get();
    if (activeSnap.size >= cfg.maxActive) {
      throw new HttpsError('failed-precondition',
        `Limite de ${cfg.maxActive} reservas ativas atingido.`);
    }
  }

  const stuSnap = await db.doc(`academies/${academyId}/students/${studentId}`).get();
  const studentName = stuSnap.data()?.fullName || '';
  const maxStudents = Number.isFinite(cls.maxStudents) ? cls.maxStudents : null;
  const slotStartTs = admin.firestore.Timestamp.fromMillis(slotStartMillis);

  return db.runTransaction(async (tx) => {
    const occDoc = await tx.get(occRef);
    const bDoc = await tx.get(bookingRef);
    if (bDoc.exists && bDoc.data().status !== 'cancelled') {
      // Idempotent: already booked. UI re-reads occurrence/roster for position.
      return { status: bDoc.data().status, position: 0 };
    }

    let confirmedCount = occDoc.exists ? (occDoc.data().confirmedCount || 0) : 0;
    let waitlistCount = occDoc.exists ? (occDoc.data().waitlistCount || 0) : 0;

    let status;
    let waitlistSeq = null;
    let position = 0;
    if (maxStudents === null || confirmedCount < maxStudents) {
      status = 'confirmed';
      confirmedCount += 1;
    } else {
      status = 'waitlist';
      waitlistCount += 1;
      waitlistSeq = now;
      position = waitlistCount;
    }

    tx.set(occRef, {
      classId, className: cls.name || '', sport: cls.sport || null,
      category: cls.category || null,
      date, slotStart: slotStartTs, startTime, endTime: slot.endTime || '',
      dayOfWeek: dow, maxStudents,
      confirmedCount, waitlistCount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.set(bookingRef, {
      occId, classId, className: cls.name || '', sport: cls.sport || null,
      studentId, studentName,
      date, slotStart: slotStartTs, startTime, endTime: slot.endTime || '',
      status, waitlistSeq,
      bookedBy: perm.bookedBy, bookedByUid: auth.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      cancelledAt: null,
    }, { merge: true });

    return { status, position };
  });
});

exports.cancelClassReservation = onCall(async (request) => {
  const { auth } = request;
  if (!auth) throw new HttpsError('unauthenticated', 'Login required.');
  const data = request.data || {};
  const { academyId, classId, date, startTime, studentId, slotStartMillis } = data;
  if (!academyId || !classId || !date || !startTime || !studentId) {
    throw new HttpsError('invalid-argument', 'Missing required fields.');
  }

  const perm = await bk_resolvePermission(auth.uid, academyId, studentId);
  const cfg = await bk_loadBookingConfig(academyId);

  // Trust the client-provided occId when present: cancel only ever targets the
  // caller's OWN booking ({occId}__{studentId}, and studentId is permission-
  // checked), so this is safe and survives the class/schedule being edited or
  // deleted after the booking was made (recomputing could diverge). Fall back
  // to recomputation for older clients.
  let occId = data.occId;
  if (!occId) {
    const classSnap = await db.doc(`academies/${academyId}/classes/${classId}`).get();
    const schedule = classSnap.exists && Array.isArray(classSnap.data().schedule)
      ? classSnap.data().schedule : [];
    occId = bk_occurrenceId(classId, date, startTime, bk_hasMultiPerDay(schedule));
  }
  const occRef = db.doc(`academies/${academyId}/classOccurrences/${occId}`);
  const bookingRef = db.doc(`academies/${academyId}/classBookings/${occId}__${studentId}`);

  // Pre-read the booking: needed for the cancel cutoff (server-derived slot
  // start) and for the next waitlist candidate (promotion happens in the tx).
  const preBooking = await bookingRef.get();

  // Student-side cancel cutoff (staff bypass). The client's slotStartMillis is
  // only a hint; fall back to the booking's stored slotStart so a non-staff
  // caller cannot skip the window by simply omitting it.
  if (!perm.isStaff && preBooking.exists) {
    const storedMs = preBooking.data().slotStart?.toMillis?.();
    const effectiveMs = Number.isFinite(slotStartMillis) ? slotStartMillis : storedMs;
    if (Number.isFinite(effectiveMs)) {
      const deadline = effectiveMs - cfg.cancelCutoffMinutes * 60 * 1000;
      if (Date.now() >= deadline) {
        throw new HttpsError('failed-precondition',
          `Cancelamento permitido só até ${cfg.cancelCutoffMinutes} min antes.`);
      }
    }
  }

  // Next waitlist candidate (promotion happens in the tx).
  let candidateRef = null;
  if (preBooking.exists && preBooking.data().status === 'confirmed') {
    const wlSnap = await db.collection(`academies/${academyId}/classBookings`)
      .where('occId', '==', occId)
      .where('status', '==', 'waitlist')
      .orderBy('waitlistSeq', 'asc')
      .limit(1)
      .get();
    if (!wlSnap.empty) candidateRef = wlSnap.docs[0].ref;
  }

  const result = await db.runTransaction(async (tx) => {
    const bDoc = await tx.get(bookingRef);
    if (!bDoc.exists || bDoc.data().status === 'cancelled') {
      return { noop: true };
    }
    const occDoc = await tx.get(occRef);
    let confirmedCount = occDoc.exists ? (occDoc.data().confirmedCount || 0) : 0;
    let waitlistCount = occDoc.exists ? (occDoc.data().waitlistCount || 0) : 0;
    const wasConfirmed = bDoc.data().status === 'confirmed';

    let candDoc = null;
    if (wasConfirmed && candidateRef) {
      candDoc = await tx.get(candidateRef);
    }

    tx.update(bookingRef, {
      status: 'cancelled',
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    let promotedStudentId = null;
    if (wasConfirmed) {
      confirmedCount = Math.max(0, confirmedCount - 1);
      if (candDoc && candDoc.exists && candDoc.data().status === 'waitlist') {
        tx.update(candidateRef, {
          status: 'confirmed',
          waitlistSeq: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        confirmedCount += 1;
        waitlistCount = Math.max(0, waitlistCount - 1);
        promotedStudentId = candDoc.data().studentId;
      }
    } else {
      waitlistCount = Math.max(0, waitlistCount - 1);
    }

    tx.set(occRef, {
      confirmedCount, waitlistCount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { promotedStudentId, className: bDoc.data().className || '' };
  });

  // Best-effort notify the promoted student outside the transaction.
  if (result && result.promotedStudentId) {
    try {
      const uid = await getStudentUserId(result.promotedStudentId, academyId);
      if (uid) {
        const title = 'Vaga confirmada!';
        const msg = `Você saiu da lista de espera de ${result.className}. Sua vaga está confirmada.`;
        await createInternalNotification(academyId, uid, 'class_booking', 'high', title, msg, {
          actionUrl: '/portal/reservas', actionLabel: 'Ver reservas',
          studentId: result.promotedStudentId, expiresInDays: 7,
        });
        await sendToUser(uid, title, msg, {
          type: 'class_booking', academyId, actionUrl: '/portal/reservas',
        });
      }
    } catch (e) {
      console.error('promote notify failed:', e);
    }
  }

  return { promotedStudentId: (result && result.promotedStudentId) || null };
});
