import 'package:cloud_firestore/cloud_firestore.dart';

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
  /// Sport id ('bjj', 'muaythai', ...) captured from the class at write time.
  /// Null on legacy docs created before multi-sport — callers should treat
  /// null as 'bjj' for backwards compatibility.
  final String? sport;
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
    this.sport,
    required this.createdAt,
  });

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
      sport: data['sport'] as String?,
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
    String? sport,
  }) async {
    final query = await _attendanceRef
        .where('studentId', isEqualTo: studentId)
        .get();

    var attendance = query.docs
        .map((doc) => Attendance.fromFirestore(doc))
        .toList();

    // Per-sport filter (additive): legacy docs without `sport` count as 'bjj',
    // mirroring belt_progression_service.getWeightedAttendanceCount. When
    // sport == null the behaviour is unchanged (global, all sports).
    if (sport != null) {
      attendance = attendance
          .where((a) => (a.sport ?? 'bjj') == sport)
          .toList();
    }

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
  // Get Attendance Count (optionally per sport)
  //
  // Counts a student's attendances, optionally filtered by sport. Legacy docs
  // without a `sport` field count as 'bjj' (same convention as
  // belt_progression_service.getWeightedAttendanceCount). When sport == null
  // this returns the global count across all sports.
  // ============================================
  Future<int> getAttendanceCount(String studentId, {String? sport}) async {
    final query = await _attendanceRef
        .where('studentId', isEqualTo: studentId)
        .get();
    if (sport == null) return query.size;
    return query.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return ((data['sport'] as String?) ?? 'bjj') == sport;
    }).length;
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
    final start = _startOfDay(startDate);
    final end = _endOfDay(endDate);

    // Server-side filter using composite indexes declared in
    // firestore.indexes.json: (classId, date DESC) or (studentId, date DESC).
    // When neither classId nor studentId is given, falls back to a date-only
    // query (single-field index is auto-created by Firestore).
    Query query = _attendanceRef;
    if (classId != null) {
      query = query.where('classId', isEqualTo: classId);
    } else if (studentId != null) {
      query = query.where('studentId', isEqualTo: studentId);
    }
    query = query
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date', descending: true);

    final snapshot = await query.get();
    var results = snapshot.docs
        .map((doc) => Attendance.fromFirestore(doc))
        .toList();

    // Secondary filter only when both classId and studentId were requested,
    // since Firestore can use a single equality + range per query.
    if (classId != null && studentId != null) {
      results = results.where((a) => a.studentId == studentId).toList();
    }

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

    // RESET se a corrente quebrou: só conta se o ÚLTIMO treino foi HOJE ou
    // ONTEM. Sem isso o streak ficava preso em ≥1 mesmo após semanas parado.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (today.difference(dates.first).inDays > 1) return 0;

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

  /// Info de streak para o dashboard do lutador: streak atual (dias), recorde
  /// (maior sequência já feita) e quais dias da SEMANA ATUAL (Seg=1..Dom=7)
  /// tiveram treino. Tudo de uma leitura só (sem custo extra).
  Future<({int current, int record, Set<int> weekDays})> getStreakInfo(
      String studentId, {String? sport}) async {
    final attendance = await getByStudent(studentId, limit: 365, sport: sport);
    if (attendance.isEmpty) {
      return (current: 0, record: 0, weekDays: <int>{});
    }
    final days = attendance
        .map((a) => DateTime(a.date.year, a.date.month, a.date.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a)); // desc

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Streak atual (reset se o último treino não foi hoje/ontem).
    int current = 0;
    if (today.difference(days.first).inDays <= 1) {
      current = 1;
      for (var i = 0; i < days.length - 1; i++) {
        if (days[i].difference(days[i + 1]).inDays == 1) {
          current++;
        } else {
          break;
        }
      }
    }

    // Recorde: maior run de dias consecutivos em todo o histórico.
    int record = days.isEmpty ? 0 : 1;
    int run = 1;
    for (var i = 0; i < days.length - 1; i++) {
      if (days[i].difference(days[i + 1]).inDays == 1) {
        run++;
        if (run > record) record = run;
      } else {
        run = 1;
      }
    }
    if (current > record) record = current;

    // Dias da semana atual (segunda → domingo) com treino.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekDays = <int>{};
    for (final d in days) {
      final diff = d.difference(monday).inDays;
      if (diff >= 0 && diff <= 6) weekDays.add(d.weekday); // 1=Seg..7=Dom
    }

    return (current: current, record: record, weekDays: weekDays);
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
    String? sport,
  }) async {
    final attendanceDate = date ?? DateTime.now();
    // Deterministic doc id makes the transactional check-and-write idempotent:
    // two concurrent writers race on the same ref, exactly one wins.
    final docId = _deterministicAttendanceId(studentId, classId, attendanceDate);
    final attendanceRef = _attendanceRef.doc(docId);
    final studentRef = _collections.student(studentId);

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
    if (weight != null && weight != 1.0) {
      payload['weight'] = weight;
    }
    // Persist the class's sport so graduation queries can filter
    // attendances by sport. Defaults to 'bjj' for legacy callers.
    payload['sport'] = sport ?? 'bjj';

    await FirebaseService.firestore.runTransaction((tx) async {
      final existing = await tx.get(attendanceRef);
      if (existing.exists) {
        throw Exception('Aluno já marcado como presente nesta aula');
      }
      tx.set(attendanceRef, payload);
      tx.update(studentRef, {
        'attendanceCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    // Milestone notification is best-effort and outside the transaction.
    checkAttendanceMilestone(studentId, studentName, verifiedBy).ignore();

    // Auto-graduation: when the academy is in graduationMode='auto', check
    // eligibility and promote on the spot. Fire-and-forget so a failure
    // here never blocks the attendance write that just succeeded.
    _maybeAutoPromote(
      studentId: studentId,
      studentName: studentName,
      verifiedBy: verifiedBy,
      verifiedByName: verifiedByName,
      sport: sport,
    ).ignore();

    final doc = await attendanceRef.get();
    return Attendance.fromFirestore(doc);
  }

  // ============================================
  // Mark MANUAL Presence (decoupled from any charge)
  //
  // Grants a presence to a student WITHOUT creating any financial doc — the
  // professor is simply registering that the student trained (e.g. a one-off
  // private/extra session, a make-up class, a courtesy presence). Mirrors the
  // server-side aula-particular grant (functions/server_functions.js ~4719):
  // classId 'aula_particular' / className 'Aula Particular' by default.
  //
  // Unlike [markPresent], this uses a NON-COLLIDING auto-generated doc id
  // (Firestore `.doc()`) instead of the day-deterministic id, so a professor
  // can grant SEVERAL presences on the SAME day without hitting the
  // "Aluno já marcado como presente" guard. The attendance write and the
  // student counter increment ship in the SAME transaction, exactly like
  // [markPresent].
  // ============================================
  Future<Attendance> markManualPresence({
    required String studentId,
    required String studentName,
    required String verifiedBy,
    required String verifiedByName,
    DateTime? date,
    String? sport,
    String? note,
    String classId = 'aula_particular',
    String className = 'Aula Particular',
  }) async {
    final attendanceDate = date ?? DateTime.now();
    // Auto-id ref: never collides, so multiple manual presences per day are OK.
    final attendanceRef = _attendanceRef.doc();
    final studentRef = _collections.student(studentId);

    final payload = <String, dynamic>{
      'studentId': studentId,
      'studentName': studentName,
      'classId': classId,
      'className': className,
      'date': Timestamp.fromDate(attendanceDate),
      'verifiedBy': verifiedBy,
      'verifiedByName': verifiedByName,
      'notes': note,
      // Defaults to 'bjj' for legacy/graduation queries — same as markPresent.
      'sport': sport ?? 'bjj',
      'createdAt': FieldValue.serverTimestamp(),
    };

    await FirebaseService.firestore.runTransaction((tx) async {
      // No existence check: the auto-id ref is unique by construction, so a
      // professor may grant several presences for the same day.
      tx.set(attendanceRef, payload);
      tx.update(studentRef, {
        'attendanceCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    // Milestone notification is best-effort and outside the transaction.
    checkAttendanceMilestone(studentId, studentName, verifiedBy).ignore();

    // Auto-graduation: mirror markPresent so a manual presence can also cross
    // the configured threshold. Fire-and-forget — never blocks the write.
    _maybeAutoPromote(
      studentId: studentId,
      studentName: studentName,
      verifiedBy: verifiedBy,
      verifiedByName: verifiedByName,
      sport: sport,
    ).ignore();

    final doc = await attendanceRef.get();
    return Attendance.fromFirestore(doc);
  }

  /// Promote the student if the academy opted into auto graduation AND
  /// they just crossed the configured threshold. No-op when the feature
  /// is off or the mode is 'manual'.
  /// Graduação automática DESATIVADA (decisão de produto: a promoção é sempre
  /// um ato DELIBERADO do professor — o sistema nunca escreve a faixa sozinho).
  /// A elegibilidade por presenças continua sendo CALCULADA e SUGERIDA ao
  /// professor na tela de detalhe do aluno (student_detail_screen →
  /// eligibilityBySport); a promoção em si é feita manualmente lá. Mantido como
  /// no-op para não alterar os call sites do check-in; o gating por dados
  /// (graduationMode != 'auto') também impede a versão antiga do app de promover.
  Future<void> _maybeAutoPromote({
    required String studentId,
    required String studentName,
    required String verifiedBy,
    required String verifiedByName,
    String? sport,
  }) async {
    // Intencionalmente vazio — ver doc acima. A sugestão ao professor vive na
    // elegibilidade exibida em student_detail_screen.
    return;
  }

  /// Student ids that already have a [classId] attendance dated today. Used by
  /// the musculação roster and self check-in UIs to mark "done today". Uses the
  /// existing (classId ASC, date DESC) composite index.
  Future<Set<String>> presentTodayForClass(String classId) async {
    final now = DateTime.now();
    final snap = await _attendanceRef
        .where('classId', isEqualTo: classId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(now)))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(now)))
        .get();
    return snap.docs
        .map((d) => (d.data() as Map<String, dynamic>)['studentId'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// Deterministic key per (student, class, day) so concurrent writes collide
  /// on the same doc id and exactly one wins inside the transaction.
  String _deterministicAttendanceId(
    String studentId,
    String classId,
    DateTime date,
  ) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${studentId}_${classId}_$y$m$d';
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
    String? sport,
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
        payload['sport'] = sport ?? 'bjj';
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
