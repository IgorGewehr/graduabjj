import 'package:cloud_firestore/cloud_firestore.dart';

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
  DateTime _startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);
  DateTime _endOfDay(DateTime date) => DateTime(date.year, date.month, date.day, 23, 59, 59);

  // ============================================
  // Get Attendance by Student
  // ============================================
  Future<List<Attendance>> getByStudent(String studentId, {int limit = 50}) async {
    final query = await _attendanceRef
        .where('studentId', isEqualTo: studentId)
        .get();

    var attendance = query.docs.map((doc) => Attendance.fromFirestore(doc)).toList();

    // Sort by date descending
    attendance.sort((a, b) => b.date.compareTo(a.date));

    if (attendance.length > limit) {
      attendance = attendance.sublist(0, limit);
    }

    return attendance;
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
    var results = snapshot.docs.map((doc) => Attendance.fromFirestore(doc)).toList();

    final start = _startOfDay(startDate);
    final end = _endOfDay(endDate);

    // Filter by date range
    results = results.where((a) =>
        a.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
        a.date.isBefore(end.add(const Duration(seconds: 1)))
    ).toList();

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
  Future<List<Attendance>> getByDateAndClass(DateTime date, String classId) async {
    final query = await _attendanceRef
        .where('classId', isEqualTo: classId)
        .get();

    final start = _startOfDay(date);
    final end = _endOfDay(date);

    final results = query.docs
        .map((doc) => Attendance.fromFirestore(doc))
        .where((a) =>
            a.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
            a.date.isBefore(end.add(const Duration(seconds: 1)))
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
  Future<bool> isStudentPresent(String studentId, String classId, DateTime date) async {
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
  Future<Set<String>> getPresentStudentIds(String classId, {DateTime? date}) async {
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
      final day = '${a.date.year}-${a.date.month.toString().padLeft(2, '0')}-${a.date.day.toString().padLeft(2, '0')}';
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
    final dates = attendance
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
  }) async {
    final attendanceDate = date ?? DateTime.now();

    // Check if already present
    final alreadyPresent = await isStudentPresent(studentId, classId, attendanceDate);
    if (alreadyPresent) {
      throw Exception('Aluno já marcado como presente nesta aula');
    }

    final docRef = await _attendanceRef.add({
      'studentId': studentId,
      'studentName': studentName,
      'classId': classId,
      'className': className,
      'date': Timestamp.fromDate(attendanceDate),
      'verifiedBy': verifiedBy,
      'verifiedByName': verifiedByName,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update student's attendance count
    await _updateStudentAttendanceCount(studentId, 1);

    final doc = await docRef.get();
    return Attendance.fromFirestore(doc);
  }

  // ============================================
  // Unmark Student as Present
  // ============================================
  Future<void> unmarkPresent(String studentId, String classId, DateTime date) async {
    final attendance = await getByDateAndClass(date, classId);
    final record = attendance.where((a) => a.studentId == studentId).firstOrNull;

    if (record == null) {
      throw Exception('Registro de presença não encontrado');
    }

    await _attendanceRef.doc(record.id).delete();

    // Update student's attendance count
    await _updateStudentAttendanceCount(studentId, -1);
  }

  // ============================================
  // Bulk Mark Students as Present
  // ============================================
  Future<List<Attendance>> bulkMarkPresent({
    required List<({String studentId, String studentName})> students,
    required String classId,
    required String className,
    required String verifiedBy,
    required String verifiedByName,
    DateTime? date,
  }) async {
    final attendanceDate = date ?? DateTime.now();
    final results = <Attendance>[];

    // Get already present students
    final presentIds = await getPresentStudentIds(classId, date: attendanceDate);

    final batch = FirebaseService.firestore.batch();
    final newRecords = <DocumentReference>[];

    for (final student in students) {
      // Skip if already present
      if (presentIds.contains(student.studentId)) continue;

      final docRef = _attendanceRef.doc();
      batch.set(docRef, {
        'studentId': student.studentId,
        'studentName': student.studentName,
        'classId': classId,
        'className': className,
        'date': Timestamp.fromDate(attendanceDate),
        'verifiedBy': verifiedBy,
        'verifiedByName': verifiedByName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      newRecords.add(docRef);
    }

    await batch.commit();

    // Update attendance counts for new records
    for (final student in students) {
      if (!presentIds.contains(student.studentId)) {
        await _updateStudentAttendanceCount(student.studentId, 1);
      }
    }

    // Fetch created records
    for (final docRef in newRecords) {
      final doc = await docRef.get();
      results.add(Attendance.fromFirestore(doc));
    }

    return results;
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
  }) async {
    final attendanceDate = date ?? DateTime.now();
    final isPresent = await isStudentPresent(studentId, classId, attendanceDate);

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
  // Helper: Update Student Attendance Count
  // ============================================
  Future<void> _updateStudentAttendanceCount(String studentId, int delta) async {
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
AttendanceService get attendanceService => AttendanceService(FirebaseService.academyId);
