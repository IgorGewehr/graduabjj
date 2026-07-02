import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ranking_entry.dart';
import '../models/student.dart';
import '../services/services.dart';
import '../services/ranking_service.dart';
import '../services/training_log_service.dart';
import '../services/weekly_streak.dart';
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

/// Dependents (kids) whose responsible is the logged-in user. Lets a parent
/// who also trains (adult student) see their kids' charges and behavior.
final dependentsProvider =
    StreamProvider.autoDispose<List<Student>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  final academyId = user?.academyId;
  final uid = user?.id;
  if (academyId == null || uid == null) {
    yield <Student>[];
    return;
  }
  yield* StudentService(academyId).streamDependents(uid);
});

/// Student service provider
final studentServiceProvider = Provider<StudentService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;

  if (currentUser?.academyId == null) return null;

  return StudentService(currentUser!.academyId!);
});

/// Student attendance history provider
///
/// Sprint 5 — uses the paginated overload (`getByStudentPaginated`) for the
/// first page only. The portal screen displays a bounded "histórico recente"
/// of 15 rows, so loading the entire collection is wasteful. The exact total
/// count is still served by `studentAttendanceCountProvider` (separate query).
/// Falls back to the legacy unpaginated read on missing-index errors so an
/// older project without the composite index keeps working.
final studentAttendanceProvider =
    FutureProvider.family<List<Attendance>, String>((ref, studentId) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return [];

      final service = AttendanceService(currentUser!.academyId!);
      try {
        final page = await service.getByStudentPaginated(studentId, limit: 15);
        return page.items;
      } catch (_) {
        // Composite index missing? Fall back to client-side sorting.
        return await service.getByStudent(studentId, limit: 15);
      }
    });

/// Student attendance count provider
final studentAttendanceCountProvider = FutureProvider.family<int, String>((
  ref,
  studentId,
) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return 0;

  final service = AttendanceService(currentUser!.academyId!);
  return await service.getStudentAttendanceCount(studentId);
});

/// Per-sport attendance count provider (multi-sport students).
///
/// Unlike [studentAttendanceProvider] — which loads only the first page (15
/// rows) — this returns the TRUE total of attendance docs for the given sport
/// (legacy null == 'bjj'), so the "total" stat card stays accurate when a sport
/// filter is active. Keyed by `(studentId, sportValue)`.
final studentAttendanceCountBySportProvider =
    FutureProvider.family<int, (String, String)>((ref, key) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return 0;

      final service = AttendanceService(currentUser!.academyId!);
      return await service.getAttendanceCount(key.$1, sport: key.$2);
    });

/// Student achievements provider
final studentAchievementsProvider =
    FutureProvider.family<List<Achievement>, String>((ref, studentId) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return [];

      final service = AchievementService(currentUser!.academyId!);
      return await service.getByStudent(studentId);
    });

/// Graduações (belt progressions) do aluno — pro hub do lutador listar as
/// faixas conquistadas na linha de conquistas.
final studentBeltProgressionsProvider =
    FutureProvider.family<List<BeltProgression>, String>((ref, studentId) async {
      final currentUser = await ref.watch(currentUserProvider.future);
      if (currentUser?.academyId == null) return const [];
      return BeltProgressionService(currentUser!.academyId!)
          .getByStudent(studentId);
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

/// Student payments provider (Real-time Stream)
final studentPaymentsProvider = StreamProvider.family<List<Payment>, String>((
  ref,
  studentId,
) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;

  if (currentUser?.academyId == null) {
    return Stream.value([]);
  }

  final service = PaymentService(currentUser!.academyId!);
  return service.streamByStudent(studentId);
});

/// Student payment stats provider (Real-time Stream)
final studentPaymentStatsProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, studentId) {
      final currentUser = ref.watch(currentUserProvider).valueOrNull;

      if (currentUser?.academyId == null) {
        return Stream.value({
          'pending': {'count': 0, 'total': 0.0},
          'overdue': {'count': 0, 'total': 0.0},
          'paid': {'count': 0, 'total': 0.0},
        });
      }

      final service = PaymentService(currentUser!.academyId!);
      return service.streamStatsByStudent(studentId);
    });

/// Student assessments provider
final studentAssessmentsProvider =
    FutureProvider.family<List<Assessment>, String>((ref, studentId) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return [];

      final service = AssessmentService(currentUser!.academyId!);
      return await service.getByStudent(studentId);
    });

/// Physical (anthropometric) assessments of a student, most recent first.
/// Drives the portal "Minha Evolução" screen and its menu gate.
final studentPhysicalAssessmentsProvider =
    FutureProvider.family<List<PhysicalAssessment>, String>((
      ref,
      studentId,
    ) async {
      final currentUser = await ref.watch(currentUserProvider.future);

      if (currentUser?.academyId == null) return [];

      final service = PhysicalAssessmentService(currentUser!.academyId!);
      return await service.getByStudent(studentId);
    });

/// Latest assessment provider
final latestAssessmentProvider = FutureProvider.family<Assessment?, String>((
  ref,
  studentId,
) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return null;

  final service = AssessmentService(currentUser!.academyId!);
  return await service.getLatest(studentId);
});

/// Assessment averages provider
final assessmentAveragesProvider =
    FutureProvider.family<Map<AssessmentCategory, double>, String>((
      ref,
      studentId,
    ) async {
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

/// Student attendance streak provider (consecutive training days)
final studentStreakProvider = FutureProvider.family<int, String>((
  ref,
  studentId,
) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return 0;

  final service = AttendanceService(currentUser!.academyId!);
  return await service.getStudentStreak(studentId);
});

/// Feed de CONQUISTAS da academia (graduações, graus, medalhas, marcos) — usado
/// pelo segmento "Academia" da aba social (só conquistas, sem treino do dia).
final academyRecentAchievementsProvider =
    FutureProvider<List<Achievement>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return const [];
  final all = await AchievementService(currentUser!.academyId!).getRecent(limit: 40);
  const keep = {
    AchievementType.graduation,
    AchievementType.stripe,
    AchievementType.competition,
    AchievementType.milestone,
  };
  return all.where((a) => keep.contains(a.type)).take(12).toList();
});

/// Funde os DIAS-TREINADOS de um aluno: presença verificada (`attendance`) +
/// self-logs (`users/{uid}/training_logs`), deduplicando por DIA (dateOnly) via
/// Set. [uid] só é passado quando os self-logs são LEGÍVEIS (owner-scoped): o
/// dono só consegue ler os PRÓPRIOS logs, então para outros alunos [uid] é null
/// e a fusão usa apenas a presença. Filtro por [sport] (legado null == 'bjj').
Future<Set<DateTime>> _fusedTrainedDays({
  required String academyId,
  required String studentId,
  String? uid,
  String? sport,
}) async {
  final days = <DateTime>{};

  // Presença verificada (academy-scoped). Bound alto p/ um RECORDE fiel.
  final attendance = await AttendanceService(academyId)
      .getByStudent(studentId, limit: 2000, sport: sport);
  for (final a in attendance) {
    days.add(DateTime(a.date.year, a.date.month, a.date.day));
  }

  // Self-logs (owner-scoped). Só quando o uid é o do próprio dono.
  if (uid != null && uid.isNotEmpty) {
    final logs = await TrainingLogService(uid).recent(limit: 400);
    for (final l in logs) {
      if (sport != null && l.effectiveSport != sport) continue;
      days.add(DateTime(l.date.year, l.date.month, l.date.day));
    }
  }

  return days;
}

/// Streak SEMANAL rico pro dashboard do lutador: semanas atuais (com GRACE da
/// semana em curso) + recorde + strip das últimas ~8 semanas. FUNDE presença
/// verificada + self-logs (dedup por dia) e computa via [computeWeeklyStreak].
///
/// Global (todos os esportes) — casa com o comportamento anterior deste
/// provider. A variante POR ESPORTE é computada no `myShowcaseProvider`
/// (esporte principal) reusando a mesma função pura.
final studentStreakInfoProvider = FutureProvider.family<WeeklyStreakResult,
    String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) {
    return (currentWeeks: 0, recordWeeks: 0, weeks: const <WeekCell>[]);
  }

  // Self-logs são owner-scoped: só funde os do PRÓPRIO usuário. Se o studentId
  // não for o do aluno logado, uid=null (só presença — não dá pra ler logs
  // alheios de qualquer forma).
  final myStudent = await ref.watch(currentStudentProvider.future);
  final uid =
      (myStudent != null && myStudent.id == studentId) ? currentUser!.id : null;

  final days = await _fusedTrainedDays(
    academyId: currentUser!.academyId!,
    studentId: studentId,
    uid: uid,
  );
  return computeWeeklyStreak(trainedDays: days, now: DateTime.now());
});

/// Student monthly attendance count provider
final studentMonthlyAttendanceProvider = FutureProvider.family<int, String>((
  ref,
  studentId,
) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser?.academyId == null) return 0;

  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);

  final service = AttendanceService(currentUser!.academyId!);
  final attendance = await service.getByDateRange(
    startOfMonth,
    now,
    studentId: studentId,
  );
  return attendance.length;
});

/// Student's GERAL ranking position for the current month (A4 surfacing).
/// Null when unranked / no academy. Scope is academy-wide; the per-category
/// milestones are computed server-side separately.
final studentMonthlyRankProvider =
    FutureProvider.family<int?, String>((ref, studentId) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return null;
  final service = RankingService(currentUser!.academyId!);
  return service.getStudentRank(
    studentId: studentId,
    period: RankingPeriod.month,
  );
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
