import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';
import '../financial_reports_screen.dart';
import '../paying_students_screen.dart';
import 'financial_widgets.dart';

// ============================================
// Financial Reports Tab
// ============================================

class FinancialReportsTab extends StatelessWidget {
  final Map<String, dynamic>? monthlySummary;
  final DateTime selectedMonth;
  final List<Plan> plans;
  final List<Student> students;
  final String Function(double) formatCurrency;

  const FinancialReportsTab({
    super.key,
    required this.monthlySummary,
    required this.selectedMonth,
    required this.plans,
    required this.students,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final summary = monthlySummary ?? {};
    final totalPaid = (summary['paid']?['value'] ?? 0).toDouble();
    final totalExpected =
        (summary['totalExpected'] ?? 0).toDouble();
    final rate =
        totalExpected > 0 ? (totalPaid / totalExpected * 100) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick summary
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(LucideIcons.pieChart,
                          color: AppTheme.primary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resumo do Mês',
                            style: AppTheme.titleMedium
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            DateFormat("MMMM 'de' yyyy", 'pt_BR')
                                .format(selectedMonth)
                                .capitalize(),
                            style: AppTheme.bodySmall
                                .copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recebido',
                              style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(totalPaid),
                            style: AppTheme.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Esperado',
                              style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(totalExpected),
                            style: AppTheme.titleMedium
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Taxa',
                              style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(
                            '${rate.toStringAsFixed(0)}%',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: rate >= 70
                                  ? AppTheme.success
                                  : rate >= 40
                                      ? AppTheme.warning
                                      : AppTheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Detailed reports button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminFinancialReportsScreen(),
                ),
              ),
              icon: const Icon(LucideIcons.externalLink, size: 18),
              label: const Text('Ver Relatórios Detalhados'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quick info cards
          Text(
            'Insights Rápidos',
            style:
                AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          QuickInsightCard(
            icon: LucideIcons.users,
            title: 'Alunos Pagantes',
            value:
                '${plans.expand((p) => p.studentIds).toSet().length}',
            subtitle: 'com planos ativos',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PayingStudentsScreen(
                  students: students,
                  plans: plans,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          QuickInsightCard(
            icon: LucideIcons.package,
            title: 'Planos Ativos',
            value: '${plans.where((p) => p.isActive).length}',
            subtitle: 'de ${plans.length} total',
          ),
        ],
      ),
    );
  }
}
