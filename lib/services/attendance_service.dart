import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/attendance_repo.dart';
import '../api/dto/attendance_dto.dart' as api;
import 'achievement_service.dart';
import 'firebase_service.dart';
import 'student_service.dart';

/// Attendance Model
class Attendance {
  final String id;
  final String studentId;
  final String studentName;
  final String classId;
  final String className;
  final DateTime date;
  final String verifiedBy;
  final String verifiedByName;
  final String? notes;

  /// Snapshot of Class.weight at the time the attendance was created. Null
  /// or 1 means "counts as one normal attendance". Kept immutable so old
  /// graduation math stays stable even if the class weight changes later.
  final double? weight;
  final DateTime createdAt;

  Attendance({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.classId,
    required this.className,
    required this.date,
    required this.verifiedBy,
    required this.verifiedByName,
    this.notes,
    this.weight,
    required this.createdAt,
  });

  /// Sprint 5 wiring — adapter `ApiAttendance` → `Attendance` legacy.
  ///
  /// Tatami trabalha com IDs (verified_by_uid, student_id, class_id);
  /// nomes não vêm na resposta. Caller passa `studentName`, `className`,
  /// `verifiedByName` via parâmetro quando souber (denormalização local).
  ///
  /// `weight` legacy é nullable e o Tatami é decimal-string "1.000".
  /// Aqui parseamos para double; "1.000" vira 1.0 (não null) pra
  /// preservar o snapshot histórico.
  factory Attendance.fromApi(
    api.ApiAttendance a, {
    String? studentName,
    String? className,
    String? verifiedByName,
  }) {
    return Attendance(
      id: a.id,
      studentId: a.studentId,
      studentName: studentName ?? '',
      classId: a.classId,
      className: className ?? '',
      date: a.date,
      verifiedBy: a.verifiedByUid,
      verifiedByName: verifiedByName ?? '',
      weight: double.tryParse(a.weight),
      createdAt: a.createdAt ?? DateTime.now(),
    );
  }

  factory Attendance.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Attendance(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      classId: data['classId'] ?? '',
      className: data['className'] ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      verifiedBy: data['verifiedBy'] ?? '',
      verifiedByName: data['verifiedByName'] ?? '',
      notes: data['notes'],
      weight: data['weight'] is num ? (data['weight'] as num).toDouble() : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Attendance Service - Multi-tenant attendance management
class AttendanceService {
  final String academyId;
  late final Collections _collections;

  AttendanceService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _attendanceRef => _collections.attendance;

  // Helper: Get start and end of day
  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);

  // ============================================
  // Get Attendance by Student
  // ============================================
  Future<List<Attendance>> getByStudent(
    String studentId, {
    int limit = 50,
  }) async {
    final query = await _attendanceRef
        .where('studentId', isEqualTo: studentId)
        .get();

    var attendance = query.docs
        .map((doc) => Attendance.fromFirestore(doc))
        .toList();

    // Sort by date descending
    attendance.sort((a, b) => b.date.compareTo(a.date));

    if (attendance.length > limit) {
      attendance = attendance.sublist(0, limit);
    }

    return attendance;
  }

  // ============================================
  // Get Attendance by Student — PAGINATED (Sprint 5)
  //
  // Server-side cursor pagination using `startAfterDocument`. Use this from
  // any list UI that supports infinite scroll. Composite index required:
  // `attendance` (studentId ASC, date DESC) — already declared in
  // `firestore.indexes.json`.
  //
  // Returns the page of items together with the last `DocumentSnapshot`,
  // which the caller passes back as `startAfter` to fetch the next page.
  // When `lastDoc` is null, the end of the collection has been reached.
  // ============================================
  Future<({List<Attendance> items, DocumentSnapshot? lastDoc})>
  getByStudentPaginated(
    String studentId, {
    int limit = 15,
    DocumentSnapshot? startAfter,
  }) async {
    Query query = _attendanceRef
        .where('studentId', isEqualTo: studentId)
        .orderBy('date', descending: true)
        .limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    final items = snap.docs
        .map((doc) => Attendance.fromFirestore(doc))
        .toList();
    return (items: items, lastDoc: snap.docs.isEmpty ? null : snap.docs.last);
  }

  // ============================================
  // Get Attendance Count by Student
  // ============================================
  Future<int> getStudentAttendanceCount(String studentId) async {
    final query = await _attendanceRef
        .where('studentId', isEqualTo: studentId)
        .get();
    return query.size;
  }

  // ============================================
  // Get Attendance by Date Range
  // ============================================
  Future<List<Attendance>> getByDateRange(
    DateTime startDate,
    DateTime endDate, {
    String? classId,
    String? studentId,
  }) async {
    final snapshot = await _attendanceRef.get();
    var results = snapshot.docs
        .map((doc) => Attendance.fromFirestore(doc))
        .toList();

    final start = _startOfDay(startDate);
    final end = _endOfDay(endDate);

    // Filter by date range
    results = results
        .where(
          (a) =>
              a.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
              a.date.isBefore(end.add(const Duration(seconds: 1))),
        )
        .toList();

    // Apply additional filters
    if (classId != null) {
      results = results.where((a) => a.classId == classId).toList();
    }
    if (studentId != null) {
      results = results.where((a) => a.studentId == studentId).toList();
    }

    // Sort by date descending
    results.sort((a, b) => b.date.compareTo(a.date));

    return results;
  }

  // ============================================
  // Get Attendance by Date and Class
  // ============================================
  Future<List<Attendance>> getByDateAndClass(
    DateTime date,
    String classId,
  ) async {
    final query = await _attendanceRef
        .where('classId', isEqualTo: classId)
        .get();

    final start = _startOfDay(date);
    final end = _endOfDay(date);

    final results = query.docs
        .map((doc) => Attendance.fromFirestore(doc))
        .where(
          (a) =>
              a.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
              a.date.isBefore(end.add(const Duration(seconds: 1))),
        )
        .toList();

    results.sort((a, b) => b.date.compareTo(a.date));
    return results;
  }

  // ============================================
  // Get Today's Attendance for Class
  // ============================================
  Future<List<Attendance>> getTodayByClass(String classId) async {
    return getByDateAndClass(DateTime.now(), classId);
  }

  // ============================================
  // Check if Student is Present
  // ============================================
  Future<bool> isStudentPresent(
    String studentId,
    String classId,
    DateTime date,
  ) async {
    final query = await _attendanceRef
        .where('studentId', isEqualTo: studentId)
        .get();

    final start = _startOfDay(date);
    final end = _endOfDay(date);

    return query.docs.any((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final docDate = (data['date'] as Timestamp?)?.toDate();
      return data['classId'] == classId &&
          docDate != null &&
          docDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
          docDate.isBefore(end.add(const Duration(seconds: 1)));
    });
  }

  // ============================================
  // Get Present Student IDs for Class
  // ============================================
  Future<Set<String>> getPresentStudentIds(
    String classId, {
    DateTime? date,
  }) async {
    final attendance = await getByDateAndClass(date ?? DateTime.now(), classId);
    return attendance.map((a) => a.studentId).toSet();
  }

  // ============================================
  // Get Monthly Stats
  // ============================================
  Future<Map<String, dynamic>> getMonthlyStats(int year, int month) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0);

    final attendance = await getByDateRange(startDate, endDate);

    final uniqueStudents = <String>{};
    final attendanceByDay = <String, int>{};

    for (final a in attendance) {
      uniqueStudents.add(a.studentId);
      final day =
          '${a.date.year}-${a.date.month.toString().padLeft(2, '0')}-${a.date.day.toString().padLeft(2, '0')}';
      attendanceByDay[day] = (attendanceByDay[day] ?? 0) + 1;
    }

    return {
      'totalClasses': attendanceByDay.length,
      'uniqueStudents': uniqueStudents.length,
      'attendanceByDay': attendanceByDay,
      'totalAttendance': attendance.length,
    };
  }

  // ============================================
  // Get Today's Total Attendance
  // ============================================
  Future<int> getTodayTotal() async {
    final today = DateTime.now();
    final attendance = await getByDateRange(today, today);
    return attendance.length;
  }

  // ============================================
  // Get Attendance Calendar Data
  // Returns a map of date -> attendance count for calendar display
  // ============================================
  Future<Map<DateTime, int>> getCalendarData(
    String studentId,
    int year,
    int month,
  ) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0);

    final attendance = await getByDateRange(
      startDate,
      endDate,
      studentId: studentId,
    );

    final result = <DateTime, int>{};
    for (final a in attendance) {
      final dateOnly = DateTime(a.date.year, a.date.month, a.date.day);
      result[dateOnly] = (result[dateOnly] ?? 0) + 1;
    }

    return result;
  }

  // ============================================
  // Get Student Streak (consecutive days)
  // ============================================
  Future<int> getStudentStreak(String studentId) async {
    final attendance = await getByStudent(studentId, limit: 365);
    if (attendance.isEmpty) return 0;

    // Get unique dates and sort ascending
    final dates =
        attendance
            .map((a) => DateTime(a.date.year, a.date.month, a.date.day))
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

    if (dates.isEmpty) return 0;

    // Count consecutive days from most recent
    int streak = 1;
    for (int i = 0; i < dates.length - 1; i++) {
      final diff = dates[i].difference(dates[i + 1]).inDays;
      if (diff == 1) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Mark Student as Present
  // ============================================
  Future<Attendance> markPresent({
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String verifiedBy,
    required String verifiedByName,
    DateTime? date,
    String? notes,
    double? weight,
  }) async {
    final attendanceDate = date ?? DateTime.now();

    // Check if already present
    final alreadyPresent = await isStudentPresent(
      studentId,
      classId,
      attendanceDate,
    );
    if (alreadyPresent) {
      throw Exception('Aluno já marcado como presente nesta aula');
    }

    final payload = <String, dynamic>{
      'studentId': studentId,
      'studentName': studentName,
      'classId': classId,
      'className': className,
      'date': Timestamp.fromDate(attendanceDate),
      'verifiedBy': verifiedBy,
      'verifiedByName': verifiedByName,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
    };
    // Persist weight only when meaningful (non-default). Keeps old docs
    // and new docs interchangeable when the academy isn't using weights.
    if (weight != null && weight != 1.0) {
      payload['weight'] = weight;
    }

    final docRef = await _attendanceRef.add(payload);

    // Update student's attendance count
    await _updateStudentAttendanceCount(studentId, 1);

    // Check for milestones (fire and forget)
    checkAttendanceMilestone(studentId, studentName, verifiedBy).ignore();

    final doc = await docRef.get();
    return Attendance.fromFirestore(doc);
  }

  // ============================================
  // Unmark Student as Present
  // ============================================
  Future<void> unmarkPresent(
    String studentId,
    String classId,
    DateTime date,
  ) async {
    final attendance = await getByDateAndClass(date, classId);
    final record = attendance
        .where((a) => a.studentId == studentId)
        .firstOrNull;

    if (record == null) {
      throw Exception('Registro de presença não encontrado');
    }

    await _attendanceRef.doc(record.id).delete();

    // Update student's attendance count
    await _updateStudentAttendanceCount(studentId, -1);
  }

  // ============================================
  // Bulk Mark Students as Present
  //
  // Optimized for "mark all" operations on a full class: everything ships in
  // a SINGLE Firestore WriteBatch — both the attendance docs and the
  // denormalized student.attendanceCount increments. This collapses what used
  // to be ~3N round trips (N inserts + N counter updates + N doc reads) into
  // one round trip total. Milestone checks remain fire-and-forget afterwards
  // since they only matter for rare ~50/100/200/etc thresholds.
  //
  // Firestore caps batches at 500 writes — we shard automatically when the
  // input exceeds that. With weight + counter, each student costs 2 writes,
  // so we cap students per batch at 240 to stay safely under the limit.
  // ============================================
  Future<List<Attendance>> bulkMarkPresent({
    required List<({String studentId, String studentName})> students,
    required String classId,
    required String className,
    required String verifiedBy,
    required String verifiedByName,
    DateTime? date,
    double? weight,
    // When provided, writes go to the Go backend instead of Firestore.
    AttendanceRemoteRepo? repo,
  }) async {
    final attendanceDate = date ?? DateTime.now();
    final now = DateTime.now();
    final results = <Attendance>[];

    // Get already present students (single query)
    final presentIds = await getPresentStudentIds(
      classId,
      date: attendanceDate,
    );

    // Filter once
    final toMark = students
        .where((s) => !presentIds.contains(s.studentId))
        .toList();
    if (toMark.isEmpty) return results;

    if (repo != null) {
      // ── Go backend path ──────────────────────────────────────────────────
      // POST /v1/academies/{id}/attendance/bulk — one round trip for all
      // students. The backend handles deduplication and counter updates.
      await repo.bulkRecord(
        academyId,
        classId,
        toMark.map((s) => s.studentId).toList(),
      );

      // Build results locally for immediate UI feedback.
      for (final student in toMark) {
        results.add(
          Attendance(
            id: '',
            studentId: student.studentId,
            studentName: student.studentName,
            classId: classId,
            className: className,
            date: attendanceDate,
            verifiedBy: verifiedBy,
            verifiedByName: verifiedByName,
            weight: (weight != null && weight != 1.0) ? weight : null,
            createdAt: now,
          ),
        );
      }
    } else {
      // ── Firestore legacy path ────────────────────────────────────────────
      // Shard into batches of 240 students (≤ 480 writes, under Firestore's 500 cap)
      const int batchStudentLimit = 240;
      for (int start = 0; start < toMark.length; start += batchStudentLimit) {
        final end = (start + batchStudentLimit).clamp(0, toMark.length);
        final shard = toMark.sublist(start, end);

        final batch = FirebaseService.firestore.batch();

        for (final student in shard) {
          // 1) Attendance doc
          final docRef = _attendanceRef.doc();
          final payload = <String, dynamic>{
            'studentId': student.studentId,
            'studentName': student.studentName,
            'classId': classId,
            'className': className,
            'date': Timestamp.fromDate(attendanceDate),
            'verifiedBy': verifiedBy,
            'verifiedByName': verifiedByName,
            'createdAt': FieldValue.serverTimestamp(),
          };
          if (weight != null && weight != 1.0) {
            payload['weight'] = weight;
          }
          batch.set(docRef, payload);

          // 2) Student counter increment — in the SAME batch (was a separate
          // serial loop before, costing N extra round trips for a class of 30)
          batch.update(_collections.student(student.studentId), {
            'attendanceCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // Build result locally — no doc.get() needed
          results.add(
            Attendance(
              id: docRef.id,
              studentId: student.studentId,
              studentName: student.studentName,
              classId: classId,
              className: className,
              date: attendanceDate,
              verifiedBy: verifiedBy,
              verifiedByName: verifiedByName,
              weight: (weight != null && weight != 1.0) ? weight : null,
              createdAt: now,
            ),
          );
        }

        await batch.commit();
      }
    }

    // Milestones: fire-and-forget after the batch is durable.
    for (final student in toMark) {
      checkAttendanceMilestone(
        student.studentId,
        student.studentName,
        verifiedBy,
      ).ignore();
    }

    return results;
  }

  // ============================================
  // Bulk Unmark Present (batched delete + counter decrement)
  //
  // Single Firestore query to locate today's attendance docs for the class,
  // then one WriteBatch deletes them all and decrements each student's
  // attendanceCount. Replaces the previous Future.wait(N×unmarkPresent) which
  // produced 3N round trips for a 30-student class.
  // ============================================
  Future<int> bulkUnmarkPresent({
    required String classId,
    required DateTime date,
  }) async {
    final start = _startOfDay(date);
    final end = _endOfDay(date);

    // Single query for the day's attendance in this class
    final snap = await _attendanceRef
        .where('classId', isEqualTo: classId)
        .get();

    final matching = snap.docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final docDate = (data['date'] as Timestamp?)?.toDate();
      return docDate != null &&
          docDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
          docDate.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();
    if (matching.isEmpty) return 0;

    const int batchLimit = 240; // 2 writes per student = under 500 cap
    int removed = 0;
    for (int s = 0; s < matching.length; s += batchLimit) {
      final e = (s + batchLimit).clamp(0, matching.length);
      final shard = matching.sublist(s, e);

      final batch = FirebaseService.firestore.batch();
      for (final doc in shard) {
        final data = doc.data() as Map<String, dynamic>;
        final sid = data['studentId'] as String?;
        batch.delete(doc.reference);
        if (sid != null && sid.isNotEmpty) {
          batch.update(_collections.student(sid), {
            'attendanceCount': FieldValue.increment(-1),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
      removed += shard.length;
    }
    return removed;
  }

  // ============================================
  // Delete Attendance Record
  // ============================================
  Future<void> delete(String id) async {
    final doc = await _attendanceRef.doc(id).get();
    if (!doc.exists) return;

    final attendance = Attendance.fromFirestore(doc);
    await _attendanceRef.doc(id).delete();

    // Update student's attendance count
    await _updateStudentAttendanceCount(attendance.studentId, -1);
  }

  // ============================================
  // Toggle Attendance (mark/unmark)
  // ============================================
  Future<bool> toggleAttendance({
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String verifiedBy,
    required String verifiedByName,
    DateTime? date,
    double? weight,
  }) async {
    final attendanceDate = date ?? DateTime.now();
    final isPresent = await isStudentPresent(
      studentId,
      classId,
      attendanceDate,
    );

    if (isPresent) {
      await unmarkPresent(studentId, classId, attendanceDate);
      return false;
    } else {
      await markPresent(
        studentId: studentId,
        studentName: studentName,
        classId: classId,
        className: className,
        verifiedBy: verifiedBy,
        verifiedByName: verifiedByName,
        date: attendanceDate,
        weight: weight,
      );
      return true;
    }
  }

  // ============================================
  // Get Student Attendance Rate
  // ============================================
  Future<double> getStudentAttendanceRate(
    String studentId,
    DateTime startDate,
    int totalPossibleClasses,
  ) async {
    if (totalPossibleClasses == 0) return 0.0;

    final attendance = await getByDateRange(
      startDate,
      DateTime.now(),
      studentId: studentId,
    );

    return (attendance.length / totalPossibleClasses * 100).clamp(0.0, 100.0);
  }

  // ============================================
  // Check Attendance Milestone
  // ============================================
  Future<void> checkAttendanceMilestone(
    String studentId,
    String studentName,
    String createdBy,
  ) async {
    const attendeesMilestones = [50, 100, 200, 500, 1000];

    // Get system attendance count
    final systemCount = await getStudentAttendanceCount(studentId);

    // Get student to access initialAttendanceCount
    final studentService = StudentService(academyId);
    final student = await studentService.getById(studentId);
    final initialCount = student?.initialAttendanceCount ?? 0;

    // Total count
    final totalCount = systemCount + initialCount;

    // Check if matches milestone
    if (attendeesMilestones.contains(totalCount)) {
      // Only create if reached through system attendance (not just initial)
      if (initialCount >= totalCount) return;

      final achievementService = AchievementService(academyId);
      final existing = await achievementService.getByStudent(studentId);

      final alreadyHas = existing.any(
        (a) =>
            a.type == AchievementType.milestone &&
            a.milestone == 'attendance_$totalCount',
      );

      if (!alreadyHas) {
        // Find exact date
        final diff = totalCount - initialCount;
        final allAttendance = await getByStudent(studentId, limit: 10000);
        // Sort ascending to find N-th attendance
        allAttendance.sort((a, b) => a.date.compareTo(b.date));

        DateTime? milestoneDate;
        if (allAttendance.length >= diff) {
          milestoneDate = allAttendance[diff - 1].date;
        }

        await achievementService.createAttendanceMilestone(
          studentId: studentId,
          studentName: studentName,
          attendanceCount: totalCount,
          milestoneDate: milestoneDate,
          createdBy: createdBy,
        );
      }
    }
  }

  // ============================================
  // Helper: Update Student Attendance Count
  // ============================================
  Future<void> _updateStudentAttendanceCount(
    String studentId,
    int delta,
  ) async {
    final studentRef = _collections.student(studentId);
    await studentRef.update({
      'attendanceCount': FieldValue.increment(delta),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

// ============================================
// Factory Function
// ============================================
AttendanceService createAttendanceService(String academyId) {
  return AttendanceService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
AttendanceService get attendanceService =>
    AttendanceService(FirebaseService.academyId);
