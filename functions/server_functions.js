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

// Query-before-create idempotent write of an auto milestone, keyed by
// (studentId + autoKey). Returns true when a new doc was created, false when one
// already existed (no-op). NEVER touches publicProfiles.
async function upsertAutoAchievement(academyId, fields) {
  const { studentId, autoKey } = fields;
  if (!studentId || !autoKey) return false;
  const ref = db
    .collection('academies').doc(academyId)
    .collection('achievements');

  // Idempotency guard: composite index achievements(studentId ASC, autoKey ASC).
  const existing = await ref
    .where('studentId', '==', studentId)
    .where('autoKey', '==', autoKey)
    .limit(1)
    .get();
  if (!existing.empty) return false;

  await ref.add({
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

  // 3. Validate user belongs to academy
  const userInfo = await getUserAcademyInfo(context.auth.uid);
  if (userInfo.academyId !== academyId) {
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

  // 3. Validate user belongs to academy
  const userInfo = await getUserAcademyInfo(context.auth.uid);
  if (userInfo.academyId !== academyId) {
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

  // 8. Verify amount matches
  const orderTotal = orderData.total ?? orderData.totalAmount;
  if (Math.abs(orderTotal - amount) > 1) {
    throw new HttpsError(
      'invalid-argument',
      `Amount (${amount}) does not match order total (${orderTotal})`
    );
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
      amount: Math.round(amount * 100), // Convert Reais to cents for AbacatePay
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
    amount: Math.round(amount * 100), // Store in cents (consistent with wallet display)
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

  // 3. Validate user belongs to academy
  const userInfo = await getUserAcademyInfo(context.auth.uid);
  if (userInfo.academyId !== academyId) {
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

  // 3. Validate user belongs to academy
  const userInfo = await getUserAcademyInfo(context.auth.uid);
  if (userInfo.academyId !== academyId) {
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
    // (short waits) instead of a single blind read, so we never return a stale
    // token. If the holder never finishes, fall through to retry the lock once.
    for (let i = 0; i < 10; i++) {
      await new Promise((r) => setTimeout(r, 300));
      const cur = await readTokens();
      if (isFresh(cur)) {
        return cur.accessToken;
      }
    }
    // Holder appears stuck; attempt to take over (acquireLock reclaims if stale).
    if (!(await acquireLock())) {
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
  const info = await getUserAcademyInfo(request.auth.uid);
  if (info.academyId !== academyId || info.role !== 'admin') {
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
exports.disconnectMercadoPago = onCall(async (request) => {
  const academyId = String(request.data?.academyId || '');
  if (!academyId) throw new HttpsError('invalid-argument', 'academyId é obrigatório.');
  await requireAdminOf(request, academyId);

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
  const userInfo = await getUserAcademyInfo(request.auth.uid);
  if (userInfo.academyId !== academyId) {
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

  const pix = await createMpPix({
    academyId,
    transactionAmount: Number(fin.amount) || 0, // server-derived REAIS
    description: sanitizeString(description) || 'Mensalidade',
    externalReference: `${academyId}:fin:${financialId}`,
    payer: { email: resolvedEmail, cpf: cpfDigits, name: studentName },
  });

  const expiresAt = admin.firestore.Timestamp.fromDate(pix.expiresAt);
  await finRef.update({
    pixCode: pix.pixCode || null,
    pixQrCode: pix.qrCodeBase64 || null,
    pixTicketUrl: pix.ticketUrl || null,
    gatewayPaymentId: pix.paymentId,
    paymentGateway: 'mercadopago',
    pixExpiresAt: expiresAt,
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
  if (order.status === 'paid') {
    throw new HttpsError('already-exists', 'This order has already been paid');
  }

  // SECURITY: never trust the client amount. Derive the charge server-side from
  // the order (reais). Prefer recomputing from the line items (each carries a
  // server-validated price), falling back to the persisted total. The client
  // now sends CENTAVOS (H1); it is only a cross-check (1-centavo tolerance).
  const expectedReais = orderExpectedTotalReais(order);
  const expectedCentavos = Math.round(expectedReais * 100);
  if (Math.abs(expectedCentavos - amount) > 1) {
    throw new HttpsError('invalid-argument',
      `Amount (${amount}) does not match order total (${expectedCentavos})`);
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

  const pix = await createMpPix({
    academyId,
    transactionAmount: expectedReais, // server-derived reais
    description: sanitizeString(description) || 'Pedido da Loja',
    externalReference: `${academyId}:order:${orderId}`,
    payer: { email: payerEmail, cpf: payerCpf, name: studentName },
  });

  const expiresAt = admin.firestore.Timestamp.fromDate(pix.expiresAt);
  await orderRef.update({
    pixCode: pix.pixCode || null,
    pixQrCode: pix.qrCodeBase64 || null,
    pixTicketUrl: pix.ticketUrl || null,
    gatewayPaymentId: pix.paymentId,
    paymentGateway: 'mercadopago',
    pixExpiresAt: expiresAt,
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
    const acadSnap = await db.doc(`academies/${academyId}`).get();
    if (acadSnap.data()?.storeCreditCardEnabled !== true) {
      throw new HttpsError('failed-precondition',
        'Pagamento com cartao nao esta habilitado para a loja desta academia.');
    }
  }

  // SECURITY: never trust the client amount. DERIVE the charge server-side from
  // the stored record. The client sends CENTAVOS; the client value is only a
  // cross-check (1-centavo tolerance). financial.amount is REAIS (canonical);
  // order total is reais -> both normalized to centavos here.
  const expectedCentavos = isOrder
    ? Math.round(orderExpectedTotalReais(recData) * 100)
    : Math.round((Number(recData.amount) || 0) * 100);
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

  let payment;
  try {
    payment = await mpRequest('POST', '/v1/payments', {
      token,
      idempotencyKey: `${externalReference}:card`,
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
          email: payerEmail || undefined,
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
    if (!dataId || !acad || (type && type !== 'payment')) {
      return res.status(200).json({ received: true, skipped: type || 'no_id' });
    }

    try {
      const token = await getMpAccessToken(acad);
      const payment = await mpRequest('GET', `/v1/payments/${dataId}`, { token });
      const parsed = mpMktParseRef(payment.external_reference);
      if (!parsed || parsed.academyId !== acad) {
        return res.status(200).json({ received: true, skipped: 'ref_mismatch' });
      }
      if (payment.status !== 'approved') {
        return res.status(200).json({ received: true, status: payment.status });
      }
      await mpMktSettle(parsed, payment);
      return res.status(200).json({ success: true });
    } catch (e) {
      console.error('[mpMktWebhook] erro', e.message);
      return res.status(500).json({ error: e.message }); // 500 => MP retries
    }
  });

/** Flips the financial/order to paid (idempotent) + stock + admin notify. */
async function mpMktSettle({ academyId, type, docId }, payment) {
  const chargeId = String(payment.id);
  const amtFmt = (Number(payment.transaction_amount) || 0).toFixed(2);
  const method = payment.payment_method_id === 'pix' ? 'pix' : 'card';
  const viaLabel = method === 'pix' ? 'via PIX' : 'via cartao';

  if (type === 'order') {
    const orderRef = db.doc(`academies/${academyId}/storeOrders/${docId}`);
    const snap = await orderRef.get();
    if (!snap.exists || snap.data().status === 'paid') return; // idempotent
    // SECURITY: refuse to settle if the paid amount differs from the order
    // total (reais, 1-centavo tolerance). Protects against a tampered or
    // mismatched MP payment flipping the order to paid for the wrong value.
    const expectedReais = orderExpectedTotalReais(snap.data());
    const paidReais = Number(payment.transaction_amount) || 0;
    if (Math.abs(expectedReais - paidReais) > 0.01) {
      console.error('[mpMktSettle] amount mismatch order', docId,
        'expected', expectedReais, 'paid', paidReais);
      return; // do NOT settle
    }
    await orderRef.update({
      status: 'paid',
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      paymentMethod: method,
      paymentGateway: 'mercadopago',
      gatewayPaymentId: chargeId,
      externalPaymentId: chargeId,
      pixCode: admin.firestore.FieldValue.delete(),
      pixQrCode: admin.firestore.FieldValue.delete(),
      pixTicketUrl: admin.firestore.FieldValue.delete(),
      pixExpiresAt: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const items = snap.data().items;
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
    const code = docId.slice(-6).toUpperCase();
    await notifyAdminCF(academyId, 'order_paid', 'Pedido Pago',
      `Pedido #${code} pago - R$ ${amtFmt} ${viaLabel}.`, { orderId: docId });
    return;
  }

  // mensalidade / financial
  const finRef = db.doc(`academies/${academyId}/financials/${docId}`);
  const snap = await finRef.get();
  if (!snap.exists || snap.data().status === 'paid') return; // idempotent
  // SECURITY: refuse to settle if the paid amount differs from the stored
  // financial amount (REAIS, canonical; 1-centavo tolerance).
  const expectedFinReais = Number(snap.data().amount) || 0;
  const paidFinReais = Number(payment.transaction_amount) || 0;
  if (Math.abs(expectedFinReais - paidFinReais) > 0.01) {
    console.error('[mpMktSettle] amount mismatch fin', docId,
      'expected', expectedFinReais, 'paid', paidFinReais);
    return; // do NOT settle
  }
  await finRef.update({
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
  await notifyAdminCF(academyId, 'payment_received', 'Pagamento Recebido',
    `Pagamento de R$ ${amtFmt} recebido ${viaLabel}.`, { financialId: docId });
}
