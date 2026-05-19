import 'dto/student_dto.dart';
import 'tatami_client.dart';

// ignore_for_file: constant_identifier_names

/// Nível de risco de retenção — bucketed pelo backend.
///
/// Mapeamento de score:
///   - low: 0–24
///   - medium: 25–49
///   - high: 50–74
///   - critical: 75–100
enum ApiRiskLevel { low, medium, high, critical }

extension ApiRiskLevelX on ApiRiskLevel {
  String get wire => name;
  static ApiRiskLevel fromWire(String? value) {
    if (value == null) return ApiRiskLevel.low;
    for (final l in ApiRiskLevel.values) {
      if (l.name == value) return l;
    }
    return ApiRiskLevel.low;
  }
}

/// Score de risco de retenção de um aluno, computado server-side via
/// materialized view `mv_student_risk_scores`.
///
/// Sub-scores explicam o total:
///   - scoreDrop: queda de presença (últimos 15d vs 15d anteriores), máx 40
///   - scoreInactivity: dias desde última presença, máx 30
///   - scoreOverdue: pagamentos em atraso × 5, máx 20
///   - scoreProgress: idade de matrícula em meses, máx 10
class ApiStudentRiskScore {
  const ApiStudentRiskScore({
    required this.studentId,
    required this.academyId,
    required this.fullName,
    required this.status,
    required this.riskScore,
    required this.level,
    required this.attendancesLast15d,
    required this.attendancesPrior15d,
    required this.daysSinceLastAttendance,
    required this.overduePaymentsCount,
    required this.daysSinceEnrollment,
    required this.scoreDrop,
    required this.scoreInactivity,
    required this.scoreOverdue,
    required this.scoreProgress,
    required this.refreshedAt,
  });

  final String studentId;
  final String academyId;
  final String fullName;
  final String status;
  final int riskScore;
  final ApiRiskLevel level;
  final int attendancesLast15d;
  final int attendancesPrior15d;
  final int daysSinceLastAttendance;
  final int overduePaymentsCount;
  final int daysSinceEnrollment;
  final int scoreDrop;
  final int scoreInactivity;
  final int scoreOverdue;
  final int scoreProgress;
  final DateTime refreshedAt;

  factory ApiStudentRiskScore.fromJson(Map<String, dynamic> j) =>
      ApiStudentRiskScore(
        studentId: j['student_id'] as String,
        academyId: j['academy_id'] as String,
        fullName: j['full_name'] as String,
        status: j['status'] as String? ?? 'active',
        riskScore: (j['risk_score'] as num?)?.toInt() ?? 0,
        level: ApiRiskLevelX.fromWire(j['level'] as String?),
        attendancesLast15d: (j['attendances_last_15d'] as num?)?.toInt() ?? 0,
        attendancesPrior15d: (j['attendances_prior_15d'] as num?)?.toInt() ?? 0,
        daysSinceLastAttendance:
            (j['days_since_last_attendance'] as num?)?.toInt() ?? 0,
        overduePaymentsCount:
            (j['overdue_payments_count'] as num?)?.toInt() ?? 0,
        daysSinceEnrollment: (j['days_since_enrollment'] as num?)?.toInt() ?? 0,
        scoreDrop: (j['score_drop'] as num?)?.toInt() ?? 0,
        scoreInactivity: (j['score_inactivity'] as num?)?.toInt() ?? 0,
        scoreOverdue: (j['score_overdue'] as num?)?.toInt() ?? 0,
        scoreProgress: (j['score_progress'] as num?)?.toInt() ?? 0,
        refreshedAt: _parseDate(j['refreshed_at']) ?? DateTime.now(),
      );
}

/// Repositório remoto do contexto Retention (retenção de alunos).
///
/// Agrega dois endpoints de leitura usados pelo dashboard de retenção:
///   - risk scores de todos os alunos (materialized view server-side)
///   - estatísticas globais da academia (total, por status, por categoria,
///     por faixa)
///
/// Antes esses dados eram calculados client-side em Dart após downloads
/// pesados de Firestore. O backend agora serve ambos em uma única chamada
/// cada.
class RetentionRemoteRepo {
  RetentionRemoteRepo(this._api);

  final TatamiClient _api;

  /// `GET /v1/academies/{academyId}/risk-scores`
  ///
  /// Retorna a lista de alunos com score de risco calculado server-side.
  /// Filtrar por nível com [levels] (ex: `['high', 'critical']`); omitir
  /// retorna todos os buckets. [limit] é clampeado a [1, 200] pelo backend.
  Future<List<ApiStudentRiskScore>> getRiskScores(
    String academyId, {
    List<ApiRiskLevel>? levels,
    int limit = 50,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (levels != null && levels.isNotEmpty) {
      params['level'] = levels.map((l) => l.wire).join(',');
    }
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/risk-scores',
      queryParameters: params,
    );
    return (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ApiStudentRiskScore.fromJson)
        .toList();
  }

  /// `GET /v1/academies/{academyId}/stats`
  ///
  /// KPIs da academia: total de alunos, breakdowns por status, categoria e
  /// faixa. Substitui os N reads Firestore que o dashboard calculava em
  /// memória. [ApiStudentStats] está em `dto/student_dto.dart`.
  Future<ApiStudentStats> getAcademyStats(String academyId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/stats',
    );
    return ApiStudentStats.fromJson(json);
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
