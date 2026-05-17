// Providers Riverpod de nível domínio para a migração graduabjj→Tatami.
//
// Estes providers consomem os *RemoteRepo de lib/api/repositories.dart e
// expõem o resultado de uma forma que telas/widgets podem consumir
// diretamente. Eles NÃO substituem ainda os providers legacy (currentUserProvider,
// studentsProvider, etc.) — telas só vão trocar para estes via PR de
// wiring específico, atrás da feature flag correspondente.
//
// A convenção é: cada provider lê a flag e, quando false, lança
// StateError. Isso garante que esquecer de checar a flag explode cedo
// no canary em vez de silenciosamente bater no BE de staging em prod.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/student.dart' as legacy;
import '../services/attendance_service.dart' as legacy_att;
import '../services/class_service.dart' show BJJClass;
import '../services/link_code_service.dart' show LinkCode;
import '../services/notification_service.dart' as legacy_notif;
import '../services/payment_service.dart' as legacy_pay;
import '../services/plan_service.dart' show Plan;
import 'dto/academy_dto.dart';
import 'dto/attendance_dto.dart';
import 'dto/competition_dto.dart';
import 'dto/financial_dto.dart';
import 'dto/identity_dto.dart';
import 'dto/notification_dto.dart';
import 'dto/store_dto.dart';
import 'dto/student_dto.dart';
import 'feature_flags.dart';
import 'repositories.dart';

class TatamiFlagDisabledError extends StateError {
  TatamiFlagDisabledError(String flag)
      : super('Tatami flag "$flag" is disabled. Toggle in Remote Config '
            'before consuming the corresponding *TatamiProvider.');
}

void _requireFlag(bool enabled, String flagName) {
  if (!enabled) throw TatamiFlagDisabledError(flagName);
}

// ---------------------------------------------------------------------------
// Identity (Sprint 1)
// ---------------------------------------------------------------------------

/// Carrega `/v1/me` quando a flag `useTatamiIdentity` está ligada.
/// Cacheado pela vida do provider — invalidar via `ref.invalidate(...)`
/// quando o usuário atualizar perfil.
final currentTatamiUserProvider =
    FutureProvider<CurrentUserResponse>((ref) async {
  _requireFlag(
    ref.watch(tatamiFlagsProvider).useTatamiIdentity,
    'useTatamiIdentity',
  );
  return ref.watch(identityRepoProvider).getMe();
});

// ---------------------------------------------------------------------------
// Student reads (Sprint 2)
// ---------------------------------------------------------------------------

/// Lista paginada de alunos para uma academia. `.family` aceita
/// (academyId, filter) como par.
///
/// Uso na tela:
/// ```dart
/// final asyncPage = ref.watch(tatamiStudentsProvider(
///   StudentsQuery(academyId: aid, filter: filter),
/// ));
/// ```
final tatamiStudentsProvider = FutureProvider.family<StudentsPage, StudentsQuery>(
  (ref, q) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiReads,
      'useTatamiReads',
    );
    return ref
        .watch(studentRepoProvider)
        .list(q.academyId, filter: q.filter);
  },
);

class StudentsQuery {
  const StudentsQuery({required this.academyId, this.filter = const StudentFilter()});

  final String academyId;
  final StudentFilter filter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudentsQuery &&
          other.academyId == academyId &&
          other.filter.status == filter.status &&
          other.filter.belt == filter.belt &&
          other.filter.category == filter.category &&
          other.filter.q == filter.q &&
          other.filter.sport == filter.sport &&
          other.filter.limit == filter.limit &&
          other.filter.cursor == filter.cursor);

  @override
  int get hashCode => Object.hash(
        academyId,
        filter.status,
        filter.belt,
        filter.category,
        filter.q,
        filter.sport,
        filter.limit,
        filter.cursor,
      );
}

/// KPIs do dashboard. Sprint 2.
final tatamiStudentStatsProvider =
    FutureProvider.family<ApiStudentStats, String>(
  (ref, academyId) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiReads,
      'useTatamiReads',
    );
    return ref.watch(studentRepoProvider).getStats(academyId);
  },
);

/// Eligibility de graduação por aluno. Sprint 2.
final tatamiStudentEligibilityProvider =
    FutureProvider.family<ApiEligibilityView, _StudentRef>(
  (ref, r) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiReads,
      'useTatamiReads',
    );
    return ref.watch(studentRepoProvider).getEligibility(r.academyId, r.studentId);
  },
);

/// Detalhe completo de um aluno (header + perfil). Sprint 2.
final tatamiStudentByIdProvider =
    FutureProvider.family<ApiStudent, _StudentRef>(
  (ref, r) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiReads,
      'useTatamiReads',
    );
    return ref.watch(studentRepoProvider).getById(r.academyId, r.studentId);
  },
);

/// Provider tipado **com modelo legacy** — telas que ainda usam Student
/// podem migrar para isto sem refatorar o widget tree inteiro. Adapta
/// ApiStudent → Student via Student.fromApi.
///
/// Quando `useTatamiReads` for ligada via Remote Config, screens que usem
/// este provider passam a ler do Tatami; quando desligada, lança
/// TatamiFlagDisabledError. Não há fallback automático aqui porque o
/// caller decide a estratégia (ex.: try { tatamiX } catch { legacyX }).
final tatamiStudentsLegacyProvider =
    FutureProvider.family<List<legacy.Student>, StudentsQuery>(
  (ref, q) async {
    final page = await ref.watch(tatamiStudentsProvider(q).future);
    return page.items.map(legacy.Student.fromApi).toList();
  },
);

/// Versão para getById que devolve o modelo legacy direto.
final tatamiStudentByIdLegacyProvider =
    FutureProvider.family<legacy.Student, StudentRef>(
  (ref, r) async {
    final api = await ref.watch(tatamiStudentByIdProvider(_StudentRef(
      r.academyId,
      r.studentId,
    )).future);
    return legacy.Student.fromApi(api);
  },
);

// ---------------------------------------------------------------------------
// Plan / Class / Settings / LinkCode (Sprint 3) — providers legacy-typed
// para screens migrarem incrementalmente. Toda chamada checa
// `useTatamiWrites` (mesma flag que reads pra esses contextos por
// simplicidade — o BE não distingue read/write na flag).
// ---------------------------------------------------------------------------

final tatamiPlansLegacyProvider = FutureProvider.family<List<Plan>, String>(
  (ref, academyId) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiWrites,
      'useTatamiWrites',
    );
    final list = await ref.watch(planRepoProvider).list(academyId);
    return list.map(Plan.fromApi).toList();
  },
);

class ClassesQuery {
  const ClassesQuery({
    required this.academyId,
    this.isActive,
    this.limit = 50,
    this.cursor,
  });
  final String academyId;
  final bool? isActive;
  final int limit;
  final String? cursor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClassesQuery &&
          other.academyId == academyId &&
          other.isActive == isActive &&
          other.limit == limit &&
          other.cursor == cursor);

  @override
  int get hashCode => Object.hash(academyId, isActive, limit, cursor);
}

final tatamiClassesLegacyProvider =
    FutureProvider.family<List<BJJClass>, ClassesQuery>(
  (ref, q) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiWrites,
      'useTatamiWrites',
    );
    final page = await ref.watch(classRepoProvider).list(
          q.academyId,
          limit: q.limit,
          cursor: q.cursor,
          isActive: q.isActive,
        );
    return page.items.map(BJJClass.fromApi).toList();
  },
);

/// Settings retornadas como `Map<String, ApiAcademySetting>` mesmo —
/// não há um "modelo legacy" estruturado (settings legacy é só um Map
/// de key/value).
final tatamiSettingsProvider =
    FutureProvider.family<Map<String, ApiAcademySetting>, String>(
  (ref, academyId) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiWrites,
      'useTatamiWrites',
    );
    return ref.watch(settingsRepoProvider).getAll(academyId);
  },
);

/// Redeem é uma ação one-shot, não um provider, mas o helper aqui
/// resolve flag check em um só lugar.
Future<RedeemLinkCodeResponse> redeemTatamiLinkCode(
  Ref ref,
  String code, {
  RedeemLinkCodeRequest profile = const RedeemLinkCodeRequest(),
}) async {
  _requireFlag(
    ref.read(tatamiFlagsProvider).useTatamiWrites,
    'useTatamiWrites',
  );
  return ref.read(linkCodeRepoProvider).redeem(code, profile: profile);
}

/// Geração de link code (admin) com mapeamento para modelo legacy.
Future<LinkCode> createTatamiStudentLinkCode(
  Ref ref,
  String academyId, {
  String? studentId,
  int? ttlSeconds,
}) async {
  _requireFlag(
    ref.read(tatamiFlagsProvider).useTatamiWrites,
    'useTatamiWrites',
  );
  final src = await ref.read(linkCodeRepoProvider).createForStudent(
        academyId,
        studentId: studentId,
        ttlSeconds: ttlSeconds,
      );
  return LinkCode.fromApi(src);
}

class _StudentRef {
  const _StudentRef(this.academyId, this.studentId);
  final String academyId;
  final String studentId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _StudentRef &&
          other.academyId == academyId &&
          other.studentId == studentId);

  @override
  int get hashCode => Object.hash(academyId, studentId);
}

/// Construtor público de _StudentRef. O record interno é mantido privado
/// para evitar criar 5 classes públicas de chave; um único factory function
/// resolve.
StudentRef studentRef(String academyId, String studentId) =>
    StudentRef._(academyId, studentId);

class StudentRef {
  const StudentRef._(this.academyId, this.studentId);
  final String academyId;
  final String studentId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudentRef &&
          other.academyId == academyId &&
          other.studentId == studentId);

  @override
  int get hashCode => Object.hash(academyId, studentId);
}

// ---------------------------------------------------------------------------
// Financial (Sprint 4) — fase 🔴, sempre via flag dedicada.
// ---------------------------------------------------------------------------

class FinancialsQuery {
  const FinancialsQuery({
    required this.academyId,
    this.filter = const FinancialFilter(),
  });

  final String academyId;
  final FinancialFilter filter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FinancialsQuery &&
          other.academyId == academyId &&
          other.filter.status == filter.status &&
          other.filter.studentId == filter.studentId &&
          other.filter.type == filter.type &&
          other.filter.dueFrom == filter.dueFrom &&
          other.filter.dueTo == filter.dueTo &&
          other.filter.limit == filter.limit &&
          other.filter.cursor == filter.cursor);

  @override
  int get hashCode => Object.hash(
        academyId,
        filter.status,
        filter.studentId,
        filter.type,
        filter.dueFrom,
        filter.dueTo,
        filter.limit,
        filter.cursor,
      );
}

final tatamiFinancialsProvider =
    FutureProvider.family<FinancialsPage, FinancialsQuery>(
  (ref, q) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiFinancials,
      'useTatamiFinancials',
    );
    return ref
        .watch(financialRepoProvider)
        .list(q.academyId, filter: q.filter);
  },
);

final tatamiMonthlyReportProvider =
    FutureProvider.family<ApiMonthlyReport, _AcademyMonth>(
  (ref, k) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiFinancials,
      'useTatamiFinancials',
    );
    return ref
        .watch(financialRepoProvider)
        .getMonthlyReport(k.academyId, month: k.month);
  },
);

class _AcademyMonth {
  const _AcademyMonth(this.academyId, this.month);
  final String academyId;
  final String? month;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _AcademyMonth &&
          other.academyId == academyId &&
          other.month == month);

  @override
  int get hashCode => Object.hash(academyId, month);
}

AcademyMonth academyMonth(String academyId, [String? month]) =>
    AcademyMonth._(academyId, month);

class AcademyMonth {
  const AcademyMonth._(this.academyId, this.month);
  final String academyId;
  final String? month;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AcademyMonth &&
          other.academyId == academyId &&
          other.month == month);

  @override
  int get hashCode => Object.hash(academyId, month);
}

final tatamiWalletProvider = FutureProvider.family<ApiWallet, String>(
  (ref, academyId) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiFinancials,
      'useTatamiFinancials',
    );
    return ref.watch(walletRepoProvider).get(academyId);
  },
);

/// Provider legacy-typed: `List<Payment>`. Permite que screens financeiras
/// migrem para Tatami trocando só o provider; o widget tree (StudentTile,
/// PaymentRow, etc.) continua consumindo o modelo Payment do legacy.
final tatamiPaymentsLegacyProvider =
    FutureProvider.family<List<legacy_pay.Payment>, FinancialsQuery>(
  (ref, q) async {
    final page = await ref.watch(tatamiFinancialsProvider(q).future);
    return page.items.map(legacy_pay.Payment.fromApi).toList();
  },
);

// ---------------------------------------------------------------------------
// Attendance (Sprint 5)
// ---------------------------------------------------------------------------

class AttendanceQuery {
  const AttendanceQuery({
    required this.academyId,
    this.filter = const AttendanceFilter(),
  });

  final String academyId;
  final AttendanceFilter filter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttendanceQuery &&
          other.academyId == academyId &&
          other.filter.studentId == filter.studentId &&
          other.filter.classId == filter.classId &&
          other.filter.dateFrom == filter.dateFrom &&
          other.filter.dateTo == filter.dateTo &&
          other.filter.limit == filter.limit &&
          other.filter.cursor == filter.cursor);

  @override
  int get hashCode => Object.hash(
        academyId,
        filter.studentId,
        filter.classId,
        filter.dateFrom,
        filter.dateTo,
        filter.limit,
        filter.cursor,
      );
}

final tatamiAttendanceProvider =
    FutureProvider.family<AttendancePage, AttendanceQuery>(
  (ref, q) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiAttendance,
      'useTatamiAttendance',
    );
    return ref
        .watch(attendanceRepoProvider)
        .list(q.academyId, filter: q.filter);
  },
);

/// Provider legacy-typed para o modelo Attendance. Screens não
/// precisam refatorar — só trocar `service.getByStudent()` por isso.
/// NOMES (studentName, className, verifiedByName) vêm vazios — caller
/// faz denorm local se precisar.
final tatamiAttendanceLegacyProvider =
    FutureProvider.family<List<legacy_att.Attendance>, AttendanceQuery>(
  (ref, q) async {
    final page = await ref.watch(tatamiAttendanceProvider(q).future);
    return page.items.map(legacy_att.Attendance.fromApi).toList();
  },
);

// ---------------------------------------------------------------------------
// Notification (Sprint 6)
// ---------------------------------------------------------------------------

final tatamiInboxProvider =
    FutureProvider.family<NotificationsPage, NotificationsFilter>(
  (ref, filter) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiNotifications,
      'useTatamiNotifications',
    );
    return ref.watch(notificationRepoProvider).list(filter: filter);
  },
);

/// Badge de notificações não-lidas. Lê o endpoint leve dedicado.
final tatamiUnreadCountProvider = FutureProvider.family<int, String?>(
  (ref, academyId) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiNotifications,
      'useTatamiNotifications',
    );
    return ref
        .watch(notificationRepoProvider)
        .getUnreadCount(academyId: academyId);
  },
);

/// Provider legacy-typed: `List<AppNotification>`. Screens consumem
/// AppNotification (do notification_service) e podem migrar trocando só
/// o provider source.
final tatamiInboxLegacyProvider =
    FutureProvider.family<List<legacy_notif.AppNotification>, NotificationsFilter>(
  (ref, filter) async {
    final page = await ref.watch(tatamiInboxProvider(filter).future);
    return page.items.map(legacy_notif.AppNotification.fromApi).toList();
  },
);

// ---------------------------------------------------------------------------
// Store (Sprint 7)
// ---------------------------------------------------------------------------

final tatamiProductsProvider = FutureProvider.family<ProductsPage, String>(
  (ref, academyId) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiStore,
      'useTatamiStore',
    );
    return ref.watch(storeRepoProvider).listProducts(academyId);
  },
);

class OrdersQuery {
  const OrdersQuery({
    required this.academyId,
    this.status,
    this.studentId,
    this.limit = 50,
    this.cursor,
  });

  final String academyId;
  final ApiOrderStatus? status;
  final String? studentId;
  final int limit;
  final String? cursor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrdersQuery &&
          other.academyId == academyId &&
          other.status == status &&
          other.studentId == studentId &&
          other.limit == limit &&
          other.cursor == cursor);

  @override
  int get hashCode =>
      Object.hash(academyId, status, studentId, limit, cursor);
}

final tatamiOrdersProvider = FutureProvider.family<OrdersPage, OrdersQuery>(
  (ref, q) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiStore,
      'useTatamiStore',
    );
    return ref.watch(storeRepoProvider).listOrders(
          q.academyId,
          status: q.status,
          studentId: q.studentId,
          limit: q.limit,
          cursor: q.cursor,
        );
  },
);

// ---------------------------------------------------------------------------
// Competition (Sprint 7)
// ---------------------------------------------------------------------------

final tatamiCompetitionsProvider =
    FutureProvider.family<CompetitionsPage, String>(
  (ref, academyId) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiCompetitions,
      'useTatamiCompetitions',
    );
    return ref.watch(competitionRepoProvider).list(academyId);
  },
);

final tatamiAchievementsProvider =
    FutureProvider.family<AchievementsPage, StudentRef>(
  (ref, r) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiCompetitions,
      'useTatamiCompetitions',
    );
    return ref
        .watch(competitionRepoProvider)
        .listAchievements(r.academyId, r.studentId);
  },
);
