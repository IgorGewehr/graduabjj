import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/repositories.dart';
import '../api/retention_repo.dart';
import '../services/retention_service.dart';
import 'selected_academy_provider.dart';

/// Data class holding all retention analysis results
class RetentionData {
  final List<StudentRiskScore> atRiskStudents;
  final RetentionMetrics metrics;
  final int totalStudents;

  RetentionData({
    required this.atRiskStudents,
    required this.metrics,
    required this.totalStudents,
  });
}

/// Retention service provider (pure computation, no academyId needed)
final retentionServiceProvider = Provider<RetentionService>((ref) {
  return RetentionService();
});

/// Combined retention data provider — busca risk scores via Tatami REST e
/// converte para [StudentRiskScore] (tipo legado consumido pelas telas).
///
/// Antes: download pesado de alunos + presenças + pagamentos do Firestore +
///        cálculo client-side via [RetentionService].
/// Agora: única chamada `GET /v1/academies/{id}/risk-scores` (server-side
///        materialized view) + mapeamento local para o tipo legado.
///
/// [RetentionService] ainda é instanciado para calcular [RetentionMetrics]
/// a partir da lista de risk scores — esse cálculo de agregação é local e
/// não requer dados extras.
final retentionDataProvider = FutureProvider<RetentionData>((ref) async {
  final academyId = ref.watch(safeAcademyIdProvider) ?? '';

  // Busca todos os risk scores do backend (materialized view server-side).
  final repo = ref.read(retentionRepoProvider);
  final apiScores = await repo.getRiskScores(academyId, limit: 200);

  // Mapeia ApiStudentRiskScore → StudentRiskScore (tipo legado das telas).
  final riskScores = apiScores.map(_fromApi).toList();

  // Computa métricas de agregação localmente a partir dos scores recebidos.
  final metrics = _computeMetrics(riskScores, apiScores.length);

  return RetentionData(
    atRiskStudents: riskScores,
    metrics: metrics,
    totalStudents: apiScores.length,
  );
});

// ---------------------------------------------------------------------------
// Mapeadores privados
// ---------------------------------------------------------------------------

/// Converte [ApiStudentRiskScore] → [StudentRiskScore] (tipo legado).
StudentRiskScore _fromApi(ApiStudentRiskScore a) {
  final level = _mapLevel(a.level);

  // Reconstrói os RiskFactors a partir dos sub-scores do backend.
  final factors = <RiskFactor>[
    RiskFactor(
      name: 'Queda de Frequencia',
      description:
          'Comparacao de presencas nos ultimos 15 dias vs 15 dias anteriores',
      weight: 40,
      score: a.scoreDrop,
      details:
          '${a.attendancesPrior15d} → ${a.attendancesLast15d} presencas (±15d)',
    ),
    RiskFactor(
      name: 'Inatividade',
      description: 'Dias desde a ultima presenca',
      weight: 30,
      score: a.scoreInactivity,
      details: '${a.daysSinceLastAttendance} dias sem treinar',
    ),
    RiskFactor(
      name: 'Pagamentos Atrasados',
      description: 'Quantidade de pagamentos em atraso',
      weight: 20,
      score: a.scoreOverdue,
      details: '${a.overduePaymentsCount} pagamento(s) atrasado(s)',
    ),
    RiskFactor(
      name: 'Tempo de Academia',
      description: 'Pontuacao baseada no tempo de matricula',
      weight: 10,
      score: a.scoreProgress,
      details: '${(a.daysSinceEnrollment / 30).round()} mes(es) matriculado',
    ),
  ];

  // attendanceTrend: variação % entre os dois períodos de 15 dias.
  final attendanceTrend = a.attendancesPrior15d > 0
      ? ((a.attendancesLast15d - a.attendancesPrior15d) /
              a.attendancesPrior15d) *
          100.0
      : (a.attendancesLast15d > 0 ? 100.0 : -100.0);

  return StudentRiskScore(
    studentId: a.studentId,
    studentName: a.fullName,
    score: a.riskScore,
    level: level,
    factors: factors,
    // Sem campo de data exata — aproximamos pela diferença de dias.
    lastAttendance: a.daysSinceLastAttendance > 0
        ? DateTime.now().subtract(Duration(days: a.daysSinceLastAttendance))
        : null,
    daysSinceLastAttendance: a.daysSinceLastAttendance,
    overduePayments: a.overduePaymentsCount,
    attendanceTrend: attendanceTrend,
    monthsAtAcademy: (a.daysSinceEnrollment / 30).round(),
  );
}

RiskLevel _mapLevel(ApiRiskLevel l) {
  switch (l) {
    case ApiRiskLevel.low:
      return RiskLevel.low;
    case ApiRiskLevel.medium:
      return RiskLevel.medium;
    case ApiRiskLevel.high:
      return RiskLevel.high;
    case ApiRiskLevel.critical:
      return RiskLevel.critical;
  }
}

/// Calcula [RetentionMetrics] a partir da lista já mapeada de
/// [StudentRiskScore] — sem precisar da lista completa de alunos.
RetentionMetrics _computeMetrics(
  List<StudentRiskScore> scores,
  int totalStudents,
) {
  final atRiskList = scores.where((s) => s.score >= 25).toList();
  final totalAtRisk = atRiskList.length;
  final atRiskPercentage =
      totalStudents > 0 ? (totalAtRisk / totalStudents) * 100.0 : 0.0;

  final compliantCount = scores.where((s) => s.overduePayments == 0).length;
  final paymentComplianceRate = totalStudents > 0
      ? (compliantCount / totalStudents) * 100.0
      : 100.0;

  final distributionByRisk = <RiskLevel, int>{
    RiskLevel.low: 0,
    RiskLevel.medium: 0,
    RiskLevel.high: 0,
    RiskLevel.critical: 0,
  };
  for (final s in scores) {
    distributionByRisk[s.level] = (distributionByRisk[s.level] ?? 0) + 1;
  }

  return RetentionMetrics(
    totalAtRisk: totalAtRisk,
    atRiskPercentage: atRiskPercentage,
    averageFrequency: 0.0, // Não disponível sem dados brutos de presença
    paymentComplianceRate: paymentComplianceRate,
    distributionByRisk: distributionByRisk,
  );
}
