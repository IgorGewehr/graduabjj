import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/financial_report_service.dart';
import '../services/firebase_service.dart';

/// Financial report service provider
final financialReportServiceProvider = Provider<FinancialReportService>((ref) {
  return FinancialReportService(FirebaseService.academyId);
});

/// Selected month state
final selectedReportMonthProvider = StateProvider<String>((ref) {
  return DateFormat('yyyy-MM').format(DateTime.now());
});

/// Combined report data (single Firestore fetch)
class FinancialReportData {
  final List<MonthlyReportData> historicalData;
  final List<RevenueProjectionData> projections;

  FinancialReportData({
    required this.historicalData,
    required this.projections,
  });
}

/// Main data provider: loads all data once, computes everything
final financialReportDataProvider = FutureProvider<FinancialReportData>((ref) async {
  final service = ref.watch(financialReportServiceProvider);
  await service.loadAll();
  final historicalData = service.getHistoricalData();
  final projections = service.projectRevenue();
  return FinancialReportData(
    historicalData: historicalData,
    projections: projections,
  );
});

/// Monthly report for selected month (derived from cached data)
final monthlyReportProvider = FutureProvider<MonthlyReportData>((ref) async {
  final data = await ref.watch(financialReportDataProvider.future);
  final month = ref.watch(selectedReportMonthProvider);
  final service = ref.watch(financialReportServiceProvider);

  // Check if it's in historical data first
  final existing = data.historicalData.where((r) => r.month == month);
  if (existing.isNotEmpty) return existing.first;

  // Otherwise generate from cached data
  return service.generateMonthlyReport(month);
});

/// Historical data (last 6 months)
final historicalDataProvider = FutureProvider<List<MonthlyReportData>>((ref) async {
  final data = await ref.watch(financialReportDataProvider.future);
  return data.historicalData;
});

/// Revenue projections (3 months ahead)
final revenueProjectionsProvider = FutureProvider<List<RevenueProjectionData>>((ref) async {
  final data = await ref.watch(financialReportDataProvider.future);
  return data.projections;
});

/// Revenue by plan for selected month (derived from cached data)
final revenueByPlanProvider = FutureProvider<List<RevenueByPlanData>>((ref) async {
  // Ensure data is loaded
  await ref.watch(financialReportDataProvider.future);
  final service = ref.watch(financialReportServiceProvider);
  final month = ref.watch(selectedReportMonthProvider);
  return service.getRevenueByPlan(month);
});

/// Recommendations
final financialRecommendationsProvider = FutureProvider<List<FinancialRecommendationData>>((ref) async {
  final report = await ref.watch(monthlyReportProvider.future);
  final historical = await ref.watch(historicalDataProvider.future);
  final service = ref.watch(financialReportServiceProvider);
  return service.generateRecommendations(report, historical);
});
