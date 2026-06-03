import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../services/firebase_service.dart';
import '../../services/financial_report_service.dart';
import '../../widgets/polish/polish.dart';

/// Admin Financial Reports Screen
/// Displays comprehensive financial reports with KPIs, charts, and export
class AdminFinancialReportsScreen extends ConsumerStatefulWidget {
  const AdminFinancialReportsScreen({super.key});

  @override
  ConsumerState<AdminFinancialReportsScreen> createState() =>
      _AdminFinancialReportsScreenState();
}

class _AdminFinancialReportsScreenState
    extends ConsumerState<AdminFinancialReportsScreen> {
  // State
  DateTime _selectedMonth = DateTime.now();
  MonthlyReportData? _monthlyReport;
  List<MonthlyReportData> _historicalData = [];
  List<RevenueProjectionData> _projections = [];
  List<RevenueByPlanData> _revenueByPlan = [];
  List<FinancialRecommendationData> _recommendations = [];
  bool _isLoading = true;
  bool _isExporting = false;

  final _currencyFormat =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String get _monthKey {
    return DateFormat('yyyy-MM').format(_selectedMonth);
  }

  String get _monthDisplayName {
    final formatted = DateFormat('MMMM yyyy', 'pt_BR').format(_selectedMonth);
    return formatted[0].toUpperCase() + formatted.substring(1);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;
      final service = FinancialReportService(academyId);

      // Load all data from Firestore once
      await service.loadAll();

      // All methods below are now synchronous (use cached data)
      final historical = service.getHistoricalData(months: 6);
      final projections = service.projectRevenue(monthsAhead: 3);
      final revenueByPlan = service.getRevenueByPlan(_monthKey);

      // Get monthly report: check if it's in historical, otherwise generate
      final report = historical.firstWhere(
        (r) => r.month == _monthKey,
        orElse: () => service.generateMonthlyReport(_monthKey),
      );

      final recommendations =
          service.generateRecommendations(report, historical);

      setState(() {
        _monthlyReport = report;
        _historicalData = historical;
        _projections = projections;
        _revenueByPlan = revenueByPlan;
        _recommendations = recommendations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadData();
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadData();
  }

  Future<void> _exportCsv() async {
    setState(() => _isExporting = true);

    try {
      final service = FinancialReportService(FirebaseService.academyId);
      final csvString = service.exportCSV(_historicalData);

      // Copy CSV to clipboard
      await Clipboard.setData(ClipboardData(text: csvString));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Relatorio copiado para a area de transferencia!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Relatorio Financeiro'),
        actions: [
          IconButton(
            onPressed: _isExporting ? null : _exportCsv,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.download, size: 20),
            tooltip: 'Exportar CSV',
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Month Selector
                    _buildMonthSelector().fadeInQuick(),
                    const SizedBox(height: 16),

                    // KPI Cards
                    _buildKpiCards().entrance(index: 0),
                    const SizedBox(height: 20),

                    // Status Distribution
                    _buildStatusDistribution().entrance(index: 1),
                    const SizedBox(height: 20),

                    // Historical Data (simple chart)
                    _buildHistoricalSection().entrance(index: 2),
                    const SizedBox(height: 20),

                    // Revenue by Plan
                    _buildRevenueByPlan().entrance(index: 3),
                    const SizedBox(height: 20),

                    // Projections
                    if (_projections.isNotEmpty) ...[
                      _buildProjections().entrance(index: 4),
                      const SizedBox(height: 20),
                    ],

                    // Recommendations
                    if (_recommendations.isNotEmpty)
                      _buildRecommendations().entrance(index: 5),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: PolishSkeleton.shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _skeletonBox(width: 180, height: 24)),
            const SizedBox(height: 20),
            SizedBox(
              height: 100,
              child: Row(
                children: List.generate(
                  3,
                  (i) => Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 12 : 0),
                    child: _skeletonBox(width: 170, height: 100, radius: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: List.generate(
                3,
                (i) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    child: _skeletonBox(height: 90, radius: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _skeletonBox(height: 220, radius: 12),
          ],
        ),
      ),
    );
  }

  Widget _skeletonBox({
    double? width,
    required double height,
    double radius = 8,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  // ============================================
  // Month Selector
  // ============================================
  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: _previousMonth,
          icon: const Icon(LucideIcons.chevronLeft),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.surfaceVariant,
          ),
        ),
        const SizedBox(width: 16),
        Text(
          _monthDisplayName,
          style: AppTheme.headlineSmall,
        ),
        const SizedBox(width: 16),
        IconButton(
          onPressed: _nextMonth,
          icon: const Icon(LucideIcons.chevronRight),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.surfaceVariant,
          ),
        ),
      ],
    );
  }

  // ============================================
  // KPI Cards
  // ============================================
  Widget _buildKpiCards() {
    if (_monthlyReport == null) return const SizedBox.shrink();

    final report = _monthlyReport!;

    // Next month projection
    final nextMonthProjection =
        _projections.isNotEmpty ? _projections.first.projected : 0.0;

    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildKpiCard(
            icon: LucideIcons.dollarSign,
            label: 'Receita Confirmada',
            value: _currencyFormat.format(report.confirmedRevenue),
            color: AppTheme.success,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            icon: LucideIcons.percent,
            label: 'Taxa Cobranca',
            value: '${report.collectionRate.toStringAsFixed(1)}%',
            color: AppTheme.info,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            icon: report.growthMoM >= 0
                ? LucideIcons.trendingUp
                : LucideIcons.trendingDown,
            label: 'Crescimento MoM',
            value:
                '${report.growthMoM >= 0 ? '+' : ''}${report.growthMoM.toStringAsFixed(1)}%',
            color:
                report.growthMoM >= 0 ? AppTheme.success : AppTheme.error,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            icon: LucideIcons.target,
            label: 'Projecao Proximo Mes',
            value: _currencyFormat.format(nextMonthProjection),
            color: const Color(0xFF7C3AED), // Purple
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.labelSmall.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTheme.titleMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ============================================
  // Status Distribution
  // ============================================
  Widget _buildStatusDistribution() {
    if (_monthlyReport == null) return const SizedBox.shrink();

    final report = _monthlyReport!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Distribuicao por Status', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatusCard(
                label: 'Pago',
                amount: report.confirmedRevenue,
                count: report.paidCount,
                color: AppTheme.success,
                icon: LucideIcons.checkCircle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatusCard(
                label: 'Pendente',
                amount: report.pendingRevenue,
                count: report.pendingCount,
                color: AppTheme.warning,
                icon: LucideIcons.clock,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatusCard(
                label: 'Vencido',
                amount: report.overdueRevenue,
                count: report.overdueCount,
                color: AppTheme.error,
                icon: LucideIcons.alertCircle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard({
    required String label,
    required double amount,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: color),
          ),
          const SizedBox(height: 4),
          Text(
            _currencyFormat.format(amount),
            style: AppTheme.titleSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '$count pagamentos',
            style: AppTheme.labelSmall.copyWith(
              color: color.withOpacity(0.7),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // Historical Section
  // ============================================
  Widget _buildHistoricalSection() {
    if (_historicalData.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Historico de Receita', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Simple bar chart using containers
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _historicalData.map((data) {
                      final maxExpected = _historicalData
                          .map((d) => d.totalExpected)
                          .fold<double>(0, (a, b) => a > b ? a : b);
                      final barHeight = maxExpected > 0
                          ? (data.confirmedRevenue / maxExpected * 120)
                              .clamp(4.0, 120.0)
                          : 4.0;
                      final expectedHeight = maxExpected > 0
                          ? (data.totalExpected / maxExpected * 120)
                              .clamp(4.0, 120.0)
                          : 4.0;

                      final monthLabel = data.month.length >= 7
                          ? data.month.substring(5, 7)
                          : data.month;

                      return Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Expected bar (background)
                              Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Container(
                                    width: 24,
                                    height: expectedHeight,
                                    decoration: BoxDecoration(
                                      color: AppTheme.divider,
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                  ),
                                  Container(
                                    width: 24,
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      color: AppTheme.success,
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                monthLabel,
                                style: AppTheme.labelSmall
                                    .copyWith(fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Pago', style: AppTheme.labelSmall),
                    const SizedBox(width: 16),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Esperado', style: AppTheme.labelSmall),
                  ],
                ),

                const SizedBox(height: 12),

                // Table view of historical data
                ...List.generate(_historicalData.length, (index) {
                  final data = _historicalData[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            data.month,
                            style: AppTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _currencyFormat
                                .format(data.confirmedRevenue),
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _currencyFormat
                                .format(data.totalExpected),
                            style: AppTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: LinearProgressIndicator(
                            value: data.collectionRate / 100,
                            backgroundColor: AppTheme.divider,
                            color: data.collectionRate >= 80
                                ? AppTheme.success
                                : data.collectionRate >= 50
                                    ? AppTheme.warning
                                    : AppTheme.error,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // Revenue by Plan
  // ============================================
  Widget _buildRevenueByPlan() {
    if (_revenueByPlan.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Receita por Plano', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header row
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text('Plano',
                            style: AppTheme.labelMedium),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text('Alunos',
                            style: AppTheme.labelMedium,
                            textAlign: TextAlign.center),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('Receita',
                            style: AppTheme.labelMedium,
                            textAlign: TextAlign.right),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text('%',
                            style: AppTheme.labelMedium,
                            textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ...List.generate(_revenueByPlan.length, (index) {
                  final plan = _revenueByPlan[index];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            plan.planName,
                            style: AppTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${plan.studentCount}',
                            style: AppTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _currencyFormat
                                .format(plan.totalRevenue),
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${plan.percentage.toStringAsFixed(0)}%',
                            style: AppTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // Projections
  // ============================================
  Widget _buildProjections() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Projecoes', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _projections.map((projection) {
                final confidenceLabel = _confidenceLabel(
                    projection.confidence);
                final confidenceColor = _confidenceColor(
                    projection.confidence);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(LucideIcons.target,
                          size: 16,
                          color: const Color(0xFF7C3AED)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          projection.month,
                          style: AppTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        _currencyFormat
                            .format(projection.projected),
                        style: AppTheme.titleMedium.copyWith(
                          color: const Color(0xFF7C3AED),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: confidenceColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          confidenceLabel,
                          style: AppTheme.labelSmall.copyWith(
                            color: confidenceColor,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _confidenceLabel(String confidence) {
    switch (confidence) {
      case 'high':
        return 'Alta';
      case 'medium':
        return 'Media';
      case 'low':
        return 'Baixa';
      default:
        return confidence;
    }
  }

  Color _confidenceColor(String confidence) {
    switch (confidence) {
      case 'high':
        return AppTheme.success;
      case 'medium':
        return AppTheme.warning;
      case 'low':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  // ============================================
  // Recommendations
  // ============================================
  Widget _buildRecommendations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recomendacoes', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        ...List.generate(_recommendations.length, (index) {
          final rec = _recommendations[index];
          final color = _recommendationColor(rec.type);
          final icon = _recommendationIcon(rec.type);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colored left border
                Container(
                  width: 4,
                  height: 80,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 20, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                rec.title,
                                style: AppTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                rec.description,
                                style: AppTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _recommendationColor(String type) {
    switch (type) {
      case 'success':
        return AppTheme.success;
      case 'warning':
        return AppTheme.warning;
      case 'error':
        return AppTheme.error;
      case 'info':
        return AppTheme.info;
      default:
        return AppTheme.textSecondary;
    }
  }

  IconData _recommendationIcon(String type) {
    switch (type) {
      case 'success':
        return LucideIcons.checkCircle;
      case 'warning':
        return LucideIcons.alertTriangle;
      case 'error':
        return LucideIcons.alertCircle;
      case 'info':
        return LucideIcons.info;
      default:
        return LucideIcons.info;
    }
  }
}
