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

async function sendToUser(userId, title, body, data) {
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
  // Primary: query userAcademyMapping to find the user linked to this student
  const mappingsSnapshot = await db
    .collection('userAcademyMapping')
    .get();

  for (const mappingDoc of mappingsSnapshot.docs) {
    const data = mappingDoc.data();
    const academyDetail = data.academyDetails?.[academyId];
    if (academyDetail?.studentId === studentId) {
      return mappingDoc.id; // doc ID is the userId
    }
  }

  // Fallback: check linkedUserId on the student document
  const studentDoc = await db
    .collection('academies')
    .doc(academyId)
    .collection('students')
    .doc(studentId)
    .get();

  if (!studentDoc.exists) {
    return null;
  }
  const student = studentDoc.data();
  return student?.linkedUserId || null;
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
// The gate lives in sendWhatsAppServer(): with no key it returns immediately
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

// ---- 1. Gated WhatsApp sender (the inert switch) -------------------------
// GATE: with no WHATSAPP_API_KEY, returns {sent:false, skipped:'no_key'}
// without calling anything. Never throws.
async function sendWhatsAppServer(phone, message, academyId) {
  const key = process.env.WHATSAPP_API_KEY;
  if (!key) {
    return { sent: false, skipped: 'no_key' };
  }
  const url = process.env.WHATSAPP_API_URL ||
    'https://notification.tensorroot.com/api/send-whatsapp';
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': key,
      },
      body: JSON.stringify({
        phone,
        message,
        academyId,
        type: 'billing_reminder',
      }),
    });
    return { sent: res.ok };
  } catch (e) {
    console.error('[S7] sendWhatsAppServer failed:', e && e.message);
    return { sent: false };
  }
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
  'D+0': 'Oi {nome}! Passando rapidinho para lembrar que hoje, dia {vencimento}, vence sua mensalidade de {valor} com a {academia}. Contamos com voce! Qualquer duvida, estamos a disposicao.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+1': 'Ola {nome}! Aqui e a {academia}. Identificamos que sua mensalidade de {valor} venceu em {vencimento}. Caso ja tenha efetuado o pagamento, por favor desconsidere esta mensagem. Caso contrario, solicitamos a regularizacao. Obrigado![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+3': 'Ola {nome}! Sua mensalidade de {valor} da {academia} esta com 3 dias de atraso (vencimento: {vencimento}). Por favor, regularize sua situacao o mais breve possivel. Em caso de duvidas, estamos a disposicao![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+7': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Precisamos que regularize sua situacao para manter seus treinos em dia. Entre em contato conosco para combinar o pagamento.[[PIX]]\n\nPara facilitar, pague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+15': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Sua situacao precisa ser regularizada com urgencia para evitar a suspensao do acesso aos treinos. Por favor, entre em contato.[[PIX]]\n\nRegularize agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  'D+30': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com mais de 30 dias de atraso. Caso a situacao nao seja regularizada, infelizmente precisaremos suspender seu acesso. Entre em contato urgente para negociarmos.[[PIX]]\n\nRegularize agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
};

// Mirrors the Dart _applyTemplate replaceAll (all occurrences).
function applyBillingTemplate(tpl, { nome, valor, vencimento, dias, academia }) {
  return String(tpl || '')
    .split('{nome}').join(nome != null ? String(nome) : '')
    .split('{valor}').join(valor != null ? String(valor) : '')
    .split('{vencimento}').join(vencimento != null ? String(vencimento) : '')
    .split('{dias}').join(dias != null ? String(dias) : '')
    .split('{academia}').join(academia != null ? String(academia) : '');
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

// ---- 5. Best-effort PIX for a reminder (graceful degradation) ------------
// GATES on the academy having mpConnected AND the financial unpaid. Sources the
// payer CPF from the student doc (kids -> guardian.cpf, else cpf), mirroring the
// Dart effectiveCpf. Reuses a still-valid PIX (idempotent), otherwise creates
// one via createMpPix and persists pixCode/pixTicketUrl/pixExpiresAt (mirroring
// createMpPixPayment). NEVER throws: returns empty strings on any failure/gate.
//
// `financial` must include { id, amount (centavos), studentId, status,
// description, gatewayPaymentId?, pixCode?, pixExpiresAt? }.
async function generateReminderPix(academyId, financial) {
  try {
    if (!financial || financial.status === 'paid') {
      return { pixCode: '', ticketUrl: '' };
    }

    // Gate: academy must have Mercado Pago connected.
    const acadSnap = await db.doc(`academies/${academyId}`).get();
    if (!acadSnap.exists || acadSnap.data()?.mpConnected !== true) {
      return { pixCode: '', ticketUrl: '' };
    }

    const financialId = financial.id;
    if (!financialId) return { pixCode: '', ticketUrl: '' };

    // Idempotency: reuse a still-valid PIX (same code for everyone, no double
    // charge) — mirrors createMpPixPayment.
    const existingExpiry =
      financial.pixExpiresAt && typeof financial.pixExpiresAt.toMillis === 'function'
        ? financial.pixExpiresAt.toMillis()
        : 0;
    if (financial.gatewayPaymentId && financial.pixCode && existingExpiry > Date.now()) {
      return {
        pixCode: financial.pixCode,
        ticketUrl: financial.pixTicketUrl || '',
      };
    }

    // Source payer info (CPF + email + name) from the student doc.
    let payerCpf = '';
    let payerEmail;
    let payerName = financial.studentName || '';
    try {
      const stuSnap = await db
        .collection('academies').doc(academyId)
        .collection('students').doc(financial.studentId)
        .get();
      if (stuSnap.exists) {
        const stu = stuSnap.data() || {};
        const isKids = stu.category === 'kids';
        payerCpf = (isKids ? stu.guardian?.cpf : stu.cpf) || '';
        payerEmail = (isKids ? stu.guardian?.email : stu.email) || undefined;
        payerName = stu.fullName || payerName;
      }
    } catch (_) {
      // fall through with whatever we have
    }

    // financials.amount is stored in REAIS (canonical); createMpPix takes REAIS.
    const pix = await createMpPix({
      academyId,
      transactionAmount: Number(financial.amount) || 0,
      description: financial.description || 'Mensalidade',
      externalReference: `${academyId}:fin:${financialId}`,
      payer: { email: payerEmail, cpf: payerCpf, name: payerName },
    });

    // Persist for reuse (mirrors createMpPixPayment).
    try {
      const finRef = db.doc(`academies/${academyId}/financials/${financialId}`);
      await finRef.update({
        pixCode: pix.pixCode || null,
        pixQrCode: pix.qrCodeBase64 || null,
        pixTicketUrl: pix.ticketUrl || null,
        gatewayPaymentId: pix.paymentId,
        paymentGateway: 'mercadopago',
        pixExpiresAt: admin.firestore.Timestamp.fromDate(pix.expiresAt),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // persistence failure is non-fatal: we still have the code to send now
    }

    return { pixCode: pix.pixCode || '', ticketUrl: pix.ticketUrl || '' };
  } catch (e) {
    console.error('[S7] generateReminderPix failed:', e && e.message);
    return { pixCode: '', ticketUrl: '' };
  }
}

// ---- 6. Orchestrator: build + send one WhatsApp billing reminder ---------
// GATES: billingSettings.whatsappEnabled !== false; recipient phone present
// (kids -> guardian.phone else phone, mirroring effectivePhone). When
// includePaymentLink !== false, generates a best-effort PIX. Picks the custom
// template (billingSettings.messageTemplates.whatsapp[stage]) or the JS default.
// NEVER throws.
//
// `stage` is 'D+0'..'D+30'. `daysOverdue` defaults to 0 for the due-soon cron.
async function sendBillingReminderWhatsApp(
  academyId,
  academyName,
  billingSettings,
  financial,
  stage,
  daysOverdue
) {
  try {
    const settings = billingSettings || {};
    if (settings.whatsappEnabled === false) return;

    // Resolve recipient phone from the student doc (effectivePhone semantics).
    let phone;
    try {
      const stuSnap = await db
        .collection('academies').doc(academyId)
        .collection('students').doc(financial.studentId)
        .get();
      if (stuSnap.exists) {
        const stu = stuSnap.data() || {};
        phone = stu.category === 'kids' ? stu.guardian?.phone : stu.phone;
      }
    } catch (_) {
      // no phone -> gate below
    }
    if (!phone || String(phone).trim() === '') return;

    // Stage-level dedup: each reminder stage (D+0, D+1, D+3, ...) goes out at
    // most once per charge, so a charge sitting overdue (or due-soon) for days
    // doesn't WhatsApp the student every single day the cron runs. Only an
    // actual send marks the stage as covered (below), so an INERT run with no
    // WHATSAPP_API_KEY still delivers once the key is later configured.
    if (financial.lastReminderStage === stage) return;

    const dueDate = financial.dueDate && typeof financial.dueDate.toDate === 'function'
      ? financial.dueDate.toDate()
      : new Date();
    const valor = formatBrlAmount(Number(financial.amount) || 0);
    const vencimento = formatBrDate(dueDate);
    const dias = daysOverdue || 0;

    // PIX (best-effort) when the academy opted into payment links.
    let pix = { pixCode: '', ticketUrl: '' };
    if (settings.includePaymentLink !== false) {
      pix = await generateReminderPix(academyId, financial);
    }

    const customTpl = settings.messageTemplates?.whatsapp?.[stage];
    const tpl = customTpl || DEFAULT_WHATSAPP_TEMPLATES[stage] ||
      DEFAULT_WHATSAPP_TEMPLATES['D+1'];

    const filled = applyBillingTemplate(tpl, {
      nome: financial.studentName || '',
      valor,
      vencimento,
      dias,
      academia: academyName || '',
    });
    const msg = mpInjectPaymentInfo(filled, pix.pixCode, pix.ticketUrl);

    const result = await sendWhatsAppServer(phone, msg, academyId);
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
  } catch (e) {
    console.error('[S7] sendBillingReminderWhatsApp failed:', e && e.message);
  }
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

// ============================================
// Cloud Functions - Firestore Triggers
// ============================================

/**
 * Trigger: New financial record created
 * Action: Notify student about new payment due
 */
exports.onFinancialCreated = functions.firestore
  .document('academies/{academyId}/financials/{financialId}')
  .onCreate(async (snapshot, context) => {
    const { academyId, financialId } = context.params;
    const financial = snapshot.data();

    console.log(`New financial created: ${financialId} in academy ${academyId}`);

    // Get student's userId
    const userId = await getStudentUserId(financial.studentId, academyId);
    if (!userId) {
      console.log(`No userId found for student: ${financial.studentId}`);
      return;
    }

    // Send notification to student
    const dueDate = financial.dueDate.toDate();
    const formattedDate = dueDate.toLocaleDateString('pt-BR');
    const formattedAmount = (Number(financial.amount) || 0).toFixed(2);

    // Push notification
    await sendToUser(
      userId,
      'Nova Mensalidade Disponivel',
      `Uma nova mensalidade de R$ ${formattedAmount} foi gerada. Vencimento: ${formattedDate}.`,
      {
        type: 'financial',
        id: financialId,
        academyId,
      }
    );

    // Internal notification
    await createInternalNotification(academyId, userId, 'financial', 'normal',
      'Nova Mensalidade',
      `Sua mensalidade de R$ ${formattedAmount} vence em ${formattedDate}.`,
      { actionUrl: '/portal/financeiro', actionLabel: 'Ver detalhes', financialId, expiresInDays: 30 }
    );

    console.log(`Notification sent to user ${userId} for financial ${financialId}`);
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
exports.scheduledOverdueCheck = functions.pubsub
  .schedule('0 9 * * *')
  .timeZone('America/Sao_Paulo')
  .onRun(async () => {
    console.log('Running scheduled overdue payment check');

    const now = new Date();
    const academiesSnapshot = await db.collection('academies').get();

    for (const academyDoc of academiesSnapshot.docs) {
      const academyId = academyDoc.id;
      const academy = academyDoc.data();

      // Skip if no admin user
      if (!academy.adminUserId) {
        console.log(`Academy ${academyId} has no admin user`);
        continue;
      }

      // Find overdue financials
      const financialsSnapshot = await db
        .collection('academies')
        .doc(academyId)
        .collection('financials')
        .where('status', '==', 'pending')
        .get();

      let overdueCount = 0;
      let totalOverdueAmount = 0;

      // S7: read the per-academy WhatsApp/PIX reminder settings once.
      const billingSettings = await getBillingReminderSettings(academyId);
      const academyName = academy.name || academy.academyName || '';

      for (const financialDoc of financialsSnapshot.docs) {
        const financial = financialDoc.data();
        const dueDate = financial.dueDate.toDate();

        // Check if overdue
        if (dueDate < now) {
          overdueCount++;
          totalOverdueAmount += financial.amount;

          // Update status to overdue if not already
          if (financial.status !== 'overdue') {
            await financialDoc.ref.update({ status: 'overdue' });
          }

          // Calculate days overdue
          const daysOverdue = Math.floor(
            (now.getTime() - dueDate.getTime()) / (1000 * 60 * 60 * 24)
          );

          // Notify the billing recipient (responsible adult for kids, else
          // the student) about the overdue payment (push + internal)
          const userId = await getBillingRecipientUid(financial.studentId, academyId);
          if (userId) {
            await sendToUser(
              userId,
              'Pagamento Atrasado',
              `Sua mensalidade de R$ ${(Number(financial.amount) || 0).toFixed(2)} esta atrasada ha ${daysOverdue} dias.`,
              {
                type: 'financial',
                id: financialDoc.id,
                academyId,
              }
            );
            await createInternalNotification(academyId, userId, 'financial', 'high',
              'Pagamento Atrasado',
              `Sua mensalidade de R$ ${(Number(financial.amount) || 0).toFixed(2)} está atrasada há ${daysOverdue} dias.`,
              { actionUrl: '/portal/financeiro', actionLabel: 'Regularizar',
                financialId: financialDoc.id, expiresInDays: 30 }
            );
          }

          // S7: additionally send the autonomous WhatsApp + PIX reminder.
          // INERT until WHATSAPP_API_KEY is set (gate in sendWhatsAppServer).
          await sendBillingReminderWhatsApp(
            academyId,
            academyName,
            billingSettings,
            { ...financial, id: financialDoc.id },
            resolveStage(daysOverdue),
            daysOverdue
          );
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
    }

    console.log('Overdue payment check completed');
    return null;
  });

/**
 * Scheduled: Daily at 8:00 AM (Brasilia Time)
 * Action: Check for payments due soon (3 days before) and notify students
 */
exports.scheduledDueSoonReminder = functions.pubsub
  .schedule('0 8 * * *')
  .timeZone('America/Sao_Paulo')
  .onRun(async () => {
    console.log('Running scheduled due soon reminder');

    const now = new Date();
    const threeDaysFromNow = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);

    const academiesSnapshot = await db.collection('academies').get();

    for (const academyDoc of academiesSnapshot.docs) {
      const academyId = academyDoc.id;
      const academy = academyDoc.data();

      // S7: read the per-academy WhatsApp/PIX reminder settings once.
      const billingSettings = await getBillingReminderSettings(academyId);
      const academyName = academy.name || academy.academyName || '';

      // Find pending financials due within 3 days
      const financialsSnapshot = await db
        .collection('academies')
        .doc(academyId)
        .collection('financials')
        .where('status', '==', 'pending')
        .get();

      for (const financialDoc of financialsSnapshot.docs) {
        const financial = financialDoc.data();
        const dueDate = financial.dueDate.toDate();

        // Check if due within 3 days (but not overdue)
        if (dueDate > now && dueDate <= threeDaysFromNow) {
          const daysUntilDue = Math.ceil(
            (dueDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)
          );
          const userId = await getBillingRecipientUid(financial.studentId, academyId);
          if (userId) {
            const amtFormatted = (Number(financial.amount) || 0).toFixed(2);
            const reminderMsg = `Sua mensalidade de R$ ${amtFormatted} vence em ${daysUntilDue} dia(s).`;
            await sendToUser(
              userId,
              'Lembrete de Pagamento',
              reminderMsg,
              {
                type: 'financial',
                id: financialDoc.id,
                academyId,
              }
            );
            await createInternalNotification(academyId, userId, 'financial', 'normal',
              'Lembrete de Pagamento',
              reminderMsg,
              { actionUrl: '/portal/financeiro', actionLabel: 'Ver detalhes',
                financialId: financialDoc.id, expiresInDays: 7 }
            );
            console.log(`Sent due soon reminder to user ${userId} for financial ${financialDoc.id}`);
          }

          // S7: the WhatsApp 'D+0' courtesy text reads "vence hoje", so only send
          // it on the due date itself (<= 1 day out), not across the whole 1-3 day
          // window — otherwise the student gets a "due today" message up to 3 days
          // early. The 2-3 day window keeps only the internal push/notification
          // above. INERT until WHATSAPP_API_KEY is set (gate in sendWhatsAppServer).
          if (daysUntilDue <= 1) {
            await sendBillingReminderWhatsApp(
              academyId,
              academyName,
              billingSettings,
              { ...financial, id: financialDoc.id },
              'D+0',
              0
            );
          }
        }
      }
    }

    console.log('Due soon reminder completed');
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
function localMonthKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
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
  if (!uid || !academyId) return false;
  const snap = await db.collection('userAcademyMapping').doc(uid).get();
  if (!snap.exists) return false;
  const data = snap.data() || {};
  const details = data.academyDetails || {};
  const entry = details[academyId];
  return !!(entry && (entry.role === 'admin' || entry.role === 'instructor'));
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
const MP_MKT_SECRETS = ['MP_OAUTH_CLIENT_ID', 'MP_OAUTH_CLIENT_SECRET'];

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
  const r = await fetch(`${MP_API_BASE}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
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
    await ref.set({
      accessToken: tok.access_token,
      refreshToken: tok.refresh_token || fresh.refreshToken,
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + (Number(tok.expires_in) || 0) * 1000),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
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
    throw new HttpsError('permission-denied', 'Apenas o admin da academia pode conectar.');
  }
  return info;
}

// ---- OAuth: start connect (admin) ----------------------------------------
exports.startMercadoPagoConnect = onCall({ secrets: MP_MKT_SECRETS }, async (request) => {
  const academyId = String(request.data?.academyId || '');
  if (!academyId) throw new HttpsError('invalid-argument', 'academyId é obrigatório.');
  await requireAdminOf(request, academyId);

  const nonce = crypto.randomBytes(8).toString('hex');
  await db.doc(`academies/${academyId}/private/mpAuth`).set({
    oauthNonce: nonce,
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
exports.mercadoPagoOAuthCallback = onRequest({ secrets: MP_MKT_SECRETS }, async (req, res) => {
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
    await ref.set({
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
    await db.doc(`academies/${academyId}`).update({
      mpConnected: true,
      mpUserId: String(tok.user_id || ''),
      mpPublicKey: tok.public_key || '',
      mpLiveMode: tok.live_mode === true,
      mpConnectedAt: admin.firestore.FieldValue.serverTimestamp(),
      abacatePayEnabled: false,
      asaasEnabled: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return res.status(200).send(mpCallbackHtml(
      'Mercado Pago conectado!',
      'Sua conta foi conectada. Volte ao app para continuar.', false));
  } catch (e) {
    console.error('[mpOAuthCallback] erro', e.message, e.data);
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
        if (!subDoc.data().mpPreapprovalId) continue;
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
          'nao continuarem sendo cobrados.', {});
      } catch (_) { /* best-effort */ }
    } else if (failed > 0) {
      throw new HttpsError('unavailable',
        `${failed} assinatura(s) ativa(s) não puderam ser canceladas no ` +
        'Mercado Pago. A conta NÃO foi desconectada — tente novamente em ' +
        'alguns minutos.');
    }
  }

  await db.doc(`academies/${academyId}/private/mpAuth`).delete().catch(() => {});
  await db.doc(`academies/${academyId}`).update({
    mpConnected: false,
    mpUserId: admin.firestore.FieldValue.delete(),
    mpPublicKey: admin.firestore.FieldValue.delete(),
    mpLiveMode: admin.firestore.FieldValue.delete(),
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
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
  const cpf = ((payer && payer.cpf) || '').replace(/\D/g, '');
  const nameParts = ((payer && payer.name) || '').trim().split(/\s+/);
  // Idempotency key must be UNIQUE per minted PIX: external_reference is FIXED
  // per financial/order (the webhook parses it), so reusing it as the
  // idempotency key would make MP return the SAME (possibly expired) payment on
  // a regeneration after the 24h expiry. Append a fresh epoch-millis suffix so
  // each mint creates a fresh, payable PIX.
  const idempotencyKey =
    `${externalReference}:${admin.firestore.Timestamp.now().toMillis()}`;
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
  return {
    paymentId: String(payment.id),
    pixCode: (tx && tx.qr_code) || '',
    qrCodeBase64: (tx && tx.qr_code_base64) || '',
    ticketUrl: (tx && tx.ticket_url) || '',
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
async function mpAcquirePixMint(docRef, uid) {
  const pixExpMs = (d) =>
    (d.pixExpiresAt && typeof d.pixExpiresAt.toMillis === 'function')
      ? d.pixExpiresAt.toMillis() : 0;
  const mintAtMs = (d) =>
    (d.pixMintAt && typeof d.pixMintAt.toMillis === 'function')
      ? d.pixMintAt.toMillis() : 0;
  const hasFreshPix = (d) =>
    d.gatewayPaymentId && d.pixCode && pixExpMs(d) > Date.now();

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
  if (fin.gatewayPaymentId && fin.pixCode && existingExpiry > Date.now()) {
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
  const cpfDigits = String(payerCpf || '').replace(/\D/g, '');
  if (cpfDigits.length < 11) {
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

  // Anti-race (achado #24): serializa o mint via lock transacional no doc —
  // dois aparelhos concorrentes geram UM PIX só (o perdedor reusa o do vencedor).
  const mint = await mpAcquirePixMint(finRef, request.auth.uid);
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

// ---- PIX: loja (amount in REAIS, matching createOrderPixPayment) ----------
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
  if (order.gatewayPaymentId && order.pixCode && existingExpiry > Date.now()) {
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
  const cpfDigits = String(payerCpf || '').replace(/\D/g, '');
  if (cpfDigits.length < 11) {
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

  // Anti-race (achado #24): serializa o mint via lock transacional no doc —
  // dois aparelhos concorrentes geram UM PIX só (o perdedor reusa o do vencedor).
  const mint = await mpAcquirePixMint(orderRef, request.auth.uid);
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
// Handles BOTH mensalidade (financialId, amount in CENTAVOS) and loja
// (orderId, amount in REAIS). Card is synchronous: settle inline when approved;
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
    throw new HttpsError('internal', 'Falha ao processar o cartao.');
  }

  // Synchronous approval → settle now; webhook covers async/3DS later.
  if (payment.status === 'approved') {
    await mpMktSettle({ academyId, type: isOrder ? 'order' : 'fin', docId }, payment);
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
    tx.set(finRef, {
      academyId,
      studentId: sub.studentId,
      studentName: sub.studentName || '',
      amount: amount > 0 ? amount : (Number(sub.recurringValue) || 0),
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
    });
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
      preapprovalId: sub.mpPreapprovalId };
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
  } else if (payStatus === 'rejected' || payStatus === 'cancelled') {
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
    .where('status', 'in', ['pending', 'authorized', 'paused'])
    .get();
  const STALE_PENDING_MS = 60 * 60 * 1000; // 1h
  let hasLiveSub = false;
  for (const dupDoc of dupSnap.docs) {
    const dup = dupDoc.data();
    const createdMs = dup.createdAt && typeof dup.createdAt.toMillis === 'function'
      ? dup.createdAt.toMillis() : 0;
    const isStaleAbort = dup.status === 'pending' && !dup.mpPreapprovalId &&
      createdMs > 0 && (Date.now() - createdMs) > STALE_PENDING_MS;
    if (isStaleAbort) {
      await dupDoc.ref.update({
        status: 'abandoned',
        lastEvent: 'abandoned_stale_pending',
        updatedAt: FV.serverTimestamp(),
      }).catch(() => { /* best-effort: não bloqueia a criação */ });
    } else {
      hasLiveSub = true;
    }
  }
  if (hasLiveSub) {
    throw new HttpsError('failed-precondition',
      'Já existe uma assinatura ativa deste plano para este aluno.');
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
    await subRef.update({
      status: 'error', lastEvent: 'create_failed', updatedAt: FV.serverTimestamp(),
    });
    const text = `${e.data ? JSON.stringify(e.data) : ''} ${e.message || ''}`
      .toLowerCase();
    if (text.includes('card_token') || text.includes('token')) {
      throw new HttpsError('failed-precondition',
        'Não foi possível usar este cartão. Digite os dados do cartão novamente.');
    }
    throw new HttpsError('internal', 'Falha ao criar a assinatura.');
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

/** Parses `${academyId}:fin:${id}` / `${academyId}:order:${id}`. */
function mpMktParseRef(ref) {
  const parts = String(ref || '').split(':');
  if (parts.length < 3) return null;
  return { academyId: parts[0], type: parts[1], docId: parts.slice(2).join(':') };
}

// ---- Marketplace webhook (flips financials/storeOrders to paid) -----------
exports.mercadoPagoMarketplaceWebhook = onRequest(
  { cors: false, secrets: ['MP_MKT_WEBHOOK_SECRET'] },
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
        return res.status(200).json({ received: true, status: payment.status });
      }
      await mpMktSettle(parsed, payment);
      return res.status(200).json({ success: true });
    } catch (e) {
      console.error('[mpMktWebhook] erro', e.message);
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
    if (Array.isArray(items)) {
      for (const item of items) {
        const productRef = db.doc(`academies/${academyId}/storeProducts/${item.productId}`);
        const p = await productRef.get();
        if (p.exists && p.data()?.stockType === 'in_stock') {
          await productRef.update({
            stockQuantity: admin.firestore.FieldValue.increment(-item.quantity),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }
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
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { didSettle: true };
  });
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
  await notifyAdminCF(academyId, 'payment_received', 'Pagamento Recebido',
    `Pagamento de R$ ${amtFmt} recebido ${viaLabel}.`, { financialId: docId });
}

// ---- Estorno / chargeback no marketplace (achado #16) ----------------------
// O MP re-notifica o MESMO payment id com status refunded/charged_back/
// cancelled quando um pagamento já liquidado é devolvido. Antes, qualquer
// status != 'approved' era ignorado: o financial/pedido ficava 'paid' para
// sempre, o estoque continuava decrementado e o admin nem ficava sabendo do
// chargeback. Só age quando o doc está 'paid' com o MESMO gatewayPaymentId —
// um PIX expirado ('cancelled') de doc pendente continua sendo no-op.
const MP_REVERSAL_STATUSES = ['refunded', 'charged_back', 'cancelled'];

/** Estorno de pagamento avulso (financial ou pedido da loja). Marca o doc como
 * 'refunded'/'chargeback', restaura o estoque do pedido (idempotente via flag
 * stockRestorePending) e notifica o admin. Nunca relança para o webhook. */
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
    const r = await db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) return { handled: false };
      const d = snap.data();
      // Re-entrega com a restauração de estoque pendente (crash entre o
      // commit e o loop de estoque): completa o efeito sem re-notificar.
      if ((d.status === 'refunded' || d.status === 'chargeback') &&
          d.gatewayPaymentId === chargeId && d.stockRestorePending === true) {
        return { handled: false, restock: true, items: d.items };
      }
      if (d.status !== 'paid' || d.gatewayPaymentId !== chargeId) {
        return { handled: false }; // outro pagamento/estado — não mexe
      }
      const update = {
        status: newStatus,
        refundedAt: FV.serverTimestamp(),
        refundEvent,
        updatedAt: FV.serverTimestamp(),
      };
      let restock = false;
      if (d.stockSettled === false) {
        // O decremento do settle NUNCA rodou (crash antes do loop): consome o
        // pendente em vez de restaurar — efeito líquido nulo no estoque, e a
        // re-entrega do 'approved' não decrementa mais (doc não está 'paid').
        update.stockSettled = true;
      } else {
        update.stockRestorePending = true; // flag de idempotência da restauração
        restock = true;
      }
      tx.update(orderRef, update);
      return { handled: true, restock, items: d.items };
    });
    if (r.restock && Array.isArray(r.items)) {
      for (const item of r.items) {
        const productRef =
          db.doc(`academies/${academyId}/storeProducts/${item.productId}`);
        const p = await productRef.get();
        if (p.exists && p.data()?.stockType === 'in_stock') {
          await productRef.update({
            stockQuantity: FV.increment(item.quantity),
            updatedAt: FV.serverTimestamp(),
          });
        }
      }
      await orderRef.update({
        stockRestorePending: FV.delete(),
        updatedAt: FV.serverTimestamp(),
      }).catch((e) => console.error(
        '[mpMktHandleReversal] stockRestorePending clear falhou', docId, e.message));
    }
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
    await sendToUser(uid, title, message, { type, academyId });
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
        await sendToUser(uid, title, msg, { type: 'class_booking', academyId });
      }
    } catch (e) {
      console.error('promote notify failed:', e);
    }
  }

  return { promotedStudentId: (result && result.promotedStudentId) || null };
});
