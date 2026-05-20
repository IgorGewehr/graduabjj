import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/dto/financial_dto.dart';
import '../api/repositories.dart';
import '../services/financial_report_service.dart'; // retém os data-classes (MonthlyReportData etc.)
import 'selected_academy_provider.dart';

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Converte o objeto ApiMonthlyReport (vindo do Tatami) em MonthlyReportData,
/// que é o tipo que as screens já consomem.
///
/// O endpoint retorna `total_revenue` (pago) + `outstanding` (pending + overdue
/// combinados). Como não há como dividir outstanding sem iterar os individuais,
/// colocamos tudo em `pendingRevenue` e zero em `overdueRevenue` — compatível
/// com a convenção já adotada em `monthlyReportToLegacyMap` no domain_providers.
MonthlyReportData _buildMonthlyReportData(
  ApiMonthlyReport api,
  String month, {
  double prevConfirmedRevenue = 0.0,
}) {
  final confirmedRevenue = double.tryParse(api.totalRevenue) ?? 0.0;
  final outstanding = double.tryParse(api.outstanding) ?? 0.0;
  final pendingRevenue = outstanding;
  const overdueRevenue = 0.0;

  final totalExpected = confirmedRevenue + outstanding;
  final collectionRate =
      totalExpected > 0 ? (confirmedRevenue / totalExpected) * 100 : 0.0;

  final growthMoM = prevConfirmedRevenue > 0
      ? ((confirmedRevenue - prevConfirmedRevenue) / prevConfirmedRevenue) * 100
      : 0.0;

  final totalPayments = api.paidCount + api.pendingCount + api.overdueCount;

  return MonthlyReportData(
    month: month,
    confirmedRevenue: confirmedRevenue,
    pendingRevenue: pendingRevenue,
    overdueRevenue: overdueRevenue,
    totalExpected: totalExpected,
    collectionRate: collectionRate,
    growthMoM: growthMoM,
    totalPayments: totalPayments,
    paidCount: api.paidCount,
    pendingCount: api.pendingCount,
    overdueCount: api.overdueCount,
  );
}

/// Projeção de receita (regressão linear simples) — mantida client-side.
List<RevenueProjectionData> _computeProjections(
  List<MonthlyReportData> historicalData, {
  int monthsAhead = 3,
}) {
  final revenues = historicalData.map((r) => r.confirmedRevenue).toList();

  final sum = revenues.fold<double>(0, (acc, v) => acc + v);
  final movingAverage = revenues.isNotEmpty ? sum / revenues.length : 0.0;

  final n = revenues.length;
  double trend = 0;

  if (n > 1) {
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += revenues[i];
      sumXY += i * revenues[i];
      sumX2 += i * i;
    }
    final denominator = n * sumX2 - sumX * sumX;
    if (denominator != 0) {
      trend = (n * sumXY - sumX * sumY) / denominator;
    }
  }

  final variance = revenues.isNotEmpty
      ? revenues.fold<double>(
              0, (acc, v) => acc + pow(v - movingAverage, 2)) /
          revenues.length
      : 0.0;
  final stdDev = sqrt(variance);
  final cv = movingAverage > 0 ? stdDev / movingAverage : 1.0;
  final confidence =
      cv < 0.1 ? 'high' : (cv < 0.25 ? 'medium' : 'low');

  final projections = <RevenueProjectionData>[];
  final now = DateTime.now();

  for (int i = 1; i <= monthsAhead; i++) {
    final futureDate = DateTime(now.year, now.month + i, 1);
    final monthStr =
        '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}';
    final projected = max(0.0, movingAverage + trend * (n + i - 1));

    projections.add(RevenueProjectionData(
      month: monthStr,
      projected: (projected * 100).roundToDouble() / 100,
      confidence: confidence,
      basis: 'Media movel de $n meses com tendencia linear',
    ));
  }

  return projections;
}

/// Motor de recomendações — mantido client-side.
List<FinancialRecommendationData> _computeRecommendations(
  MonthlyReportData report,
  List<MonthlyReportData> historical,
) {
  final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final recommendations = <FinancialRecommendationData>[];

  if (report.collectionRate < 70) {
    recommendations.add(FinancialRecommendationData(
      type: 'warning',
      title: 'Taxa de cobranca baixa',
      description:
          'A taxa de cobranca este mes esta em '
          '${report.collectionRate.toStringAsFixed(1)}%. Considere revisar os '
          'processos de cobranca e comunicacao com os alunos inadimplentes.',
    ));
  }

  if (report.growthMoM < -10) {
    recommendations.add(FinancialRecommendationData(
      type: 'warning',
      title: 'Queda na receita',
      description:
          'A receita caiu ${report.growthMoM.abs().toStringAsFixed(1)}% em '
          'relacao ao mes anterior. Verifique se houve cancelamentos ou aumento '
          'de inadimplencia.',
    ));
  }

  if (report.growthMoM > 10) {
    recommendations.add(FinancialRecommendationData(
      type: 'success',
      title: 'Crescimento na receita',
      description:
          'A receita cresceu ${report.growthMoM.toStringAsFixed(1)}% em '
          'relacao ao mes anterior. Continue com as estrategias atuais!',
    ));
  }

  if (report.overdueRevenue > report.confirmedRevenue * 0.3) {
    recommendations.add(FinancialRecommendationData(
      type: 'error',
      title: 'Alto volume de inadimplencia',
      description:
          'O valor vencido (${fmt.format(report.overdueRevenue)}) representa '
          'mais de 30% da receita confirmada. Priorize a recuperacao desses '
          'valores.',
    ));
  }

  if (historical.length >= 2) {
    final lastTwo = historical.sublist(historical.length - 2);
    if (lastTwo[1].collectionRate > lastTwo[0].collectionRate &&
        lastTwo[1].collectionRate >= 70) {
      recommendations.add(FinancialRecommendationData(
        type: 'success',
        title: 'Taxa de cobranca melhorando',
        description:
            'A taxa de cobranca melhorou de '
            '${lastTwo[0].collectionRate.toStringAsFixed(1)}% para '
            '${lastTwo[1].collectionRate.toStringAsFixed(1)}%. O trabalho de '
            'cobranca esta dando resultado!',
      ));
    }
  }

  final averageTicket = report.paidCount > 0
      ? report.confirmedRevenue / report.paidCount
      : 0.0;

  recommendations.add(FinancialRecommendationData(
    type: 'info',
    title: 'Ticket medio',
    description:
        'O ticket medio dos pagamentos confirmados este mes e de '
        '${fmt.format(averageTicket)}. Acompanhe essa metrica para avaliar o '
        'valor percebido dos planos.',
  ));

  return recommendations;
}

String _billingTypeLabel(String wire) {
  switch (wire) {
    case 'monthly_tuition':
      return 'Mensalidade';
    case 'uniform':
      return 'Kimono';
    case 'seminar':
      return 'Seminario';
    case 'graduation':
      return 'Graduacao';
    case 'competition':
      return 'Competicao';
    default:
      return 'Outros';
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Selected month state
final selectedReportMonthProvider = StateProvider<String>((ref) {
  return DateFormat('yyyy-MM').format(DateTime.now());
});

/// Combined report data (loaded from Tatami)
class FinancialReportData {
  final List<MonthlyReportData> historicalData;
  final List<RevenueProjectionData> projections;

  FinancialReportData({
    required this.historicalData,
    required this.projections,
  });
}

/// Main data provider: fetches 6 months from Tatami concurrently, then
/// computes projections client-side (linear regression — mantida pré-migração).
final financialReportDataProvider =
    FutureProvider<FinancialReportData>((ref) async {
  final repo = ref.watch(financialRepoProvider);
  final academyId = ref.watch(safeAcademyIdProvider) ?? '';
  final now = DateTime.now();

  // Last 6 months in chronological order (oldest first)
  final months = List.generate(6, (i) {
    final d = DateTime(now.year, now.month - (5 - i), 1);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  });

  final apiReports = await Future.wait(
    months.map((m) => repo.getMonthlyReport(academyId, month: m)),
  );

  final historicalData = <MonthlyReportData>[];
  for (int i = 0; i < apiReports.length; i++) {
    final prevRevenue = i == 0
        ? 0.0
        : (double.tryParse(apiReports[i - 1].totalRevenue) ?? 0.0);
    historicalData.add(
      _buildMonthlyReportData(apiReports[i], months[i],
          prevConfirmedRevenue: prevRevenue),
    );
  }

  final projections = _computeProjections(historicalData, monthsAhead: 3);

  return FinancialReportData(
    historicalData: historicalData,
    projections: projections,
  );
});

/// Monthly report for selected month.
/// Checks the cached historical window first; fetches from Tatami on demand
/// if the selected month is outside the 6-month window.
final monthlyReportProvider = FutureProvider<MonthlyReportData>((ref) async {
  final data = await ref.watch(financialReportDataProvider.future);
  final month = ref.watch(selectedReportMonthProvider);

  final existing = data.historicalData.where((r) => r.month == month);
  if (existing.isNotEmpty) return existing.first;

  // On-demand fetch for months outside the cached window
  final repo = ref.watch(financialRepoProvider);
  final academyId = ref.watch(safeAcademyIdProvider) ?? '';
  final apiReport = await repo.getMonthlyReport(academyId, month: month);
  return _buildMonthlyReportData(apiReport, month);
});

/// Historical data (last 6 months)
final historicalDataProvider =
    FutureProvider<List<MonthlyReportData>>((ref) async {
  final data = await ref.watch(financialReportDataProvider.future);
  return data.historicalData;
});

/// Revenue projections (3 months ahead)
final revenueProjectionsProvider =
    FutureProvider<List<RevenueProjectionData>>((ref) async {
  final data = await ref.watch(financialReportDataProvider.future);
  return data.projections;
});

/// Revenue by plan for selected month — computed client-side from individual
/// financials fetched via Tatami (the monthly report endpoint does not break
/// down by billing type / plan).
final revenueByPlanProvider =
    FutureProvider<List<RevenueByPlanData>>((ref) async {
  // Warm the main cache first
  await ref.watch(financialReportDataProvider.future);

  final repo = ref.watch(financialRepoProvider);
  final academyId = ref.watch(safeAcademyIdProvider) ?? '';
  final month = ref.watch(selectedReportMonthProvider);

  final parts = month.split('-');
  final year = int.parse(parts[0]);
  final monthNum = int.parse(parts[1]);
  final nextMonthDate = DateTime(year, monthNum + 1, 1);

  final page = await repo.list(
    academyId,
    filter: FinancialFilter(
      dueFrom: DateTime(year, monthNum, 1),
      dueTo: nextMonthDate,
      limit: 500,
    ),
  );

  // Group by billing type (proxy for plan, since the API financial has no planId)
  final groupedRevenue = <String, double>{};
  final groupedStudents = <String, Set<String>>{};

  for (final f in page.items) {
    if (f.status == ApiFinancialStatus.cancelled) continue;
    final key = f.type.wire;
    final amount = double.tryParse(f.amount) ?? 0.0;

    groupedRevenue[key] = (groupedRevenue[key] ?? 0) + amount;
    groupedStudents.putIfAbsent(key, () => <String>{});
    groupedStudents[key]!.add(f.studentId);
  }

  final grandTotal =
      groupedRevenue.values.fold<double>(0, (acc, v) => acc + v);

  final result = groupedRevenue.entries.map((e) {
    return RevenueByPlanData(
      planId: e.key,
      planName: _billingTypeLabel(e.key),
      studentCount: groupedStudents[e.key]?.length ?? 0,
      totalRevenue: e.value,
      percentage: grandTotal > 0 ? (e.value / grandTotal) * 100 : 0,
    );
  }).toList()
    ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

  return result;
});

/// Recommendations (client-side, derived from monthly + historical data)
final financialRecommendationsProvider =
    FutureProvider<List<FinancialRecommendationData>>((ref) async {
  final report = await ref.watch(monthlyReportProvider.future);
  final historical = await ref.watch(historicalDataProvider.future);
  return _computeRecommendations(report, historical);
});
