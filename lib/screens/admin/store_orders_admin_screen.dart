import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../services/firebase_service.dart';
import '../../services/store_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/store_provider.dart';
import '../../widgets/polish/polish.dart';
import '../../widgets/store/order_status_timeline.dart';

/// Filters for the admin order-management board. [all] keeps every order;
/// the remaining entries map 1:1 to a [StoreOrderStatus].
enum _OrderBoardFilter {
  all,
  pendingPayment,
  paid,
  preparing,
  ready,
  delivered,
  cancelled,
}

extension _OrderBoardFilterX on _OrderBoardFilter {
  String get label {
    switch (this) {
      case _OrderBoardFilter.all:
        return 'Todos';
      case _OrderBoardFilter.pendingPayment:
        return 'Aguardando';
      case _OrderBoardFilter.paid:
        return 'Pagos';
      case _OrderBoardFilter.preparing:
        return 'Preparando';
      case _OrderBoardFilter.ready:
        return 'Prontos';
      case _OrderBoardFilter.delivered:
        return 'Entregues';
      case _OrderBoardFilter.cancelled:
        return 'Cancelados';
    }
  }

  /// The [StoreOrderStatus] this filter selects, or `null` for [all].
  StoreOrderStatus? get status {
    switch (this) {
      case _OrderBoardFilter.all:
        return null;
      case _OrderBoardFilter.pendingPayment:
        return StoreOrderStatus.pendingPayment;
      case _OrderBoardFilter.paid:
        return StoreOrderStatus.paid;
      case _OrderBoardFilter.preparing:
        return StoreOrderStatus.preparing;
      case _OrderBoardFilter.ready:
        return StoreOrderStatus.ready;
      case _OrderBoardFilter.delivered:
        return StoreOrderStatus.delivered;
      case _OrderBoardFilter.cancelled:
        return StoreOrderStatus.cancelled;
    }
  }

  bool matches(StoreOrder order) {
    final s = status;
    return s == null || order.status == s;
  }
}

/// Admin/instructor board for managing store orders, grouped by status filters.
///
/// Reads the academy-scoped [ordersProvider] (all orders) and lets staff advance
/// an order through its lifecycle. Stock is only decremented on the
/// pendingPayment -> paid transition (guarded in [StoreService.updateOrderStatus]),
/// so advancing already-paid orders never double-decrements.
///
/// Access is gated to admins and instructors (`store:manage` permission); other
/// users are redirected back to the admin home.
class StoreOrdersAdminScreen extends ConsumerStatefulWidget {
  const StoreOrdersAdminScreen({super.key});

  @override
  ConsumerState<StoreOrdersAdminScreen> createState() =>
      _StoreOrdersAdminScreenState();
}

class _StoreOrdersAdminScreenState
    extends ConsumerState<StoreOrdersAdminScreen> {
  _OrderBoardFilter _filter = _OrderBoardFilter.all;

  bool _canManage(dynamic user) {
    if (user == null) return false;
    return user.isAdmin == true ||
        user.isInstructor == true ||
        user.hasPermission('store:manage') == true;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    // Gate: only staff (admin/instructor or store:manage) may open this board.
    if (!_canManage(currentUser)) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  LucideIcons.lock,
                  size: 48,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Acesso restrito',
                  style: AppTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Voce nao tem permissao para gerenciar pedidos.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/admin'),
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          ref.invalidate(ordersProvider);
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
                          context.go('/admin/loja');
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
                          Text('Pedidos da Loja', style: AppTheme.headlineMedium),
                          Text(
                            'Gerencie os pedidos recebidos',
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

            // Status filter chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _OrderBoardFilter.values.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = _OrderBoardFilter.values[index];
                    final count = ordersAsync.valueOrNull
                        ?.where(filter.matches)
                        .length;
                    return _FilterChip(
                      label: filter.label,
                      badge: count,
                      isSelected: _filter == filter,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _filter = filter);
                      },
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // Orders list (filtered)
            ordersAsync.when(
              data: (orders) {
                final filtered =
                    orders.where(_filter.matches).toList(growable: false);

                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: PolishedEmptyState(
                      icon: LucideIcons.shoppingBag,
                      title: _filter == _OrderBoardFilter.all
                          ? 'Nenhum pedido ainda'
                          : 'Nenhum pedido neste filtro',
                      subtitle: _filter == _OrderBoardFilter.all
                          ? 'Os pedidos recebidos aparecerao aqui'
                          : 'Tente outro filtro',
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AdminOrderCard(
                          order: filtered[index],
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showOrderDetails(context, filtered[index]);
                          },
                        ),
                      ).entrance(index: index),
                      childCount: filtered.length,
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
                      Text('Erro ao carregar pedidos',
                          style: AppTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(ordersProvider),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(BuildContext context, StoreOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AdminOrderDetailsSheet(order: order),
    );
  }
}

/// Animated status filter chip (single selection).
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badge;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTheme.labelMedium.copyWith(
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge != null && badge! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style: AppTheme.labelSmall.copyWith(
                    color: isSelected ? Colors.white : AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Order card for the admin board (always shows the student name).
class _AdminOrderCard extends StatelessWidget {
  final StoreOrder order;
  final VoidCallback onTap;

  const _AdminOrderCard({required this.order, required this.onTap});

  Color _statusColor() {
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

  IconData _statusIcon() {
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
    final statusColor = _statusColor();
    // Highlight orders that need staff attention (awaiting payment).
    final needsAttention = order.status == StoreOrderStatus.pendingPayment;

    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: needsAttention
                ? statusColor.withValues(alpha: 0.5)
                : AppTheme.divider,
            width: needsAttention ? 1.5 : 1,
          ),
          boxShadow: needsAttention
              ? [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_statusIcon(), size: 20, color: statusColor),
                  ),
                  const SizedBox(width: 12),
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
                              child: Container(
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
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(order.createdAt),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          order.studentName,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
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
      child: Row(
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
        ],
      ),
    );
  }
}

/// Admin order details + status-advance actions.
class _AdminOrderDetailsSheet extends ConsumerStatefulWidget {
  final StoreOrder order;

  const _AdminOrderDetailsSheet({required this.order});

  @override
  ConsumerState<_AdminOrderDetailsSheet> createState() =>
      _AdminOrderDetailsSheetState();
}

class _AdminOrderDetailsSheetState
    extends ConsumerState<_AdminOrderDetailsSheet> {
  bool _isUpdatingStatus = false;

  Future<void> _updateStatus(StoreOrderStatus newStatus) async {
    final academyId = FirebaseService.academyId;
    setState(() => _isUpdatingStatus = true);
    try {
      // Stock is decremented only on pendingPayment -> paid inside
      // [StoreService.updateOrderStatus]; advancing already-paid orders is safe.
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
      // Auditoria MP: cancelar via StoreService.cancelOrder (nao _updateStatus),
      // pois cancelOrder restaura o estoque de pedidos ja pagos/preparando/prontos
      // (estoque foi decrementado na transicao -> paid). _updateStatus(cancelled)
      // pulava a restauracao, causando drift silencioso de estoque.
      await _cancelOrderWithStockRestore();
    }
  }

  /// Cancela o pedido restaurando estoque (delega ao StoreService.cancelOrder,
  /// que so devolve estoque de itens inStock quando o pedido nao era pendente).
  Future<void> _cancelOrderWithStockRestore() async {
    final academyId = FirebaseService.academyId;
    setState(() => _isUpdatingStatus = true);
    try {
      final storeService = StoreService(academyId);
      await storeService.cancelOrder(widget.order.id);
      if (mounted) {
        Navigator.pop(context);
        context.showSuccess('Pedido cancelado!');
        ref.invalidate(ordersProvider);
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao cancelar pedido: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Color _statusColor() {
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
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

  /// The next-status action button for the order's current status, or `null`
  /// when there is no forward action (delivered/cancelled). "Marcar como Pago"
  /// is only offered while pending, so the paid-transition (and its stock
  /// decrement) never runs twice.
  Widget? _nextActionButton() {
    switch (widget.order.status) {
      case StoreOrderStatus.pendingPayment:
        return _buildAdminActionButton(
          label: 'Marcar como Pago',
          icon: LucideIcons.checkCircle,
          color: Colors.green,
          onPressed: () => _updateStatus(StoreOrderStatus.paid),
        );
      case StoreOrderStatus.paid:
        return _buildAdminActionButton(
          label: 'Iniciar Preparo',
          icon: LucideIcons.package,
          color: Colors.purple,
          onPressed: () => _updateStatus(StoreOrderStatus.preparing),
        );
      case StoreOrderStatus.preparing:
        return _buildAdminActionButton(
          label: 'Marcar como Pronto',
          icon: LucideIcons.packageCheck,
          color: Colors.green,
          onPressed: () => _updateStatus(StoreOrderStatus.ready),
        );
      case StoreOrderStatus.ready:
        return _buildAdminActionButton(
          label: 'Marcar como Entregue',
          icon: LucideIcons.truck,
          color: Colors.blue,
          onPressed: () => _updateStatus(StoreOrderStatus.delivered),
        );
      case StoreOrderStatus.delivered:
      case StoreOrderStatus.cancelled:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final statusColor = _statusColor();
    final nextAction = _nextActionButton();
    final isClosed = order.status == StoreOrderStatus.delivered ||
        order.status == StoreOrderStatus.cancelled;

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
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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
                        Container(
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
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrderStatusTimeline(order: order),
                    const SizedBox(height: 24),
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

                    // Customer info
                    const SizedBox(height: 24),
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

                    // Status actions (only while the order is still open)
                    if (!isClosed) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Acoes',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (nextAction != null) ...[
                        nextAction,
                        const SizedBox(height: 12),
                      ],
                      _buildAdminActionButton(
                        label: 'Cancelar Pedido',
                        icon: LucideIcons.xCircle,
                        color: AppTheme.error,
                        outlined: true,
                        onPressed: _cancelOrder,
                      ),
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
