import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto/attendance_dto.dart' as api_att;
import '../api/repositories.dart';
import '../models/checkin.dart';
import '../providers/auth_provider.dart';
import '../services/checkin_service.dart';

// ---------------------------------------------------------------------------
// NOTE (tatami migration):
//
// The Checkin concept (pending student self-checkins stored in Firestore
// `checkins` collection) has no direct server-side equivalent in the tatami
// backend yet.  Until a tatami endpoint for the pending-queue is available we
// keep the Firestore reads for queries that have no tatami counterpart.
//
// Mapping summary:
//   createCheckin       → repo.selfCheckin  (self check-in via QR / legacy)
//   addManualCheckin    → repo.markPresent  (direct attendance, skip queue)
//   confirmCheckins     → repo.markPresent per item  (confirmed → attendance)
//   removeCheckin       → TODO(tatami): no endpoint yet, keep Firestore
//   getPendingByClass   → TODO(tatami): no list-pending endpoint, keep Firestore
//   getStudentPending   → TODO(tatami): no list-pending endpoint, keep Firestore
//   hasCheckin          → TODO(tatami): approximate via attendance list
//   getStudentCheckin   → TODO(tatami): no pending-queue endpoint, keep Firestore
//   countPendingCheckins→ TODO(tatami): no pending-queue endpoint, keep Firestore
// ---------------------------------------------------------------------------

/// Pending check-ins for a class and date.
// TODO(tatami): migrate to tatami endpoint once a pending-checkin list API
// exists; currently falls back to Firestore CheckinService.
final pendingCheckinsProvider = FutureProvider.family<List<Checkin>, PendingCheckinsParams>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return [];

  // TODO(tatami): replace with attendanceRepoProvider call when
  // GET /v1/academies/{id}/pending-checkins is available.
  final service = CheckinService(currentUser!.academyId!);
  return service.getPendingByClassAndDate(params.classId, params.date);
});

/// Parameters for pending check-ins provider.
class PendingCheckinsParams {
  final String classId;
  final DateTime date;

  PendingCheckinsParams({required this.classId, required this.date});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PendingCheckinsParams) return false;
    return classId == other.classId &&
        date.year == other.date.year &&
        date.month == other.date.month &&
        date.day == other.date.day;
  }

  @override
  int get hashCode => Object.hash(classId, date.year, date.month, date.day);
}

/// Student's pending check-ins.
// TODO(tatami): no tatami endpoint yet — keep Firestore.
final studentPendingCheckinsProvider = FutureProvider.family<List<Checkin>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return [];

  // TODO(tatami): replace with attendanceRepoProvider when a pending-checkin
  // query per student is available in tatami.
  final service = CheckinService(currentUser!.academyId!);
  return service.getStudentPendingCheckins(studentId);
});

/// Check if student has check-in for class on date.
// TODO(tatami): approximate via AttendanceFilter once per-student presence
// lookup by date+class is confirmed cheap on the backend.
final hasCheckinProvider = FutureProvider.family<bool, HasCheckinParams>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return false;

  // TODO(tatami): replace with attendanceRepoProvider.list filtered by
  // studentId + classId + date when the pending-queue concept is dropped.
  final service = CheckinService(currentUser!.academyId!);
  return service.hasCheckin(params.studentId, params.classId, params.date);
});

/// Parameters for has check-in provider.
class HasCheckinParams {
  final String studentId;
  final String classId;
  final DateTime date;

  HasCheckinParams({
    required this.studentId,
    required this.classId,
    required this.date,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HasCheckinParams) return false;
    return studentId == other.studentId &&
        classId == other.classId &&
        date.year == other.date.year &&
        date.month == other.date.month &&
        date.day == other.date.day;
  }

  @override
  int get hashCode =>
      Object.hash(studentId, classId, date.year, date.month, date.day);
}

/// Count pending check-ins for class/date.
// TODO(tatami): no pending-queue count endpoint in tatami yet.
final checkinCountProvider = FutureProvider.family<int, PendingCheckinsParams>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return 0;

  // TODO(tatami): replace with attendanceRepoProvider when a count/list
  // pending-checkins endpoint is available.
  final service = CheckinService(currentUser!.academyId!);
  return service.countPendingCheckins(params.classId, params.date);
});

/// Student check-in for specific class/date.
// TODO(tatami): no pending-queue lookup endpoint in tatami yet.
final studentCheckinProvider = FutureProvider.family<Checkin?, HasCheckinParams>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return null;

  // TODO(tatami): replace with attendanceRepoProvider when tatami exposes a
  // per-student pending-checkin fetch.
  final service = CheckinService(currentUser!.academyId!);
  return service.getStudentCheckin(params.studentId, params.classId, params.date);
});

/// Checkin actions notifier for mutations.
class CheckinActionsNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  CheckinActionsNotifier(this._ref) : super(const AsyncValue.data(null));

  /// Student self check-in (legacy path — no QR token).
  ///
  /// Tatami: POST /v1/academies/{id}/attendance/self-checkin.
  /// Maps to [AttendanceRemoteRepo.selfCheckin] with [SelfCheckinRequest]
  /// (no qrToken → legacy roster-only path on the backend).
  Future<Checkin?> createCheckin({
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String scheduleStartTime,
    required String scheduleEndTime,
    required int scheduleDayOfWeek,
  }) async {
    final currentUser = _ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return null;

    final academyId = currentUser!.academyId!;

    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(attendanceRepoProvider);
      final apiAttendance = await repo.selfCheckin(
        academyId,
        api_att.SelfCheckinRequest(classId: classId),
      );

      state = const AsyncValue.data(null);
      _invalidateCheckins();

      // Build a Checkin from the returned ApiAttendance for callers that
      // still rely on the Checkin model for immediate UI feedback.
      return Checkin(
        id: apiAttendance.id,
        studentId: apiAttendance.studentId,
        studentName: studentName,
        classId: apiAttendance.classId,
        className: className,
        scheduleDate: apiAttendance.date,
        scheduleDayOfWeek: scheduleDayOfWeek,
        scheduleStartTime: scheduleStartTime,
        scheduleEndTime: scheduleEndTime,
        checkinTime: apiAttendance.createdAt ?? DateTime.now(),
        status: CheckinStatus.pending,
        createdAt: apiAttendance.createdAt ?? DateTime.now(),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Remove a pending check-in from the Firestore pending queue.
  // TODO(tatami): replace with attendanceRepoProvider.delete once tatami
  // exposes DELETE /v1/academies/{id}/pending-checkins/{id}.
  Future<void> removeCheckin(String checkinId) async {
    final currentUser = _ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    state = const AsyncValue.loading();
    try {
      // TODO(tatami): no tatami endpoint yet — keep Firestore removal.
      final service = CheckinService(currentUser!.academyId!);
      await service.removeCheckin(checkinId);
      state = const AsyncValue.data(null);
      _invalidateCheckins();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Add a manual check-in as direct attendance (admin/instructor).
  ///
  /// Tatami: POST /v1/academies/{id}/students/{sid}/attendance
  /// Maps to [AttendanceRemoteRepo.markPresent].
  Future<Checkin?> addManualCheckin({
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String scheduleStartTime,
    required String scheduleEndTime,
    required int scheduleDayOfWeek,
    required DateTime date,
  }) async {
    final currentUser = _ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return null;

    final academyId = currentUser!.academyId!;

    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(attendanceRepoProvider);
      final apiAttendance = await repo.markPresent(
        academyId,
        studentId,
        api_att.AttendanceSingleRequest(classId: classId, date: date),
      );

      state = const AsyncValue.data(null);
      _invalidateCheckins();

      return Checkin(
        id: apiAttendance.id,
        studentId: apiAttendance.studentId,
        studentName: studentName,
        classId: apiAttendance.classId,
        className: className,
        scheduleDate: apiAttendance.date,
        scheduleDayOfWeek: scheduleDayOfWeek,
        scheduleStartTime: scheduleStartTime,
        scheduleEndTime: scheduleEndTime,
        checkinTime: apiAttendance.createdAt ?? DateTime.now(),
        status: CheckinStatus.pending,
        createdAt: apiAttendance.createdAt ?? DateTime.now(),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Confirm pending check-ins: mark each as present via tatami, then remove
  /// the pending entry from the Firestore queue.
  ///
  /// Tatami: POST /v1/academies/{id}/students/{sid}/attendance per item.
  /// Maps to [AttendanceRemoteRepo.markPresent].
  Future<Map<String, int>> confirmCheckins(
    List<Checkin> checkins,
    String confirmedBy,
    String confirmedByName,
  ) async {
    final currentUser = _ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) {
      return {'success': 0, 'failed': checkins.length};
    }

    final academyId = currentUser!.academyId!;

    state = const AsyncValue.loading();
    int success = 0;
    int failed = 0;
    try {
      final repo = _ref.read(attendanceRepoProvider);
      // TODO(tatami): no tatami endpoint for removing pending-queue entries.
      // Keep Firestore removal until a DELETE pending-checkin endpoint exists.
      final checkinService = CheckinService(academyId);

      for (final checkin in checkins) {
        try {
          await repo.markPresent(
            academyId,
            checkin.studentId,
            api_att.AttendanceSingleRequest(
              classId: checkin.classId,
              date: checkin.scheduleDate,
            ),
          );
          // Remove from Firestore pending queue after successful mark.
          await checkinService.removeCheckin(checkin.id);
          success++;
        } catch (_) {
          // Duplicate or other error — student may already be present.
          failed++;
        }
      }

      state = const AsyncValue.data(null);
      _invalidateCheckins();
      return {'success': success, 'failed': failed};
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  void _invalidateCheckins() {
    _ref.invalidateSelf();
  }
}

/// Checkin actions provider.
final checkinActionsProvider =
    StateNotifierProvider<CheckinActionsNotifier, AsyncValue<void>>((ref) {
  return CheckinActionsNotifier(ref);
});
