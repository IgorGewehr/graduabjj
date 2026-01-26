import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../services/abacate_pay_service.dart';

/// AbacatePay enabled provider
final abacatePayEnabledProvider = FutureProvider<bool>((ref) async {
  final academyId = FirebaseService.academyId;
  if (academyId == null) return false;

  final service = AbacatePayService(academyId);
  return service.isEnabled();
});

/// Financial Screen - Financeiro (Redesigned)
class FinancialScreen extends ConsumerStatefulWidget {
  const FinancialScreen({super.key});

  @override
  ConsumerState<FinancialScreen> createState() => _FinancialScreenState();
}

class _FinancialScreenState extends ConsumerState<FinancialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatCurrency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  void _copyPixKey(String pixKey) {
    if (pixKey.isEmpty) return;
    Clipboard.setData(ClipboardData(text: pixKey));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Chave PIX copiada!'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showPixPaymentDialog(Payment payment, String studentName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PixPaymentBottomSheet(
        payment: payment,
        studentName: studentName,
        formatCurrency: _formatCurrency,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentAsync = ref.watch(currentStudentProvider);
    final pixInfoAsync = ref.watch(pixInfoProvider);
    final abacatePayEnabled = ref.watch(abacatePayEnabledProvider).valueOrNull ?? false;

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildNoStudentState();
        }

        final paymentsAsync = ref.watch(studentPaymentsProvider(student.id));
        final statsAsync = ref.watch(studentPaymentStatsProvider(student.id));
        final pixInfo = pixInfoAsync.valueOrNull ?? {};
        final pixKey = pixInfo['key'] ?? '';

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(studentPaymentsProvider(student.id));
            ref.invalidate(studentPaymentStatsProvider(student.id));
            ref.invalidate(pixInfoProvider);
            ref.invalidate(abacatePayEnabledProvider);
          },
          child: paymentsAsync.when(
            data: (payments) {
              final stats = statsAsync.valueOrNull ?? _defaultStats;
              final pendingCount = (stats['pending'] as Map?)?['count'] ?? 0;
              final pendingAmount =
                  ((stats['pending'] as Map?)?['total'] ?? 0).toDouble();
              final overdueCount = (stats['overdue'] as Map?)?['count'] ?? 0;
              final overdueAmount =
                  ((stats['overdue'] as Map?)?['total'] ?? 0).toDouble();

              // Separate payments by status
              final pendingPayments = payments
                  .where((p) => p.status == PaymentStatus.pending)
                  .toList();
              final overduePayments = payments
                  .where((p) => p.status == PaymentStatus.overdue)
                  .toList();
              final historyPayments = payments
                  .where((p) =>
                      p.status == PaymentStatus.paid ||
                      p.status == PaymentStatus.cancelled)
                  .toList();

              final hasDebts = pendingCount > 0 || overdueCount > 0;

              return Column(
                children: [
                  // Fixed header section
                  Container(
                    color: AppTheme.background,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Summary Cards
                              Row(
                                children: [
                                  Expanded(
                                    child: _SummaryCard(
                                      icon: LucideIcons.clock,
                                      iconColor: AppTheme.warning,
                                      label: 'Pendentes',
                                      count: pendingCount,
                                      amount: pendingAmount,
                                      formatCurrency: _formatCurrency,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _SummaryCard(
                                      icon: LucideIcons.alertTriangle,
                                      iconColor: AppTheme.error,
                                      label: 'Em Atraso',
                                      count: overdueCount,
                                      amount: overdueAmount,
                                      formatCurrency: _formatCurrency,
                                      isAlert: overdueCount > 0,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // PIX Info (when has debts)
                              if (hasDebts && pixKey.isNotEmpty)
                                _PixCard(
                                  pixKey: pixKey,
                                  onCopy: () => _copyPixKey(pixKey),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Tab Bar
                        Container(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom:
                                  BorderSide(color: AppTheme.divider, width: 1),
                            ),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            labelColor: AppTheme.textPrimary,
                            unselectedLabelColor: AppTheme.textSecondary,
                            labelStyle: AppTheme.labelMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            unselectedLabelStyle: AppTheme.labelMedium,
                            indicatorColor: AppTheme.textPrimary,
                            indicatorWeight: 2,
                            tabs: [
                              Tab(
                                text: pendingCount > 0
                                    ? 'Pendentes ($pendingCount)'
                                    : 'Pendentes',
                              ),
                              Tab(
                                text: overdueCount > 0
                                    ? 'Em Atraso ($overdueCount)'
                                    : 'Em Atraso',
                              ),
                              Tab(
                                text: historyPayments.isNotEmpty
                                    ? 'Historico (${historyPayments.length})'
                                    : 'Historico',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab Content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Pendentes Tab
                        _PaymentsList(
                          payments: pendingPayments,
                          emptyIcon: LucideIcons.checkCircle,
                          emptyTitle: 'Nenhum pagamento pendente',
                          emptySubtitle: 'Voce esta em dia!',
                          formatCurrency: _formatCurrency,
                          abacatePayEnabled: abacatePayEnabled,
                          onPayPix: (payment) => _showPixPaymentDialog(
                            payment,
                            student.fullName ?? student.nickname ?? 'Aluno',
                          ),
                        ),

                        // Em Atraso Tab
                        _PaymentsList(
                          payments: overduePayments,
                          emptyIcon: LucideIcons.partyPopper,
                          emptyTitle: 'Nenhum pagamento atrasado',
                          emptySubtitle: 'Continue assim!',
                          formatCurrency: _formatCurrency,
                          abacatePayEnabled: abacatePayEnabled,
                          onPayPix: (payment) => _showPixPaymentDialog(
                            payment,
                            student.fullName ?? student.nickname ?? 'Aluno',
                          ),
                        ),

                        // Historico Tab
                        _PaymentsList(
                          payments: historyPayments,
                          emptyIcon: LucideIcons.history,
                          emptyTitle: 'Nenhum historico',
                          emptySubtitle: 'Seus pagamentos aparecerao aqui',
                          formatCurrency: _formatCurrency,
                          showStatus: true,
                        ),
                      ],
                    ),
                  ),
                ],
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

  Widget _buildNoStudentState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                LucideIcons.wallet,
                size: 40,
                color: AppTheme.textDisabled,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Financeiro',
              style: AppTheme.titleLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 100,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 160,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: List.generate(
              2,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index < 1 ? 12 : 0),
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
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
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.errorLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                LucideIcons.alertCircle,
                size: 40,
                color: AppTheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Erro ao carregar dados',
              style: AppTheme.titleLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente novamente mais tarde.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Summary Card
class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  final double amount;
  final String Function(double) formatCurrency;
  final bool isAlert;

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.amount,
    required this.formatCurrency,
    this.isAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAlert ? AppTheme.error : AppTheme.divider,
          width: isAlert ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isAlert
                      ? AppTheme.errorLight
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count.toString(),
                  style: AppTheme.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isAlert ? AppTheme.error : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatCurrency(amount),
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: isAlert ? AppTheme.error : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// PIX Card
class _PixCard extends StatelessWidget {
  final String pixKey;
  final VoidCallback onCopy;

  const _PixCard({
    required this.pixKey,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.qrCode,
              size: 22,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chave PIX',
                  style: AppTheme.labelSmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pixKey,
                  style: AppTheme.bodyMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.copy,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Copiar',
                      style: AppTheme.labelMedium.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Payments List
class _PaymentsList extends StatelessWidget {
  final List<Payment> payments;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final String Function(double) formatCurrency;
  final bool showStatus;
  final bool abacatePayEnabled;
  final void Function(Payment)? onPayPix;

  const _PaymentsList({
    required this.payments,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.formatCurrency,
    this.showStatus = false,
    this.abacatePayEnabled = false,
    this.onPayPix,
  });

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  emptyIcon,
                  size: 32,
                  color: AppTheme.textDisabled,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                emptyTitle,
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                emptySubtitle,
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PaymentCard(
            payment: payments[index],
            formatCurrency: formatCurrency,
            showStatus: showStatus,
            showPayButton: abacatePayEnabled && onPayPix != null,
            onPayPix: onPayPix,
          ),
        );
      },
    );
  }
}

/// Payment Card
class _PaymentCard extends StatelessWidget {
  final Payment payment;
  final String Function(double) formatCurrency;
  final bool showStatus;
  final bool showPayButton;
  final void Function(Payment)? onPayPix;

  const _PaymentCard({
    required this.payment,
    required this.formatCurrency,
    this.showStatus = false,
    this.showPayButton = false,
    this.onPayPix,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = payment.status == PaymentStatus.overdue;
    final isPaid = payment.status == PaymentStatus.paid;
    final canPay = (payment.status == PaymentStatus.pending ||
        payment.status == PaymentStatus.overdue);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOverdue ? AppTheme.error : AppTheme.divider,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isOverdue
                      ? AppTheme.errorLight
                      : isPaid
                          ? AppTheme.successLight
                          : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isOverdue
                      ? LucideIcons.alertTriangle
                      : isPaid
                          ? LucideIcons.checkCircle
                          : LucideIcons.receipt,
                  size: 20,
                  color: isOverdue
                      ? AppTheme.error
                      : isPaid
                          ? AppTheme.success
                          : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.description ?? 'Mensalidade',
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.calendar,
                          size: 12,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat("dd/MM/yyyy").format(payment.dueDate),
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (payment.referenceMonth != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(${payment.referenceMonth})',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Value & Status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(payment.value),
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isOverdue ? AppTheme.error : AppTheme.textPrimary,
                    ),
                  ),
                  if (showStatus) ...[
                    const SizedBox(height: 4),
                    _StatusChip(status: payment.status),
                  ],
                ],
              ),
            ],
          ),
          // Pay Button
          if (showPayButton && canPay) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => onPayPix?.call(payment),
                icon: const Icon(LucideIcons.qrCode, size: 18),
                label: const Text('Pagar com PIX'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

/// PIX Payment Bottom Sheet
class _PixPaymentBottomSheet extends ConsumerStatefulWidget {
  final Payment payment;
  final String studentName;
  final String Function(double) formatCurrency;

  const _PixPaymentBottomSheet({
    required this.payment,
    required this.studentName,
    required this.formatCurrency,
  });

  @override
  ConsumerState<_PixPaymentBottomSheet> createState() =>
      _PixPaymentBottomSheetState();
}

class _PixPaymentBottomSheetState
    extends ConsumerState<_PixPaymentBottomSheet> {
  bool _isLoading = true;
  PaymentLink? _paymentLink;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generatePixPayment();
  }

  Future<void> _generatePixPayment() async {
    final academyId = FirebaseService.academyId;
    if (academyId == null) {
      setState(() {
        _error = 'Academia nao encontrada';
        _isLoading = false;
      });
      return;
    }

    try {
      final service = AbacatePayService(academyId);
      final link = await service.createPixPayment(
        amount: widget.payment.value,
        financialId: widget.payment.id,
        studentId: widget.payment.studentId,
        studentName: widget.studentName,
        description:
            widget.payment.description ?? 'Mensalidade - ${widget.payment.referenceMonth ?? ''}',
      );

      setState(() {
        _paymentLink = link;
        _isLoading = false;
        if (link == null) {
          _error = 'Erro ao gerar pagamento PIX';
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Erro ao gerar pagamento: $e';
        _isLoading = false;
      });
    }
  }

  void _copyPixCode() {
    if (_paymentLink?.pixCode != null) {
      Clipboard.setData(ClipboardData(text: _paymentLink!.pixCode));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Codigo PIX copiado!'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Pagar com PIX',
                style: AppTheme.titleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.payment.description ?? 'Mensalidade'} - ${widget.formatCurrency(widget.payment.value)}',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Content
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Gerando QR Code...'),
                    ],
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        size: 48,
                        color: AppTheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else if (_paymentLink != null)
                Column(
                  children: [
                    // QR Code
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: QrImageView(
                        data: _paymentLink!.pixCode,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Instructions
                    Text(
                      'Escaneie o QR Code ou copie o codigo PIX',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Copy Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _copyPixCode,
                        icon: const Icon(LucideIcons.copy, size: 18),
                        label: const Text('Copiar Codigo PIX'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.info,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Apos o pagamento, seu status sera atualizado automaticamente.',
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Close Button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
