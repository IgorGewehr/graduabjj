import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto/competition_dto.dart' show ApiTransportPreference;
import '../api/link_code_repo.dart';
import '../api/repositories.dart';
import '../services/services.dart';
import 'auth_provider.dart';
import 'student_provider.dart';

// ============================================
// Class Schedule Providers
// ============================================

/// All classes provider
final classesProvider = FutureProvider<List<BJJClass>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final page = await ref.read(classRepoProvider).list(currentUser!.academyId!);
  return page.items.map(BJJClass.fromApi).toList();
});

/// Today's classes provider
final todayClassesProvider = FutureProvider<List<BJJClass>>((ref) async {
  final allClasses = await ref.watch(classesProvider.future);
  final dayOfWeek = DateTime.now().weekday % 7;
  return allClasses
      .where((cls) => cls.schedule.any((s) => s.dayOfWeek == dayOfWeek))
      .toList();
});

/// Current class provider (class happening now or starting soon)
final currentClassProvider = FutureProvider<BJJClass?>((ref) async {
  final now = DateTime.now();
  final dayOfWeek = now.weekday % 7;
  final currentMinutes = now.hour * 60 + now.minute;

  final todayClasses = await ref.watch(todayClassesProvider.future);

  for (final cls in todayClasses) {
    for (final schedule in cls.schedule) {
      if (schedule.dayOfWeek != dayOfWeek) continue;

      final startParts = schedule.startTime.split(':').map(int.parse).toList();
      final endParts = schedule.endTime.split(':').map(int.parse).toList();
      final startMinutes = startParts[0] * 60 + startParts[1];
      final endMinutes = endParts[0] * 60 + endParts[1];

      // Check if within 30 min before start or during class
      if (currentMinutes >= startMinutes - 30 && currentMinutes <= endMinutes) {
        return cls;
      }
    }
  }

  return null;
});

/// Weekly schedule provider
final weeklyScheduleProvider = FutureProvider<Map<int, List<BJJClass>>>((ref) async {
  final allClasses = await ref.watch(classesProvider.future);

  final schedule = <int, List<BJJClass>>{
    0: [], // Sunday
    1: [], // Monday
    2: [], // Tuesday
    3: [], // Wednesday
    4: [], // Thursday
    5: [], // Friday
    6: [], // Saturday
  };

  for (final cls in allClasses) {
    for (final s in cls.schedule) {
      if (!schedule[s.dayOfWeek]!.any((c) => c.id == cls.id)) {
        schedule[s.dayOfWeek]!.add(cls);
      }
    }
  }

  // Sort each day by start time
  for (final day in schedule.keys) {
    schedule[day]!.sort((a, b) {
      final aTime = a.schedule.where((s) => s.dayOfWeek == day).firstOrNull?.startTime ?? '00:00';
      final bTime = b.schedule.where((s) => s.dayOfWeek == day).firstOrNull?.startTime ?? '00:00';
      return aTime.compareTo(bTime);
    });
  }

  return schedule;
});

// ============================================
// Competition Providers
// ============================================

/// Competition service provider — mantido para métodos sem equivalente Tatami
/// (getResultsForStudent, addResult, updateResult, deleteResult, getByStudent).
final competitionServiceProvider = Provider<CompetitionService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return CompetitionService(currentUser!.academyId!);
});

/// All competitions provider
final competitionsProvider = FutureProvider<List<Competition>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final page = await ref.read(competitionRepoProvider).list(currentUser!.academyId!);
  return page.items.map(Competition.fromApi).toList();
});

/// Upcoming competitions provider
final upcomingCompetitionsProvider = FutureProvider<List<Competition>>((ref) async {
  final competitions = await ref.watch(competitionsProvider.future);
  return competitions
      .where((c) => c.status == CompetitionStatus.upcoming)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
});

/// Student competition results provider (returns competitions where student participated)
/// NOTE: CompetitionRepo does not expose a getByStudent method — keeping service.
final studentCompetitionResultsProvider = FutureProvider.family<List<Competition>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = CompetitionService(currentUser!.academyId!);
  return await service.getByStudent(studentId);
});

/// Student results provider (returns all CompetitionResult for a student)
/// NOTE: CompetitionRepo only has listResults per-competition — keeping service.
final studentAllResultsProvider = FutureProvider.family<List<CompetitionResult>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final service = CompetitionService(currentUser!.academyId!);
  return await service.getResultsForStudent(studentId);
});

// ============================================
// Competition Enrollment Providers
// ============================================

/// Competition enrollment service provider — mantido para compatibilidade
/// com código legado que ainda não foi migrado.
final competitionEnrollmentServiceProvider = Provider<CompetitionEnrollmentService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return CompetitionEnrollmentService(currentUser!.academyId!);
});

/// Student enrollments provider — migrado para Tatami.
/// Usa GET /v1/academies/{id}/students/{sid}/enrollments (endpoint novo).
final studentEnrollmentsProvider = FutureProvider.family<List<CompetitionEnrollment>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) {
    return [];
  }

  if (studentId.isEmpty) {
    return [];
  }

  final apiEnrollments = await ref
      .read(competitionRepoProvider)
      .listStudentEnrollments(currentUser!.academyId!, studentId);

  return apiEnrollments.map((e) {
    final tp = switch (e.transportPreference) {
      ApiTransportPreference.need_transport => TransportPreference.needTransport,
      ApiTransportPreference.own_transport => TransportPreference.ownTransport,
      _ => TransportPreference.undecided,
    };
    return CompetitionEnrollment(
      id: e.id,
      competitionId: e.competitionId,
      studentId: e.studentId,
      studentName: e.studentId, // nome não retornado neste endpoint
      ageCategory: e.ageCategory,
      weightCategory: e.weightCategory,
      transportPreference: tp,
      enrolledAt: e.enrolledAt,
    );
  }).toList();
});

/// Check if student is enrolled in competition — via Tatami listEnrollments.
final isStudentEnrolledProvider = FutureProvider.family<bool, ({String competitionId, String studentId})>((ref, params) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return false;

  final page = await ref
      .read(competitionRepoProvider)
      .listEnrollments(currentUser!.academyId!, params.competitionId, limit: 200);
  return page.items.any((e) => e.studentId == params.studentId);
});

// ============================================
// Settings Providers
// ============================================

// TODO(tatami): remover settingsServiceProvider quando SettingsRepo.getAll()
//   expor campos tipados de AcademySettings (branding, PIX, toggles).
//   Hoje retorna Map<String,ApiAcademySetting> genérico — sem fábrica
//   AcademySettings.fromApi. Manter Firestore provisoriamente.
final settingsServiceProvider = Provider<SettingsService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return SettingsService(currentUser!.academyId!);
});

/// Academy settings provider
// TODO(tatami): migrar para settingsRepoProvider.getAll() quando tatami
//   expor GET /v1/academies/{id}/settings com campos tipados (name, logoUrl,
//   pixKey, etc.) mapeáveis para AcademySettings.fromApi. Blocker: o endpoint
//   atual devolve chave/valor genérico sem cobertura de todos os campos de
//   AcademySettings (branding, integrations, store, etc.).
final academySettingsProvider = FutureProvider<AcademySettings?>((ref) async {
  final service = ref.watch(settingsServiceProvider);
  if (service == null) return null;
  return service.getAcademySettings();
});

/// Academy name provider
final academyNameProvider = FutureProvider<String>((ref) async {
  final settings = await ref.watch(academySettingsProvider.future);
  return settings?.name ?? 'Minha Academia';
});

/// PIX info provider
// TODO(tatami): migrar para settingsRepoProvider.getAll() quando tatami
//   expor pix_key e pix_key_type nas settings de academia.
final pixInfoProvider = FutureProvider<Map<String, String?>>((ref) async {
  final service = ref.watch(settingsServiceProvider);
  if (service == null) return {};
  return service.getPixInfo();
});

// ============================================
// Plan Providers
// ============================================

/// Active plans provider
final activePlansProvider = FutureProvider<List<Plan>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final apiPlans = await ref.read(planRepoProvider).list(currentUser!.academyId!);
  return apiPlans
      .map(Plan.fromApi)
      .where((p) => p.isActive)
      .toList();
});

/// Student plan provider (legacy — returns first plan)
final studentPlanProvider = FutureProvider.family<Plan?, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return null;

  final apiPlans = await ref.read(planRepoProvider).list(currentUser!.academyId!);
  final plans = apiPlans.map(Plan.fromApi).toList();
  return plans.where((p) => p.studentIds.contains(studentId)).firstOrNull;
});

/// Student plans provider (returns all plans for a student)
final studentPlansProvider = FutureProvider.family<List<Plan>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return [];

  final apiPlans = await ref.read(planRepoProvider).list(currentUser!.academyId!);
  return apiPlans
      .map(Plan.fromApi)
      .where((p) => p.studentIds.contains(studentId))
      .toList();
});

/// Plan by ID provider
final planByIdProvider = FutureProvider.family<Plan?, String>((ref, planId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return null;

  final apiPlan = await ref.read(planRepoProvider).getById(currentUser!.academyId!, planId);
  return Plan.fromApi(apiPlan);
});

// ============================================
// Belt Progression Providers
// ============================================

/// Belt progression service provider — mantido para cálculos locais
/// (checkEligibility, calculateProgress) que são puramente computacionais.
final beltProgressionServiceProvider = Provider<BeltProgressionService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return BeltProgressionService(currentUser!.academyId!);
});

/// Belt eligibility provider — via Tatami graduation-eligibility endpoint.
final beltEligibilityProvider = FutureProvider<EligibilityResult?>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  final student = await ref.watch(currentStudentProvider.future);

  if (currentUser?.academyId == null || student == null) return null;

  try {
    final apiEligibility = await ref
        .read(beltProgressionRepoProvider)
        .getEligibility(currentUser!.academyId!, student.id);

    return EligibilityResult(
      eligible: apiEligibility.eligible,
      nextBelt: apiEligibility.nextBelt?.name, // wire == name for ApiBelt
      nextStripes: apiEligibility.nextStripes,
      currentClasses: apiEligibility.currentCount,
      requiredClasses: apiEligibility.requiredCount,
      missingClasses: apiEligibility.attendancesNeeded,
      message: apiEligibility.eligible
          ? (apiEligibility.nextStripes != null && apiEligibility.nextStripes! > 0
              ? 'Elegível para ${apiEligibility.nextStripes}º grau!'
              : 'Elegível para faixa!')
          : 'Faltam ${apiEligibility.attendancesNeeded} aulas',
    );
  } catch (_) {
    // Fallback para cálculo local se o endpoint falhar
    final service = BeltProgressionService(currentUser!.academyId!);
    return service.checkEligibility(
      currentBelt: student.currentBelt,
      currentStripes: student.currentStripes,
      totalClasses: student.totalAttendanceCount,
    );
  }
});

/// Belt progress percentage provider — cálculo local (sem I/O).
final beltProgressProvider = FutureProvider<double>((ref) async {
  final student = await ref.watch(currentStudentProvider.future);
  if (student == null) return 0.0;

  // Cálculo puramente local — não precisa de academyId nem de chamada remota.
  final service = BeltProgressionService('_local_');
  return service.calculateProgress(
    currentBelt: student.currentBelt,
    currentStripes: student.currentStripes,
    totalClasses: student.totalAttendanceCount,
  );
});

// ============================================
// Notification Providers
// ============================================

/// User notifications provider — SSE stream via Tatami.
///
/// Substitui o Firestore `.snapshots()` pelo endpoint
/// `GET /v1/me/notifications/stream`. Cada evento SSE pode carregar uma ou
/// mais notificações; o provider acumula a lista mais recente emitida pelo
/// servidor (o SSE envia snapshots, não deltas).
final userNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser == null) return Stream.value([]);

  return ref
      .read(notificationRepoProvider)
      .streamNotifications()
      .map((apiList) => apiList.map(AppNotification.fromApi).toList());
});

/// Unread notification count provider — polling a cada 30 s via Tatami.
///
/// O endpoint dedicado `GET /v1/me/notifications/unread-count` é leve e
/// evita leituras Firestore. O SSE stream não emite contagens separadas,
/// por isso usamos polling periódico.
final unreadNotificationCountProvider = StreamProvider<int>((ref) async* {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser == null) {
    yield 0;
    return;
  }

  while (true) {
    try {
      final count =
          await ref.read(notificationRepoProvider).getUnreadCount();
      yield count;
    } catch (_) {
      yield 0;
    }
    await Future.delayed(const Duration(seconds: 30));
  }
});

// ============================================
// Link Code Providers
// ============================================

/// Link code repo provider — acesso ao LinkCodeRemoteRepo (tatami).
///
/// Expõe createForStudent, createForInstructor, getPreview, redeem.
/// O serviço legado [LinkCodeService] (Firestore) não é mais necessário
/// neste escopo; as telas de auth usam este provider ou chamam o repo
/// diretamente via [linkCodeRepoProvider].
// ignore: unused_element — mantido para call-sites futuros.
final linkCodeProvider = Provider<LinkCodeRemoteRepo>(
  (ref) => ref.watch(linkCodeRepoProvider),
);

