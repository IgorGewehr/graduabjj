import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/domain_providers.dart' as tatami;
import '../api/dto/attendance_dto.dart' as api_att;
import '../api/dto/financial_dto.dart' as api_fin;
import '../api/repositories.dart';
import '../models/student.dart';
import '../services/services.dart';
import 'auth_provider.dart';

/// Current student provider - fetches the student linked to the logged-in user.
///
/// Pós-Fase 1: Tatami é o único path. Caminho `getByLinkedUserId` (busca
/// quando não tem studentId direto) ainda usa Firestore — gap registrado
/// para BE (sem endpoint `/v1/students?linked_user_id=...`).
final currentStudentProvider = FutureProvider<Student?>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser == null) return null;

  // If user has a studentId, fetch the student via Tatami
  if (currentUser.studentId != null && currentUser.academyId != null) {
    try {
      return await ref.read(
        tatami.tatamiStudentByIdLegacyProvider(
          tatami.studentRef(currentUser.academyId!, currentUser.studentId!),
        ).future,
      );
    } catch (_) {
      return null;
    }
  }

  // Fallback by linkedUserId (Firestore-only — Tatami não tem o endpoint).
  if (currentUser.academyId != null) {
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
///
/// Migrado para Tatami (repo): usa `tatamiAttendanceLegacyProvider` com
/// `AttendanceFilter(studentId:, limit: 15)` — equivalente ao antigo
/// `getByStudentPaginated(limit: 15)`. O índice composto do Firestore não
/// é mais necessário; a REST API não tem esse problema.
final studentAttendanceProvider =
    FutureProvider.family<List<Attendance>, String>((ref, studentId) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return [];

      final academyId = currentUser!.academyId!;
      return await ref.watch(
        tatami.tatamiAttendanceLegacyProvider(
          tatami.AttendanceQuery(
            academyId: academyId,
            filter: api_att.AttendanceFilter(studentId: studentId, limit: 15),
          ),
        ).future,
      );
    });

/// Student attendance count provider
///
/// Sem endpoint de count no AttendanceRemoteRepo — mantém Firestore via
/// `AttendanceService.getStudentAttendanceCount()`. Gap registrado para BE
/// (endpoint `/v1/academies/{id}/attendance/count?studentId=...`).
final studentAttendanceCountProvider = FutureProvider.family<int, String>((
  ref,
  studentId,
) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return 0;

  final service = AttendanceService(currentUser!.academyId!);
  return await service.getStudentAttendanceCount(studentId);
});

/// Student achievements provider
///
/// Migrado para Tatami (repo): usa `achievementRepoProvider.getByStudent`.
/// `Achievement.fromApi` adapta `ApiAchievement` → modelo legado.
final studentAchievementsProvider =
    FutureProvider.family<List<Achievement>, String>((ref, studentId) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return [];

      final academyId = currentUser!.academyId!;
      final repo = ref.read(achievementRepoProvider);
      final page = await repo.getByStudent(academyId, studentId);
      return page.items.map((a) => Achievement.fromApiRepo(a)).toList();
    });

/// Student medal count provider
final studentMedalCountProvider =
    FutureProvider.family<Map<String, int>, String>((ref, studentId) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) {
        return {'gold': 0, 'silver': 0, 'bronze': 0, 'total': 0};
      }

      final service = AchievementService(currentUser!.academyId!);
      return await service.getMedalCount(studentId);
    });

/// Student timeline provider (achievements grouped by year)
final studentTimelineProvider =
    FutureProvider.family<Map<int, List<Achievement>>, String>((
      ref,
      studentId,
    ) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return {};

      final service = AchievementService(currentUser!.academyId!);
      return await service.getTimeline(studentId);
    });

/// Student payments provider.
///
/// Migrado para Tatami (repo): usa `tatamiPaymentsLegacyProvider` com
/// `FinancialFilter(studentId:, limit: 200)`. Substituiu o antigo
/// `PaymentService.streamByStudent` (Firestore real-time). O tipo de retorno
/// permanece `List<Payment>` para não quebrar o widget tree existente.
final studentPaymentsProvider =
    FutureProvider.family<List<Payment>, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return [];

  final academyId = currentUser!.academyId!;
  return ref.watch(
    tatami.tatamiPaymentsLegacyProvider(
      tatami.FinancialsQuery(
        academyId: academyId,
        filter: api_fin.FinancialFilter(studentId: studentId, limit: 200),
      ),
    ).future,
  );
});

/// Student payment stats provider.
///
/// Migrado para Tatami (repo): computa stats localmente a partir dos dados
/// retornados por `tatamiPaymentsLegacyProvider`. Substituiu o antigo
/// `PaymentService.streamStatsByStudent` (Firestore real-time).
final studentPaymentStatsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  studentId,
) async {
  final payments = await ref.watch(
    studentPaymentsProvider(studentId).future,
  );

  int pendingCount = 0;
  int overdueCount = 0;
  int paidCount = 0;
  double pendingTotal = 0;
  double overdueTotal = 0;
  double paidTotal = 0;

  for (final p in payments) {
    switch (p.status) {
      case PaymentStatus.pending:
        if (p.isOverdue) {
          overdueCount++;
          overdueTotal += p.value;
        } else {
          pendingCount++;
          pendingTotal += p.value;
        }
        break;
      case PaymentStatus.paid:
        paidCount++;
        paidTotal += p.value;
        break;
      case PaymentStatus.overdue:
        overdueCount++;
        overdueTotal += p.value;
        break;
      case PaymentStatus.cancelled:
        break;
    }
  }

  return {
    'pending': {'count': pendingCount, 'total': pendingTotal},
    'overdue': {'count': overdueCount, 'total': overdueTotal},
    'paid': {'count': paidCount, 'total': paidTotal},
  };
});

/// Student assessments provider
///
/// Migrado para Tatami (repo): usa `assessmentRepoProvider.getByStudent`.
/// `Assessment.fromApi` adapta `ApiAssessment` → modelo legado.
final studentAssessmentsProvider =
    FutureProvider.family<List<Assessment>, String>((ref, studentId) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return [];

      final academyId = currentUser!.academyId!;
      final repo = ref.read(assessmentRepoProvider);
      final page = await repo.getByStudent(academyId, studentId);
      return page.items.map(Assessment.fromApi).toList();
    });

/// Latest assessment provider
///
/// Migrado para Tatami (repo): usa `assessmentRepoProvider.getByStudent` com
/// `limit: 1` e retorna o primeiro item. Substituiu `AssessmentService.getLatest`
/// (Firestore).
final latestAssessmentProvider = FutureProvider.family<Assessment?, String>((
  ref,
  studentId,
) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return null;

  final academyId = currentUser!.academyId!;
  final repo = ref.read(assessmentRepoProvider);
  final page = await repo.getByStudent(academyId, studentId, limit: 1);
  if (page.items.isEmpty) return null;
  return Assessment.fromApi(page.items.first);
});

/// Assessment averages provider
///
/// Migrado para Tatami (repo): busca a lista completa via
/// `assessmentRepoProvider.getByStudent` e computa as médias por categoria
/// localmente (o tatami retorna scores em cada item). Substituiu
/// `AssessmentService.getAveragesByCategory` (Firestore).
final assessmentAveragesProvider =
    FutureProvider.family<Map<AssessmentCategory, double>, String>((
      ref,
      studentId,
    ) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      final emptyResult = {
        AssessmentCategory.respeito: 0.0,
        AssessmentCategory.disciplina: 0.0,
        AssessmentCategory.pontualidade: 0.0,
        AssessmentCategory.tecnica: 0.0,
        AssessmentCategory.esforco: 0.0,
      };

      if (currentUser?.academyId == null) return emptyResult;

      final academyId = currentUser!.academyId!;
      final repo = ref.read(assessmentRepoProvider);
      final page = await repo.getByStudent(academyId, studentId, limit: 100);

      if (page.items.isEmpty) return emptyResult;

      final totals = <AssessmentCategory, int>{};
      final counts = <AssessmentCategory, int>{};

      for (final item in page.items) {
        final s = item.scores;
        final entries = [
          (AssessmentCategory.respeito, s.respeito),
          (AssessmentCategory.disciplina, s.disciplina),
          (AssessmentCategory.pontualidade, s.pontualidade),
          (AssessmentCategory.tecnica, s.tecnica),
          (AssessmentCategory.esforco, s.esforco),
        ];
        for (final (cat, score) in entries) {
          totals[cat] = (totals[cat] ?? 0) + score;
          counts[cat] = (counts[cat] ?? 0) + 1;
        }
      }

      return {
        for (final cat in AssessmentCategory.values)
          cat: counts[cat] != null && counts[cat]! > 0
              ? totals[cat]! / counts[cat]!
              : 0.0,
      };
    });

/// Student attendance streak provider (consecutive training days)
///
/// `getStudentStreak` é lógica computada client-side em cima de uma lista
/// completa — sem endpoint de streak no AttendanceRemoteRepo. Mantém
/// Firestore via `AttendanceService`. Gap registrado para BE.
final studentStreakProvider = FutureProvider.family<int, String>((
  ref,
  studentId,
) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return 0;

  final service = AttendanceService(currentUser!.academyId!);
  return await service.getStudentStreak(studentId);
});

/// Student monthly attendance count provider
///
/// Migrado para Tatami (repo): usa `tatamiAttendanceLegacyProvider` com
/// filtros `dateFrom`/`dateTo` + `studentId`. Limite de 100 é suficiente
/// para um mês de treinos (máximo ~31 dias úteis). Se `hasMore` for true,
/// a contagem retorna o total de itens recebidos (conservativo).
final studentMonthlyAttendanceProvider = FutureProvider.family<int, String>((
  ref,
  studentId,
) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return 0;

  final academyId = currentUser!.academyId!;
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);

  final attendance = await ref.watch(
    tatami.tatamiAttendanceLegacyProvider(
      tatami.AttendanceQuery(
        academyId: academyId,
        filter: api_att.AttendanceFilter(
          studentId: studentId,
          dateFrom: startOfMonth,
          dateTo: now,
          limit: 100,
        ),
      ),
    ).future,
  );
  return attendance.length;
});

/// Next class for student provider
final studentNextClassProvider =
    FutureProvider.family<
      ({BJJClass? classInfo, ClassSchedule? schedule, DateTime? nextDate})?,
      String
    >((ref, studentId) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return null;

      final classService = ClassService(currentUser!.academyId!);
      final allClasses = await classService.list();

      // Filter classes where student is enrolled or classes have no restrictions
      final studentClasses = allClasses
          .where(
            (c) => c.studentIds.contains(studentId) || c.studentIds.isEmpty,
          )
          .toList();

      if (studentClasses.isEmpty) return null;

      final now = DateTime.now();
      final currentDayOfWeek = now.weekday % 7;
      final currentMinutes = now.hour * 60 + now.minute;

      // Find next class considering current time
      BJJClass? nextClass;
      ClassSchedule? nextSchedule;
      int daysUntilNext = 8; // More than a week
      int minutesDiff = 9999;

      for (final cls in studentClasses) {
        for (final schedule in cls.schedule) {
          final startParts = schedule.startTime
              .split(':')
              .map(int.parse)
              .toList();
          final startMinutes = startParts[0] * 60 + startParts[1];

          // Calculate days until this class
          int daysUntil = (schedule.dayOfWeek - currentDayOfWeek + 7) % 7;

          // If same day, check if class hasn't started yet
          if (daysUntil == 0) {
            if (startMinutes <= currentMinutes) {
              // Class already started or passed today, check next week
              daysUntil = 7;
            }
          }

          // Find the closest class
          if (daysUntil < daysUntilNext ||
              (daysUntil == daysUntilNext && startMinutes < minutesDiff)) {
            daysUntilNext = daysUntil;
            minutesDiff = startMinutes;
            nextClass = cls;
            nextSchedule = schedule;
          }
        }
      }

      if (nextClass == null || nextSchedule == null) return null;

      // Calculate the actual next date
      final nextDate = now.add(Duration(days: daysUntilNext));
      final nextDateTime = DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        int.parse(nextSchedule.startTime.split(':')[0]),
        int.parse(nextSchedule.startTime.split(':')[1]),
      );

      return (
        classInfo: nextClass,
        schedule: nextSchedule,
        nextDate: nextDateTime,
      );
    });
