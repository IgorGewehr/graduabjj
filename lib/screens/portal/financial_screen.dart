import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';

/// Financial Screen - Financeiro
class FinancialScreen extends ConsumerWidget {
  const FinancialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);
    final pixInfoAsync = ref.watch(pixInfoProvider);
    final planAsync = studentAsync.whenData(
      (s) => s != null ? ref.watch(studentPlanProvider(s.id)) : const AsyncValue.data(null),
    );

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildNoStudentState();
        }

        final paymentsAsync = ref.watch(studentPaymentsProvider(student.id));
        final statsAsync = ref.watch(studentPaymentStatsProvider(student.id));
        final pixInfo = pixInfoAsync.valueOrNull ?? {};
        final pixKey = pixInfo['key'] ?? '';
        final plan = planAsync.valueOrNull?.valueOrNull;

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(studentPaymentsProvider(student.id));
            ref.invalidate(studentPaymentStatsProvider(student.id));
            ref.invalidate(pixInfoProvider);
          },
          child: paymentsAsync.when(
            data: (payments) {
              final stats = statsAsync.valueOrNull ?? _defaultStats;
              final pendingCount = (stats['pending'] as Map?)?['count'] ?? 0;
              final pendingAmount = ((stats['pending'] as Map?)?['total'] ?? 0).toDouble();
              final overdueCount = (stats['overdue'] as Map?)?['count'] ?? 0;
              final overdueAmount = ((stats['overdue'] as Map?)?['total'] ?? 0).toDouble();
              final paidCount = (stats['paid'] as Map?)?['count'] ?? 0;
              final totalPaid = ((stats['paid'] as Map?)?['total'] ?? 0).toDouble();

              final hasDebts = pendingCount > 0 || overdueCount > 0;

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Text(
                      'Financeiro',
                      style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Acompanhe suas mensalidades e pagamentos',
                      style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                    ),

                    // Plan info
                    if (plan != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.infoLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.calendar, size: 14, color: AppTheme.info),
                            const SizedBox(width: 8),
                            Text(
                              'Plano: ${plan.name} - Vencimento: Dia ${plan.defaultDueDay}',
                              style: AppTheme.labelSmall.copyWith(
                                color: AppTheme.info,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Overdue Alert
                    if (overdueCount > 0) ...[
                      _OverdueAlert(
                        count: overdueCount,
                        amount: overdueAmount,
                        formatCurrency: _formatCurrency,
                        onCopyPix: () => _copyPixKey(context, pixKey),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Stats Cards
                    _StatsRow(
                      pendingCount: pendingCount,
                      pendingAmount: pendingAmount,
                      overdueCount: overdueCount,
                      overdueAmount: overdueAmount,
                      paidCount: paidCount,
                      totalPaid: totalPaid,
                      formatCurrency: _formatCurrency,
                    ),
                    const SizedBox(height: 24),

                    // Payment Info
                    if (hasDebts && pixKey.isNotEmpty) ...[
                      _PaymentInfoCard(
                        pixKey: pixKey,
                        onCopyPix: () => _copyPixKey(context, pixKey),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Payment History
                    Text(
                      'HISTORICO DE PAGAMENTOS',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (payments.isEmpty)
                      _buildEmptyState()
                    else
                      ...payments.map((payment) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PaymentCard(
                          payment: payment,
                          formatCurrency: _formatCurrency,
                        ),
                      )),

                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
            loading: () => _buildLoadingState(),
            error: (_, __) => _buildErrorState(),
          ),
        );
      },
      loading: () => _buildLoadingState(),
      error: (_, __) => _buildErrorState(),
    );
  }

  Map<String, dynamic> get _defaultStats => {
        'pending': {'count': 0, 'total': 0.0},
        'overdue': {'count': 0, 'total': 0.0},
        'paid': {'count': 0, 'total': 0.0},
      };

  String _formatCurrency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  void _copyPixKey(BuildContext context, String pixKey) {
    if (pixKey.isEmpty) return;
    Clipboard.setData(ClipboardData(text: pixKey));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chave PIX copiada!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildNoStudentState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.creditCard, size: 64, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Financeiro',
              style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Vincule sua conta a um aluno para ver o financeiro.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index < 2 ? 12 : 0),
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.alertCircle, size: 64, color: AppTheme.error),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar dados',
              style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Center(
        child: Text(
          'Nenhum pagamento registrado',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// Overdue Alert
class _OverdueAlert extends StatelessWidget {
  final int count;
  final double amount;
  final String Function(double) formatCurrency;
  final VoidCallback onCopyPix;

  const _OverdueAlert({
    required this.count,
    required this.amount,
    required this.formatCurrency,
    required this.onCopyPix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.alertCircle, size: 18, color: AppTheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voce tem $count pagamento${count > 1 ? 's' : ''} em atraso totalizando ${formatCurrency(amount)}.',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.error),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onCopyPix,
                  icon: const Icon(LucideIcons.copy, size: 14),
                  label: const Text('Copiar PIX'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

/// Stats Row
class _StatsRow extends StatelessWidget {
  final int pendingCount;
  final double pendingAmount;
  final int overdueCount;
  final double overdueAmount;
  final int paidCount;
  final double totalPaid;
  final String Function(double) formatCurrency;

  const _StatsRow({
    required this.pendingCount,
    required this.pendingAmount,
    required this.overdueCount,
    required this.overdueAmount,
    required this.paidCount,
    required this.totalPaid,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: LucideIcons.clock,
            iconColor: AppTheme.warning,
            iconBgColor: AppTheme.warningLight,
            value: formatCurrency(pendingAmount),
            label: 'Pendente ($pendingCount)',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: LucideIcons.alertCircle,
            iconColor: AppTheme.error,
            iconBgColor: AppTheme.errorLight,
            value: formatCurrency(overdueAmount),
            valueColor: overdueCount > 0 ? AppTheme.error : null,
            label: 'Em Atraso ($overdueCount)',
            hasBorder: overdueCount > 0,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: LucideIcons.checkCircle,
            iconColor: AppTheme.success,
            iconBgColor: AppTheme.successLight,
            value: formatCurrency(totalPaid),
            valueColor: AppTheme.success,
            label: 'Total Pago ($paidCount)',
          ),
        ),
      ],
    );
  }
}

/// Stat Card
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String value;
  final Color? valueColor;
  final String label;
  final bool hasBorder;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.value,
    this.valueColor,
    required this.label,
    this.hasBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasBorder ? AppTheme.error : AppTheme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppTheme.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Payment Info Card
class _PaymentInfoCard extends StatelessWidget {
  final String pixKey;
  final VoidCallback onCopyPix;

  const _PaymentInfoCard({
    required this.pixKey,
    required this.onCopyPix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.infoLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.info.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dados para Pagamento',
            style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(LucideIcons.creditCard, size: 18, color: AppTheme.info),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chave PIX',
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                    ),
                    Text(
                      pixKey,
                      style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onCopyPix,
                icon: const Icon(LucideIcons.copy, size: 14),
                label: const Text('Copiar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Apos o pagamento, envie o comprovante via WhatsApp para confirmar.',
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Payment Card
class _PaymentCard extends StatelessWidget {
  final Payment payment;
  final String Function(double) formatCurrency;

  const _PaymentCard({
    required this.payment,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = payment.status == PaymentStatus.overdue;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOverdue ? AppTheme.error : AppTheme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.description ?? 'Mensalidade',
                      style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (payment.referenceMonth != null)
                      Text(
                        'Ref: ${payment.referenceMonth}',
                        style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                      ),
                  ],
                ),
              ),
              _StatusChip(status: payment.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat("dd 'de' MMM 'de' yyyy", 'pt_BR').format(payment.dueDate),
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              ),
              Text(
                formatCurrency(payment.value),
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isOverdue ? AppTheme.error : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Status Chip
class _StatusChip extends StatelessWidget {
  final PaymentStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case PaymentStatus.paid:
        bgColor = AppTheme.successLight;
        textColor = AppTheme.success;
        label = 'Pago';
        break;
      case PaymentStatus.pending:
        bgColor = AppTheme.warningLight;
        textColor = AppTheme.warning;
        label = 'Pendente';
        break;
      case PaymentStatus.overdue:
        bgColor = AppTheme.errorLight;
        textColor = AppTheme.error;
        label = 'Atrasado';
        break;
      case PaymentStatus.cancelled:
        bgColor = AppTheme.surfaceVariant;
        textColor = AppTheme.textSecondary;
        label = 'Cancelado';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
