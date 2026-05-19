import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/financial_dto.dart' as api_fin;
import '../../../api/dto/store_dto.dart' as api_store;
import '../../../api/repositories.dart' as tatami_repos;
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/store_provider.dart';
import '../../../services/abacate_pay_service.dart'; // PaymentLink type
import '../../../services/store_service.dart';
import 'order_pix_payment_sheet.dart';
import 'order_status_timeline.dart';

/// Order Details Bottom Sheet
class OrderDetailsSheet extends ConsumerStatefulWidget {
  final StoreOrder order;
  final bool isAdminView;

  const OrderDetailsSheet({
    super.key,
    required this.order,
    this.isAdminView = false,
  });

  @override
  ConsumerState<OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends ConsumerState<OrderDetailsSheet> {
  bool _isLoadingPayment = false;
  bool _isUpdatingStatus = false;

  Future<void> _updateStatus(StoreOrderStatus newStatus) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final academyId = currentUser?.academyId;
    if (academyId == null) return;

    setState(() => _isUpdatingStatus = true);

    try {
      await ref
          .read(tatami_repos.storeRepoProvider)
          .updateOrderStatus(
            academyId,
            widget.order.id,
            _toApiOrderStatus(newStatus),
          );
      if (mounted) {
        Navigator.pop(context);
        context.showSuccess('Status atualizado!');
        ref.invalidate(ordersProvider);
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao atualizar status: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  api_store.ApiOrderStatus _toApiOrderStatus(StoreOrderStatus s) {
    switch (s) {
      case StoreOrderStatus.pendingPayment:
        return api_store.ApiOrderStatus.pending_payment;
      case StoreOrderStatus.paid:
        return api_store.ApiOrderStatus.paid;
      case StoreOrderStatus.preparing:
        return api_store.ApiOrderStatus.preparing;
      case StoreOrderStatus.ready:
        return api_store.ApiOrderStatus.ready;
      case StoreOrderStatus.delivered:
        return api_store.ApiOrderStatus.delivered;
      case StoreOrderStatus.cancelled:
        return api_store.ApiOrderStatus.cancelled;
    }
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Pedido'),
        content: const Text('Tem certeza que deseja cancelar este pedido?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nao'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _updateStatus(StoreOrderStatus.cancelled);
    }
  }

  Color _getStatusColor() {
    switch (widget.order.status) {
      case StoreOrderStatus.pendingPayment:
        return Colors.orange;
      case StoreOrderStatus.paid:
        return Colors.blue;
      case StoreOrderStatus.preparing:
        return Colors.purple;
      case StoreOrderStatus.ready:
        return Colors.green;
      case StoreOrderStatus.delivered:
        return Colors.grey;
      case StoreOrderStatus.cancelled:
        return AppTheme.error;
    }
  }

  Future<void> _handlePixPayment() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;
    final academyId = currentUser.academyId ?? '';

    setState(() => _isLoadingPayment = true);

    try {
      final payIntent = await ref
          .read(tatami_repos.financialRepoProvider)
          .payWithPix(
            academyId,
            widget.order.id,
            body: api_fin.PayIntentRequest(
              customerName: currentUser.displayName,
            ),
          );

      final paymentLink = PaymentLink(
        pixCode: payIntent.pixCopyPaste ?? '',
        qrCodeUrl: payIntent.pixQrCode,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        abacatePayId: payIntent.externalId,
      );

      if (mounted) {
        Navigator.pop(context);
        _showPixPaymentSheet(context, paymentLink);
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao gerar PIX: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingPayment = false);
      }
    }
  }

  void _showPixPaymentSheet(BuildContext context, PaymentLink paymentLink) {
    final studentId =
        ref.read(currentUserProvider).valueOrNull?.studentId ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => OrderPixPaymentSheet(
        paymentLink: paymentLink,
        orderId: widget.order.id,
        amount: widget.order.total,
        studentId: studentId,
        onPaymentConfirmed: () {
          // Refresh the orders list when payment is confirmed
          ref.invalidate(studentOrdersProvider(studentId));
        },
      ),
    );
  }

  Widget _buildAdminActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool outlined = false,
  }) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isUpdatingStatus ? null : onPressed,
          icon: _isUpdatingStatus
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon, color: color),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isUpdatingStatus ? null : onPressed,
        icon: _isUpdatingStatus
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final statusColor = _getStatusColor();

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedido #${order.id.substring(order.id.length - 6).toUpperCase()}',
                          style: AppTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Container(
                            key: ValueKey(order.status),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              order.status.label,
                              style: AppTheme.labelMedium.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(order.createdAt),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Timeline
                    OrderStatusTimeline(order: order),
                    const SizedBox(height: 24),
                    // Items
                    Text(
                      'Itens do Pedido',
                      style: AppTheme.titleSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...order.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                LucideIcons.package,
                                size: 20,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: AppTheme.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (item.size != null || item.color != null)
                                    Text(
                                      [
                                        item.size,
                                        item.color,
                                      ].whereType<String>().join(' - '),
                                      style: AppTheme.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  item.formattedSubtotal,
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${item.quantity}x ${item.formattedPrice}',
                                  style: AppTheme.labelSmall.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 32),
                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          order.formattedTotal,
                          style: AppTheme.headlineSmall.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (order.notes?.isNotEmpty == true) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Observacoes',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(order.notes!),
                    ],

                    // ADMIN VIEW: Customer info and status actions
                    if (widget.isAdminView) ...[
                      const SizedBox(height: 24),
                      // Customer Info
                      Text(
                        'Cliente',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                LucideIcons.user,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.studentName,
                                    style: AppTheme.titleSmall.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (order.studentId.isNotEmpty)
                                    Text(
                                      'ID: ${order.studentId.substring(0, order.studentId.length.clamp(0, 8))}...',
                                      style: AppTheme.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Status Actions for Admin
                      if (order.status != StoreOrderStatus.delivered &&
                          order.status != StoreOrderStatus.cancelled) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Acoes',
                          style: AppTheme.titleSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Next status button based on current status
                        if (order.status == StoreOrderStatus.pendingPayment)
                          _buildAdminActionButton(
                            label: 'Marcar como Pago',
                            icon: LucideIcons.checkCircle,
                            color: Colors.green,
                            onPressed: () =>
                                _updateStatus(StoreOrderStatus.paid),
                          ),
                        if (order.status == StoreOrderStatus.paid)
                          _buildAdminActionButton(
                            label: 'Iniciar Preparo',
                            icon: LucideIcons.package,
                            color: Colors.purple,
                            onPressed: () =>
                                _updateStatus(StoreOrderStatus.preparing),
                          ),
                        if (order.status == StoreOrderStatus.preparing)
                          _buildAdminActionButton(
                            label: 'Marcar como Pronto',
                            icon: LucideIcons.packageCheck,
                            color: Colors.green,
                            onPressed: () =>
                                _updateStatus(StoreOrderStatus.ready),
                          ),
                        if (order.status == StoreOrderStatus.ready)
                          _buildAdminActionButton(
                            label: 'Marcar como Entregue',
                            icon: LucideIcons.truck,
                            color: Colors.blue,
                            onPressed: () =>
                                _updateStatus(StoreOrderStatus.delivered),
                          ),

                        const SizedBox(height: 12),
                        // Cancel button
                        _buildAdminActionButton(
                          label: 'Cancelar Pedido',
                          icon: LucideIcons.xCircle,
                          color: AppTheme.error,
                          outlined: true,
                          onPressed: _cancelOrder,
                        ),
                      ],
                    ]
                    // STUDENT VIEW: Payment Buttons for pending orders
                    else if (order.status ==
                        StoreOrderStatus.pendingPayment) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Formas de Pagamento',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // PIX Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoadingPayment
                              ? null
                              : _handlePixPayment,
                          icon: _isLoadingPayment
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(LucideIcons.qrCode),
                          label: Text(
                            _isLoadingPayment
                                ? 'Gerando PIX...'
                                : 'Pagar com PIX',
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      // Card payment disabled - coming soon
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
