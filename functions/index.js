/**
 * GraduaBJJ Cloud Functions
 *
 * Role/membership operations that require admin privilege (bypass client-side
 * Firestore Rules). After the security hardening in firestore.rules, these are
 * the only paths that can:
 *   - Add a second academy to an existing user's mapping (any role)
 *   - Promote / demote a member to instructor
 *   - Revoke membership cleanly
 *
 * All functions are HTTPS callable; the client invokes them via
 * `FirebaseFunctions.httpsCallable('name')`.
 */

const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const crypto = require('crypto');

initializeApp();

const db = getFirestore();

// ============================================================
// Helpers
// ============================================================

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'Login required.');
  }
  return request.auth.uid;
}

/** Returns true when uid is admin of academyId per userAcademyMapping. */
async function isAdmin(uid, academyId) {
  const snap = await db.collection('userAcademyMapping').doc(uid).get();
  if (!snap.exists) return false;
  const data = snap.data() || {};
  const details = data.academyDetails || {};
  const entry = details[academyId];
  return entry && entry.role === 'admin';
}

/** Returns true when uid is admin OR instructor of academyId. */
async function isStaff(uid, academyId) {
  const snap = await db.collection('userAcademyMapping').doc(uid).get();
  if (!snap.exists) return false;
  const data = snap.data() || {};
  const details = data.academyDetails || {};
  const entry = details[academyId];
  return entry && (entry.role === 'admin' || entry.role === 'instructor');
}

// ============================================================
// joinAcademy — student joining an academy via student link code
// ============================================================
//
// Body: { code: string }
// Adds caller to userAcademyMapping with role='student' and marks code used.
// Used both for the FIRST academy (caller had no mapping) and for ADDITIONAL
// academies (caller already has a mapping pointing at another academy).
exports.joinAcademy = onCall(async (request) => {
  const uid = requireAuth(request);
  const code = (request.data && request.data.code || '').toString().trim().toUpperCase();
  if (!code) {
    throw new HttpsError('invalid-argument', 'Código é obrigatório.');
  }

  // 1. Find code via collectionGroup. Codes are unique by string within each
  //    academy, but we accept the first unused match.
  const codeQuery = await db
      .collectionGroup('linkCodes')
      .where('code', '==', code)
      .where('usedAt', '==', null)
      .limit(1)
      .get();

  if (codeQuery.empty) {
    throw new HttpsError('not-found', 'Código inválido ou já utilizado.');
  }

  const codeDoc = codeQuery.docs[0];
  const codeData = codeDoc.data() || {};
  const codeRef = codeDoc.ref;
  const academyId = codeRef.parent.parent.id; // .../academies/{id}/linkCodes/{code}

  // 2. Expiry check
  if (codeData.expiresAt && codeData.expiresAt.toDate() < new Date()) {
    throw new HttpsError('failed-precondition', 'Este código expirou.');
  }

  // 3. Fetch caller's current mapping (may not exist yet)
  const mappingRef = db.collection('userAcademyMapping').doc(uid);
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError('failed-precondition', 'Usuário sem documento root.');
  }
  const userData = userSnap.data() || {};

  // 4. Atomic: add academy to mapping + mark code used + upsert academy user doc.
  await db.runTransaction(async (tx) => {
    const mappingSnap = await tx.get(mappingRef);
    const mappingData = mappingSnap.exists ? (mappingSnap.data() || {}) : null;

    // Refuse double-join
    if (mappingData && Array.isArray(mappingData.academyIds) &&
        mappingData.academyIds.includes(academyId)) {
      throw new HttpsError('already-exists', 'Você já está vinculado a esta academia.');
    }

    const detailEntry = {
      studentId: codeData.studentId || null,
      role: 'student',
      joinedAt: FieldValue.serverTimestamp(),
      status: 'active',
    };

    if (mappingData) {
      tx.update(mappingRef, {
        academyIds: FieldValue.arrayUnion(academyId),
        primaryAcademyId: mappingData.primaryAcademyId || academyId,
        [`academyDetails.${academyId}`]: detailEntry,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      tx.set(mappingRef, {
        academyIds: [academyId],
        primaryAcademyId: academyId,
        academyDetails: {[academyId]: detailEntry},
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    // Mark code used
    tx.update(codeRef, {
      usedAt: FieldValue.serverTimestamp(),
      usedBy: uid,
      usedByName: userData.displayName || userData.email || uid,
    });

    // Upsert academy-scoped user doc (legacy reads still depend on this)
    const academyUserRef = db
        .collection('academies').doc(academyId)
        .collection('users').doc(uid);
    tx.set(academyUserRef, {
      role: 'student',
      email: userData.email || null,
      displayName: userData.displayName || null,
      status: 'active',
      isActive: true,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    // Bump accountType from 'free' to 'linked' if needed
    if (userData.accountType !== 'linked') {
      tx.update(userRef, {
        accountType: 'linked',
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });

  return {
    success: true,
    academyId,
    studentId: codeData.studentId || null,
  };
});

// ============================================================
// redeemInstructorCode — instructor joining via instructor code
// ============================================================
//
// Body: { code: string }
// Adds caller as 'instructor' with extraPermissions stamped by the code.
exports.redeemInstructorCode = onCall(async (request) => {
  const uid = requireAuth(request);
  const code = (request.data && request.data.code || '').toString().trim().toUpperCase();
  if (!code) {
    throw new HttpsError('invalid-argument', 'Código é obrigatório.');
  }

  const codeQuery = await db
      .collectionGroup('instructorLinkCodes')
      .where('code', '==', code)
      .where('usedAt', '==', null)
      .limit(1)
      .get();

  if (codeQuery.empty) {
    throw new HttpsError('not-found', 'Código inválido ou já utilizado.');
  }

  const codeDoc = codeQuery.docs[0];
  const codeData = codeDoc.data() || {};
  const codeRef = codeDoc.ref;
  const academyId = codeRef.parent.parent.id;

  if (codeData.expiresAt && codeData.expiresAt.toDate() < new Date()) {
    throw new HttpsError('failed-precondition', 'Este código expirou.');
  }

  const mappingRef = db.collection('userAcademyMapping').doc(uid);
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError('failed-precondition', 'Usuário sem documento root.');
  }
  const userData = userSnap.data() || {};

  await db.runTransaction(async (tx) => {
    const mappingSnap = await tx.get(mappingRef);
    const mappingData = mappingSnap.exists ? (mappingSnap.data() || {}) : null;

    if (mappingData && Array.isArray(mappingData.academyIds) &&
        mappingData.academyIds.includes(academyId)) {
      throw new HttpsError('already-exists', 'Você já está vinculado a esta academia.');
    }

    const detailEntry = {
      studentId: null,
      role: 'instructor',
      joinedAt: FieldValue.serverTimestamp(),
      status: 'active',
    };
    if (Array.isArray(codeData.extraPermissions) && codeData.extraPermissions.length > 0) {
      detailEntry.extraPermissions = codeData.extraPermissions;
    }

    if (mappingData) {
      tx.update(mappingRef, {
        academyIds: FieldValue.arrayUnion(academyId),
        primaryAcademyId: mappingData.primaryAcademyId || academyId,
        [`academyDetails.${academyId}`]: detailEntry,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      tx.set(mappingRef, {
        academyIds: [academyId],
        primaryAcademyId: academyId,
        academyDetails: {[academyId]: detailEntry},
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    tx.update(codeRef, {
      usedAt: FieldValue.serverTimestamp(),
      usedBy: uid,
      usedByName: userData.displayName || userData.email || uid,
    });

    const academyUserRef = db
        .collection('academies').doc(academyId)
        .collection('users').doc(uid);
    tx.set(academyUserRef, {
      role: 'instructor',
      email: userData.email || null,
      displayName: userData.displayName || null,
      status: 'active',
      isActive: true,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    if (userData.accountType !== 'linked') {
      tx.update(userRef, {
        accountType: 'linked',
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });

  return {success: true, academyId};
});

// ============================================================
// promoteToInstructor — admin promoting an existing member
// ============================================================
//
// Body: { userId: string, academyId: string, extraPermissions: string[] }
// Caller must be admin of academyId. Target must already be in the academy.
exports.promoteToInstructor = onCall(async (request) => {
  const adminUid = requireAuth(request);
  const {userId, academyId, extraPermissions} = request.data || {};
  if (!userId || !academyId) {
    throw new HttpsError('invalid-argument', 'userId e academyId são obrigatórios.');
  }
  if (!(await isAdmin(adminUid, academyId))) {
    throw new HttpsError('permission-denied', 'Apenas admins podem promover membros.');
  }

  const mappingRef = db.collection('userAcademyMapping').doc(userId);
  const academyUserRef = db
      .collection('academies').doc(academyId)
      .collection('users').doc(userId);

  await db.runTransaction(async (tx) => {
    const mappingSnap = await tx.get(mappingRef);
    if (!mappingSnap.exists) {
      throw new HttpsError('not-found', 'Usuário não encontrado.');
    }
    const data = mappingSnap.data() || {};
    const details = data.academyDetails || {};
    if (!details[academyId]) {
      throw new HttpsError('failed-precondition',
          'Usuário precisa estar na academia antes de virar instrutor.');
    }

    const update = {
      [`academyDetails.${academyId}.role`]: 'instructor',
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (Array.isArray(extraPermissions)) {
      update[`academyDetails.${academyId}.extraPermissions`] = extraPermissions;
    }
    tx.update(mappingRef, update);

    tx.set(academyUserRef, {
      role: 'instructor',
      status: 'active',
      isActive: true,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {success: true};
});

// ============================================================
// demoteToStudent — admin reverting an instructor back to student
// ============================================================
exports.demoteToStudent = onCall(async (request) => {
  const adminUid = requireAuth(request);
  const {userId, academyId} = request.data || {};
  if (!userId || !academyId) {
    throw new HttpsError('invalid-argument', 'userId e academyId são obrigatórios.');
  }
  if (!(await isAdmin(adminUid, academyId))) {
    throw new HttpsError('permission-denied', 'Apenas admins podem rebaixar membros.');
  }
  if (userId === adminUid) {
    throw new HttpsError('failed-precondition', 'Você não pode rebaixar a si mesmo.');
  }

  const mappingRef = db.collection('userAcademyMapping').doc(userId);
  const academyUserRef = db
      .collection('academies').doc(academyId)
      .collection('users').doc(userId);

  await db.runTransaction(async (tx) => {
    const mappingSnap = await tx.get(mappingRef);
    if (!mappingSnap.exists) {
      throw new HttpsError('not-found', 'Usuário não encontrado.');
    }
    const data = mappingSnap.data() || {};
    const details = data.academyDetails || {};
    if (!details[academyId]) {
      throw new HttpsError('failed-precondition', 'Usuário não pertence a esta academia.');
    }

    tx.update(mappingRef, {
      [`academyDetails.${academyId}.role`]: 'student',
      [`academyDetails.${academyId}.extraPermissions`]: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    tx.set(academyUserRef, {
      role: 'student',
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {success: true};
});

// ============================================================
// revokeMember — admin removing a user from an academy entirely
// ============================================================
exports.revokeMember = onCall(async (request) => {
  const adminUid = requireAuth(request);
  const {userId, academyId} = request.data || {};
  if (!userId || !academyId) {
    throw new HttpsError('invalid-argument', 'userId e academyId são obrigatórios.');
  }
  if (!(await isAdmin(adminUid, academyId))) {
    throw new HttpsError('permission-denied', 'Apenas admins podem remover membros.');
  }
  if (userId === adminUid) {
    throw new HttpsError('failed-precondition', 'Você não pode remover a si mesmo.');
  }

  const mappingRef = db.collection('userAcademyMapping').doc(userId);
  const academyUserRef = db
      .collection('academies').doc(academyId)
      .collection('users').doc(userId);

  await db.runTransaction(async (tx) => {
    const mappingSnap = await tx.get(mappingRef);
    if (!mappingSnap.exists) {
      return; // already gone
    }
    const data = mappingSnap.data() || {};
    const academyIds = Array.isArray(data.academyIds) ? data.academyIds : [];
    const remaining = academyIds.filter((id) => id !== academyId);
    const details = Object.assign({}, data.academyDetails || {});
    delete details[academyId];

    let primary = data.primaryAcademyId;
    if (primary === academyId) {
      primary = remaining.length > 0 ? remaining[0] : null;
    }

    tx.update(mappingRef, {
      academyIds: remaining,
      primaryAcademyId: primary,
      academyDetails: details,
      updatedAt: FieldValue.serverTimestamp(),
    });

    tx.set(academyUserRef, {
      status: 'revoked',
      isActive: false,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {success: true};
});

// ============================================================
// listAcademyMembers — admin listing all staff/students in their academy
// ============================================================
//
// Returns { admins: [...], instructors: [...], students: [...] } each entry
// shaped { userId, displayName, email, role, extraPermissions, studentId }.
//
// Uses the academies/{id}/users subcollection (legacy authoritative for
// per-academy reads). Caller must be staff.
exports.listAcademyMembers = onCall(async (request) => {
  const callerUid = requireAuth(request);
  const {academyId} = request.data || {};
  if (!academyId) {
    throw new HttpsError('invalid-argument', 'academyId é obrigatório.');
  }
  if (!(await isStaff(callerUid, academyId))) {
    throw new HttpsError('permission-denied', 'Sem acesso a esta academia.');
  }

  const usersSnap = await db
      .collection('academies').doc(academyId)
      .collection('users')
      .get();

  const admins = [];
  const instructors = [];
  const students = [];

  for (const doc of usersSnap.docs) {
    const data = doc.data() || {};
    if (data.status === 'revoked' || data.isActive === false) continue;

    // Cross-reference userAcademyMapping for extraPermissions / studentId
    let extraPermissions = [];
    let studentId = null;
    try {
      const mappingSnap = await db.collection('userAcademyMapping').doc(doc.id).get();
      if (mappingSnap.exists) {
        const md = mappingSnap.data() || {};
        const entry = (md.academyDetails || {})[academyId] || {};
        if (Array.isArray(entry.extraPermissions)) {
          extraPermissions = entry.extraPermissions;
        }
        if (typeof entry.studentId === 'string') {
          studentId = entry.studentId;
        }
      }
    } catch (e) {
      // Ignore lookup failures — member still listed without these extras.
    }

    const entry = {
      userId: doc.id,
      displayName: data.displayName || '',
      email: data.email || '',
      role: data.role || 'student',
      extraPermissions,
      studentId,
    };

    if (entry.role === 'admin') admins.push(entry);
    else if (entry.role === 'instructor') instructors.push(entry);
    else students.push(entry);
  }

  return {admins, instructors, students};
});

// ============================================================
// caktoWebhook — recebe eventos de pagamento do Cakto e ativa
// a subscription da academia correspondente ao e-mail do comprador.
//
// Configurar no Firebase:
//   firebase functions:secrets:set CAKTO_WEBHOOK_SECRET
//
// IDs dos produtos Cakto (configurar como secrets ou env vars):
//   CAKTO_PRODUCT_MENSAL, CAKTO_PRODUCT_TRIMESTRAL, CAKTO_PRODUCT_ANUAL
// ============================================================
exports.caktoWebhook = onRequest(
  {cors: false, secrets: ['CAKTO_WEBHOOK_SECRET']},
  async (req, res) => {
    if (req.method !== 'POST') {
      return res.status(405).send('Method Not Allowed');
    }

    // ---- Validação de assinatura HMAC-SHA256 ----
    const secret = process.env.CAKTO_WEBHOOK_SECRET;
    if (secret) {
      const signature = req.headers['x-cakto-signature'] || req.headers['x-webhook-signature'];
      if (!signature) {
        return res.status(401).json({error: 'Missing signature'});
      }
      const body = JSON.stringify(req.body);
      const expected = crypto.createHmac('sha256', secret).update(body).digest('hex');
      if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
        return res.status(401).json({error: 'Invalid signature'});
      }
    }

    const payload = req.body;
    // Cakto pode enviar o evento no root ou em payload.event
    const event = payload.event || payload.type || '';

    // Só processa eventos de pagamento confirmado / assinatura ativa
    const relevantEvents = [
      'payment.confirmed',
      'payment.approved',
      'subscription.active',
      'subscription.renewed',
      'order.paid',
    ];
    if (!relevantEvents.includes(event)) {
      return res.status(200).json({received: true, skipped: event});
    }

    // ---- Extrair e-mail e produto ----
    const data = payload.data || payload;
    const buyerEmail =
      data.customer?.email ||
      data.buyer?.email ||
      data.email ||
      null;
    const productId =
      data.product?.id ||
      data.offer?.id ||
      data.offer_id ||
      data.product_id ||
      null;

    if (!buyerEmail) {
      console.warn('[caktoWebhook] Missing buyer email in payload', JSON.stringify(payload));
      return res.status(200).json({received: true, warning: 'missing_email'});
    }

    // ---- Mapear e-mail → uid Firebase ----
    let uid;
    try {
      const userRecord = await getAuth().getUserByEmail(buyerEmail);
      uid = userRecord.uid;
    } catch (e) {
      console.warn('[caktoWebhook] Firebase user not found for email:', buyerEmail);
      return res.status(200).json({received: true, warning: 'user_not_found', email: buyerEmail});
    }

    // ---- Encontrar academia do owner ----
    const academySnap = await db
      .collection('academies')
      .where('ownerId', '==', uid)
      .limit(1)
      .get();

    if (academySnap.empty) {
      console.warn('[caktoWebhook] Academy not found for uid:', uid);
      return res.status(200).json({received: true, warning: 'academy_not_found'});
    }

    const academyId = academySnap.docs[0].id;

    // ---- Calcular paidUntil com base no produto ----
    const mensalId = process.env.CAKTO_PRODUCT_MENSAL || 'MENSAL_ID';
    const trimestralId = process.env.CAKTO_PRODUCT_TRIMESTRAL || 'TRIMESTRAL_ID';
    const anualId = process.env.CAKTO_PRODUCT_ANUAL || 'ANUAL_ID';

    let daysToAdd = 35; // default: mensal + 4 dias de buffer
    if (productId === trimestralId) daysToAdd = 95;
    else if (productId === anualId) daysToAdd = 370;

    const paidUntil = new Date();
    paidUntil.setDate(paidUntil.getDate() + daysToAdd);

    // ---- Atualizar Firestore ----
    await db.collection('academies').doc(academyId).update({
      'subscription.plan': 'pro',
      'subscription.status': 'active',
      'subscription.paidUntil': Timestamp.fromDate(paidUntil),
      'subscription.lastPaymentAt': FieldValue.serverTimestamp(),
      'subscription.externalPaymentId': data.id || data.transaction_id || null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    console.log('[caktoWebhook] Subscription activated', {academyId, buyerEmail, paidUntil, daysToAdd});
    return res.status(200).json({success: true, academyId, paidUntil});
  },
);
