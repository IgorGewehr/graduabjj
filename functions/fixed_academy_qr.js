'use strict';

const crypto = require('crypto');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');

const CHECKIN_BEFORE_MINUTES = 30;
const CHECKIN_AFTER_MINUTES = 60;
const FIXED_QR_VERSION = 2;

function requiredId(value, field) {
  const normalized = String(value || '').trim();
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(normalized)) {
    throw new HttpsError('invalid-argument', `${field} invalido.`);
  }
  return normalized;
}

function requiredCode(value) {
  const normalized = String(value || '').trim();
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(normalized)) {
    throw new HttpsError('invalid-argument', 'QR invalido.');
  }
  return normalized;
}

function studentIdFromMapping(mapping, academyId) {
  const details = (mapping && mapping.academyDetails) || {};
  const entry = details[academyId];
  return entry && typeof entry.studentId === 'string' ? entry.studentId : null;
}

function parseTime(value) {
  const match = /^(\d{1,2}):(\d{2})$/.exec(String(value || '').trim());
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) return null;
  return {hour, minute};
}

function scheduleOccurrenceInWindow(schedule, now) {
  if (!schedule || !Number.isInteger(schedule.dayOfWeek)) return null;
  const startParts = parseTime(schedule.startTime);
  const endParts = parseTime(schedule.endTime);
  if (!startParts || !endParts) return null;

  // Check today and yesterday so an overnight class (23:30-00:30) remains
  // selectable after midnight. The process timezone is pinned by index.js.
  for (const daysAgo of [0, 1]) {
    const base = new Date(now);
    base.setDate(base.getDate() - daysAgo);
    base.setHours(0, 0, 0, 0);
    if (base.getDay() !== schedule.dayOfWeek) continue;

    const start = new Date(base);
    start.setHours(startParts.hour, startParts.minute, 0, 0);
    const end = new Date(base);
    end.setHours(endParts.hour, endParts.minute, 0, 0);
    if (end <= start) end.setDate(end.getDate() + 1);

    const opensAt = new Date(start.getTime() - CHECKIN_BEFORE_MINUTES * 60000);
    const closesAt = new Date(end.getTime() + CHECKIN_AFTER_MINUTES * 60000);
    if (now >= opensAt && now <= closesAt) return {start, end};
  }
  return null;
}

function acceptsStudent(cls, studentId) {
  const roster = Array.isArray(cls.studentIds) ? cls.studentIds : [];
  if (cls.isOpenClass === true) return true;
  if (cls.isOpenClass === false) return roster.includes(studentId);
  return roster.length === 0 || roster.includes(studentId);
}

function eligibleClass(cls, studentId, now) {
  if (!cls || cls.isActive === false || !acceptsStudent(cls, studentId)) {
    return null;
  }
  const schedules = Array.isArray(cls.schedule) ? cls.schedule : [];
  for (const schedule of schedules) {
    const occurrence = scheduleOccurrenceInWindow(schedule, now);
    if (occurrence) return {schedule, occurrence};
  }
  return null;
}

function attendanceDayKey(now) {
  const year = String(now.getFullYear()).padStart(4, '0');
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}${month}${day}`;
}

function validateStoredQr(academy, code) {
  const qr = academy.fixedAttendanceQr || {};
  if (qr.enabled === false || typeof qr.code !== 'string' || qr.code !== code) {
    throw new HttpsError('permission-denied', 'QR fixo invalido ou desativado.');
  }
}

function classDto(doc, match) {
  const cls = doc.data() || {};
  return {
    id: doc.id,
    name: String(cls.name || 'Turma'),
    sport: String(cls.sport || 'bjj'),
    startTime: String(match.schedule.startTime || ''),
    endTime: String(match.schedule.endTime || ''),
  };
}

/**
 * Creates the fixed-academy QR callables without coupling this module to the
 * giant index.js. Dependencies are injected so pure rules remain unit-testable.
 */
function createFixedAcademyQrFunctions({db, requireAuth, isAdmin}) {
  const getOrCreateFixedAcademyQr = onCall(async (request) => {
    const uid = requireAuth(request);
    const academyId = requiredId(request.data && request.data.academyId, 'academyId');
    const hasAdminRole = await isAdmin(uid, academyId);

    const academyRef = db.collection('academies').doc(academyId);
    let result;
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(academyRef);
      if (!snap.exists) throw new HttpsError('not-found', 'Academia nao encontrada.');
      const academy = snap.data() || {};
      if (!hasAdminRole && academy.ownerId !== uid) {
        throw new HttpsError(
          'permission-denied',
          'Somente o dono ou administrador pode gerar este QR.',
        );
      }
      const current = academy.fixedAttendanceQr || {};
      const hasValidCode = typeof current.code === 'string' && current.code.length >= 16;
      const code = hasValidCode
        ? current.code
        : crypto.randomBytes(24).toString('base64url');

      if (!hasValidCode) {
        tx.update(academyRef, {
          'fixedAttendanceQr.version': FIXED_QR_VERSION,
          'fixedAttendanceQr.code': code,
          'fixedAttendanceQr.enabled': true,
          'fixedAttendanceQr.createdAt': FieldValue.serverTimestamp(),
          'fixedAttendanceQr.createdBy': uid,
        });
      }
      result = {academyId, academyName: String(academy.name || 'Academia'), code};
    });
    return result;
  });

  const resolveFixedAcademyQr = onCall(async (request) => {
    const uid = requireAuth(request);
    const academyId = requiredId(request.data && request.data.academyId, 'academyId');
    const code = requiredCode(request.data && request.data.code);
    const academyRef = db.collection('academies').doc(academyId);

    const [mappingSnap, academySnap] = await Promise.all([
      db.collection('userAcademyMapping').doc(uid).get(),
      academyRef.get(),
    ]);
    if (!academySnap.exists) throw new HttpsError('not-found', 'Academia nao encontrada.');
    const academy = academySnap.data() || {};
    validateStoredQr(academy, code);

    const studentId = studentIdFromMapping(mappingSnap.data(), academyId);
    if (!studentId) {
      throw new HttpsError('permission-denied', 'Voce nao pertence a esta academia.');
    }
    const studentSnap = await academyRef.collection('students').doc(studentId).get();
    if (!studentSnap.exists) throw new HttpsError('not-found', 'Aluno nao encontrado.');
    const student = studentSnap.data() || {};
    if (student.status && student.status !== 'active') {
      throw new HttpsError('failed-precondition', 'Sua matricula nao esta ativa.');
    }

    // Only query the roster after QR, membership and student status pass. This
    // prevents an authenticated outsider from turning invalid scans into a
    // repeated full classes query for an academy they do not belong to.
    const classesSnap = await academyRef.collection('classes')
      .where('isActive', '==', true).get();
    const now = new Date();
    const classes = [];
    for (const doc of classesSnap.docs) {
      const match = eligibleClass(doc.data(), studentId, now);
      if (match) classes.push(classDto(doc, match));
    }
    classes.sort((a, b) => a.startTime.localeCompare(b.startTime) || a.name.localeCompare(b.name));
    return {academyId, academyName: String(academy.name || 'Academia'), classes};
  });

  const checkInWithFixedAcademyQr = onCall(async (request) => {
    const uid = requireAuth(request);
    const academyId = requiredId(request.data && request.data.academyId, 'academyId');
    const classId = requiredId(request.data && request.data.classId, 'classId');
    const code = requiredCode(request.data && request.data.code);
    const academyRef = db.collection('academies').doc(academyId);
    const mappingRef = db.collection('userAcademyMapping').doc(uid);
    let response;

    await db.runTransaction(async (tx) => {
      const [mappingSnap, academySnap] = await Promise.all([
        tx.get(mappingRef),
        tx.get(academyRef),
      ]);
      if (!academySnap.exists) throw new HttpsError('not-found', 'Academia nao encontrada.');
      const academy = academySnap.data() || {};
      validateStoredQr(academy, code);

      const studentId = studentIdFromMapping(mappingSnap.data(), academyId);
      if (!studentId) {
        throw new HttpsError('permission-denied', 'Voce nao pertence a esta academia.');
      }
      const studentRef = academyRef.collection('students').doc(studentId);
      const classRef = academyRef.collection('classes').doc(classId);
      const [studentSnap, classSnap] = await Promise.all([
        tx.get(studentRef),
        tx.get(classRef),
      ]);
      if (!studentSnap.exists) throw new HttpsError('not-found', 'Aluno nao encontrado.');
      if (!classSnap.exists) throw new HttpsError('not-found', 'Turma nao encontrada.');

      const student = studentSnap.data() || {};
      const cls = classSnap.data() || {};
      if (student.status && student.status !== 'active') {
        throw new HttpsError('failed-precondition', 'Sua matricula nao esta ativa.');
      }
      const now = new Date();
      const match = eligibleClass(cls, studentId, now);
      if (!match) {
        throw new HttpsError('failed-precondition', 'Esta turma nao esta disponivel para seu check-in agora.');
      }

      const attendanceRef = academyRef.collection('attendance')
        .doc(`${studentId}_${classId}_${attendanceDayKey(now)}`);
      const attendanceSnap = await tx.get(attendanceRef);
      if (attendanceSnap.exists) {
        throw new HttpsError('already-exists', 'Voce ja registrou presenca nesta aula.');
      }

      const studentName = String(student.fullName || student.nickname || 'Aluno');
      const className = String(cls.name || 'Turma');
      const weight = Number(cls.weight || 1);
      tx.set(attendanceRef, {
        studentId,
        studentName,
        classId,
        className,
        date: Timestamp.fromDate(now),
        verifiedBy: uid,
        verifiedByName: studentName,
        sport: String(cls.sport || 'bjj'),
        source: 'academy_fixed_qr',
        ...(Number.isFinite(weight) && weight > 0 && weight !== 1 ? {weight} : {}),
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.update(studentRef, {
        attendanceCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
      response = {
        classId,
        className,
        studentId,
        studentName,
        markedAt: now.toISOString(),
      };
    });
    return response;
  });

  return {
    getOrCreateFixedAcademyQr,
    resolveFixedAcademyQr,
    checkInWithFixedAcademyQr,
  };
}

module.exports = {
  createFixedAcademyQrFunctions,
  _internals: {
    acceptsStudent,
    attendanceDayKey,
    eligibleClass,
    parseTime,
    scheduleOccurrenceInWindow,
    studentIdFromMapping,
  },
};
