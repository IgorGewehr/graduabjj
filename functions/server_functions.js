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
    const formattedAmount = (financial.amount / 100).toFixed(2);

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
              `Sua mensalidade de R$ ${(financial.amount / 100).toFixed(2)} esta atrasada ha ${daysOverdue} dias.`,
              {
                type: 'financial',
                id: financialDoc.id,
                academyId,
              }
            );
            await createInternalNotification(academyId, userId, 'financial', 'high',
              'Pagamento Atrasado',
              `Sua mensalidade de R$ ${(financial.amount / 100).toFixed(2)} está atrasada há ${daysOverdue} dias.`,
              { actionUrl: '/portal/financeiro', actionLabel: 'Regularizar',
                financialId: financialDoc.id, expiresInDays: 30 }
            );
          }
        }
      }

      // Notify admin about overdue summary (push + internal)
      if (overdueCount > 0) {
        const adminId = academy.ownerId || academy.adminUserId;
        const totalFormatted = (totalOverdueAmount / 100).toFixed(2);
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
          const userId = await getBillingRecipientUid(financial.studentId, academyId);
          if (userId) {
            const daysUntilDue = Math.ceil(
              (dueDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)
            );

            const amtFormatted = (financial.amount / 100).toFixed(2);
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
        }
      }
    }

    console.log('Due soon reminder completed');
    return null;
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
  const bufferMs = 5 * 60 * 1000;

  const readTokens = async () => {
    const s = await ref.get();
    if (!s.exists || !s.data().refreshToken) {
      throw new HttpsError('failed-precondition', 'Academia não conectou o Mercado Pago.');
    }
    return s.data();
  };

  const d = await readTokens();
  const exp = (x) => (x && typeof x.toMillis === 'function') ? x.toMillis() : 0;
  if (d.accessToken && Date.now() < exp(d.expiresAt) - bufferMs) {
    return d.accessToken;
  }

  // Token expired/near expiry. Acquire a lock so concurrent calls don't both
  // refresh — MP ROTATES the refresh_token on every refresh, so a double
  // refresh would invalidate the connection.
  try {
    await lockRef.create({ at: admin.firestore.FieldValue.serverTimestamp() });
  } catch (_) {
    // Another call is refreshing — wait briefly and return the fresh token.
    await new Promise((r) => setTimeout(r, 2000));
    return (await readTokens()).accessToken;
  }
  try {
    const fresh = await readTokens();
    if (fresh.accessToken && Date.now() < exp(fresh.expiresAt) - bufferMs) {
      return fresh.accessToken; // someone else refreshed before we locked
    }
    const tok = await mpRequest('POST', '/oauth/token', {
      body: {
        client_id: process.env.MP_OAUTH_CLIENT_ID,
        client_secret: process.env.MP_OAUTH_CLIENT_SECRET,
        grant_type: 'refresh_token',
        refresh_token: fresh.refreshToken,
      },
    });
    await ref.set({
      accessToken: tok.access_token,
      refreshToken: tok.refresh_token || fresh.refreshToken,
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + (Number(tok.expires_in) || 0) * 1000),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
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
    return res.status(200).send(
      '<html><body style="font-family:sans-serif;text-align:center;padding:40px">' +
      '<h2>Mercado Pago conectado!</h2>' +
      '<p>Pode fechar esta janela e voltar ao app.</p></body></html>');
  } catch (e) {
    console.error('[mpOAuthCallback] erro', e.message, e.data);
    return res.status(500).send('Falha ao conectar o Mercado Pago. Tente novamente.');
  }
});

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
  const text = `${e && e.data ? JSON.stringify(e.data) : ''} ${e && e.message ? e.message : ''}`
    .toLowerCase();
  if (text.includes('without key enabled for qr') || text.includes('qr render')) {
    return new HttpsError('failed-precondition',
      'A conta Mercado Pago da academia ainda nao tem uma chave PIX habilitada. ' +
      'Ative o PIX no app do Mercado Pago e tente novamente.');
  }
  return new HttpsError('internal', 'Falha ao gerar a cobranca PIX.');
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
  let payment;
  try {
    payment = await mpRequest('POST', '/v1/payments', {
      token,
      idempotencyKey: externalReference,
      body: {
        transaction_amount: Number(transactionAmount.toFixed(2)),
        description: description || 'Pagamento',
        payment_method_id: 'pix',
        date_of_expiration: expiresAt.toISOString(),
        external_reference: externalReference,
        notification_url: `${mpMktWebhookUrl()}?acad=${encodeURIComponent(academyId)}`,
        application_fee: 0,
        payer: {
          email: (payer && payer.email) || 'sememail@bjjeasy.com.br',
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

  // Idempotency: reuse a still-valid PIX so the kid and the responsible adult
  // opening the same charge get the SAME code (no double charge).
  const existingExpiry = fin.pixExpiresAt && typeof fin.pixExpiresAt.toMillis === 'function'
    ? fin.pixExpiresAt.toMillis() : 0;
  if (fin.gatewayPaymentId && fin.pixCode && existingExpiry > Date.now()) {
    return {
      pixCode: fin.pixCode,
      qrCodeUrl: fin.pixQrCode || '',
      paymentId: fin.gatewayPaymentId,
      expiresAt: fin.pixExpiresAt.toDate().toISOString(),
    };
  }

  const pix = await createMpPix({
    academyId,
    transactionAmount: amount / 100, // centavos -> reais
    description: sanitizeString(description) || 'Mensalidade',
    externalReference: `${academyId}:fin:${financialId}`,
    payer: { email: payerEmail, cpf: payerCpf, name: studentName },
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

  const existingExpiry = order.pixExpiresAt && typeof order.pixExpiresAt.toMillis === 'function'
    ? order.pixExpiresAt.toMillis() : 0;
  if (order.gatewayPaymentId && order.pixCode && existingExpiry > Date.now()) {
    return {
      pixCode: order.pixCode,
      qrCodeUrl: order.pixQrCode || '',
      paymentId: order.gatewayPaymentId,
      expiresAt: order.pixExpiresAt.toDate().toISOString(),
    };
  }

  const pix = await createMpPix({
    academyId,
    transactionAmount: Number(amount), // already in reais
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
  if (snap.data().status === 'paid') {
    throw new HttpsError('already-exists', 'Already paid');
  }
  if (!isOrder && snap.data().studentId !== studentId) {
    throw new HttpsError('permission-denied', 'Record does not belong to this student');
  }

  // mensalidade=centavos, loja=reais (match the PIX contracts).
  const transactionAmount = isOrder ? Number(amount) : amount / 100;
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
        application_fee: 0,
        payer: {
          email: payerEmail || 'sememail@bjjeasy.com.br',
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
    const secret = process.env.MP_MKT_WEBHOOK_SECRET;
    if (secret) {
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
    await orderRef.update({
      status: 'paid',
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      paymentMethod: method,
      paymentGateway: 'mercadopago',
      gatewayPaymentId: chargeId,
      externalPaymentId: chargeId,
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
  await finRef.update({
    status: 'paid',
    paymentDate: admin.firestore.FieldValue.serverTimestamp(),
    method: method,
    paymentGateway: 'mercadopago',
    gatewayPaymentId: chargeId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await notifyAdminCF(academyId, 'payment_received', 'Pagamento Recebido',
    `Pagamento de R$ ${amtFmt} recebido ${viaLabel}.`, { financialId: docId });
}
