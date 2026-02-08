import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'firebase_service.dart';

/// Monthly Report Data
class MonthlyReportData {
  final String month;
  final double confirmedRevenue;
  final double pendingRevenue;
  final double overdueRevenue;
  final double totalExpected;
  final double collectionRate;
  final double growthMoM;
  final int totalPayments;
  final int paidCount;
  final int pendingCount;
  final int overdueCount;

  MonthlyReportData({
    required this.month,
    required this.confirmedRevenue,
    required this.pendingRevenue,
    required this.overdueRevenue,
    required this.totalExpected,
    required this.collectionRate,
    required this.growthMoM,
    required this.totalPayments,
    required this.paidCount,
    required this.pendingCount,
    required this.overdueCount,
  });
}

/// Revenue Projection Data
class RevenueProjectionData {
  final String month;
  final double projected;
  final String confidence; // 'high', 'medium', 'low'
  final String basis;

  RevenueProjectionData({
    required this.month,
    required this.projected,
    required this.confidence,
    required this.basis,
  });
}

/// Revenue by Plan Data
class RevenueByPlanData {
  final String planId;
  final String planName;
  final int studentCount;
  final double totalRevenue;
  final double percentage;

  RevenueByPlanData({
    required this.planId,
    required this.planName,
    required this.studentCount,
    required this.totalRevenue,
    required this.percentage,
  });
}

/// Financial Recommendation Data
class FinancialRecommendationData {
  final String type; // 'success', 'warning', 'error', 'info'
  final String title;
  final String description;

  FinancialRecommendationData({
    required this.type,
    required this.title,
    required this.description,
  });
}

/// Financial Report Service - Multi-tenant financial reporting
class FinancialReportService {
  final String academyId;
  late final Collections _collections;

  // Cached data (populated by loadAll)
  Map<String, List<Map<String, dynamic>>>? _financialsByMonth;
  Map<String, String>? _planNames;

  FinancialReportService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _financialsRef => _collections.payments;
  CollectionReference get _plansRef => _collections.plans;

  /// Currency formatter for Brazilian Real
  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  final DateFormat _monthFormat = DateFormat('yyyy-MM');

  // ============================================
  // Load all data once (call before batch operations)
  // ============================================
  Future<void> loadAll() async {
    final results = await Future.wait([
      _financialsRef.get(),
      _plansRef.get(),
    ]);

    final financialsSnap = results[0];
    final plansSnap = results[1];

    // Build plan name map
    _planNames = {};
    for (final doc in plansSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      _planNames![doc.id] = data['name'] as String? ?? '';
    }

    // Group financials by effective month (excluding cancelled)
    _financialsByMonth = {};
    for (final doc in financialsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      if (status == 'cancelled') continue;

      final dueDate = data['dueDate'] is Timestamp
          ? (data['dueDate'] as Timestamp).toDate()
          : DateTime.now();

      // Derive month: use referenceMonth if present, otherwise derive from dueDate
      final refMonth = data['referenceMonth'] as String?;
      final effectiveMonth =
          (refMonth != null && refMonth.isNotEmpty) ? refMonth : _monthFormat.format(dueDate);

      final record = {
        'id': doc.id,
        'studentId': data['studentId'] ?? '',
        'studentName': data['studentName'] ?? '',
        'amount': (data['amount'] ?? data['value'] ?? 0).toDouble(),
        'dueDate': dueDate,
        'status': status,
        'paymentDate': data['paymentDate'] is Timestamp
            ? (data['paymentDate'] as Timestamp).toDate()
            : null,
        'method': data['method'],
        'referenceMonth': effectiveMonth,
        'planId': data['planId'],
        'description': data['description'],
      };

      _financialsByMonth!.putIfAbsent(effectiveMonth, () => []);
      _financialsByMonth![effectiveMonth]!.add(record);
    }
  }

  // ============================================
  // Helper: Get financials for a given month (from cache)
  // ============================================
  List<Map<String, dynamic>> _getFinancialsForMonth(String month) {
    return _financialsByMonth?[month] ?? [];
  }

  // ============================================
  // 1. Generate Monthly Report
  // ============================================
  MonthlyReportData generateMonthlyReport(String month, {String? prevMonth}) {
    final financials = _getFinancialsForMonth(month);

    double confirmedRevenue = 0;
    double pendingRevenue = 0;
    double overdueRevenue = 0;
    int paidCount = 0;
    int pendingCount = 0;
    int overdueCount = 0;

    for (final f in financials) {
      final status = f['status'] as String;
      final amount = (f['amount'] as num).toDouble();

      switch (status) {
        case 'paid':
          confirmedRevenue += amount;
          paidCount++;
          break;
        case 'pending':
          pendingRevenue += amount;
          pendingCount++;
          break;
        case 'overdue':
          overdueRevenue += amount;
          overdueCount++;
          break;
      }
    }

    final totalExpected = confirmedRevenue + pendingRevenue + overdueRevenue;
    final collectionRate =
        totalExpected > 0 ? (confirmedRevenue / totalExpected) * 100 : 0.0;

    // Calculate growth MoM by comparing with previous month
    final prevMonthStr = prevMonth ?? (() {
      final parts = month.split('-');
      final year = int.parse(parts[0]);
      final monthNum = int.parse(parts[1]);
      final prevDate = DateTime(year, monthNum - 1, 1);
      return '${prevDate.year}-${prevDate.month.toString().padLeft(2, '0')}';
    })();

    final prevFinancials = _getFinancialsForMonth(prevMonthStr);
    double prevConfirmedRevenue = 0;
    for (final f in prevFinancials) {
      if (f['status'] == 'paid') {
        prevConfirmedRevenue += (f['amount'] as num).toDouble();
      }
    }

    final growthMoM = prevConfirmedRevenue > 0
        ? ((confirmedRevenue - prevConfirmedRevenue) / prevConfirmedRevenue) *
            100
        : 0.0;

    return MonthlyReportData(
      month: month,
      confirmedRevenue: confirmedRevenue,
      pendingRevenue: pendingRevenue,
      overdueRevenue: overdueRevenue,
      totalExpected: totalExpected,
      collectionRate: collectionRate,
      growthMoM: growthMoM,
      totalPayments: financials.length,
      paidCount: paidCount,
      pendingCount: pendingCount,
      overdueCount: overdueCount,
    );
  }

  // ============================================
  // 2. Get Historical Data
  // ============================================
  List<MonthlyReportData> getHistoricalData({int months = 6}) {
    final now = DateTime.now();
    final reports = <MonthlyReportData>[];

    String? prevMonth;
    for (int i = months - 1; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      final month =
          '${date.year}-${date.month.toString().padLeft(2, '0')}';
      final report = generateMonthlyReport(month, prevMonth: prevMonth);
      reports.add(report);
      prevMonth = month;
    }

    return reports;
  }

  // ============================================
  // 3. Project Revenue
  // ============================================
  List<RevenueProjectionData> projectRevenue({int monthsAhead = 3}) {
    final historicalData = getHistoricalData(months: 6);
    final revenues = historicalData.map((r) => r.confirmedRevenue).toList();

    // Calculate simple moving average
    final sum = revenues.fold<double>(0, (acc, v) => acc + v);
    final movingAverage = revenues.isNotEmpty ? sum / revenues.length : 0.0;

    // Calculate trend using linear regression (least squares)
    final n = revenues.length;
    double trend = 0;

    if (n > 1) {
      double sumX = 0;
      double sumY = 0;
      double sumXY = 0;
      double sumX2 = 0;

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

    // Calculate standard deviation for confidence
    final mean = movingAverage;
    final variance = revenues.isNotEmpty
        ? revenues.fold<double>(0, (acc, v) => acc + pow(v - mean, 2)) /
            revenues.length
        : 0.0;
    final stdDev = sqrt(variance);
    final coefficientOfVariation = mean > 0 ? stdDev / mean : 1.0;

    String confidence;
    if (coefficientOfVariation < 0.1) {
      confidence = 'high';
    } else if (coefficientOfVariation < 0.25) {
      confidence = 'medium';
    } else {
      confidence = 'low';
    }

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

  // ============================================
  // 4. Get Revenue By Plan
  // ============================================
  List<RevenueByPlanData> getRevenueByPlan(String month) {
    final financials = _getFinancialsForMonth(month);

    final planMap = _planNames ?? {};

    // Group by planId
    final groupedRevenue = <String, double>{};
    final groupedStudents = <String, Set<String>>{};

    for (final f in financials) {
      final key = (f['planId'] as String?) ?? '__no_plan__';
      final amount = (f['amount'] as num).toDouble();
      final studentId = f['studentId'] as String;

      groupedRevenue[key] = (groupedRevenue[key] ?? 0) + amount;
      groupedStudents.putIfAbsent(key, () => <String>{});
      groupedStudents[key]!.add(studentId);
    }

    final grandTotal =
        groupedRevenue.values.fold<double>(0, (acc, v) => acc + v);

    final result = <RevenueByPlanData>[];

    groupedRevenue.forEach((key, totalRevenue) {
      final planName = key != '__no_plan__'
          ? (planMap[key] ?? 'Plano desconhecido')
          : 'Sem plano';
      result.add(RevenueByPlanData(
        planId: key,
        planName: planName,
        studentCount: groupedStudents[key]?.length ?? 0,
        totalRevenue: totalRevenue,
        percentage:
            grandTotal > 0 ? (totalRevenue / grandTotal) * 100 : 0,
      ));
    });

    // Sort by revenue descending
    result.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    return result;
  }

  // ============================================
  // 5. Generate Recommendations
  // ============================================
  List<FinancialRecommendationData> generateRecommendations(
    MonthlyReportData report,
    List<MonthlyReportData> historical,
  ) {
    final recommendations = <FinancialRecommendationData>[];

    // Low collection rate
    if (report.collectionRate < 70) {
      recommendations.add(FinancialRecommendationData(
        type: 'warning',
        title: 'Taxa de cobranca baixa',
        description:
            'A taxa de cobranca este mes esta em ${report.collectionRate.toStringAsFixed(1)}%. Considere revisar os processos de cobranca e comunicacao com os alunos inadimplentes.',
      ));
    }

    // Revenue decline
    if (report.growthMoM < -10) {
      recommendations.add(FinancialRecommendationData(
        type: 'warning',
        title: 'Queda na receita',
        description:
            'A receita caiu ${report.growthMoM.abs().toStringAsFixed(1)}% em relacao ao mes anterior. Verifique se houve cancelamentos ou aumento de inadimplencia.',
      ));
    }

    // Revenue growth
    if (report.growthMoM > 10) {
      recommendations.add(FinancialRecommendationData(
        type: 'success',
        title: 'Crescimento na receita',
        description:
            'A receita cresceu ${report.growthMoM.toStringAsFixed(1)}% em relacao ao mes anterior. Continue com as estrategias atuais!',
      ));
    }

    // High overdue
    if (report.overdueRevenue > report.confirmedRevenue * 0.3) {
      recommendations.add(FinancialRecommendationData(
        type: 'error',
        title: 'Alto volume de inadimplencia',
        description:
            'O valor vencido (${_currencyFormat.format(report.overdueRevenue)}) representa mais de 30% da receita confirmada. Priorize a recuperacao desses valores.',
      ));
    }

    // Collection rate improving month-over-month
    if (historical.length >= 2) {
      final lastTwo = historical.sublist(historical.length - 2);
      if (lastTwo[1].collectionRate > lastTwo[0].collectionRate &&
          lastTwo[1].collectionRate >= 70) {
        recommendations.add(FinancialRecommendationData(
          type: 'success',
          title: 'Taxa de cobranca melhorando',
          description:
              'A taxa de cobranca melhorou de ${lastTwo[0].collectionRate.toStringAsFixed(1)}% para ${lastTwo[1].collectionRate.toStringAsFixed(1)}%. O trabalho de cobranca esta dando resultado!',
        ));
      }
    }

    // Average ticket info
    final averageTicket = report.paidCount > 0
        ? report.confirmedRevenue / report.paidCount
        : 0.0;

    recommendations.add(FinancialRecommendationData(
      type: 'info',
      title: 'Ticket medio',
      description:
          'O ticket medio dos pagamentos confirmados este mes e de ${_currencyFormat.format(averageTicket)}. Acompanhe essa metrica para avaliar o valor percebido dos planos.',
    ));

    return recommendations;
  }

  // ============================================
  // 6. Export CSV
  // ============================================
  String exportCSV(List<MonthlyReportData> reports) {
    final headers = [
      'Mes',
      'Receita Confirmada',
      'Receita Pendente',
      'Receita Vencida',
      'Total Esperado',
      'Taxa Cobranca',
      'Crescimento MoM',
    ];

    final rows = reports.map((r) => [
          r.month,
          r.confirmedRevenue.toStringAsFixed(2),
          r.pendingRevenue.toStringAsFixed(2),
          r.overdueRevenue.toStringAsFixed(2),
          r.totalExpected.toStringAsFixed(2),
          r.collectionRate.toStringAsFixed(1),
          r.growthMoM.toStringAsFixed(1),
        ]);

    final csvContent = [
      headers.join(','),
      ...rows.map((row) => row.join(',')),
    ].join('\n');

    return csvContent;
  }
}

// ============================================
// Factory Function
// ============================================
FinancialReportService createFinancialReportService(String academyId) {
  return FinancialReportService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
FinancialReportService get financialReportService =>
    FinancialReportService(FirebaseService.academyId);
