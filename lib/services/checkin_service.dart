import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/checkin.dart';
import 'attendance_service.dart';
import 'class_service.dart';
import 'firebase_service.dart';

/// Virtual class identity for schedule-less modalities (musculação). Musculação
/// has no turma/horário, so attendance is recorded against this shared id.
/// [AttendanceService.markPresent] stores it as a plain string and never looks
/// the class up, so no real class document is required. The same string is
/// mirrored in the `selfCheckin` Cloud Function.
const String kMusculacaoClassId = 'musculacao';
const String kMusculacaoClassName = 'Musculação';

/// Helper: Check if current time is within check-in window
/// Window: 30 min before class START until 1 hour after class END
bool isInCheckinWindow({
  required String startTime,
  required String endTime,
  required DateTime date,
}) {
  final now = DateTime.now();
  if (!_isSameDay(now, date)) return false;

  final startParts = startTime.split(':').map(int.parse).toList();
  final endParts = endTime.split(':').map(int.parse).toList();

  // Use Duration arithmetic to avoid silent overflow when raw minutes go
  // negative or above 60 (e.g. class at 00:15 would otherwise resolve to the
  // previous day, opening the window incorrectly).
  final classStart = DateTime(
    date.year,
    date.month,
    date.day,
    startParts[0],
    startParts[1],
  );
  final classEnd = DateTime(
    date.year,
    date.month,
    date.day,
    endParts[0],
    endParts[1],
  );
  final windowStart = classStart.subtract(const Duration(minutes: 30));
  final windowEnd = classEnd.add(const Duration(hours: 1));

  return now.isAfter(windowStart) && now.isBefore(windowEnd);
}

/// Helper: Get time until check-in window opens
Map<String, int>? getTimeUntilCheckinOpens({
  required String startTime,
  required DateTime date,
}) {
  final now = DateTime.now();
  if (!_isSameDay(now, date)) return null;

  final startParts = startTime.split(':').map(int.parse).toList();

  final windowStart = DateTime(
    date.year,
    date.month,
    date.day,
    startParts[0],
    startParts[1],
  ).subtract(const Duration(minutes: 30));

  if (now.isAfter(windowStart)) return null;

  final diff = windowStart.difference(now);
  final totalMinutes = diff.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;

  return {'hours': hours, 'minutes': minutes};
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Checkin Service - Multi-tenant check-in management
class CheckinService {
  final String academyId;
  late final Collections _collections;

  CheckinService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _checkinRef => _collections.checkins;

  // Helper: Get start and end of day
  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);

  // ============================================
  // Create Check-in (Student)
  // ============================================
  Future<Checkin> createCheckin({
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String scheduleStartTime,
    required String scheduleEndTime,
    required int scheduleDayOfWeek,
  }) async {
    final now = DateTime.now();

    // Normalize schedule date to noon
    final scheduleDate = DateTime(now.year, now.month, now.day, 12, 0, 0);

    // Check if student already has a check-in for this class today
    final existingCheckin =
        await getStudentCheckin(studentId, classId, scheduleDate);
    if (existingCheckin != null) {
      throw Exception('Voce ja fez check-in para esta aula');
    }

    // Check if within check-in window
    final inWindow = isInCheckinWindow(
      startTime: scheduleStartTime,
      endTime: scheduleEndTime,
      date: scheduleDate,
    );
    if (!inWindow) {
      throw Exception('Fora do horario de check-in');
    }

    final docData = {
      'studentId': studentId,
      'studentName': studentName,
      'classId': classId,
      'className': className,
      'scheduleDate': Timestamp.fromDate(scheduleDate),
      'scheduleDayOfWeek': scheduleDayOfWeek,
      'scheduleStartTime': scheduleStartTime,
      'scheduleEndTime': scheduleEndTime,
      'checkinTime': Timestamp.fromDate(now),
      'status': CheckinStatus.pending.value,
      'createdAt': Timestamp.fromDate(now),
    };

    final docRef = await _checkinRef.add(docData);

    return Checkin(
      id: docRef.id,
      studentId: studentId,
      studentName: studentName,
      classId: classId,
      className: className,
      scheduleDate: scheduleDate,
      scheduleDayOfWeek: scheduleDayOfWeek,
      scheduleStartTime: scheduleStartTime,
      scheduleEndTime: scheduleEndTime,
      checkinTime: now,
      status: CheckinStatus.pending,
      createdAt: now,
    );
  }

  // ============================================
  // Get Pending Check-ins by Class and Date
  // ============================================
  Future<List<Checkin>> getPendingByClassAndDate(
    String classId,
    DateTime date,
  ) async {
    final start = _startOfDay(date);
    final end = _endOfDay(date);

    final query = await _checkinRef
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: CheckinStatus.pending.value)
        .get();

    final checkins = query.docs.map((doc) => Checkin.fromFirestore(doc)).toList();

    // Filter by date range in memory
    final filtered = checkins
        .where((c) =>
            c.scheduleDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
            c.scheduleDate.isBefore(end.add(const Duration(seconds: 1))))
        .toList();

    // Sort by check-in time
    filtered.sort((a, b) => a.checkinTime.compareTo(b.checkinTime));

    return filtered;
  }

  // ============================================
  // Check if Student has Check-in
  // ============================================
  Future<bool> hasCheckin(String studentId, String classId, DateTime date) async {
    final checkin = await getStudentCheckin(studentId, classId, date);
    return checkin != null;
  }

  // ============================================
  // Get Student Check-in
  // ============================================
  Future<Checkin?> getStudentCheckin(
    String studentId,
    String classId,
    DateTime date,
  ) async {
    final start = _startOfDay(date);
    final end = _endOfDay(date);

    final query = await _checkinRef
        .where('studentId', isEqualTo: studentId)
        .where('classId', isEqualTo: classId)
        .get();

    final checkins = query.docs.map((doc) => Checkin.fromFirestore(doc)).toList();

    // Filter by date in memory
    final todayCheckin = checkins.firstWhere(
      (c) =>
          c.scheduleDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
          c.scheduleDate.isBefore(end.add(const Duration(seconds: 1))),
      orElse: () => Checkin(
        id: '',
        studentId: '',
        studentName: '',
        classId: '',
        className: '',
        scheduleDate: DateTime.now(),
        scheduleDayOfWeek: 0,
        scheduleStartTime: '',
        scheduleEndTime: '',
        checkinTime: DateTime.now(),
        status: CheckinStatus.pending,
        createdAt: DateTime.now(),
      ),
    );

    return todayCheckin.id.isEmpty ? null : todayCheckin;
  }

  // ============================================
  // Remove Check-in
  // ============================================
  Future<void> removeCheckin(String checkinId) async {
    await _collections.checkin(checkinId).delete();
  }

  // ============================================
  // Add Manual Check-in (Admin)
  // ============================================
  Future<Checkin> addManualCheckin({
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String scheduleStartTime,
    required String scheduleEndTime,
    required int scheduleDayOfWeek,
    required DateTime date,
  }) async {
    final now = DateTime.now();

    // Normalize schedule date to noon
    final scheduleDate = DateTime(date.year, date.month, date.day, 12, 0, 0);

    // Check if student already has a check-in for this class on this date
    final existingCheckin =
        await getStudentCheckin(studentId, classId, scheduleDate);
    if (existingCheckin != null) {
      throw Exception('Aluno ja possui check-in para esta aula');
    }

    final docData = {
      'studentId': studentId,
      'studentName': studentName,
      'classId': classId,
      'className': className,
      'scheduleDate': Timestamp.fromDate(scheduleDate),
      'scheduleDayOfWeek': scheduleDayOfWeek,
      'scheduleStartTime': scheduleStartTime,
      'scheduleEndTime': scheduleEndTime,
      'checkinTime': Timestamp.fromDate(now),
      'status': CheckinStatus.pending.value,
      'createdAt': Timestamp.fromDate(now),
    };

    final docRef = await _checkinRef.add(docData);

    return Checkin(
      id: docRef.id,
      studentId: studentId,
      studentName: studentName,
      classId: classId,
      className: className,
      scheduleDate: scheduleDate,
      scheduleDayOfWeek: scheduleDayOfWeek,
      scheduleStartTime: scheduleStartTime,
      scheduleEndTime: scheduleEndTime,
      checkinTime: now,
      status: CheckinStatus.pending,
      createdAt: now,
    );
  }

  // ============================================
  // Confirm Check-ins (Convert to Attendance)
  // ============================================
  Future<Map<String, int>> confirmCheckins(
    List<String> checkinIds,
    String confirmedBy,
    String confirmedByName,
  ) async {
    final attendanceService = AttendanceService(academyId);
    final classService = ClassService(academyId);
    final classWeightCache = <String, double>{};
    int success = 0;
    int failed = 0;

    for (final checkinId in checkinIds) {
      try {
        // Get the check-in
        final docSnap = await _collections.checkin(checkinId).get();

        if (!docSnap.exists) {
          failed++;
          continue;
        }

        final checkin = Checkin.fromFirestore(docSnap);

        // Look up the class weight (cached per call) so weighted academies
        // can still benefit from check-in approvals.
        double? weight;
        if (!classWeightCache.containsKey(checkin.classId)) {
          final cls = await classService.getById(checkin.classId);
          classWeightCache[checkin.classId] = cls?.effectiveWeight() ?? 1.0;
        }
        weight = classWeightCache[checkin.classId];

        // Create attendance record
        await attendanceService.markPresent(
          studentId: checkin.studentId,
          studentName: checkin.studentName,
          classId: checkin.classId,
          className: checkin.className,
          verifiedBy: confirmedBy,
          verifiedByName: confirmedByName,
          date: checkin.scheduleDate,
          weight: weight,
        );

        // Delete the check-in
        await _collections.checkin(checkinId).delete();

        success++;
      } catch (e) {
        // Student might already be marked present, skip
        failed++;
      }
    }

    return {'success': success, 'failed': failed};
  }

  // ============================================
  // Count Pending Check-ins for Class/Date
  // ============================================
  Future<int> countPendingCheckins(String classId, DateTime date) async {
    final checkins = await getPendingByClassAndDate(classId, date);
    return checkins.length;
  }

  // ============================================
  // Get All Pending Check-ins for Student
  // ============================================
  Future<List<Checkin>> getStudentPendingCheckins(String studentId) async {
    final query = await _checkinRef
        .where('studentId', isEqualTo: studentId)
        .where('status', isEqualTo: CheckinStatus.pending.value)
        .get();

    final checkins = query.docs.map((doc) => Checkin.fromFirestore(doc)).toList();

    // Sort by check-in time descending
    checkins.sort((a, b) => b.checkinTime.compareTo(a.checkinTime));

    return checkins;
  }
}
