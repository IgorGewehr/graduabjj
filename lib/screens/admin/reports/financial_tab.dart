import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../providers/portal_providers.dart';
import '../../../services/services.dart';
import 'shared_widgets.dart';

class FinancialTab extends ConsumerWidget {
  final double totalRevenue;
  final double totalPending;
  final double totalOverdue;
  final int paidPayments;
  final int pendingPayments;
  final int overduePayments;
  final double lastMonthRevenue;
  final double averageTicket;
  final double storeRevenue;
  final int storeOrderCount;
  final double storePending;
  final int storePendingCount;
  final MonthlyReportData? monthlyReport;
  final List<MonthlyReportData> historicalData;
  final List<RevenueProjectionData> projections;
  final List<RevenueByPlanData> revenueByPlan;
  final List<FinancialRecommendationData> recommendations;
  final bool isExporting;
  final VoidCallback onExportCsv;

  const FinancialTab({
    super.key,
    required this.totalRevenue,
    required this.totalPending,
    required this.totalOverdue,
    required this.paidPayments,
    required this.pendingPayments,
    required this.overduePayments,
    required this.lastMonthRevenue,
    required this.averageTicket,
    required this.storeRevenue,
    required this.storeOrderCount,
    required this.storePending,
    required this.storePendingCount,
    required this.monthlyReport,
    required this.historicalData,
    required this.projections,
    required this.revenueByPlan,
    required this.recommendations,
    required this.isExporting,
    required this.onExportCsv,
  });

  static final _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  String _formatCurrency(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(0);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tuitionTotal = totalRevenue + totalPending + totalOverdue;
    final tuitionRevenueRate =
        tuitionTotal > 0 ? totalRevenue / tuitionTotal : 0.0;
    final revenueChange = lastMonthRevenue > 0
        ? ((totalRevenue - lastMonthRevenue) / lastMonthRevenue * 100)
        : 0.0;
    final hasStore =
        storeRevenue > 0 || storeOrderCount > 0 || storePendingCount > 0;

    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final isStorePublished = settings?.storePublished ?? false;
    final showStore = hasStore || isStorePublished;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Export CSV button
          if (historicalData.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: isExporting ? null : onExportCsv,
                icon: isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.download, size: 16),
                label: const Text('Exportar CSV'),
              ),
            ),

          // =============================================
          // SECTION: Mensalidades
          // =============================================
          const SectionHeader(
            title: 'Mensalidades',
            icon: LucideIcons.creditCard,
          ),
          const SizedBox(height: 12),

          // KPI Cards (from FinancialReportService — tuition only)
          if (monthlyReport != null) ...[
            _buildKpiCards(),
            const SizedBox(height: 16),

            // Status Distribution
            _buildStatusDistribution(),
            const SizedBox(height: 16),
          ],

          // Main stat card - tuition only
          MainStatCard(
            title: 'Receita Mensalidades',
            value: 'R\$ ${_formatCurrency(totalRevenue)}',
            subtitle: '$paidPayments pagamentos recebidos',
            icon: LucideIcons.dollarSign,
            color: AppTheme.success,
            change: revenueChange,
            isPositive: revenueChange >= 0,
          ),
          const SizedBox(height: 16),

          // Tuition stats
          Row(
            children: [
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.clock,
                  label: 'Pendente',
                  value: 'R\$ ${_formatCurrency(totalPending)}',
                  subtitle: '$pendingPayments pagtos',
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.alertCircle,
                  label: 'Atrasado',
                  value: 'R\$ ${_formatCurrency(totalOverdue)}',
                  subtitle: '$overduePayments pagtos',
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.receipt,
                  label: 'Ticket Medio',
                  value: 'R\$ ${_formatCurrency(averageTicket)}',
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.percent,
                  label: 'Taxa Recebimento',
                  value: '${(tuitionRevenueRate * 100).toStringAsFixed(0)}%',
                  color: tuitionRevenueRate > 0.8
                      ? AppTheme.success
                      : (tuitionRevenueRate > 0.5
                            ? AppTheme.warning
                            : AppTheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tuition breakdown card
          ReportCard(
            title: 'Detalhamento',
            icon: LucideIcons.pieChart,
            badge: '$paidPayments recebidos',
            child: Column(
              children: [
                ProgressRow(
                  label: 'Recebido',
                  value: 'R\$ ${_formatCurrency(totalRevenue)}',
                  percentage: tuitionTotal > 0 ? totalRevenue / tuitionTotal : 0,
                  color: AppTheme.success,
                ),
                const SizedBox(height: 16),
                ProgressRow(
                  label: 'Pendente',
                  value: 'R\$ ${_formatCurrency(totalPending)}',
                  percentage: tuitionTotal > 0 ? totalPending / tuitionTotal : 0,
                  color: AppTheme.warning,
                ),
                const SizedBox(height: 16),
                ProgressRow(
                  label: 'Atrasado',
                  value: 'R\$ ${_formatCurrency(totalOverdue)}',
                  percentage: tuitionTotal > 0 ? totalOverdue / tuitionTotal : 0,
                  color: AppTheme.error,
                ),
              ],
            ),
          ),

          // =============================================
          // SECTION: Vendas da Loja
          // =============================================
          if (showStore) ...[
            const SizedBox(height: 32),
            const SectionHeader(
              title: 'Vendas da Loja',
              icon: LucideIcons.shoppingBag,
            ),
            const SizedBox(height: 12),

            if (hasStore) ...[
              // Store main stat
              MainStatCard(
                title: 'Receita da Loja',
                value: 'R\$ ${_formatCurrency(storeRevenue)}',
                subtitle: '$storeOrderCount pedidos pagos',
                icon: LucideIcons.shoppingBag,
                color: AppTheme.primary,
              ),
              const SizedBox(height: 16),

              if (storePendingCount > 0)
                Row(
                  children: [
                    Expanded(
                      child: MiniStatCard(
                        icon: LucideIcons.checkCircle,
                        label: 'Recebido',
                        value: 'R\$ ${_formatCurrency(storeRevenue)}',
                        subtitle: '$storeOrderCount pedidos',
                        color: AppTheme.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MiniStatCard(
                        icon: LucideIcons.clock,
                        label: 'Aguardando Pagto',
                        value: 'R\$ ${_formatCurrency(storePending)}',
                        subtitle: '$storePendingCount pedidos',
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
            ] else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.shoppingBag,
                      size: 32,
                      color: AppTheme.textSecondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nenhuma venda neste mes',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // =============================================
          // SECTION: Resumo Geral (only if store has data)
          // =============================================
          if (hasStore) ...[
            const SizedBox(height: 32),
            const SectionHeader(
              title: 'Resumo Geral',
              icon: LucideIcons.barChart3,
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.textPrimary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Recebido',
                        style: AppTheme.bodyMedium.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        'R\$ ${_formatCurrency(totalRevenue + storeRevenue)}',
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppTheme.success,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Mensalidades',
                            style: AppTheme.bodySmall.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'R\$ ${_formatCurrency(totalRevenue)}',
                        style: AppTheme.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Vendas da Loja',
                            style: AppTheme.bodySmall.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'R\$ ${_formatCurrency(storeRevenue)}',
                        style: AppTheme.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // =============================================
          // SECTION: Analise Avancada
          // =============================================
          if (historicalData.isNotEmpty ||
              revenueByPlan.isNotEmpty ||
              projections.isNotEmpty ||
              recommendations.isNotEmpty) ...[
            const SizedBox(height: 32),
            const SectionHeader(
              title: 'Analise Avancada',
              icon: LucideIcons.trendingUp,
            ),
            const SizedBox(height: 12),
          ],

          // Historical Revenue Section
          if (historicalData.isNotEmpty) ...[
            _buildHistoricalSection(),
            const SizedBox(height: 20),
          ],

          // Revenue by Plan
          if (revenueByPlan.isNotEmpty) ...[
            _buildRevenueByPlan(),
            const SizedBox(height: 20),
          ],

          // Projections
          if (projections.isNotEmpty) ...[
            _buildProjections(),
            const SizedBox(height: 20),
          ],

          // Recommendations
          if (recommendations.isNotEmpty) _buildRecommendations(),
        ],
      ),
    );
  }

  Widget _buildKpiCards() {
    if (monthlyReport == null) return const SizedBox.shrink();

    final report = monthlyReport!;
    final nextMonthProjection =
        projections.isNotEmpty ? projections.first.projected : 0.0;

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
            color: report.growthMoM >= 0 ? AppTheme.success : AppTheme.error,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            icon: LucideIcons.target,
            label: 'Projecao Proximo Mes',
            value: _currencyFormat.format(nextMonthProjection),
            color: const Color(0xFF7C3AED),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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

  Widget _buildStatusDistribution() {
    if (monthlyReport == null) return const SizedBox.shrink();

    final report = monthlyReport!;

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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(label, style: AppTheme.labelSmall.copyWith(color: color)),
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
              color: color.withValues(alpha: 0.7),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricalSection() {
    if (historicalData.isEmpty) return const SizedBox.shrink();

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
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: historicalData.map((data) {
                      final maxExpected = historicalData
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
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Container(
                                    width: 24,
                                    height: expectedHeight,
                                    decoration: BoxDecoration(
                                      color: AppTheme.divider,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  Container(
                                    width: 24,
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      color: AppTheme.success,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                monthLabel,
                                style: AppTheme.labelSmall.copyWith(
                                  fontSize: 9,
                                ),
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
                ...List.generate(historicalData.length, (index) {
                  final data = historicalData[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child:
                              Text(data.month, style: AppTheme.bodySmall),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _currencyFormat.format(data.confirmedRevenue),
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
                            _currencyFormat.format(data.totalExpected),
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

  Widget _buildRevenueByPlan() {
    if (revenueByPlan.isEmpty) return const SizedBox.shrink();

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
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text('Plano', style: AppTheme.labelMedium),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Alunos',
                          style: AppTheme.labelMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Receita',
                          style: AppTheme.labelMedium,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          '%',
                          style: AppTheme.labelMedium,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ...List.generate(revenueByPlan.length, (index) {
                  final plan = revenueByPlan[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
                            _currencyFormat.format(plan.totalRevenue),
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
              children: projections.map((projection) {
                final confidenceLabel =
                    _confidenceLabel(projection.confidence);
                final confidenceColor =
                    _confidenceColor(projection.confidence);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.target,
                        size: 16,
                        color: Color(0xFF7C3AED),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          projection.month,
                          style: AppTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        _currencyFormat.format(projection.projected),
                        style: AppTheme.titleMedium.copyWith(
                          color: const Color(0xFF7C3AED),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: confidenceColor.withValues(alpha: 0.1),
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

  Widget _buildRecommendations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recomendacoes', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        ...List.generate(recommendations.length, (index) {
          final rec = recommendations[index];
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rec.title, style: AppTheme.titleSmall),
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
}
