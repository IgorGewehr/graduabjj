import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/services.dart';
import '../../../models/student.dart';

// ============================================
// String extension
// ============================================

extension StringCapExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

// ============================================
// _StatCard - compact 3-column stat card
// ============================================

class FinancialStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;

  const FinancialStatCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: AppTheme.labelSmall
                .copyWith(color: AppTheme.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ============================================
// _InfoChip - used inside PlanCard
// ============================================

class FinancialInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const FinancialInfoChip({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ============================================
// _ClassesChip - used in create/edit plan dialogs
// ============================================

class FinancialClassesChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const FinancialClassesChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.textPrimary : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppTheme.bodySmall.copyWith(
            color: isSelected ? Colors.white : AppTheme.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ============================================
// _FilterChip - payment status filter chip
// ============================================

class FinancialFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const FinancialFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.textPrimary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected ? chipColor.withValues(alpha: 0.1) : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? chipColor : AppTheme.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTheme.labelSmall.copyWith(
                color: isSelected ? chipColor : AppTheme.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? chipColor : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Shared form field builder (used by plan dialogs)
// ============================================

Widget buildFinancialFormField(
  String label,
  TextEditingController controller,
  String hint, {
  TextInputType? keyboardType,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppTheme.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    ),
  );
}

// ============================================
// Handle bar (drag indicator) used in sheets
// ============================================

class SheetHandleBar extends StatelessWidget {
  const SheetHandleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ============================================
// _PlanCard
// ============================================

class PlanCard extends StatelessWidget {
  final Plan plan;
  final String Function(double) formatCurrency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManageStudents;

  const PlanCard({
    super.key,
    required this.plan,
    required this.formatCurrency,
    required this.onEdit,
    required this.onDelete,
    required this.onManageStudents,
  });

  @override
  Widget build(BuildContext context) {
    final expectedRevenue = plan.studentIds
        .fold(0.0, (sum, sid) => sum + plan.getStudentValue(sid));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style:
                      AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: plan.isActive
                      ? AppTheme.successLight
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plan.isActive ? 'Ativo' : 'Inativo',
                  style: AppTheme.labelSmall.copyWith(
                    color: plan.isActive
                        ? AppTheme.success
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEdit,
                child: const Icon(LucideIcons.pencil,
                    size: 18, color: AppTheme.textSecondary),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(LucideIcons.trash2,
                    size: 18, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Info chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FinancialInfoChip(
                icon: LucideIcons.dollarSign,
                label: formatCurrency(plan.monthlyValue),
              ),
              FinancialInfoChip(
                icon: LucideIcons.layoutGrid,
                label: plan.classesPerWeek == null
                    ? 'Ilimitado'
                    : '${plan.classesPerWeek}x/sem',
              ),
              FinancialInfoChip(
                icon: LucideIcons.users,
                label:
                    '${plan.studentCount} aluno${plan.studentCount != 1 ? 's' : ''}',
              ),
              if (plan.customValues.isNotEmpty)
                FinancialInfoChip(
                  icon: LucideIcons.tag,
                  label:
                      '${plan.customValues.length} c/ valor personalizado',
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Expected revenue
          Text(
            'Receita Esperada/Mes',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.success,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            formatCurrency(expectedRevenue),
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(height: 16),

          // Manage students button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onManageStudents,
              icon: const Icon(LucideIcons.users, size: 18),
              label: const Text('Gerenciar Alunos'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppTheme.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// _PaymentCard
// ============================================

class PaymentCard extends StatelessWidget {
  final Payment payment;
  final String Function(double) formatCurrency;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onSendReminder;
  final VoidCallback? onCancel;
  final VoidCallback? onReactivate;

  const PaymentCard({
    super.key,
    required this.payment,
    required this.formatCurrency,
    this.onMarkPaid,
    this.onSendReminder,
    this.onCancel,
    this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = payment.isOverdue;
    final isPaid = payment.status == PaymentStatus.paid;
    final isCancelled = payment.status == PaymentStatus.cancelled;

    return Opacity(
      opacity: isCancelled ? 0.6 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isOverdue
              ? AppTheme.error.withValues(alpha: 0.05)
              : isPaid
                  ? AppTheme.success.withValues(alpha: 0.05)
                  : isCancelled
                      ? AppTheme.surfaceVariant
                      : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOverdue
                ? AppTheme.error.withValues(alpha: 0.2)
                : isPaid
                    ? AppTheme.success.withValues(alpha: 0.2)
                    : AppTheme.divider,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? AppTheme.error.withValues(alpha: 0.1)
                        : isPaid
                            ? AppTheme.success.withValues(alpha: 0.1)
                            : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      payment.studentName.isNotEmpty
                          ? payment.studentName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: isOverdue
                            ? AppTheme.error
                            : isPaid
                                ? AppTheme.success
                                : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payment.studentName,
                        style: AppTheme.bodyMedium
                            .copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              payment.description ?? 'Mensalidade',
                              style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            width: 4,
                            height: 4,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 6),
                            decoration: const BoxDecoration(
                              color: AppTheme.textDisabled,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            'Venc: ${DateFormat('dd/MM').format(payment.dueDate)}',
                            style: AppTheme.labelSmall.copyWith(
                              color: isOverdue
                                  ? AppTheme.error
                                  : AppTheme.textSecondary,
                              fontWeight: isOverdue
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatCurrency(payment.value),
                      style: AppTheme.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color:
                            isPaid ? AppTheme.success : AppTheme.textPrimary,
                      ),
                    ),
                    if (isPaid)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Pago',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (isCancelled)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.textDisabled.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Cancelado',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textDisabled,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                // Menu de ações
                PopupMenuButton<String>(
                  icon: const Icon(LucideIcons.moreVertical, size: 20),
                  itemBuilder: (context) => [
                    if (!isPaid && !isCancelled)
                      const PopupMenuItem(
                        value: 'mark_paid',
                        child: Row(
                          children: [
                            Icon(LucideIcons.check, size: 16),
                            SizedBox(width: 8),
                            Text('Dar Baixa'),
                          ],
                        ),
                      ),
                    if (!isPaid && !isCancelled)
                      PopupMenuItem(
                        value: 'cancel',
                        child: Row(
                          children: [
                            Icon(LucideIcons.x,
                                size: 16, color: AppTheme.error),
                            const SizedBox(width: 8),
                            Text('Cancelar',
                                style: TextStyle(color: AppTheme.error)),
                          ],
                        ),
                      ),
                    if (isCancelled)
                      PopupMenuItem(
                        value: 'reactivate',
                        child: Row(
                          children: [
                            Icon(LucideIcons.rotateCcw,
                                size: 16, color: AppTheme.success),
                            const SizedBox(width: 8),
                            Text('Reativar',
                                style: TextStyle(color: AppTheme.success)),
                          ],
                        ),
                      ),
                    if (isPaid)
                      const PopupMenuItem(
                        value: 'none',
                        enabled: false,
                        child: Text('Sem ações disponíveis',
                            style:
                                TextStyle(color: AppTheme.textDisabled)),
                      ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'mark_paid':
                        onMarkPaid?.call();
                        break;
                      case 'cancel':
                        onCancel?.call();
                        break;
                      case 'reactivate':
                        onReactivate?.call();
                        break;
                    }
                  },
                ),
              ],
            ),
            if (onMarkPaid != null || onSendReminder != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onSendReminder != null)
                    TextButton.icon(
                      onPressed: onSendReminder,
                      icon: Icon(LucideIcons.messageSquare,
                          size: 16, color: AppTheme.textSecondary),
                      label: Text(
                        'Lembrar',
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                    ),
                  if (onMarkPaid != null) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: onMarkPaid,
                      icon: const Icon(LucideIcons.check, size: 16),
                      label: const Text('Confirmar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        textStyle: AppTheme.bodySmall
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================
// _QuickInsightCard - used in reports tab
// ============================================

class QuickInsightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  const QuickInsightCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.labelSmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                  Row(
                    children: [
                      Text(
                        value,
                        style: AppTheme.titleMedium
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        subtitle,
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(LucideIcons.chevronRight,
                  size: 18, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ============================================
// FinancialMonthSelector
// ============================================

class FinancialMonthSelector extends StatelessWidget {
  final DateTime selectedMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const FinancialMonthSelector({
    super.key,
    required this.selectedMonth,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final monthYear = DateFormat("MMM 'De' yyyy", 'pt_BR')
        .format(selectedMonth)
        .replaceFirst(
          DateFormat("MMM", 'pt_BR').format(selectedMonth),
          DateFormat("MMM", 'pt_BR').format(selectedMonth).capitalize(),
        );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: onPrev,
            child: const Icon(LucideIcons.chevronLeft,
                size: 24, color: AppTheme.textSecondary),
          ),
          Text(
            monthYear,
            style:
                AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          GestureDetector(
            onTap: onNext,
            child: const Icon(LucideIcons.chevronRight,
                size: 24, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ============================================
// FinancialStatsGrid
// ============================================

class FinancialStatsGrid extends StatelessWidget {
  final Map<String, dynamic>? monthlySummary;
  final String Function(double) formatCurrency;

  const FinancialStatsGrid({
    super.key,
    required this.monthlySummary,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final summary = monthlySummary ?? {};
    final totalPaid = (summary['paid']?['value'] ?? 0).toDouble();
    final totalPending = (summary['pending']?['value'] ?? 0).toDouble();
    final totalOverdue = (summary['overdue']?['value'] ?? 0).toDouble();
    final paidCount = summary['paid']?['count'] ?? 0;
    final pendingCount = summary['pending']?['count'] ?? 0;
    final overdueCount = summary['overdue']?['count'] ?? 0;
    final totalExpected = (summary['totalExpected'] ?? 0).toDouble();
    final rate =
        totalExpected > 0 ? (totalPaid / totalExpected * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FinancialStatCard(
                  icon: LucideIcons.checkCircle,
                  iconColor: AppTheme.success,
                  label: 'Recebido',
                  value: formatCurrency(totalPaid),
                  subtitle: '$paidCount pagos',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinancialStatCard(
                  icon: LucideIcons.clock,
                  iconColor: AppTheme.warning,
                  label: 'Pendente',
                  value: formatCurrency(totalPending),
                  subtitle: '$pendingCount pend.',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinancialStatCard(
                  icon: LucideIcons.alertTriangle,
                  iconColor: AppTheme.error,
                  label: 'Atrasado',
                  value: formatCurrency(totalOverdue),
                  subtitle: '$overdueCount atras.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.trendingUp,
                  size: 18,
                  color: rate >= 70
                      ? AppTheme.success
                      : rate >= 40
                          ? AppTheme.warning
                          : AppTheme.error,
                ),
                const SizedBox(width: 10),
                Text(
                  'Taxa: ${rate.toStringAsFixed(0)}%',
                  style: AppTheme.labelMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: rate / 100,
                      minHeight: 8,
                      backgroundColor: AppTheme.divider,
                      valueColor: AlwaysStoppedAnimation(
                        rate >= 70
                            ? AppTheme.success
                            : rate >= 40
                                ? AppTheme.warning
                                : AppTheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// FinancialTabBar
// ============================================

class FinancialTabBar extends StatelessWidget {
  final TabController tabController;
  final int pendingTotal;

  const FinancialTabBar({
    super.key,
    required this.tabController,
    required this.pendingTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      child: TabBar(
        controller: tabController,
        labelColor: AppTheme.textPrimary,
        unselectedLabelColor: AppTheme.textSecondary,
        labelStyle:
            AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTheme.labelMedium,
        indicatorColor: AppTheme.textPrimary,
        indicatorWeight: 2,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        tabs: [
          const Tab(text: 'Planos'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Pagamentos'),
                if (pendingTotal > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warning,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$pendingTotal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Tab(text: 'Relatórios'),
        ],
      ),
    );
  }
}

// ============================================
// _StudentToggleCard - used in ManageStudentsSheet
// ============================================

class StudentToggleCard extends StatelessWidget {
  final Student student;
  final bool isInPlan;
  final bool isLoading;
  final VoidCallback onTap;

  const StudentToggleCard({
    super.key,
    required this.student,
    required this.isInPlan,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isInPlan
              ? AppTheme.success.withValues(alpha: 0.05)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isInPlan ? AppTheme.success : AppTheme.divider,
            width: isInPlan ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Toggle indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isInPlan ? AppTheme.success : AppTheme.surfaceVariant,
                shape: BoxShape.circle,
                border: isInPlan
                    ? null
                    : Border.all(color: AppTheme.divider, width: 2),
              ),
              child: isInPlan
                  ? const Icon(
                      LucideIcons.check,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isInPlan
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  student.fullName[0].toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: isInPlan ? AppTheme.success : AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.nickname ?? student.fullName.split(' ').first,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color:
                          isInPlan ? AppTheme.success : AppTheme.textPrimary,
                    ),
                  ),
                  if (student.nickname != null)
                    Text(
                      student.fullName,
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Status text
            Text(
              isInPlan ? 'Vinculado' : 'Adicionar',
              style: AppTheme.labelSmall.copyWith(
                color:
                    isInPlan ? AppTheme.success : AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
