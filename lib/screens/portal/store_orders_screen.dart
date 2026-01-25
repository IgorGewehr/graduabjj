import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../services/store_service.dart';
import '../../providers/store_provider.dart';
import '../../providers/auth_provider.dart';

/// Portal Store Orders Screen - Student's Orders
class PortalStoreOrdersScreen extends ConsumerWidget {
  const PortalStoreOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final studentId = currentUser?.studentId;

    if (studentId == null) {
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

    final ordersAsync = ref.watch(studentOrdersProvider(studentId));

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(studentOrdersProvider(studentId));
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
                      onPressed: () => context.pop(),
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
                          Text('Meus Pedidos', style: AppTheme.headlineMedium),
                          Text(
                            'Acompanhe seus pedidos',
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
                          onTap: () => _showOrderDetails(context, orders[index]),
                        ),
                      ),
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
                      const Icon(LucideIcons.alertCircle,
                          size: 48, color: AppTheme.error),
                      const SizedBox(height: 16),
                      Text('Erro ao carregar pedidos', style: AppTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(studentOrdersProvider(studentId)),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
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
      builder: (context) => _OrderDetailsSheet(order: order),
    );
  }
}

/// Empty State Widget
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.shoppingBag,
                size: 48,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Nenhum pedido ainda',
              style: AppTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Seus pedidos aparecerao aqui',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/portal/loja'),
              icon: const Icon(LucideIcons.store),
              label: const Text('Ir para Loja'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Order Card Widget
class _OrderCard extends StatelessWidget {
  final StoreOrder order;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.onTap,
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
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
                            Container(
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
                order.items.map((i) => '${i.quantity}x ${i.productName}').join(', '),
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
class _OrderDetailsSheet extends StatelessWidget {
  final StoreOrder order;

  const _OrderDetailsSheet({required this.order});

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

  @override
  Widget build(BuildContext context) {
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
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Pedido #${order.id.substring(order.id.length - 6).toUpperCase()}',
                              style: AppTheme.headlineSmall,
                            ),
                            const SizedBox(width: 12),
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
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(order.createdAt),
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary),
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
                    ...order.items.map((item) => Padding(
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
                                        [item.size, item.color]
                                            .whereType<String>()
                                            .join(' - '),
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
                                    'R\$ ${item.subtotal.toStringAsFixed(2)}',
                                    style: AppTheme.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${item.quantity}x R\$ ${item.price.toStringAsFixed(2)}',
                                    style: AppTheme.labelSmall.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )),
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
        label: 'Pedido Criado',
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
        isCompleted: order.status == StoreOrderStatus.preparing ||
            order.status == StoreOrderStatus.ready ||
            order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.preparing,
      ),
      _TimelineStep(
        label: 'Pronto',
        status: StoreOrderStatus.ready,
        isCompleted:
            order.status == StoreOrderStatus.ready || order.status == StoreOrderStatus.delivered,
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
              Column(
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
                      fontWeight: step.isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 20),
                    color: step.isCompleted
                        ? AppTheme.primary
                        : AppTheme.surfaceVariant,
                  ),
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
