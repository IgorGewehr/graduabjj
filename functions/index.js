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

// Server-side allowlist of extra permissions an admin may grant to an
// instructor. Mirrors kGrantableExtraPermissions in
// lib/services/instructor_link_code_service.dart — keep these in sync.
// Authoritative: any key NOT in this set is silently dropped, so a forged
// instructorLinkCodes doc (or a tampered call) cannot escalate privilege.
const GRANTABLE_EXTRA_PERMISSIONS = new Set([
  'attendance:take',
  'financial:view',
  'financial:create',
  'students:create',
  'students:delete',
  'reports:view',
  'competitions:create',
  'graduation:manage',
  'students:manage',
]);

/**
 * Clamp an arbitrary extraPermissions value to the grantable allowlist.
 * Returns a de-duplicated array containing only allowed string permissions.
 */
function sanitizeExtraPermissions(raw) {
  if (!Array.isArray(raw)) return [];
  const seen = new Set();
  for (const p of raw) {
    if (typeof p === 'string' && GRANTABLE_EXTRA_PERMISSIONS.has(p)) {
      seen.add(p);
    }
  }
  return Array.from(seen);
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

  // Captures the studentId actually linked (validated inside the transaction).
  let linkedStudentId = null;

  // 4. Atomic: add academy to mapping + mark code used + upsert academy user doc.
  await db.runTransaction(async (tx) => {
    // Re-read the code doc INSIDE the transaction so codeRef is part of the
    // read-set. This forces Firestore to abort the losing transaction when two
    // redemptions of the same one-shot code race, guaranteeing single use.
    const codeSnap = await tx.get(codeRef);
    if (!codeSnap.exists || codeSnap.get('usedAt') != null) {
      throw new HttpsError('not-found', 'Código inválido ou já utilizado.');
    }

    const mappingSnap = await tx.get(mappingRef);
    const mappingData = mappingSnap.exists ? (mappingSnap.data() || {}) : null;

    // Refuse double-join
    if (mappingData && Array.isArray(mappingData.academyIds) &&
        mappingData.academyIds.includes(academyId)) {
      throw new HttpsError('already-exists', 'Você já está vinculado a esta academia.');
    }

    // The studentId carried by the code is set by whoever created the code
    // (staff OR monitor — monitors are non-admin students). Trusting it verbatim
    // would let a malicious monitor point a code at ANOTHER student's record,
    // linking the redeeming account to that student's data. Only honour the
    // studentId when it references an UNCLAIMED student record (no linkedUserId
    // yet). Otherwise ignore it and join with no studentId. All reads must
    // precede writes in a transaction, so resolve this before any tx.set/update.
    let resolvedStudentId = null;
    let studentRefToClaim = null;
    if (codeData.studentId) {
      const studentRef = db
          .collection('academies').doc(academyId)
          .collection('students').doc(String(codeData.studentId));
      const studentSnap = await tx.get(studentRef);
      if (studentSnap.exists) {
        const existingLink = studentSnap.get('linkedUserId');
        // Accept only if the record is orphan, or already linked to THIS caller.
        if (!existingLink || existingLink === uid) {
          resolvedStudentId = codeData.studentId;
          // Stamp ownership on an orphan record so it can never be re-pointed
          // by a later code crafted with the same studentId.
          if (!existingLink) studentRefToClaim = studentRef;
        }
      }
    }
    linkedStudentId = resolvedStudentId;

    const detailEntry = {
      studentId: resolvedStudentId,
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

    // Claim the orphan student record for this caller.
    if (studentRefToClaim) {
      tx.update(studentRefToClaim, {
        linkedUserId: uid,
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
    studentId: linkedStudentId,
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
    // Re-read the code doc INSIDE the transaction so codeRef is part of the
    // read-set. This forces Firestore to abort the losing transaction when two
    // redemptions of the same one-shot code race, guaranteeing single use.
    const codeSnap = await tx.get(codeRef);
    if (!codeSnap.exists || codeSnap.get('usedAt') != null) {
      throw new HttpsError('not-found', 'Código inválido ou já utilizado.');
    }

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
    // Clamp to the server allowlist — never trust extraPermissions stamped on
    // the code doc (an instructor could have forged it via direct write).
    const grantedPermissions = sanitizeExtraPermissions(codeData.extraPermissions);
    if (grantedPermissions.length > 0) {
      detailEntry.extraPermissions = grantedPermissions;
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

      // Consent guard: never synthesise a membership from scratch. The target
      // must already belong to the academy (linked student record above, or an
      // existing academies/{id}/users/{userId} doc). Otherwise an admin could
      // inject an arbitrary uid into someone else's mapping without consent.
      if (studentId === null) {
        const academyUserSnap = await tx.get(academyUserRef);
        if (!academyUserSnap.exists) {
          throw new HttpsError(
              'failed-precondition', 'Usuário não é membro desta academia.');
        }
      }
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
    // Clamp to the server allowlist before persisting (defense in depth even
    // though only admins reach here).
    if (Array.isArray(extraPermissions)) {
      update[`academyDetails.${academyId}.extraPermissions`] =
          sanitizeExtraPermissions(extraPermissions);
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

// ============================================================
// mercadoPagoWebhook — recebe notificações do Mercado Pago e concede/revoga
// a assinatura da academia. Espelha o caktoWebhook.
//
// CONTRATO com a criação do checkout (createMercadoPagoCheckout, a fazer):
//   - external_reference = `${academyId}:${period}`  (period = mensal|trimestral|anual)
//     academyId é id do Firestore (alfanumérico, nunca tem ':'), então o split é seguro.
//   - como reforço, metadata.period também é enviado.
//   - se nada disso vier (ex.: cobrança recorrente de assinatura), o período é
//     inferido pelo valor pago (amountToPeriod).
//
// Config Firebase (a conta precisa de IAM no Secret Manager p/ estes):
//   firebase functions:secrets:set MP_WEBHOOK_SECRET        (segredo de assinatura do webhook)
//   firebase functions:secrets:set MERCADOPAGO_ACCESS_TOKEN (token de produção)
// Cadastre a URL desta function em: MP → sua aplicação → Webhooks.
// ============================================================
const MP_API = 'https://api.mercadopago.com';
const MP_GRACE_DAYS = 5;

function mpPeriodToDays(period) {
  switch (String(period || '').toLowerCase()) {
    case 'anual': return 365 + MP_GRACE_DAYS;
    case 'trimestral': return 90 + MP_GRACE_DAYS;
    case 'mensal': return 30 + MP_GRACE_DAYS;
    default: return 0;
  }
}

// Fallback: infere o ciclo pelo valor pago (preços do paywall em constants.dart).
function mpAmountToDays(amount) {
  const v = Number(amount || 0);
  if (v >= 800) return 365 + MP_GRACE_DAYS; // anual 854,99
  if (v >= 200) return 90 + MP_GRACE_DAYS; // trimestral 224,99
  if (v >= 80) return 30 + MP_GRACE_DAYS; // mensal 89,99
  return 30 + MP_GRACE_DAYS;
}

function mpParseExternalRef(ref) {
  const s = String(ref || '');
  const idx = s.indexOf(':');
  if (idx === -1) return {academyId: s || null, period: ''};
  return {academyId: s.slice(0, idx) || null, period: s.slice(idx + 1)};
}

async function mpFetch(path, accessToken) {
  const r = await fetch(`${MP_API}${path}`, {
    headers: {Authorization: `Bearer ${accessToken}`},
  });
  if (!r.ok) throw new Error(`MP API ${path} -> ${r.status}`);
  return r.json();
}

// Resolve a academia: external_reference (academyId) primeiro; senão, e-mail do
// pagador → Firebase Auth UID → academia ownerId==uid. (Mesma estratégia do Cakto.)
async function mpResolveAcademyRef(academyId, payerEmail) {
  if (academyId) {
    const snap = await db.collection('academies').doc(String(academyId)).get();
    if (snap.exists) return snap.ref;
  }
  if (payerEmail) {
    let uid;
    try {
      uid = (await getAuth().getUserByEmail(payerEmail)).uid;
    } catch (e) {
      return null;
    }
    const q = await db.collection('academies')
        .where('ownerId', '==', uid).limit(1).get();
    if (!q.empty) return q.docs[0].ref;
  }
  return null;
}

async function mpHandlePayment(payment, res) {
  const status = payment.status; // approved|pending|in_process|rejected|refunded|cancelled|charged_back
  const {academyId: refAcademyId, period: refPeriod} =
    mpParseExternalRef(payment.external_reference);
  const payerEmail = payment.payer && payment.payer.email;

  const academyRef = await mpResolveAcademyRef(refAcademyId, payerEmail);
  if (!academyRef) {
    console.warn('[mpWebhook] academia não resolvida', {refAcademyId, payerEmail});
    return res.status(200).json({received: true, warning: 'academy_not_found'});
  }
  const academyId = academyRef.id;
  const chargeId = String(payment.id);

  // Reembolso / chargeback / cancelado → revoga acesso.
  if (status === 'refunded' || status === 'charged_back' || status === 'cancelled') {
    await academyRef.update({
      'subscription.status': 'cancelled',
      'subscription.plan': 'free',
      'subscription.paidUntil': Timestamp.fromDate(new Date()),
      'subscription.lastEvent': `payment_${status}`,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    console.log('[mpWebhook] acesso revogado', {academyId, status});
    return res.status(200).json({success: true, academyId, action: 'revoked'});
  }

  // Só concede no approved.
  if (status !== 'approved') {
    return res.status(200).json({received: true, academyId, status});
  }

  const snap = await academyRef.get();

  // Idempotência: mesma cobrança já processada.
  if (snap.get('subscription.externalPaymentId') === chargeId) {
    return res.status(200).json({success: true, academyId, action: 'duplicate'});
  }

  // Período: external_reference > metadata.period > valor pago.
  const metaPeriod = payment.metadata &&
    (payment.metadata.period || payment.metadata.Period);
  let daysToAdd = mpPeriodToDays(refPeriod) || mpPeriodToDays(metaPeriod);
  if (daysToAdd === 0) daysToAdd = mpAmountToDays(payment.transaction_amount);

  // Estende a partir do maior entre hoje e o paidUntil atual.
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
    'subscription.lastEvent': 'payment_approved',
    'subscription.externalPaymentId': chargeId,
    'subscription.gateway': 'mercadopago',
    'updatedAt': FieldValue.serverTimestamp(),
  });
  console.log('[mpWebhook] acesso concedido', {academyId, chargeId, daysToAdd, paidUntil});
  return res.status(200).json({success: true, academyId, action: 'granted', paidUntil});
}

async function mpHandlePreapproval(pre, res) {
  // pre.status: authorized | paused | pending | cancelled
  const {academyId: refAcademyId} = mpParseExternalRef(pre.external_reference);
  const academyRef = await mpResolveAcademyRef(refAcademyId, pre.payer_email);
  if (!academyRef) {
    return res.status(200).json({received: true, warning: 'academy_not_found'});
  }
  const academyId = academyRef.id;

  if (pre.status === 'cancelled') {
    // Mantém acesso até o paidUntil atual (igual ao cancelamento do Cakto).
    await academyRef.update({
      'subscription.status': 'cancelled',
      'subscription.lastEvent': 'preapproval_cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return res.status(200).json({success: true, academyId, action: 'canceled'});
  }
  if (pre.status === 'paused') {
    await academyRef.update({
      'subscription.status': 'past_due',
      'subscription.lastEvent': 'preapproval_paused',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return res.status(200).json({success: true, academyId, action: 'past_due'});
  }
  // authorized/pending: a concessão de período vem dos pagamentos
  // (subscription_authorized_payment → mpHandlePayment). Aqui só marca o estado.
  await academyRef.update({
    'subscription.status': 'active',
    'subscription.lastEvent': 'preapproval_authorized',
    'subscription.gateway': 'mercadopago',
    'updatedAt': FieldValue.serverTimestamp(),
  });
  return res.status(200).json({success: true, academyId, action: 'preapproval_active'});
}

exports.mercadoPagoWebhook = onRequest(
  {cors: false, secrets: ['MP_WEBHOOK_SECRET', 'MERCADOPAGO_ACCESS_TOKEN']},
  async (req, res) => {
    if (req.method !== 'POST') {
      return res.status(405).send('Method Not Allowed');
    }

    const accessToken = process.env.MERCADOPAGO_ACCESS_TOKEN;
    const webhookSecret = process.env.MP_WEBHOOK_SECRET;

    // O id do recurso vem em ?data.id= (ou ?id= no IPN legado) ou no corpo.
    const dataId = String(
      req.query['data.id'] ||
      (req.query.data && req.query.data.id) ||
      req.query.id ||
      (req.body && req.body.data && req.body.data.id) ||
      '',
    ).toLowerCase();

    // ---- Validação de assinatura (x-signature) ----
    // header: "ts=<ms>,v1=<hmac>"; manifest = id:<data.id>;request-id:<x-request-id>;ts:<ts>;
    if (webhookSecret) {
      const xSignature = req.header('x-signature') || '';
      const xRequestId = req.header('x-request-id') || '';
      let ts = '';
      let v1 = '';
      for (const part of xSignature.split(',')) {
        const [k, val] = part.split('=').map((s) => (s || '').trim());
        if (k === 'ts') ts = val;
        if (k === 'v1') v1 = val;
      }
      const manifest = `id:${dataId};request-id:${xRequestId};ts:${ts};`;
      const expected = crypto.createHmac('sha256', webhookSecret)
          .update(manifest).digest('hex');
      const valid = v1.length === expected.length &&
        crypto.timingSafeEqual(Buffer.from(v1), Buffer.from(expected));
      if (!valid) {
        console.warn('[mpWebhook] assinatura inválida — rejeitado');
        return res.status(401).json({error: 'invalid signature'});
      }
    }

    if (!dataId) {
      return res.status(200).json({received: true, skipped: 'no_id'});
    }

    const type = String(
      req.query.type || req.query.topic || (req.body && req.body.type) || '',
    );

    try {
      if (type === 'payment') {
        const payment = await mpFetch(`/v1/payments/${dataId}`, accessToken);
        return await mpHandlePayment(payment, res);
      }
      if (type === 'subscription_preapproval' || type === 'preapproval') {
        const pre = await mpFetch(`/preapproval/${dataId}`, accessToken);
        return await mpHandlePreapproval(pre, res);
      }
      if (type === 'subscription_authorized_payment') {
        const authPay = await mpFetch(`/authorized_payments/${dataId}`, accessToken);
        const paymentId = authPay.payment && authPay.payment.id;
        if (!paymentId) {
          return res.status(200).json({received: true, skipped: 'no_payment'});
        }
        const payment = await mpFetch(`/v1/payments/${paymentId}`, accessToken);
        return await mpHandlePayment(payment, res);
      }
      // merchant_order, plan, etc. — ignorados.
      return res.status(200).json({received: true, skipped: type});
    } catch (e) {
      // 500 → MP re-tenta (bom p/ falhas transitórias de rede/API).
      console.error('[mpWebhook] erro', e.message);
      return res.status(500).json({error: e.message});
    }
  },
);

// ============================================================
// createMercadoPagoCheckout — callable. O app pede o checkout de um plano e
// recebe de volta a URL hospedada do MP (init_point) pra abrir no navegador.
// recurring=true → assinatura (preapproval, renova sozinha);
// recurring=false → pagamento avulso (preference: Pix/boleto/cartão à vista).
// O external_reference carrega `${academyId}:${plano}` — é o que o
// mercadoPagoWebhook lê pra liberar o período certo.
// ============================================================
const MP_PLANS = {
  mensal: {label: 'Mensal', amount: 89.99, freq: 1},
  trimestral: {label: 'Trimestral', amount: 224.99, freq: 3},
  anual: {label: 'Anual', amount: 854.99, freq: 12},
};

exports.createMercadoPagoCheckout = onCall(
  {secrets: ['MERCADOPAGO_ACCESS_TOKEN']},
  async (request) => {
    const uid = requireAuth(request);
    const academyId = String((request.data && request.data.academyId) || '');
    const plan = String((request.data && request.data.plan) || 'mensal').toLowerCase();
    const recurring = (request.data && request.data.recurring) !== false; // default: recorrente

    if (!academyId) {
      throw new HttpsError('invalid-argument', 'academyId é obrigatório.');
    }
    const cfg = MP_PLANS[plan];
    if (!cfg) {
      throw new HttpsError('invalid-argument', `Plano inválido: ${plan}`);
    }
    // Só o admin/dono da academia pode iniciar a assinatura dela.
    if (!(await isAdmin(uid, academyId))) {
      throw new HttpsError('permission-denied', 'Apenas o admin da academia pode assinar.');
    }

    const accessToken = process.env.MERCADOPAGO_ACCESS_TOKEN;
    const email = (await getAuth().getUser(uid)).email || undefined;
    const externalReference = `${academyId}:${plan}`;
    const appUrl = process.env.APP_BASE_URL || 'https://bjjeasy.netlify.app';
    const backUrl = `${appUrl}/obrigado`;

    let endpoint;
    let body;
    if (recurring) {
      endpoint = '/preapproval';
      body = {
        reason: `BJJEasy — Plano ${cfg.label}`,
        external_reference: externalReference,
        payer_email: email,
        back_url: backUrl,
        status: 'pending', // sem card_token → MP coleta o cartão na página
        auto_recurring: {
          frequency: cfg.freq,
          frequency_type: 'months',
          transaction_amount: cfg.amount,
          currency_id: 'BRL',
        },
      };
    } else {
      endpoint = '/checkout/preferences';
      body = {
        items: [{
          title: `BJJEasy — Plano ${cfg.label}`,
          quantity: 1,
          unit_price: cfg.amount,
          currency_id: 'BRL',
        }],
        payer: email ? {email} : undefined,
        external_reference: externalReference,
        metadata: {academy_id: academyId, period: plan},
        back_urls: {success: backUrl, pending: backUrl, failure: backUrl},
        auto_return: 'approved',
      };
    }

    const r = await fetch(`${MP_API}${endpoint}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    const data = await r.json();
    if (!r.ok) {
      console.error('[mpCheckout] erro', r.status, data);
      throw new HttpsError('internal', `Falha ao criar checkout (MP ${r.status}).`);
    }

    return {
      initPoint: data.init_point || data.sandbox_init_point,
      id: data.id,
      recurring,
    };
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
// NOTE: buildPublicProfileProjection (a plain helper) and
// PUBLIC_PROFILE_SAFE_FIELDS (a plain array) are exported by server_functions
// for the backfill script's reuse, but they are NOT Cloud Functions — strip
// them here so Firebase's endpoint discovery doesn't try to deploy them as
// invalid functions. The backfill requires them directly from server_functions.
{
  const {
    buildPublicProfileProjection: _bppHelper,
    PUBLIC_PROFILE_SAFE_FIELDS: _ppSafeFields,
    // Gamification helpers are plain functions reused by the on-demand
    // recompute callable / tests — NOT Cloud Functions. Strip so endpoint
    // discovery does not try to deploy them as invalid functions.
    processAcademyGamification: _procGami,
    computeCurrentStreak: _computeStreak,
    rankFromGamificationPairs: _rankPairs,
    ...serverTriggers
  } = require('./server_functions');
  Object.assign(exports, serverTriggers);
}
