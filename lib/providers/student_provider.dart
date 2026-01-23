import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/student.dart';
import '../services/services.dart';
import 'auth_provider.dart';

/// Current student provider - fetches the student linked to the logged-in user
final currentStudentProvider = FutureProvider<Student?>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser == null) return null;

  // If user has a studentId, fetch the student
  if (currentUser.studentId != null && currentUser.academyId != null) {
    // Set the academy context
    FirebaseService.setAcademyId(currentUser.academyId!);

    final service = StudentService(currentUser.academyId!);
    return await service.getById(currentUser.studentId!);
  }

  // Try to find student by linkedUserId
  if (currentUser.academyId != null) {
    FirebaseService.setAcademyId(currentUser.academyId!);

    final service = StudentService(currentUser.academyId!);
    return await service.getByLinkedUserId(currentUser.id);
  }

  return null;
});

/// Student service provider
final studentServiceProvider = Provider<StudentService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;

  if (currentUser?.academyId == null) return null;

  return StudentService(currentUser!.academyId!);
});

/// Student attendance history provider
final studentAttendanceProvider = FutureProvider.family<List<Attendance>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return [];

  final service = AttendanceService(currentUser!.academyId!);
  return await service.getByStudent(studentId);
});

/// Student attendance count provider
final studentAttendanceCountProvider = FutureProvider.family<int, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return 0;

  final service = AttendanceService(currentUser!.academyId!);
  return await service.getStudentAttendanceCount(studentId);
});

/// Student achievements provider
final studentAchievementsProvider = FutureProvider.family<List<Achievement>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return [];

  final service = AchievementService(currentUser!.academyId!);
  return await service.getByStudent(studentId);
});

/// Student medal count provider
final studentMedalCountProvider = FutureProvider.family<Map<String, int>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) {
    return {'gold': 0, 'silver': 0, 'bronze': 0, 'total': 0};
  }

  final service = AchievementService(currentUser!.academyId!);
  return await service.getMedalCount(studentId);
});

/// Student timeline provider (achievements grouped by year)
final studentTimelineProvider = FutureProvider.family<Map<int, List<Achievement>>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return {};

  final service = AchievementService(currentUser!.academyId!);
  return await service.getTimeline(studentId);
});

/// Student payments provider
final studentPaymentsProvider = FutureProvider.family<List<Payment>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return [];

  final service = PaymentService(currentUser!.academyId!);
  return await service.getByStudent(studentId);
});

/// Student payment stats provider
final studentPaymentStatsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) {
    return {
      'pending': {'count': 0, 'total': 0.0},
      'overdue': {'count': 0, 'total': 0.0},
      'paid': {'count': 0, 'total': 0.0},
    };
  }

  final service = PaymentService(currentUser!.academyId!);
  return await service.getStatsByStudent(studentId);
});

/// Student assessments provider
final studentAssessmentsProvider = FutureProvider.family<List<Assessment>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return [];

  final service = AssessmentService(currentUser!.academyId!);
  return await service.getByStudent(studentId);
});

/// Latest assessment provider
final latestAssessmentProvider = FutureProvider.family<Assessment?, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return null;

  final service = AssessmentService(currentUser!.academyId!);
  return await service.getLatest(studentId);
});

/// Assessment averages provider
final assessmentAveragesProvider = FutureProvider.family<Map<AssessmentCategory, double>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) {
    return {
      AssessmentCategory.respeito: 0,
      AssessmentCategory.disciplina: 0,
      AssessmentCategory.pontualidade: 0,
      AssessmentCategory.tecnica: 0,
      AssessmentCategory.esforco: 0,
    };
  }

  final service = AssessmentService(currentUser!.academyId!);
  return await service.getAveragesByCategory(studentId);
});
