import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/checkin.dart';
import '../services/checkin_service.dart';
import 'auth_provider.dart';

/// Checkin service provider
final checkinServiceProvider = Provider<CheckinService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;

  if (currentUser?.academyId == null) return null;

  return CheckinService(currentUser!.academyId!);
});

/// Pending check-ins for a class and date
final pendingCheckinsProvider = FutureProvider.family<List<Checkin>, PendingCheckinsParams>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return [];

  final service = CheckinService(currentUser!.academyId!);
  return await service.getPendingByClassAndDate(params.classId, params.date);
});

/// Parameters for pending check-ins provider
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

/// Student's pending check-ins
final studentPendingCheckinsProvider = FutureProvider.family<List<Checkin>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return [];

  final service = CheckinService(currentUser!.academyId!);
  return await service.getStudentPendingCheckins(studentId);
});

/// Check if student has check-in for class on date
final hasCheckinProvider = FutureProvider.family<bool, HasCheckinParams>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return false;

  final service = CheckinService(currentUser!.academyId!);
  return await service.hasCheckin(params.studentId, params.classId, params.date);
});

/// Parameters for has check-in provider
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

/// Count pending check-ins for class/date
final checkinCountProvider = FutureProvider.family<int, PendingCheckinsParams>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return 0;

  final service = CheckinService(currentUser!.academyId!);
  return await service.countPendingCheckins(params.classId, params.date);
});

/// Student check-in for specific class/date
final studentCheckinProvider = FutureProvider.family<Checkin?, HasCheckinParams>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return null;

  final service = CheckinService(currentUser!.academyId!);
  return await service.getStudentCheckin(params.studentId, params.classId, params.date);
});

/// Checkin actions notifier for mutations
class CheckinActionsNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref ref;

  CheckinActionsNotifier(this.ref) : super(const AsyncValue.data(null));

  Future<Checkin?> createCheckin({
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String scheduleStartTime,
    required String scheduleEndTime,
    required int scheduleDayOfWeek,
  }) async {
    final service = ref.read(checkinServiceProvider);
    if (service == null) return null;

    state = const AsyncValue.loading();
    try {
      final checkin = await service.createCheckin(
        studentId: studentId,
        studentName: studentName,
        classId: classId,
        className: className,
        scheduleStartTime: scheduleStartTime,
        scheduleEndTime: scheduleEndTime,
        scheduleDayOfWeek: scheduleDayOfWeek,
      );
      state = const AsyncValue.data(null);
      _invalidateCheckins();
      return checkin;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> removeCheckin(String checkinId) async {
    final service = ref.read(checkinServiceProvider);
    if (service == null) return;

    state = const AsyncValue.loading();
    try {
      await service.removeCheckin(checkinId);
      state = const AsyncValue.data(null);
      _invalidateCheckins();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

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
    final service = ref.read(checkinServiceProvider);
    if (service == null) return null;

    state = const AsyncValue.loading();
    try {
      final checkin = await service.addManualCheckin(
        studentId: studentId,
        studentName: studentName,
        classId: classId,
        className: className,
        scheduleStartTime: scheduleStartTime,
        scheduleEndTime: scheduleEndTime,
        scheduleDayOfWeek: scheduleDayOfWeek,
        date: date,
      );
      state = const AsyncValue.data(null);
      _invalidateCheckins();
      return checkin;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<Map<String, int>> confirmCheckins(
    List<String> checkinIds,
    String confirmedBy,
    String confirmedByName,
  ) async {
    final service = ref.read(checkinServiceProvider);
    if (service == null) return {'success': 0, 'failed': checkinIds.length};

    state = const AsyncValue.loading();
    try {
      final result = await service.confirmCheckins(
        checkinIds,
        confirmedBy,
        confirmedByName,
      );
      state = const AsyncValue.data(null);
      _invalidateCheckins();
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  void _invalidateCheckins() {
    // This will cause dependent providers to refetch
    ref.invalidateSelf();
  }
}

/// Checkin actions provider
final checkinActionsProvider =
    StateNotifierProvider<CheckinActionsNotifier, AsyncValue<void>>((ref) {
  return CheckinActionsNotifier(ref);
});
