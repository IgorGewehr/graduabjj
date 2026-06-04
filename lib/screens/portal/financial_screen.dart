import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../providers/providers.dart';
import '../../providers/payment_providers.dart';
import '../../providers/selected_academy_provider.dart';
import '../../services/services.dart';
import '../../services/abacate_pay_service.dart';
import '../../services/asaas_payment_service.dart';
import '../../services/mercado_pago_service.dart';
import '../../services/payment/payment_gateway_resolver.dart';
import '../../models/student.dart';
import '../../widgets/payment/payment_method_sheet.dart';
import '../../widgets/payment/payment_target.dart';
import '../../widgets/polish/polish.dart';
import '../../widgets/skeletons/skeletons.dart';

/// PIX payment enabled provider — true when any gateway is connected.
///
/// Derived from [currentPaymentGatewayProvider] (the single source of truth for
/// the MP > Asaas > AbacatePay precedence) via the [PaymentGatewayCapabilities]
/// `pixEnabled` flag, preserving the previous "PIX available?" semantics.
final abacatePayEnabledProvider = FutureProvider<bool>((ref) async {
  final gateway = await ref.watch(currentPaymentGatewayProvider.future);
  return gateway.pixEnabled;
});

/// One section per dependent: their OPEN charges with a pay button. Hidden when
/// the dependent has no open charges.
class _DependentSection extends ConsumerWidget {
  final Student dependent;
  final bool abacatePayEnabled;
  final String Function(double) formatCurrency;
  final void Function(Payment) onPayPix;

  const _DependentSection({
    required this.dependent,
    required this.abacatePayEnabled,
    required this.formatCurrency,
    required this.onPayPix,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(studentPaymentsProvider(dependent.id));
    return paymentsAsync.maybeWhen(
      data: (payments) {
        final open = payments
            .where((p) =>
                p.status == PaymentStatus.pending ||
                p.status == PaymentStatus.overdue)
            .toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        if (open.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'Dependente: ${dependent.displayName}',
              count: open.length,
            ),
            const SizedBox(height: 12),
            ...open.map(
              (payment) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PaymentCard(
                  payment: payment,
                  formatCurrency: formatCurrency,
                  showPayButton: abacatePayEnabled,
                  gatewayConnected: abacatePayEnabled,
                  onPayPix: () => onPayPix(payment),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

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

  Future<void> _showPixPaymentDialog(
    Payment payment,
    Student payer,
  ) async {
    final academyId = FirebaseService.academyId;
    final studentName = payer.fullName;
    final description = payment.description ??
        'Mensalidade - ${payment.referenceMonth ?? ''}';

    // Resolve the connected gateway up front (single source of truth) so we
    // know whether the payer CPF must be captured (Mercado Pago requires it for
    // PIX). Precedence: Mercado Pago > Asaas > AbacatePay.
    final gateway =
        await ref.read(paymentGatewayProvider(academyId).future);

    if (!mounted) return;

    // One-tap checkout: if Mercado Pago needs the CPF and the payer already has
    // a VALID one saved on their student doc, skip the CPF form and generate the
    // PIX straight away with it. The saved value is used only to build the
    // charge (sent to the CF/MP) — it is never re-exposed beyond the field.
    final savedCpf = (payer.cpf ?? '').replaceAll(RegExp(r'\D'), '');
    final hasSavedCpf =
        savedCpf.length == 11 && Validators.cpf(savedCpf) == null;
    final needsCpf = gateway.requireCpf && !hasSavedCpf;

    // Builds the PIX link on the resolved gateway. Only Mercado Pago forwards
    // the payer CPF; Asaas/AbacatePay createPix* do not accept it. When a CPF is
    // typed in the form (first payment), persist it to the student doc so the
    // next payment becomes a single tap.
    Future<PaymentLink?> generate(String? cpf) async {
      switch (gateway) {
        case PaymentGateway.mercadoPago:
          // Prefer the just-typed CPF (form), else the one saved on the doc.
          final effectiveCpf = (cpf != null && cpf.isNotEmpty)
              ? cpf.replaceAll(RegExp(r'\D'), '')
              : (hasSavedCpf ? savedCpf : null);
          // Persist a freshly captured, valid CPF for next time (best-effort —
          // a failure here must never block the payment).
          if (!hasSavedCpf &&
              effectiveCpf != null &&
              effectiveCpf.length == 11 &&
              effectiveCpf != savedCpf) {
            await _persistPayerCpf(payer, effectiveCpf);
          }
          return MercadoPagoService(academyId).createPixPayment(
            amount: payment.value,
            financialId: payment.id,
            studentId: payment.studentId,
            studentName: studentName,
            description: description,
            cpf: effectiveCpf,
          );
        case PaymentGateway.asaas:
          return AsaasPaymentService(academyId).createPixPayment(
            amount: payment.value,
            financialId: payment.id,
            studentId: payment.studentId,
            studentName: studentName,
            description: description,
          );
        case PaymentGateway.abacatePay:
        case PaymentGateway.none:
          return AbacatePayService(academyId).createPixPayment(
            amount: payment.value,
            financialId: payment.id,
            studentId: payment.studentId,
            studentName: studentName,
            description: description,
          );
      }
    }

    // Tuition target: PIX is always offered; Cartao only when the gateway can
    // charge a card (Mercado Pago). The store-only card flag never gates tuition.
    final target = PaymentTarget.tuition(
      financialId: payment.id,
      amount: payment.value,
      description: description,
      studentId: payment.studentId,
      studentName: studentName,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => PaymentMethodSheet(
        target: target,
        gateway: gateway,
        // CPF form only when MP needs it AND none is saved; otherwise the PIX
        // generates in one tap from the saved CPF.
        requireCpf: needsCpf,
        // MP forwards the (typed or saved) CPF; Asaas/AbacatePay ignore it.
        createPix: (cpf) => generate(cpf),
        onSettled: () {
          ref.invalidate(studentPaymentsProvider(payment.studentId));
        },
      ),
    );
  }

  /// Persists a validated, digits-only [cpf] on the payer's student doc so the
  /// next checkout is a single tap. Best-effort: errors are swallowed (the
  /// payment already succeeded and the CPF will simply be asked again). The CPF
  /// is never logged. Invalidates the relevant student provider so the in-memory
  /// model reflects the saved value.
  Future<void> _persistPayerCpf(Student payer, String cpf) async {
    try {
      await StudentService(FirebaseService.academyId).update(
        payer.id,
        {'cpf': cpf},
      );
      if (!mounted) return;
      // Refresh whichever view this payer maps to.
      ref.invalidate(currentStudentProvider);
      ref.invalidate(dependentsProvider);
    } catch (_) {
      // Saving the CPF for next time is a convenience, not a requirement.
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentAsync = ref.watch(currentStudentProvider);
    final pixInfoAsync = ref.watch(pixInfoProvider);
    final abacatePayEnabled =
        ref.watch(abacatePayEnabledProvider).valueOrNull ?? false;

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
            ref.invalidate(dependentsProvider);
            ref.invalidate(pixInfoProvider);
            ref.invalidate(abacatePayEnabledProvider);
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

                  // When this student is managed by a financial responsible,
                  // their OPEN charges live in the responsible's login — hide
                  // them here (historico stays visible) and show a short notice.
                  if (student.hasResponsible) ...[
                    _ManagedByResponsibleNotice(
                      responsibleName: student.responsibleName,
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    // Alert if has open payments
                    if (openPayments.isNotEmpty) ...[
                      _DebtAlertCard(
                        totalOpen: totalOpen,
                        openCount: openPayments.length,
                        overdueCount: overdueCount,
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
                      ...openPayments.asMap().entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PaymentCard(
                            payment: entry.value,
                            formatCurrency: _formatCurrency,
                            showPayButton: abacatePayEnabled,
                            gatewayConnected: abacatePayEnabled,
                            pixKey: pixKey,
                            onCopyPix: () => _copyPixKey(pixKey),
                            onPayPix: () => _showPixPaymentDialog(
                              entry.value,
                              student,
                            ),
                          ).entrance(index: entry.key),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // All paid message
                    if (openPayments.isEmpty) ...[
                      _AllPaidCard(),
                      const SizedBox(height: 24),
                    ],
                  ],

                  // Dependentes — cobrancas de alunos kids sob este responsavel
                  ...ref.watch(dependentsProvider).maybeWhen(
                        data: (deps) => deps
                            .where((d) => d.id != student.id)
                            .map<Widget>(
                              (dep) => _DependentSection(
                                dependent: dep,
                                abacatePayEnabled: abacatePayEnabled,
                                formatCurrency: _formatCurrency,
                                onPayPix: (payment) =>
                                    _showPixPaymentDialog(payment, dep),
                              ),
                            )
                            .toList(),
                        orElse: () => const <Widget>[],
                      ),

                  // History Section
                  _SectionHeader(
                    title: 'Historico',
                    count: historyPayments.length,
                  ),
                  const SizedBox(height: 12),

                  if (historyPayments.isEmpty)
                    _EmptyHistoryCard()
                  else
                    ...historyPayments.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PaymentCard(
                          payment: entry.value,
                          formatCurrency: _formatCurrency,
                          showStatus: true,
                        ).entrance(index: entry.key),
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
  final String Function(double) formatCurrency;

  const _DebtAlertCard({
    required this.totalOpen,
    required this.openCount,
    required this.overdueCount,
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

/// Shown in a managed kid's own login: their open charges are handled by the
/// financial responsible, so they don't appear here.
class _ManagedByResponsibleNotice extends StatelessWidget {
  final String? responsibleName;
  const _ManagedByResponsibleNotice({this.responsibleName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.users, size: 24, color: AppTheme.info),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cobrancas com o responsavel',
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.info,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  responsibleName != null && responsibleName!.isNotEmpty
                      ? 'Suas cobrancas sao gerenciadas e pagas por $responsibleName.'
                      : 'Suas cobrancas sao gerenciadas e pagas pelo seu responsavel.',
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

  /// Whether a payment gateway is connected for this academy. When false and
  /// the charge is open, a friendly "not connected" notice replaces the button.
  final bool gatewayConnected;
  final VoidCallback? onPayPix;

  /// Academy static PIX key, shown ONLY as an explicit manual fallback when no
  /// gateway is connected (never alongside the in-app checkout, to avoid
  /// off-app payments the webhook can't reconcile).
  final String pixKey;
  final VoidCallback? onCopyPix;

  const _PaymentCard({
    required this.payment,
    required this.formatCurrency,
    this.showStatus = false,
    this.showPayButton = false,
    this.gatewayConnected = true,
    this.onPayPix,
    this.pixKey = '',
    this.onCopyPix,
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
                icon: const Icon(LucideIcons.wallet, size: 18),
                label: const Text('Pagar mensalidade'),
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
          ]
          // No gateway connected: friendly notice instead of the pay button.
          else if (!gatewayConnected && !isPaid && !isCancelled) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pagamento online indisponivel. Fale com a recepcao para quitar.',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (pixKey.isNotEmpty) ...[
              const SizedBox(height: 8),
              Pressable(
                onTap: onCopyPix,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.qrCode,
                          size: 16, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chave PIX da academia (pagamento manual)',
                              style: AppTheme.labelSmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Text(
                              pixKey,
                              style: AppTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(LucideIcons.copy,
                          size: 16, color: AppTheme.textPrimary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pague pela chave acima e envie o comprovante; a baixa e feita na recepcao.',
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textDisabled),
              ),
            ],
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
