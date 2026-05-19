import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/dto/financial_dto.dart' as api_fin;
import '../../api/repositories.dart' as tatami_repos;
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../providers/selected_academy_provider.dart';
import '../../services/services.dart';
import '../../services/abacate_pay_service.dart';
import '../../widgets/skeletons/skeletons.dart';

/// Payment enabled provider — lê direto do academySettingsProvider (Tatami/
/// Firestore-backed via portal_providers). Elimina as chamadas diretas a
/// AbacatePayService.isEnabled() e SettingsService.isAsaasEnabled() que
/// faziam round-trips individuais ao Firestore.
final abacatePayEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(academySettingsProvider).valueOrNull;
  return settings?.isPaymentEnabled ?? false;
});

/// Financial Screen - Pagamentos (Simplified)
class FinancialScreen extends ConsumerStatefulWidget {
  const FinancialScreen({super.key});

  @override
  ConsumerState<FinancialScreen> createState() => _FinancialScreenState();
}

class _FinancialScreenState extends ConsumerState<FinancialScreen> {
  String _formatCurrency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  void _copyPixKey(String pixKey) {
    if (pixKey.isEmpty) return;
    Clipboard.setData(ClipboardData(text: pixKey));
    context.showSuccess('Chave PIX copiada!');
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
    final abacatePayEnabled = ref.watch(abacatePayEnabledProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildNoStudentState();
        }

        final paymentsAsync = ref.watch(studentPaymentsProvider(student.id));
        final pixInfo = pixInfoAsync.valueOrNull ?? {};
        final pixKey = pixInfo['key'] ?? '';

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            ref.invalidate(studentPaymentsProvider(student.id));
            ref.invalidate(pixInfoProvider);
            ref.invalidate(academySettingsProvider);
          },
          child: paymentsAsync.when(
            data: (payments) {
              // Separate payments by status
              final openPayments =
                  payments
                      .where(
                        (p) =>
                            p.status == PaymentStatus.pending ||
                            p.status == PaymentStatus.overdue,
                      )
                      .toList()
                    ..sort((a, b) {
                      // Overdue first, then by due date
                      if (a.status == PaymentStatus.overdue &&
                          b.status != PaymentStatus.overdue)
                        return -1;
                      if (b.status == PaymentStatus.overdue &&
                          a.status != PaymentStatus.overdue)
                        return 1;
                      return a.dueDate.compareTo(b.dueDate);
                    });

              final historyPayments =
                  payments
                      .where(
                        (p) =>
                            p.status == PaymentStatus.paid ||
                            p.status == PaymentStatus.cancelled,
                      )
                      .toList()
                    ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

              final totalOpen = openPayments.fold<double>(
                0,
                (sum, p) => sum + p.value,
              );
              final overdueCount = openPayments
                  .where((p) => p.status == PaymentStatus.overdue)
                  .length;

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Academy indicator for multi-academy users
                  const _AcademyIndicator(),

                  // Header
                  Text(
                    'Pagamentos',
                    style: AppTheme.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gerencie suas mensalidades e pagamentos',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Alert if has open payments
                  if (openPayments.isNotEmpty) ...[
                    _DebtAlertCard(
                      totalOpen: totalOpen,
                      openCount: openPayments.length,
                      overdueCount: overdueCount,
                      pixKey: pixKey,
                      onCopyPix: () => _copyPixKey(pixKey),
                      formatCurrency: _formatCurrency,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Open Payments Section
                  if (openPayments.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Em Aberto',
                      count: openPayments.length,
                    ),
                    const SizedBox(height: 12),
                    ...openPayments.map(
                      (payment) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PaymentCard(
                          payment: payment,
                          formatCurrency: _formatCurrency,
                          showPayButton: abacatePayEnabled,
                          onPayPix: () =>
                              _showPixPaymentDialog(payment, student.fullName),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // All paid message
                  if (openPayments.isEmpty) ...[
                    _AllPaidCard(),
                    const SizedBox(height: 24),
                  ],

                  // History Section
                  _SectionHeader(
                    title: 'Historico',
                    count: historyPayments.length,
                  ),
                  const SizedBox(height: 12),

                  if (historyPayments.isEmpty)
                    _EmptyHistoryCard()
                  else
                    ...historyPayments.map(
                      (payment) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PaymentCard(
                          payment: payment,
                          formatCurrency: _formatCurrency,
                          showStatus: true,
                        ),
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
                LucideIcons.receipt,
                size: 40,
                color: AppTheme.textDisabled,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Pagamentos',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Vincule sua conta a um aluno para ver os pagamentos.',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        SkeletonStats(count: 2, height: 80),
        SizedBox(height: 24),
        SkeletonList(
          itemCount: 5,
          scrollable: false,
          padding: EdgeInsets.zero,
          showAvatar: false,
          itemHeight: 80,
        ),
      ],
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
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente novamente mais tarde.',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Debt Alert Card - Shows when there are open payments
class _DebtAlertCard extends StatelessWidget {
  final double totalOpen;
  final int openCount;
  final int overdueCount;
  final String pixKey;
  final VoidCallback onCopyPix;
  final String Function(double) formatCurrency;

  const _DebtAlertCard({
    required this.totalOpen,
    required this.openCount,
    required this.overdueCount,
    required this.pixKey,
    required this.onCopyPix,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final hasOverdue = overdueCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasOverdue ? AppTheme.errorLight : AppTheme.warningLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasOverdue
              ? AppTheme.error.withValues(alpha: 0.3)
              : AppTheme.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasOverdue
                      ? AppTheme.error.withValues(alpha: 0.1)
                      : AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasOverdue ? LucideIcons.alertTriangle : LucideIcons.clock,
                  size: 20,
                  color: hasOverdue ? AppTheme.error : AppTheme.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasOverdue
                          ? 'Voce tem pagamentos atrasados'
                          : 'Voce tem pagamentos pendentes',
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: hasOverdue
                            ? AppTheme.error
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$openCount pagamento(s) - ${formatCurrency(totalOpen)}',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pixKey.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  LucideIcons.qrCode,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PIX: $pixKey',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onCopyPix,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.copy,
                          size: 14,
                          color: AppTheme.textPrimary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Copiar',
                          style: AppTheme.labelSmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// All Paid Card - Shows when there are no open payments
class _AllPaidCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.successLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.checkCircle,
              size: 24,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tudo em dia!',
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Voce nao possui pagamentos pendentes',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
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

/// Section Header
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: AppTheme.labelSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Empty History Card
class _EmptyHistoryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.history, size: 32, color: AppTheme.textDisabled),
          const SizedBox(height: 12),
          Text(
            'Nenhum pagamento no historico',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
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
  final bool showStatus;
  final bool showPayButton;
  final VoidCallback? onPayPix;

  const _PaymentCard({
    required this.payment,
    required this.formatCurrency,
    this.showStatus = false,
    this.showPayButton = false,
    this.onPayPix,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = payment.isOverdue;
    final isPaid = payment.status == PaymentStatus.paid;
    final isCancelled = payment.status == PaymentStatus.cancelled;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue
              ? AppTheme.error.withValues(alpha: 0.5)
              : AppTheme.divider,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isOverdue
                      ? AppTheme.errorLight
                      : isPaid
                      ? AppTheme.successLight
                      : isCancelled
                      ? AppTheme.surfaceVariant
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isOverdue
                      ? LucideIcons.alertTriangle
                      : isPaid
                      ? LucideIcons.checkCircle
                      : isCancelled
                      ? LucideIcons.xCircle
                      : LucideIcons.receipt,
                  size: 18,
                  color: isOverdue
                      ? AppTheme.error
                      : isPaid
                      ? AppTheme.success
                      : isCancelled
                      ? AppTheme.textDisabled
                      : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.description ?? 'Mensalidade',
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isCancelled
                            ? AppTheme.textDisabled
                            : AppTheme.textPrimary,
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
                            payment.referenceMonth!,
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
                      color: isOverdue
                          ? AppTheme.error
                          : isCancelled
                          ? AppTheme.textDisabled
                          : AppTheme.textPrimary,
                      decoration: isCancelled
                          ? TextDecoration.lineThrough
                          : null,
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
          if (showPayButton && !isPaid && !isCancelled && onPayPix != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPayPix,
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Container(
        // ValueKey ensures AnimatedSwitcher detects the status change.
        key: ValueKey(status),
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
  bool _paymentConfirmed = false;
  // Firestore listener removido na Fase 1 — polling Tatami é o único caminho.
  Timer? _paymentPollTimer;

  @override
  void initState() {
    super.initState();
    _generatePixPayment();
    _setupPaymentListener();
  }

  @override
  void dispose() {
    _paymentPollTimer?.cancel();
    super.dispose();
  }

  void _setupPaymentListener() {
    final academyId = FirebaseService.academyId;

    // Tatami não tem stream em tempo real para um único financial; o padrão
    // é polling de 2s no GET /v1/.../financials/{id} até o status sair de
    // pending. Cancela ao confirmar ou no dispose. (Listener Firestore
    // removido na Fase 1.)
    _paymentPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }
        try {
          final repo = ref.read(tatami_repos.financialRepoProvider);
          final f = await repo.getById(academyId, widget.payment.id);
          if (!mounted) return;
          if (f.status == api_fin.ApiFinancialStatus.paid &&
              !_paymentConfirmed) {
            setState(() => _paymentConfirmed = true);
            timer.cancel();
            _showPaymentConfirmedDialog();
            ref.invalidate(studentPaymentsProvider(widget.payment.studentId));
          }
        } catch (_) {
          // Erro transiente — segue o polling sem propagar para a UI.
        }
      },
    );
  }

  void _showPaymentConfirmedDialog() {
    final sheetContext = context;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.successLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.checkCircle,
                size: 48,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Pagamento Confirmado!',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Seu pagamento foi recebido com sucesso.',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                if (mounted) Navigator.pop(sheetContext); // Close bottom sheet
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Fechar'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePixPayment() async {
    final academyId = FirebaseService.academyId;

    try {
      // Tatami: POST /financials/{id}/pay/pix — idempotente, BE escolhe
      // gateway (Asaas/AbacatePay) baseado no settings da academia.
      // Substitui os 2 client-paths (asaas/abacatePay) — fallback gateway-
      // specific removido na Fase 1.
      final payIntent =
          await ref.read(tatami_repos.financialRepoProvider).payWithPix(
                academyId,
                widget.payment.id,
                body: api_fin.PayIntentRequest(
                  customerName: widget.studentName,
                ),
              );
      final link = PaymentLink(
        pixCode: payIntent.pixCopyPaste ?? '',
        qrCodeUrl: payIntent.pixQrCode,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        abacatePayId: payIntent.externalId,
      );

      setState(() {
        _paymentLink = link;
        _isLoading = false;
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
      context.showSuccess('Codigo PIX copiado!');
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
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

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

                    Text(
                      'Escaneie o QR Code ou copie o codigo PIX',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

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

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _paymentConfirmed
                            ? AppTheme.successLight
                            : AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          if (_paymentConfirmed)
                            const Icon(
                              LucideIcons.checkCircle,
                              size: 18,
                              color: AppTheme.success,
                            )
                          else
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primary,
                                ),
                              ),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _paymentConfirmed
                                  ? 'Pagamento confirmado!'
                                  : 'Aguardando pagamento...',
                              style: AppTheme.bodySmall.copyWith(
                                color: _paymentConfirmed
                                    ? AppTheme.success
                                    : AppTheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

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

/// Academy indicator for multi-academy users
class _AcademyIndicator extends ConsumerWidget {
  const _AcademyIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);
    final academyInfo = ref.watch(currentAcademyInfoProvider);

    // Only show if user has multiple academies
    if (!hasMultiple || academyInfo == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.receipt, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pagamentos de',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  academyInfo.name,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push('/portal/academias'),
            icon: Icon(LucideIcons.arrowRightLeft, size: 14),
            label: const Text('Trocar'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: AppTheme.labelSmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
