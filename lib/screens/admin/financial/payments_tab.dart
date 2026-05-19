import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/financial_dto.dart' as api_fin;
import '../../../api/repositories.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../services/services.dart';
import 'financial_widgets.dart';

// ============================================
// Payments Tab
// ============================================

class PaymentsTab extends ConsumerStatefulWidget {
  final List<Payment> allPayments;
  final List<Payment> pendingPayments;
  final List<Payment> overduePayments;
  final String Function(double) formatCurrency;
  final bool canWrite;
  final Future<void> Function(Payment) onMarkPaid;
  final Future<void> Function(Payment) onSendReminder;
  final Future<void> Function(Payment) onCancel;
  final Future<void> Function(Payment) onReactivate;

  const PaymentsTab({
    super.key,
    required this.allPayments,
    required this.pendingPayments,
    required this.overduePayments,
    required this.formatCurrency,
    required this.canWrite,
    required this.onMarkPaid,
    required this.onSendReminder,
    required this.onCancel,
    required this.onReactivate,
  });

  @override
  ConsumerState<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends ConsumerState<PaymentsTab> {
  String _paymentFilter = 'all';
  String _paymentSearch = '';

  List<Payment> get _filteredPayments {
    List<Payment> filtered = widget.allPayments;

    switch (_paymentFilter) {
      case 'paid':
        filtered = widget.allPayments
            .where((p) => p.status == PaymentStatus.paid)
            .toList();
        break;
      case 'pending':
        filtered = widget.pendingPayments;
        break;
      case 'overdue':
        filtered = widget.overduePayments;
        break;
      case 'cancelled':
        filtered = widget.allPayments
            .where((p) => p.status == PaymentStatus.cancelled)
            .toList();
        break;
    }

    if (_paymentSearch.isNotEmpty) {
      filtered = filtered
          .where((p) => p.studentName
              .toLowerCase()
              .contains(_paymentSearch.toLowerCase()))
          .toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredPayments = _filteredPayments;

    return Column(
      children: [
        // Filter chips and search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              // Search bar
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome...',
                    hintStyle: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textDisabled),
                    prefixIcon: Icon(LucideIcons.search,
                        size: 18, color: AppTheme.textSecondary),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    suffixIcon: _paymentSearch.isNotEmpty
                        ? IconButton(
                            icon: Icon(LucideIcons.x,
                                size: 16, color: AppTheme.textSecondary),
                            onPressed: () =>
                                setState(() => _paymentSearch = ''),
                          )
                        : null,
                  ),
                  onChanged: (value) =>
                      setState(() => _paymentSearch = value),
                ),
              ),
              const SizedBox(height: 12),
              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FinancialFilterChip(
                      label: 'Todos',
                      count: widget.allPayments.length,
                      isSelected: _paymentFilter == 'all',
                      onTap: () =>
                          setState(() => _paymentFilter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    FinancialFilterChip(
                      label: 'Pagos',
                      count: widget.allPayments
                          .where((p) => p.status == PaymentStatus.paid)
                          .length,
                      isSelected: _paymentFilter == 'paid',
                      color: AppTheme.success,
                      onTap: () =>
                          setState(() => _paymentFilter = 'paid'),
                    ),
                    const SizedBox(width: 8),
                    FinancialFilterChip(
                      label: 'Pendentes',
                      count: widget.pendingPayments.length,
                      isSelected: _paymentFilter == 'pending',
                      color: AppTheme.warning,
                      onTap: () =>
                          setState(() => _paymentFilter = 'pending'),
                    ),
                    const SizedBox(width: 8),
                    FinancialFilterChip(
                      label: 'Atrasados',
                      count: widget.overduePayments.length,
                      isSelected: _paymentFilter == 'overdue',
                      color: AppTheme.error,
                      onTap: () =>
                          setState(() => _paymentFilter = 'overdue'),
                    ),
                    const SizedBox(width: 8),
                    FinancialFilterChip(
                      label: 'Cancelados',
                      count: widget.allPayments
                          .where(
                              (p) => p.status == PaymentStatus.cancelled)
                          .length,
                      isSelected: _paymentFilter == 'cancelled',
                      color: AppTheme.textDisabled,
                      onTap: () =>
                          setState(() => _paymentFilter = 'cancelled'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Payments list
        Expanded(
          child: filteredPayments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.receipt,
                          size: 32,
                          color: AppTheme.textDisabled,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhum pagamento',
                        style: AppTheme.titleMedium
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _paymentSearch.isNotEmpty
                            ? 'Nenhum resultado para "$_paymentSearch"'
                            : 'Não há pagamentos nesta categoria',
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: filteredPayments.length,
                  itemBuilder: (context, index) {
                    final payment = filteredPayments[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PaymentCard(
                        payment: payment,
                        formatCurrency: widget.formatCurrency,
                        onMarkPaid: widget.canWrite &&
                                payment.status != PaymentStatus.paid &&
                                payment.status !=
                                    PaymentStatus.cancelled
                            ? () => _handleMarkPaid(context, payment)
                            : null,
                        onSendReminder: widget.canWrite &&
                                payment.status != PaymentStatus.paid &&
                                payment.status !=
                                    PaymentStatus.cancelled
                            ? () => widget.onSendReminder(payment)
                            : null,
                        onCancel: widget.canWrite &&
                                payment.status != PaymentStatus.paid &&
                                payment.status !=
                                    PaymentStatus.cancelled
                            ? () => widget.onCancel(payment)
                            : null,
                        onReactivate: widget.canWrite &&
                                payment.status ==
                                    PaymentStatus.cancelled
                            ? () => widget.onReactivate(payment)
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _handleMarkPaid(BuildContext context, Payment payment) {
    _showMarkPaidDialog(context, payment);
  }

  // ============================================
  // Mark Paid Dialog
  // ============================================

  void _showMarkPaidDialog(BuildContext context, Payment payment) {
    PaymentMethod selectedMethod = PaymentMethod.pix;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandleBar(),
              const SizedBox(height: 20),
              Text(
                'Confirmar Pagamento',
                style:
                    AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),

              // Payment info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          payment.studentName.isNotEmpty
                              ? payment.studentName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: AppTheme.primary,
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
                          ),
                          Text(
                            'Vencimento: ${DateFormat('dd/MM').format(payment.dueDate)}',
                            style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      widget.formatCurrency(payment.value),
                      style: AppTheme.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Payment method
              Text(
                'Metodo de pagamento',
                style:
                    AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PaymentMethod.values.map((method) {
                  final isSelected = selectedMethod == method;
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => selectedMethod = method),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.textPrimary
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.textPrimary
                              : AppTheme.divider,
                        ),
                      ),
                      child: Text(
                        method.label,
                        style: AppTheme.bodySmall.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: AppTheme.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              setDialogState(() => isSaving = true);
                              try {
                                final academyId = FirebaseService.academyId;
                                final apiMethod = _toApiMethod(selectedMethod);
                                await ref
                                    .read(financialRepoProvider)
                                    .updateStatus(
                                      academyId,
                                      payment.id,
                                      api_fin.UpdateFinancialStatusRequest(
                                        status: api_fin.ApiFinancialStatus.paid,
                                        method: apiMethod,
                                        paymentDate: DateTime.now(),
                                      ),
                                    );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  context.showSuccess(
                                      'Pagamento confirmado!');
                                  await widget.onMarkPaid(payment);
                                }
                              } catch (e) {
                                setDialogState(() => isSaving = false);
                                if (context.mounted) {
                                  context.showError('Erro: $e');
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
              SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Converte `PaymentMethod` (modelo legacy) → `ApiPaymentMethod` (Tatami).
  static api_fin.ApiPaymentMethod _toApiMethod(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.pix:
        return api_fin.ApiPaymentMethod.pix;
      case PaymentMethod.creditCard:
      case PaymentMethod.debitCard:
        return api_fin.ApiPaymentMethod.credit_card;
      case PaymentMethod.cash:
        return api_fin.ApiPaymentMethod.cash;
      case PaymentMethod.bankTransfer:
        return api_fin.ApiPaymentMethod.bank_transfer;
    }
  }
}
