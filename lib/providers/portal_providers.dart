import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sports.dart';
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

// ============================================
// App Bootstrap (post-login gate)
// ============================================

/// Coarse state used by the router to decide between the splash and the
/// landed shell. The point is to surface a SINGLE, stable splash until the
/// whole session context (user + academy settings + linked student) is ready
/// — so the home never flashes before its data resolves.
enum AppBootstrapStatus { loading, unauthenticated, ready }

/// Aggregates every async dependency needed before the portal/admin shell can
/// render without a follow-up loading flicker.
///
/// Returns:
///   * [AppBootstrapStatus.unauthenticated] — no signed-in firebase user;
///   * [AppBootstrapStatus.loading]         — auth/user/settings/student still
///     resolving for the first time;
///   * [AppBootstrapStatus.ready]           — everything resolved.
///
/// IMPORTANT: This does NOT latch. Latching (so a transient re-fetch after the
/// user has already landed does not bounce them back to the splash) is handled
/// in the router redirect via [_LandingLatch], which is the only place that
/// knows whether the user is currently sitting on a post-login route.
final appBootstrapProvider = Provider<AppBootstrapStatus>((ref) {
  final auth = ref.watch(authStateProvider);

  // Still resolving the auth stream → loading.
  if (auth.isLoading) return AppBootstrapStatus.loading;
  if (auth.valueOrNull == null) return AppBootstrapStatus.unauthenticated;

  // Logged in: the user document must resolve first (it determines academy
  // context for the providers below).
  final userAsync = ref.watch(currentUserProvider);
  if (userAsync.isLoading) return AppBootstrapStatus.loading;
  final user = userAsync.valueOrNull;

  // Free users (no academy) have no academy-scoped context to wait on.
  if (user == null || user.academyId == null) {
    return AppBootstrapStatus.ready;
  }

  // Academy-scoped users: wait for settings AND the linked student so the
  // shell + home render fully populated on first paint.
  final settingsAsync = ref.watch(academySettingsProvider);
  if (settingsAsync.isLoading) return AppBootstrapStatus.loading;

  final studentAsync = ref.watch(currentStudentProvider);
  if (studentAsync.isLoading) return AppBootstrapStatus.loading;

  return AppBootstrapStatus.ready;
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

/// Per-sport eligibility for a student (sport-filtered count + per-belt
/// threshold + since-last-promotion baseline). Used by the portal progress
/// card to show one progress per sport the student trains.
final studentSportEligibilityProvider = FutureProvider.family<EligibilityResult?,
    ({String studentId, SportId sport})>((ref, args) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return null;
  final service = BeltProgressionService(currentUser!.academyId!);
  return service.checkEligibilityForStudent(
    args.studentId,
    sportId: args.sport,
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

/// All Jornal posts (drafts + published), newest-first, for the admin
/// management UI. Service already orders by startDate descending.
final journalAllProvider = FutureProvider<List<AcademyEvent>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];
  return EventService(currentUser!.academyId!).listAll();
});

/// Published posts (events, news, seminars) for the student-facing "Jornal da
/// Academia" feed, sorted by startDate DESCENDING (newest first).
final journalEventsProvider = FutureProvider<List<AcademyEvent>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];
  final posts = await EventService(currentUser!.academyId!).listPublished();
  posts.sort((a, b) => b.startDate.compareTo(a.startDate));
  return posts;
});

// ============================================
// Sport Selection (session / in-memory)
// ============================================

/// The sport currently selected on a given screen, keyed by [screenKey] so
/// each screen (e.g. graduation, attendance, portal home) keeps its own choice.
///
/// `null` means "not chosen yet" — consumers should fall back to the student's
/// primary sport (`student.getPrimarySport()`) on first build. This is session
/// state only (a [StateProvider] lives in memory): it survives rebuilds and
/// navigation within a session but is not persisted across app launches.
final selectedSportProvider =
    StateProvider.family<SportId?, String>((ref, screenKey) => null);

