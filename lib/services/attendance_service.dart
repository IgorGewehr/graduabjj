import '../api/attendance_repo.dart';
import '../api/dto/attendance_dto.dart' as api;
import '../api/tatami_client.dart';
import 'firebase_service.dart';

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
}

/// Attendance Service - Multi-tenant attendance management (HTTP/Tatami backend)
class AttendanceService {
  final String academyId;
  late final AttendanceRemoteRepo _repo;

  /// [repo] is optional for backward-compat with callers that only pass
  /// [academyId]. When omitted, a default [AttendanceRemoteRepo] backed by a
  /// fresh [TatamiClient] is created automatically.
  AttendanceService(this.academyId, {AttendanceRemoteRepo? repo}) {
    _repo = repo ??
        AttendanceRemoteRepo(
          TatamiClient(
            baseUrl: const String.fromEnvironment(
              'TATAMI_BASE_URL',
              defaultValue: 'https://tatami.tensorroot.com',
            ),
          ),
        );
  }

  // ============================================
  // Get Attendance by Student
  // ============================================
  Future<List<Attendance>> getByStudent(
    String studentId, {
    int limit = 50,
  }) async {
    final page = await _repo.list(
      academyId,
      filter: api.AttendanceFilter(studentId: studentId, limit: limit),
    );
    return page.items.map((a) => Attendance.fromApi(a)).toList();
  }

  // ============================================
  // Get Attendance by Student — PAGINATED
  //
  // Uses server-side cursor pagination. Returns the page of items together
  // with the next cursor string. When [nextCursor] is null, the end of the
  // collection has been reached.
  // ============================================
  Future<({List<Attendance> items, String? nextCursor})>
  getByStudentPaginated(
    String studentId, {
    int limit = 15,
    String? cursor,
  }) async {
    final page = await _repo.list(
      academyId,
      filter: api.AttendanceFilter(
        studentId: studentId,
        limit: limit,
        cursor: cursor,
      ),
    );
    final items = page.items.map((a) => Attendance.fromApi(a)).toList();
    return (items: items, nextCursor: page.hasMore ? page.nextCursor : null);
  }

  // ============================================
  // Get Attendance Count by Student
  // ============================================
  Future<int> getStudentAttendanceCount(String studentId) async {
    // Fetch up to 500 items; for a milestone check this is enough.
    // The backend total field is not exposed in AttendancePage — count items.
    final page = await _repo.list(
      academyId,
      filter: api.AttendanceFilter(studentId: studentId, limit: 500),
    );
    return page.items.length;
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
    final page = await _repo.list(
      academyId,
      filter: api.AttendanceFilter(
        studentId: studentId,
        classId: classId,
        dateFrom: startDate,
        dateTo: endDate,
        limit: 500,
      ),
    );
    return page.items.map((a) => Attendance.fromApi(a)).toList();
  }

  // ============================================
  // Get Attendance by Date and Class
  // ============================================
  Future<List<Attendance>> getByDateAndClass(
    DateTime date,
    String classId,
  ) async {
    final page = await _repo.list(
      academyId,
      filter: api.AttendanceFilter(
        classId: classId,
        dateFrom: date,
        dateTo: date,
        limit: 500,
      ),
    );
    return page.items.map((a) => Attendance.fromApi(a)).toList();
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
    final page = await _repo.list(
      academyId,
      filter: api.AttendanceFilter(
        studentId: studentId,
        classId: classId,
        dateFrom: date,
        dateTo: date,
        limit: 1,
      ),
    );
    return page.items.isNotEmpty;
  }

  // ============================================
  // Get Present Student IDs for Class
  // ============================================
  Future<Set<String>> getPresentStudentIds(
    String classId, {
    DateTime? date,
  }) async {
    final d = date ?? DateTime.now();
    final page = await _repo.list(
      academyId,
      filter: api.AttendanceFilter(
        classId: classId,
        dateFrom: d,
        dateTo: d,
        limit: 500,
      ),
    );
    return page.items.map((a) => a.studentId).toSet();
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

    // Get unique dates and sort descending
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

    final apiResult = await _repo.markPresent(
      academyId,
      studentId,
      api.AttendanceSingleRequest(classId: classId, date: attendanceDate),
    );

    return Attendance.fromApi(
      apiResult,
      studentName: studentName,
      className: className,
      verifiedByName: verifiedByName,
    );
  }

  // ============================================
  // Unmark Student as Present
  // ============================================
  Future<void> unmarkPresent(
    String studentId,
    String classId,
    DateTime date,
  ) async {
    await _repo.unmarkPresent(
      academyId,
      studentId,
      api.AttendanceSingleRequest(classId: classId, date: date),
    );
  }

  // ============================================
  // Bulk Mark Students as Present
  //
  // Single round trip to POST /attendance/bulk. The backend handles
  // deduplication, counter updates, and milestone/achievement logic.
  // Returns the count of students actually recorded (excluding duplicates
  // and sport_mismatch).
  // ============================================
  Future<int> bulkMarkPresent({
    required List<({String studentId, String studentName})> students,
    required String classId,
    required String className,
    required String verifiedBy,
    required String verifiedByName,
    DateTime? date,
    double? weight,
  }) async {
    if (students.isEmpty) return 0;

    final studentIds = students.map((s) => s.studentId).toList();
    final recorded = await _repo.bulkRecord(academyId, classId, studentIds);
    return recorded;
  }

  // ============================================
  // Bulk Unmark Present
  //
  // No bulk DELETE endpoint exists — fan out as parallel individual DELETEs
  // in batches of 20 to avoid overloading the server.
  // Returns the number of records removed (ignores 404s — already absent).
  // ============================================
  Future<int> bulkUnmarkPresent({
    required String classId,
    required DateTime date,
  }) async {
    // Discover which students are present for this class/date first.
    final presentIds = await getPresentStudentIds(classId, date: date);
    if (presentIds.isEmpty) return 0;

    final ids = presentIds.toList();
    const batchSize = 20;
    int removed = 0;

    for (int start = 0; start < ids.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, ids.length);
      final batch = ids.sublist(start, end);

      await Future.wait(
        batch.map((sid) async {
          try {
            await _repo.unmarkPresent(
              academyId,
              sid,
              api.AttendanceSingleRequest(classId: classId, date: date),
            );
            removed++;
          } catch (_) {
            // Student was already absent — not an error.
          }
        }),
      );
    }

    return removed;
  }

  // ============================================
  // Delete Attendance Record
  // ============================================
  Future<void> delete(String id) async {
    await _repo.delete(academyId, id);
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
  //
  // NOTE: Achievement/milestone logic is now managed server-side. This method
  // is kept as a thin client-side check that can be used for local UI
  // feedback only; the backend will have already recorded the achievement.
  // ============================================
  Future<void> checkAttendanceMilestone(
    String studentId,
    String studentName,
    String createdBy,
  ) async {
    // Milestone creation is now server-side. No-op on the client.
    // Kept for call-site compatibility during incremental migration.
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
