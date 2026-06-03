import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../services/store_service.dart';
import '../../services/abacate_pay_service.dart';
import '../../services/asaas_payment_service.dart';
import '../../services/mercado_pago_service.dart';
import '../../services/firebase_service.dart';
import '../../providers/store_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/polish/polish.dart';

/// Portal Store Orders Screen - Student's Orders or All Orders for Admin/Instructor
class PortalStoreOrdersScreen extends ConsumerWidget {
  const PortalStoreOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final studentId = currentUser?.studentId;
    final isAdminOrInstructor =
        currentUser?.isAdmin == true || currentUser?.isInstructor == true;

    // For students without studentId, show error
    // For admin/instructor, show all orders
    if (studentId == null && !isAdminOrInstructor) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  size: 48,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Voce precisa estar vinculado a um aluno',
                  style: AppTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Use all orders for admin/instructor, student orders for students
    final ordersAsync = isAdminOrInstructor
        ? ref.watch(ordersProvider)
        : ref.watch(studentOrdersProvider(studentId!));

    final title = isAdminOrInstructor ? 'Pedidos da Loja' : 'Meus Pedidos';
    final subtitle = isAdminOrInstructor
        ? 'Gerencie os pedidos recebidos'
        : 'Acompanhe seus pedidos';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          if (isAdminOrInstructor) {
            ref.invalidate(ordersProvider);
          } else {
            ref.invalidate(studentOrdersProvider(studentId!));
          }
        },
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          context.pop();
                        } else {
                          context.go('/portal/loja');
                        }
                      },
                      icon: const Icon(LucideIcons.arrowLeft),
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.surfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTheme.headlineMedium),
                          Text(
                            subtitle,
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Orders List
            ordersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _OrderCard(
                          order: orders[index],
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showOrderDetails(
                              context,
                              orders[index],
                              isAdminView: isAdminOrInstructor,
                            );
                          },
                          showStudentName: isAdminOrInstructor,
                        ),
                      ).entrance(index: index),
                      childCount: orders.length,
                    ),
                  ),
                );
              },
              loading: () => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: _OrderCardSkeleton(),
                    ),
                    childCount: 3,
                  ),
                ),
              ),
              error: (error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        size: 48,
                        color: AppTheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Erro ao carregar pedidos',
                        style: AppTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          if (isAdminOrInstructor) {
                            ref.invalidate(ordersProvider);
                          } else {
                            ref.invalidate(studentOrdersProvider(studentId!));
                          }
                        },
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(
    BuildContext context,
    StoreOrder order, {
    bool isAdminView = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _OrderDetailsSheet(order: order, isAdminView: isAdminView),
    );
  }
}

/// Empty State Widget
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return PolishedEmptyState(
      icon: LucideIcons.shoppingBag,
      title: 'Nenhum pedido ainda',
      subtitle: 'Seus pedidos aparecerao aqui',
      actionLabel: 'Ir para Loja',
      onAction: () => context.go('/portal/loja'),
    );
  }
}

/// Order Card Widget
class _OrderCard extends StatelessWidget {
  final StoreOrder order;
  final VoidCallback onTap;
  final bool showStudentName;

  const _OrderCard({
    required this.order,
    required this.onTap,
    this.showStudentName = false,
  });

  Color _getStatusColor() {
    switch (order.status) {
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

  IconData _getStatusIcon() {
    switch (order.status) {
      case StoreOrderStatus.pendingPayment:
        return LucideIcons.clock;
      case StoreOrderStatus.paid:
        return LucideIcons.checkCircle;
      case StoreOrderStatus.preparing:
        return LucideIcons.package;
      case StoreOrderStatus.ready:
        return LucideIcons.packageCheck;
      case StoreOrderStatus.delivered:
        return LucideIcons.truck;
      case StoreOrderStatus.cancelled:
        return LucideIcons.xCircle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final statusColor = _getStatusColor();
    // Highlight orders awaiting payment so they stand out in the list.
    final isNew = order.status == StoreOrderStatus.pendingPayment;

    return Pressable(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isNew ? statusColor.withValues(alpha: 0.5) : AppTheme.divider,
          width: isNew ? 1.5 : 1,
        ),
        boxShadow: isNew
            ? [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Status Icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_getStatusIcon(), size: 20, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  // Order Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#${order.id.substring(order.id.length - 6).toUpperCase()}',
                              style: AppTheme.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                child: Container(
                                  key: ValueKey(order.status),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    order.status.label,
                                    style: AppTheme.labelSmall.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(order.createdAt),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (showStudentName) ...[
                          const SizedBox(height: 2),
                          Text(
                            order.studentName,
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Total
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        order.formattedTotal,
                        style: AppTheme.titleMedium.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${order.itemCount} itens',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Items Preview
              const SizedBox(height: 12),
              Text(
                order.items
                    .map((i) => '${i.quantity}x ${i.productName}')
                    .join(', '),
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _OrderCardSkeleton extends StatelessWidget {
  const _OrderCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 60,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Order Details Bottom Sheet
class _OrderDetailsSheet extends ConsumerStatefulWidget {
  final StoreOrder order;
  final bool isAdminView;

  const _OrderDetailsSheet({required this.order, this.isAdminView = false});

  @override
  ConsumerState<_OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends ConsumerState<_OrderDetailsSheet> {
  bool _isLoadingPayment = false;
  bool _isUpdatingStatus = false;

  Future<void> _updateStatus(StoreOrderStatus newStatus) async {
    final academyId = FirebaseService.academyId;

    setState(() => _isUpdatingStatus = true);

    try {
      final storeService = StoreService(academyId);
      await storeService.updateOrderStatus(widget.order.id, newStatus);
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
    final academyId = FirebaseService.academyId;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    setState(() => _isLoadingPayment = true);

    try {
      final desc =
          'Pedido #${widget.order.id.substring(widget.order.id.length - 6).toUpperCase()}';
      final studentId = currentUser.studentId ?? '';

      // Gateway precedence: Mercado Pago (connected) > Asaas > AbacatePay.
      final mp = MercadoPagoService(academyId);
      final asaasService = AsaasPaymentService(academyId);

      PaymentLink? paymentLink;
      if (await mp.isEnabled()) {
        paymentLink = await mp.createStoreOrderPayment(
          amount: widget.order.total,
          orderId: widget.order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: desc,
        );
      } else if (await asaasService.isEnabled()) {
        paymentLink = await asaasService.createStoreOrderPayment(
          amount: widget.order.total,
          orderId: widget.order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: desc,
        );
      } else {
        paymentLink = await AbacatePayService(academyId).createStoreOrderPayment(
          amount: widget.order.total,
          orderId: widget.order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: desc,
        );
      }

      if (paymentLink != null && mounted) {
        Navigator.pop(context);
        _showPixPaymentSheet(context, paymentLink);
      } else if (mounted) {
        context.showError('Erro ao gerar pagamento PIX');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
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
      builder: (context) => _PixPaymentBottomSheet(
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
                    _StatusTimeline(order: order),
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

/// Status Timeline Widget
class _StatusTimeline extends StatelessWidget {
  final StoreOrder order;

  const _StatusTimeline({required this.order});

  @override
  Widget build(BuildContext context) {
    final steps = [
      _TimelineStep(
        label: 'Criado',
        status: StoreOrderStatus.pendingPayment,
        isCompleted: true,
        isActive: order.status == StoreOrderStatus.pendingPayment,
      ),
      _TimelineStep(
        label: 'Pago',
        status: StoreOrderStatus.paid,
        isCompleted: order.isPaid,
        isActive: order.status == StoreOrderStatus.paid,
      ),
      _TimelineStep(
        label: 'Preparando',
        status: StoreOrderStatus.preparing,
        isCompleted:
            order.status == StoreOrderStatus.preparing ||
            order.status == StoreOrderStatus.ready ||
            order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.preparing,
      ),
      _TimelineStep(
        label: 'Pronto',
        status: StoreOrderStatus.ready,
        isCompleted:
            order.status == StoreOrderStatus.ready ||
            order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.ready,
      ),
      _TimelineStep(
        label: 'Entregue',
        status: StoreOrderStatus.delivered,
        isCompleted: order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.delivered,
      ),
    ];

    if (order.status == StoreOrderStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.errorLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.xCircle, color: AppTheme.error),
            const SizedBox(width: 12),
            Text(
              'Pedido cancelado',
              style: AppTheme.titleSmall.copyWith(color: AppTheme.error),
            ),
          ],
        ),
      );
    }

    return Row(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isLast = index == steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: step.isCompleted || step.isActive
                            ? AppTheme.primary
                            : AppTheme.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: step.isCompleted
                          ? const Icon(
                              LucideIcons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : step.isActive
                          ? Container(
                              margin: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.label,
                      style: AppTheme.labelSmall.copyWith(
                        color: step.isCompleted || step.isActive
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontWeight: step.isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        fontSize: 9,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Container(
                  width: 16,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 20),
                  color: step.isCompleted
                      ? AppTheme.primary
                      : AppTheme.surfaceVariant,
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TimelineStep {
  final String label;
  final StoreOrderStatus status;
  final bool isCompleted;
  final bool isActive;

  _TimelineStep({
    required this.label,
    required this.status,
    required this.isCompleted,
    required this.isActive,
  });
}

/// PIX Payment Bottom Sheet with real-time payment listener
class _PixPaymentBottomSheet extends StatefulWidget {
  final PaymentLink paymentLink;
  final String orderId;
  final double amount;
  final String studentId;
  final void Function()? onPaymentConfirmed;

  const _PixPaymentBottomSheet({
    required this.paymentLink,
    required this.orderId,
    required this.amount,
    required this.studentId,
    this.onPaymentConfirmed,
  });

  @override
  State<_PixPaymentBottomSheet> createState() => _PixPaymentBottomSheetState();
}

class _PixPaymentBottomSheetState extends State<_PixPaymentBottomSheet> {
  bool _paymentConfirmed = false;
  StreamSubscription<DocumentSnapshot>? _orderListener;

  @override
  void initState() {
    super.initState();
    _setupOrderListener();
  }

  @override
  void dispose() {
    _orderListener?.cancel();
    super.dispose();
  }

  /// Listen to order status changes in real-time
  void _setupOrderListener() {
    final academyId = FirebaseService.academyId;

    _orderListener = FirebaseFirestore.instance
        .collection('academies')
        .doc(academyId)
        .collection('storeOrders')
        .doc(widget.orderId)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;

          final data = snapshot.data();
          if (data != null && data['status'] == 'paid' && !_paymentConfirmed) {
            setState(() {
              _paymentConfirmed = true;
            });

            // Show success feedback
            _showPaymentConfirmedDialog();

            // Notify parent
            widget.onPaymentConfirmed?.call();
          }
        });
  }

  void _showPaymentConfirmedDialog() {
    final sheetContext = context;
    Celebration.confetti(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SuccessCheck(size: 80),
            const SizedBox(height: 24),
            Text(
              'Pagamento Confirmado!',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Seu pedido foi pago com sucesso.',
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
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
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    LucideIcons.qrCode,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pagar com PIX',
                        style: AppTheme.titleLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Pedido #${widget.orderId.substring(widget.orderId.length - 6).toUpperCase()}',
                        style: AppTheme.bodyMedium.copyWith(
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
            const SizedBox(height: 24),
            // Amount
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Valor: ',
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    'R\$ ${widget.amount.toStringAsFixed(2)}',
                    style: AppTheme.headlineMedium.copyWith(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // QR Code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: widget.paymentLink.pixCode,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Escaneie o QR Code com o app do seu banco',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Copy Code Button
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.paymentLink.pixCode.length > 30
                          ? '${widget.paymentLink.pixCode.substring(0, 30)}...'
                          : widget.paymentLink.pixCode,
                      style: AppTheme.bodySmall.copyWith(
                        fontFamily: 'monospace',
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.paymentLink.pixCode),
                      );
                      context.showSuccess('Codigo PIX copiado!');
                    },
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: const Text('Copiar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.info,
                        size: 20,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Instrucoes',
                        style: AppTheme.titleSmall.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInstruction('1', 'Abra o app do seu banco'),
                  const SizedBox(height: 8),
                  _buildInstruction('2', 'Escolha pagar via PIX'),
                  const SizedBox(height: 8),
                  _buildInstruction('3', 'Escaneie o QR Code ou cole o codigo'),
                  const SizedBox(height: 8),
                  _buildInstruction('4', 'Confirme o pagamento'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Real-time payment status indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _paymentConfirmed
                    ? AppTheme.successLight
                    : AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
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
                  Text(
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
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInstruction(String number, String text) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: AppTheme.labelSmall.copyWith(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// Card Payment Bottom Sheet
class _CardPaymentBottomSheet extends StatefulWidget {
  final String orderId;
  final double amount;
  final String studentId;
  final String studentName;
  final VoidCallback onPaymentSuccess;

  const _CardPaymentBottomSheet({
    required this.orderId,
    required this.amount,
    required this.studentId,
    required this.studentName,
    required this.onPaymentSuccess,
  });

  @override
  State<_CardPaymentBottomSheet> createState() =>
      _CardPaymentBottomSheetState();
}

class _CardPaymentBottomSheetState extends State<_CardPaymentBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _expirationController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cpfController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _expirationController.dispose();
    _cvvController.dispose();
    _cpfController.dispose();
    super.dispose();
  }

  String _formatCardNumber(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digitsOnly[i]);
    }
    return buffer.toString();
  }

  String _formatExpiration(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length >= 2) {
      return '${digitsOnly.substring(0, 2)}/${digitsOnly.substring(2, digitsOnly.length.clamp(2, 4))}';
    }
    return digitsOnly;
  }

  String _formatCpf(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length && i < 11; i++) {
      if (i == 3 || i == 6) buffer.write('.');
      if (i == 9) buffer.write('-');
      buffer.write(digitsOnly[i]);
    }
    return buffer.toString();
  }

  Future<void> _handlePayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final academyId = FirebaseService.academyId;

    try {
      final expParts = _expirationController.text.split('/');
      final cardData = CardData(
        cardNumber: _cardNumberController.text,
        cardHolder: _cardHolderController.text,
        expirationMonth: expParts[0],
        expirationYear: expParts.length > 1 ? expParts[1] : '',
        cvv: _cvvController.text,
        cpf: _cpfController.text,
      );

      final desc =
          'Pedido #${widget.orderId.substring(widget.orderId.length - 6).toUpperCase()}';

      // Gateway precedence: Mercado Pago (connected) > Asaas > AbacatePay.
      final mp = MercadoPagoService(academyId);
      final asaasService = AsaasPaymentService(academyId);
      final useMp = await mp.isEnabled();
      final isAsaas = !useMp && await asaasService.isEnabled();

      CardPaymentResult result;
      if (useMp) {
        result = await mp.createStoreOrderCardPayment(
          amount: widget.amount,
          orderId: widget.orderId,
          studentId: widget.studentId,
          studentName: widget.studentName,
          cardData: cardData,
          description: desc,
        );
      } else if (isAsaas) {
        result = await asaasService.createStoreOrderCardPayment(
          amount: widget.amount,
          orderId: widget.orderId,
          studentId: widget.studentId,
          studentName: widget.studentName,
          cardData: cardData,
          description: desc,
        );
      } else {
        result = await AbacatePayService(academyId).createStoreOrderCardPayment(
          amount: widget.amount,
          orderId: widget.orderId,
          studentId: widget.studentId,
          studentName: widget.studentName,
          cardData: cardData,
          description: desc,
        );
      }

      if (result.success) {
        if (mounted) {
          context.showSuccess(result.message ?? 'Pagamento aprovado!');
          widget.onPaymentSuccess();
        }
      } else {
        setState(() {
          _errorMessage = result.message ?? 'Erro ao processar pagamento';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.creditCard,
                      color: AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pagar com Cartao',
                          style: AppTheme.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'R\$ ${widget.amount.toStringAsFixed(2)}',
                          style: AppTheme.titleMedium.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
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
              const SizedBox(height: 24),

              // Error Message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        color: AppTheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Card Number
              TextFormField(
                controller: _cardNumberController,
                decoration: const InputDecoration(
                  labelText: 'Numero do Cartao',
                  hintText: '0000 0000 0000 0000',
                  prefixIcon: Icon(LucideIcons.creditCard),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final formatted = _formatCardNumber(value);
                  if (formatted != value) {
                    _cardNumberController.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                validator: (value) {
                  if (value == null || value.replaceAll(' ', '').length < 16) {
                    return 'Numero do cartao invalido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Card Holder
              TextFormField(
                controller: _cardHolderController,
                decoration: const InputDecoration(
                  labelText: 'Nome no Cartao',
                  hintText: 'NOME COMO NO CARTAO',
                  prefixIcon: Icon(LucideIcons.user),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nome obrigatorio';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Expiration and CVV
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expirationController,
                      decoration: const InputDecoration(
                        labelText: 'Validade',
                        hintText: 'MM/AA',
                        prefixIcon: Icon(LucideIcons.calendar),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final formatted = _formatExpiration(value);
                        if (formatted != value) {
                          _expirationController.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                              offset: formatted.length,
                            ),
                          );
                        }
                      },
                      validator: (value) {
                        if (value == null ||
                            !value.contains('/') ||
                            value.length < 5) {
                          return 'Invalido';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _cvvController,
                      decoration: const InputDecoration(
                        labelText: 'CVV',
                        hintText: '000',
                        prefixIcon: Icon(LucideIcons.lock),
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      validator: (value) {
                        if (value == null || value.length < 3) {
                          return 'Invalido';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // CPF
              TextFormField(
                controller: _cpfController,
                decoration: const InputDecoration(
                  labelText: 'CPF do Titular',
                  hintText: '000.000.000-00',
                  prefixIcon: Icon(LucideIcons.fileText),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final formatted = _formatCpf(value);
                  if (formatted != value) {
                    _cpfController.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                validator: (value) {
                  if (value == null ||
                      value.replaceAll(RegExp(r'\D'), '').length < 11) {
                    return 'CPF invalido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handlePayment,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.check),
                  label: Text(_isLoading ? 'Processando...' : 'Pagar'),
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

              // Security Note
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    LucideIcons.shield,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Pagamento seguro',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
