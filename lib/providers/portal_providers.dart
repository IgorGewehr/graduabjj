import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/academy_event.dart';
import '../services/services.dart';
import 'auth_provider.dart';
import 'student_provider.dart';

// ============================================
// Class Schedule Providers
// ============================================

/// Class service provider
final classServiceProvider = Provider<ClassService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return ClassService(currentUser!.academyId!);
});

/// All classes provider
final classesProvider = FutureProvider<List<BJJClass>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = ClassService(currentUser!.academyId!);
  return await service.list();
});

/// Today's classes provider
final todayClassesProvider = FutureProvider<List<BJJClass>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = ClassService(currentUser!.academyId!);
  return await service.getTodayClasses();
});

/// Current class provider (class happening now)
final currentClassProvider = FutureProvider<BJJClass?>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return null;

  final service = ClassService(currentUser!.academyId!);
  return await service.getCurrentClass();
});

/// Weekly schedule provider
final weeklyScheduleProvider = FutureProvider<Map<int, List<BJJClass>>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return {};

  final service = ClassService(currentUser!.academyId!);
  return await service.getWeeklySchedule();
});

// ============================================
// Competition Providers
// ============================================

/// Competition service provider
final competitionServiceProvider = Provider<CompetitionService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return CompetitionService(currentUser!.academyId!);
});

/// All competitions provider
final competitionsProvider = FutureProvider<List<Competition>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = CompetitionService(currentUser!.academyId!);
  return await service.list();
});

/// Upcoming competitions provider
final upcomingCompetitionsProvider = FutureProvider<List<Competition>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = CompetitionService(currentUser!.academyId!);
  return await service.getUpcoming();
});

/// Student competition results provider (returns competitions where student participated)
final studentCompetitionResultsProvider = FutureProvider.family<List<Competition>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = CompetitionService(currentUser!.academyId!);
  return await service.getByStudent(studentId);
});

/// Student results provider (returns all CompetitionResult for a student)
final studentAllResultsProvider = FutureProvider.family<List<CompetitionResult>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = CompetitionService(currentUser!.academyId!);
  return await service.getResultsForStudent(studentId);
});

// ============================================
// Competition Enrollment Providers
// ============================================

/// Competition enrollment service provider
final competitionEnrollmentServiceProvider = Provider<CompetitionEnrollmentService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return CompetitionEnrollmentService(currentUser!.academyId!);
});

/// Student enrollments provider
final studentEnrollmentsProvider = FutureProvider.family<List<CompetitionEnrollment>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) {
    print('[ENROLLMENTS] No academyId found for current user');
    return [];
  }

  if (studentId.isEmpty) {
    print('[ENROLLMENTS] Empty studentId provided');
    return [];
  }

  print('[ENROLLMENTS] Fetching enrollments for studentId: $studentId in academy: ${currentUser!.academyId}');
  final service = CompetitionEnrollmentService(currentUser.academyId!);
  final enrollments = await service.getByStudent(studentId);
  print('[ENROLLMENTS] Found ${enrollments.length} enrollments for student $studentId');
  return enrollments;
});

/// Check if student is enrolled in competition
final isStudentEnrolledProvider = FutureProvider.family<bool, ({String competitionId, String studentId})>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return false;

  final service = CompetitionEnrollmentService(currentUser!.academyId!);
  return await service.isEnrolled(params.competitionId, params.studentId);
});

// ============================================
// Settings Providers
// ============================================

/// Settings service provider
final settingsServiceProvider = Provider<SettingsService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return SettingsService(currentUser!.academyId!);
});

/// Academy settings provider
final academySettingsProvider = FutureProvider<AcademySettings?>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return null;

  final service = SettingsService(currentUser!.academyId!);
  return await service.getAcademySettings();
});

/// Academy name provider
final academyNameProvider = FutureProvider<String>((ref) async {
  final settings = await ref.watch(academySettingsProvider.future);
  return settings?.name ?? 'Minha Academia';
});

/// PIX info provider
final pixInfoProvider = FutureProvider<Map<String, String?>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return {};

  final service = SettingsService(currentUser!.academyId!);
  return await service.getPixInfo();
});

// ============================================
// Plan Providers
// ============================================

/// Plan service provider
final planServiceProvider = Provider<PlanService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return PlanService(currentUser!.academyId!);
});

/// Active plans provider
final activePlansProvider = FutureProvider<List<Plan>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = PlanService(currentUser!.academyId!);
  return await service.getActive();
});

/// Student plan provider (legacy — returns first plan)
final studentPlanProvider = FutureProvider.family<Plan?, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return null;

  final service = PlanService(currentUser!.academyId!);
  return await service.getPlanForStudent(studentId);
});

/// Student plans provider (returns all plans for a student)
final studentPlansProvider = FutureProvider.family<List<Plan>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = PlanService(currentUser!.academyId!);
  return await service.getPlansForStudent(studentId);
});

/// Plan by ID provider
final planByIdProvider = FutureProvider.family<Plan?, String>((ref, planId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return null;

  final service = PlanService(currentUser!.academyId!);
  return await service.getById(planId);
});

// ============================================
// Belt Progression Providers
// ============================================

/// Belt progression service provider
final beltProgressionServiceProvider = Provider<BeltProgressionService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return BeltProgressionService(currentUser!.academyId!);
});

/// Belt eligibility provider
final beltEligibilityProvider = FutureProvider<EligibilityResult?>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  final student = await ref.watch(currentStudentProvider.future);

  if (currentUser?.academyId == null || student == null) return null;

  final service = BeltProgressionService(currentUser!.academyId!);
  return service.checkEligibility(
    currentBelt: student.currentBelt,
    currentStripes: student.currentStripes,
    totalClasses: student.totalAttendanceCount,
  );
});

/// Belt progress percentage provider
final beltProgressProvider = FutureProvider<double>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  final student = await ref.watch(currentStudentProvider.future);

  if (currentUser?.academyId == null || student == null) return 0.0;

  final service = BeltProgressionService(currentUser!.academyId!);
  return service.calculateProgress(
    currentBelt: student.currentBelt,
    currentStripes: student.currentStripes,
    totalClasses: student.totalAttendanceCount,
  );
});

// ============================================
// Notification Providers
// ============================================

/// Notification service provider
final notificationServiceProvider = Provider<NotificationService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return NotificationService(currentUser!.academyId!);
});

/// User notifications provider (Real-time Stream)
final userNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser == null || currentUser.academyId == null) {
    return Stream.value([]);
  }

  final service = NotificationService(currentUser.academyId!);
  return service.streamByUser(currentUser.id);
});

/// Unread notification count provider (Real-time Stream)
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser == null || currentUser.academyId == null) {
    return Stream.value(0);
  }

  final service = NotificationService(currentUser.academyId!);
  return service.streamUnreadCount(currentUser.id);
});

// ============================================
// Link Code Providers
// ============================================

/// Link code service provider
final linkCodeServiceProvider = Provider<LinkCodeService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return LinkCodeService(currentUser!.academyId!);
});

// ============================================
// Events Providers
// ============================================

/// Upcoming published events for the student portal home screen.
final upcomingEventsProvider = FutureProvider<List<AcademyEvent>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];
  return EventService(currentUser!.academyId!).listUpcoming(limit: 5);
});

