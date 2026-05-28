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
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const crypto = require('crypto');

// Cloud Functions run in UTC by default. Pin the process timezone to Brazil
// so selfCheckin's operating-hours check (getHours/getDay) and any date-based
// math use local wall-clock time. Academies outside this zone would need this
// revisited (e.g. a per-academy timezone setting).
process.env.TZ = 'America/Sao_Paulo';

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

/**
 * Whether `now` falls inside the academy's configured operating hours.
 * `raw` is the Firestore map { "<dow>": { open: "HH:mm", close: "HH:mm" } }
 * where dow is 0=Sun..6=Sat (matches the app's OperatingHours). Empty/absent
 * config means no time gate (returns true). Mirrors OperatingHours.isOpenAt.
 */
function isWithinOperatingHours(raw) {
  if (!raw || typeof raw !== 'object' || Object.keys(raw).length === 0) {
    return true;
  }
  const now = new Date();
  const dow = now.getDay(); // JS getDay: 0=Sun..6=Sat
  const window = raw[String(dow)];
  if (!window || !window.open || !window.close) return false;
  const toMin = (s) => {
    const parts = String(s).split(':');
    return (parseInt(parts[0], 10) || 0) * 60 + (parseInt(parts[1], 10) || 0);
  };
  const cur = now.getHours() * 60 + now.getMinutes();
  return cur >= toMin(window.open) && cur < toMin(window.close);
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
    const hasEntry = !!details[academyId];

    // Legacy monitors were added via academy.monitorIds only and have no
    // academyDetails entry. Resolve their studentId from the students
    // subcollection so we can synthesise the entry and let the promote proceed
    // (previously this threw failed-precondition — the reported promote error).
    // All reads must precede writes in a transaction.
    let studentId = hasEntry ? (details[academyId].studentId || null) : null;
    if (!hasEntry) {
      const studentsSnap = await tx.get(
          db.collection('academies').doc(academyId)
              .collection('students')
              .where('linkedUserId', '==', userId)
              .limit(1),
      );
      studentId = studentsSnap.empty ? null : studentsSnap.docs[0].id;
    }

    // One field-path update: creates the entry when missing (keeping studentId
    // so the user stays linked to their student record), otherwise just flips
    // role → instructor. Distinct leaf paths never conflict.
    const update = {
      [`academyDetails.${academyId}.role`]: 'instructor',
      [`academyDetails.${academyId}.status`]: 'active',
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!hasEntry) {
      update.academyIds = FieldValue.arrayUnion(academyId);
      update.primaryAcademyId = data.primaryAcademyId || academyId;
      update[`academyDetails.${academyId}.studentId`] = studentId;
      update[`academyDetails.${academyId}.joinedAt`] = FieldValue.serverTimestamp();
    }
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
// selfCheckin — student self check-in for schedule-less modalities (musculação)
// ============================================================
//
// Body: { academyId: string }
// The student (caller) records their own attendance for musculação. Used by the
// "button" and "fixed QR" check-in modes, where the client cannot write to the
// attendance subcollection directly (rules restrict it to staff/monitors).
//
// Validates server-side: membership (resolves the caller's studentId from the
// mapping), the academy's configured mode allows self check-in, operating
// hours, that the student practices musculação and is active, and one-per-day
// dedup via a deterministic doc id. Mirrors AttendanceService.markPresent so
// reports and counts stay consistent.
exports.selfCheckin = onCall(async (request) => {
  const uid = requireAuth(request);
  const academyId = (request.data && request.data.academyId || '').toString().trim();
  if (!academyId) {
    throw new HttpsError('invalid-argument', 'academyId é obrigatório.');
  }

  // 1. Resolve caller's studentId for this academy from the mapping.
  const mappingSnap = await db.collection('userAcademyMapping').doc(uid).get();
  const details = (mappingSnap.exists && (mappingSnap.data().academyDetails || {})) || {};
  const entry = details[academyId];
  if (!entry || !entry.studentId) {
    throw new HttpsError('permission-denied', 'Você não pertence a esta academia.');
  }
  const studentId = entry.studentId;

  // 2. Academy mode must allow self check-in and respect operating hours.
  const academyRef = db.collection('academies').doc(academyId);
  const academySnap = await academyRef.get();
  const settings = (academySnap.exists && academySnap.data()) || {};
  const mode = settings.musculacaoCheckinMode || 'manual';
  if (mode !== 'qr' && mode !== 'button') {
    throw new HttpsError('failed-precondition',
        'O check-in pelo aluno não está habilitado nesta academia.');
  }
  if (!isWithinOperatingHours(settings.operatingHours)) {
    throw new HttpsError('failed-precondition',
        'Fora do horário de funcionamento da academia.');
  }

  // 3. Student must exist, practice musculação, and be active.
  const studentRef = academyRef.collection('students').doc(studentId);
  const studentSnap = await studentRef.get();
  if (!studentSnap.exists) {
    throw new HttpsError('not-found', 'Aluno não encontrado.');
  }
  const student = studentSnap.data() || {};
  const sports = Array.isArray(student.sports) ? student.sports : [];
  if (!sports.includes('musculacao')) {
    throw new HttpsError('failed-precondition',
        'Você não está matriculado na musculação.');
  }
  if (student.status && student.status !== 'active') {
    throw new HttpsError('failed-precondition', 'Sua matrícula não está ativa.');
  }

  // 4. Deterministic id → one check-in per day. Transaction makes it idempotent
  //    (matches AttendanceService._deterministicAttendanceId).
  const now = new Date();
  const y = now.getFullYear().toString().padStart(4, '0');
  const m = (now.getMonth() + 1).toString().padStart(2, '0');
  const d = now.getDate().toString().padStart(2, '0');
  const docId = `${studentId}_musculacao_${y}${m}${d}`;
  const attendanceRef = academyRef.collection('attendance').doc(docId);
  const studentName = student.fullName || student.nickname || 'Aluno';

  await db.runTransaction(async (tx) => {
    const existing = await tx.get(attendanceRef);
    if (existing.exists) {
      throw new HttpsError('already-exists', 'Você já registrou presença hoje.');
    }
    tx.set(attendanceRef, {
      studentId,
      studentName,
      classId: 'musculacao',
      className: 'Musculação',
      date: Timestamp.fromDate(now),
      verifiedBy: uid,
      verifiedByName: studentName,
      sport: 'musculacao',
      source: mode === 'qr' ? 'self_qr' : 'self_button',
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(studentRef, {
      attendanceCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return {success: true, checkedInAt: now.toISOString()};
});

// ============================================================
// caktoWebhook — recebe eventos do Cakto e concede/revoga a
// subscription da academia.
//
// Formato real do Cakto (doc oficial):
//   payload = { secret, event, data: { id, refId, customer:{email,...},
//     offer:{id,name,price}, product:{id,...}, amount, paymentMethod, paidAt } }
//   Autenticação: campo `secret` NO CORPO (não há header HMAC).
//
// Config Firebase:
//   firebase functions:secrets:set CAKTO_WEBHOOK_SECRET
//
// Mapa de ofertas → período (usa offer.id, pois as 3 ofertas do produto
// "BJJEasy" compartilham o mesmo product.id):
//   CAKTO_OFFER_MENSAL, CAKTO_OFFER_TRIMESTRAL, CAKTO_OFFER_ANUAL
// ============================================================
exports.caktoWebhook = onRequest(
  {cors: false, secrets: ['CAKTO_WEBHOOK_SECRET']},
  async (req, res) => {
    if (req.method !== 'POST') {
      return res.status(405).send('Method Not Allowed');
    }

    const payload = req.body || {};

    // ---- Autenticação: o Cakto manda o `secret` no corpo (não em header) ----
    const expectedSecret = process.env.CAKTO_WEBHOOK_SECRET;
    if (expectedSecret) {
      const provided = Buffer.from(String(payload.secret || ''));
      const expected = Buffer.from(String(expectedSecret));
      if (
        provided.length !== expected.length ||
        !crypto.timingSafeEqual(provided, expected)
      ) {
        console.warn('[caktoWebhook] secret mismatch — requisição rejeitada');
        return res.status(401).json({error: 'invalid secret'});
      }
    }

    const event = String(payload.event || payload.type || '');
    // O Cakto manda `data` como ARRAY de pedidos; usamos o primeiro.
    const data = Array.isArray(payload.data)
        ? (payload.data[0] || {})
        : (payload.data || payload);

    // ---- Classificar evento (nomes reais do Cakto) ----
    const grantEvents = [
      'purchase_approved',
      'subscription_created',
      'subscription_renewed',
    ];
    const revokeEvents = ['refund', 'chargeback'];
    // Falha de renovação recorrente → marca past_due (não revoga na hora).
    // ⚠️ Nomes a CONFIRMAR com um evento real do Cakto (a doc não cita o de
    // falha de cobrança recorrente). Estes são defensivos.
    const pastDueEvents = [
      'subscription_renewal_refused',
      'subscription_renewal_failed',
      'subscription_late',
      'purchase_refused',
      'payment_failed',
    ];
    const isGrant = grantEvents.includes(event);
    const isRevoke = revokeEvents.includes(event);
    const isCancel = event === 'subscription_canceled';
    const isPastDue = pastDueEvents.includes(event);

    if (!isGrant && !isRevoke && !isCancel && !isPastDue) {
      return res.status(200).json({received: true, skipped: event});
    }

    // ---- Resolver a academia: academyId (passado como ?src= → vem em `sck`)
    // primeiro; senão, e-mail do comprador (pré-preenchido = login do dono). ----
    const srcAcademyId =
      data.sck || data.src || payload.src || null;
    const buyerEmail =
      data.customer?.email || data.buyer?.email || data.email || null;

    let academyRef = null;

    if (srcAcademyId) {
      const snap = await db
        .collection('academies')
        .doc(String(srcAcademyId))
        .get();
      if (snap.exists) academyRef = snap.ref;
    }

    if (!academyRef && buyerEmail) {
      let uid;
      try {
        uid = (await getAuth().getUserByEmail(buyerEmail)).uid;
      } catch (e) {
        console.warn('[caktoWebhook] user not found for email:', buyerEmail);
        return res
          .status(200)
          .json({received: true, warning: 'user_not_found', email: buyerEmail});
      }
      const academySnap = await db
        .collection('academies')
        .where('ownerId', '==', uid)
        .limit(1)
        .get();
      if (!academySnap.empty) academyRef = academySnap.docs[0].ref;
    }

    if (!academyRef) {
      console.warn('[caktoWebhook] academy not resolved', {srcAcademyId, buyerEmail});
      return res.status(200).json({received: true, warning: 'academy_not_found'});
    }
    const academyId = academyRef.id;

    // ---- Reembolso / chargeback → revoga acesso imediatamente ----
    if (isRevoke) {
      await academyRef.update({
        'subscription.status': 'cancelled',
        'subscription.plan': 'free',
        'subscription.paidUntil': Timestamp.fromDate(new Date()),
        'subscription.lastEvent': event,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      console.log('[caktoWebhook] access revoked', {academyId, event});
      return res.status(200).json({success: true, academyId, action: 'revoked'});
    }

    // ---- Cancelamento de assinatura → mantém acesso até o paidUntil atual ----
    if (isCancel) {
      await academyRef.update({
        'subscription.status': 'cancelled',
        'subscription.lastEvent': event,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      console.log('[caktoWebhook] subscription canceled (acesso até paidUntil)', {academyId});
      return res.status(200).json({success: true, academyId, action: 'canceled'});
    }

    // ---- Falha de renovação → marca past_due (não mexe no paidUntil; o app
    // mostra a tela "atualize seu pagamento" quando o acesso expirar). ----
    if (isPastDue) {
      await academyRef.update({
        'subscription.status': 'past_due',
        'subscription.lastEvent': event,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      console.log('[caktoWebhook] subscription past_due', {academyId, event});
      return res.status(200).json({success: true, academyId, action: 'past_due'});
    }

    // ---- Conceder/estender acesso ----
    // Período: o Cakto manda `subscription.recurrence_period` = ciclo em DIAS
    // (mensal=30, trimestral=90, anual=365). É o sinal mais confiável, pois
    // independe do nome/id da oferta — funciona até para ofertas novas. Só
    // caímos no offer id (env) / nome da oferta se o ciclo não vier.
    const recurrenceDays = Number(
      data.subscription?.recurrence_period ?? data.recurrence_period ?? 0,
    );
    const offerId = data.offer?.id || data.offer_id || null;
    const offerName = String(data.offer?.name || '').toLowerCase();

    const anualOffer = process.env.CAKTO_OFFER_ANUAL || '';
    const trimestralOffer = process.env.CAKTO_OFFER_TRIMESTRAL || '';
    const mensalOffer = process.env.CAKTO_OFFER_MENSAL || '';

    const graceDays = 5; // folga p/ atraso de webhook/renovação
    let daysToAdd;
    if (recurrenceDays > 0) {
      daysToAdd = recurrenceDays + graceDays; // 30→35, 90→95, 365→370
    } else if (offerId && offerId === anualOffer) {
      daysToAdd = 370;
    } else if (offerId && offerId === trimestralOffer) {
      daysToAdd = 95;
    } else if (offerId && offerId === mensalOffer) {
      daysToAdd = 35;
    } else if (offerName.includes('anual')) {
      daysToAdd = 370;
    } else if (offerName.includes('trimestral')) {
      daysToAdd = 95;
    } else {
      daysToAdd = 35; // default: mensal + buffer
    }

    const snap = await academyRef.get();

    // Idempotência: se já processamos exatamente esta cobrança (mesmo id), não
    // estende de novo. Evita double-grant quando o Cakto manda mais de um evento
    // para a mesma compra (ex.: purchase_approved + subscription_created) com o
    // mesmo id, ou em reentregas. (Eventos com ids distintos pra mesma cobrança
    // ainda precisam ser confirmados na compra real e tratados se necessário.)
    const chargeId = data.id || data.transaction_id || null;
    if (chargeId && snap.get('subscription.externalPaymentId') === chargeId) {
      console.log('[caktoWebhook] evento duplicado ignorado', {academyId, chargeId, event});
      return res.status(200).json({success: true, academyId, action: 'duplicate'});
    }

    // Estende a partir do maior entre hoje e o paidUntil atual — assim uma
    // renovação não encurta o período já pago.
    const current = snap.get('subscription.paidUntil');
    const now = new Date();
    let base = now;
    if (current && typeof current.toDate === 'function' && current.toDate() > now) {
      base = current.toDate();
    }
    const paidUntil = new Date(base);
    paidUntil.setDate(paidUntil.getDate() + daysToAdd);

    await academyRef.update({
      'subscription.plan': 'pro',
      'subscription.status': 'active',
      'subscription.paidUntil': Timestamp.fromDate(paidUntil),
      'subscription.lastPaymentAt': FieldValue.serverTimestamp(),
      'subscription.lastEvent': event,
      'subscription.externalPaymentId': chargeId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    console.log('[caktoWebhook] access granted', {academyId, event, offerId, recurrenceDays, daysToAdd, paidUntil});
    return res.status(200).json({success: true, academyId, action: 'granted', paidUntil});
  },
);

/* DESABILITADO TEMPORARIAMENTE — cobrança por e-mail será finalizada depois.
   Mantido comentado pra não disparar e-mails enquanto não está 100%.
// ============================================================
// trialExpiryReminder — agendado (diário). Avisa por e-mail o dono de
// academias cujo trial vence nas próximas ~48h e que ainda não assinaram.
// Reusa o notification-server (mesmo do billing): POST /api/send-email,
// appId "gestao-raiz" (SMTP do BJJEasy).
//
// Config Firebase:
//   firebase functions:secrets:set NOTIFICATION_API_KEY   (x-api-key do server)
//   (opcional) NOTIFICATION_API_URL — default: .../api/send-email
// ============================================================
async function sendTrialReminderEmail(email, academyName, daysLeft) {
  const url = process.env.NOTIFICATION_API_URL ||
    'https://notification.tensorroot.com/api/send-email';
  const key = process.env.NOTIFICATION_API_KEY || '';
  const dias = daysLeft <= 1 ? '1 dia' : `${daysLeft} dias`;
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(key ? {'x-api-key': key} : {}),
      },
      body: JSON.stringify({
        appId: 'gestao-raiz',
        email,
        subject: `Seu teste gratis do BJJEasy termina em ${dias}`,
        message:
          `Ola! Seu periodo de avaliacao gratis do BJJEasy termina em ${dias}.\n\n` +
          `Assine para continuar gerenciando ${academyName} sem interrupcoes — ` +
          `alunos, graduacoes, financeiro, check-in e o portal do aluno.\n\n` +
          `Abra o app e escolha seu plano. Qualquer duvida, e so chamar o suporte.`,
      }),
    });
    return res.ok;
  } catch (e) {
    console.error('[trialReminder] email failed for', email, e.message);
    return false;
  }
}

exports.trialExpiryReminder = onSchedule(
  {
    schedule: 'every day 13:00',
    timeZone: 'America/Sao_Paulo',
    // NOTIFICATION_API_KEY vem de functions/.env (a conta atual não tem
    // permissão de IAM no Secret Manager). A chave já é pública no build.sh.
  },
  async () => {
    // Trial = createdAt + TRIAL_DAYS (mesma regra do gate no app). "Vence em
    // ~0–2 dias" → createdAt entre (now - TRIAL_DAYS) e (now - (TRIAL_DAYS-2)].
    const TRIAL_DAYS = 7; // = AppConstants.trialDays no app
    const now = new Date();
    const createdAfter = new Date(now);
    createdAfter.setDate(createdAfter.getDate() - TRIAL_DAYS);
    const createdBefore = new Date(now);
    createdBefore.setDate(createdBefore.getDate() - (TRIAL_DAYS - 2));

    const snap = await db
      .collection('academies')
      .where('createdAt', '>', Timestamp.fromDate(createdAfter))
      .where('createdAt', '<=', Timestamp.fromDate(createdBefore))
      .get();

    let sent = 0;
    for (const doc of snap.docs) {
      const data = doc.data();
      const sub = data.subscription || {};
      // Pula quem já paga, é cortesia, ou já foi avisado neste ciclo de trial.
      if (sub.freeOverride === true) continue;
      if (sub.paidUntil && sub.paidUntil.toDate() > now) continue;
      if (sub.trialReminderSentAt) continue;

      // E-mail do dono: login (Auth) primeiro; senão o contato da academia.
      let email = null;
      if (data.ownerId) {
        try {
          email = (await getAuth().getUser(data.ownerId)).email || null;
        } catch (_) {}
      }
      if (!email) email = data.email || null;
      if (!email) continue;

      const created =
        data.createdAt && typeof data.createdAt.toDate === 'function'
          ? data.createdAt.toDate()
          : null;
      if (!created) continue;
      const trialEnd = new Date(created);
      trialEnd.setDate(trialEnd.getDate() + TRIAL_DAYS);
      if (trialEnd <= now) continue; // já venceu (segurança)
      const daysLeft = Math.max(
        1,
        Math.ceil((trialEnd.getTime() - now.getTime()) / 86400000),
      );

      const ok = await sendTrialReminderEmail(
        email,
        data.name || 'sua academia',
        daysLeft,
      );
      if (ok) {
        await doc.ref.update({
          'subscription.trialReminderSentAt': FieldValue.serverTimestamp(),
        });
        sent++;
      }
    }
    console.log(`[trialReminder] checked ${snap.size}, sent ${sent}`);
  },
);
*/

// ============================================================
// Server-side functions (payments + notifications) migrated from the
// discontinued ERP web repo. Required AFTER initializeApp() so the module's
// top-level admin.firestore()/admin.messaging() resolve against the default
// app. Callables are gen2; Firestore triggers and scheduled jobs are gen1.
// They coexist with the gen2 functions above (no name collisions).
// ============================================================
Object.assign(exports, require('./server_functions'));
