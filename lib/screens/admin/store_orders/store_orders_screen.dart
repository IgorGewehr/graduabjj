import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/store_dto.dart';
import '../../../api/repositories.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/store_provider.dart';
import '../../../services/store_service.dart';
import 'order_card.dart';
import 'order_details_sheet.dart';
import 'orders_widgets.dart';

/// Admin Store Orders Screen
class AdminStoreOrdersScreen extends ConsumerStatefulWidget {
  const AdminStoreOrdersScreen({super.key});

  @override
  ConsumerState<AdminStoreOrdersScreen> createState() =>
      _AdminStoreOrdersScreenState();
}

class _AdminStoreOrdersScreenState
    extends ConsumerState<AdminStoreOrdersScreen> {
  String _searchQuery = '';
  StoreOrderStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);
    final statsAsync = ref.watch(storeStatsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ordersProvider);
          ref.invalidate(storeStatsProvider);
        },
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                              Text('Pedidos', style: AppTheme.headlineMedium),
                              Text(
                                'Gerencie os pedidos da loja',
                                style: AppTheme.bodyMedium.copyWith(
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
              ),
            ),

            // Stats Cards
            SliverToBoxAdapter(
              child: statsAsync.when(
                data: (stats) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OrdersStatCard(
                          label: 'Aguardando',
                          value: '${stats['pending'] ?? 0}',
                          icon: LucideIcons.clock,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OrdersStatCard(
                          label: 'Preparando',
                          value:
                              '${(stats['paid'] ?? 0) + (stats['preparing'] ?? 0)}',
                          icon: LucideIcons.package,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OrdersStatCard(
                          label: 'Prontos',
                          value: '${stats['ready'] ?? 0}',
                          icon: LucideIcons.checkCircle,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(child: OrdersStatCardSkeleton()),
                      SizedBox(width: 12),
                      Expanded(child: OrdersStatCardSkeleton()),
                      SizedBox(width: 12),
                      Expanded(child: OrdersStatCardSkeleton()),
                    ],
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // Search and Filter
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Search
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Buscar por cliente...',
                        prefixIcon: const Icon(LucideIcons.search, size: 20),
                        filled: true,
                        fillColor: AppTheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.divider),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    // Status Filters
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          OrdersFilterChip(
                            label: 'Todos',
                            isSelected: _statusFilter == null,
                            onTap: () => setState(() => _statusFilter = null),
                          ),
                          ...StoreOrderStatus.values
                              .where((s) => s != StoreOrderStatus.cancelled)
                              .map((status) => Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: OrdersFilterChip(
                                      label: status.label,
                                      isSelected: _statusFilter == status,
                                      onTap: () =>
                                          setState(() => _statusFilter = status),
                                    ),
                                  )),
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
                var filtered = orders;

                // Apply search
                if (_searchQuery.isNotEmpty) {
                  filtered = filtered.where((o) {
                    return o.studentName
                            .toLowerCase()
                            .contains(_searchQuery.toLowerCase()) ||
                        o.id.toLowerCase().contains(_searchQuery.toLowerCase());
                  }).toList();
                }

                // Apply status filter
                if (_statusFilter != null) {
                  filtered = filtered
                      .where((o) => o.status == _statusFilter)
                      .toList();
                }

                if (filtered.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: OrdersEmptyState(),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OrderCard(
                          order: filtered[index],
                          onTap: () => _showOrderDetails(filtered[index]),
                          onUpdateStatus: (status) =>
                              _updateOrderStatus(filtered[index], status),
                        ),
                      ),
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
                      child: OrderCardSkeleton(),
                    ),
                    childCount: 4,
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

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(StoreOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => OrderDetailsSheet(
        order: order,
        onUpdateStatus: (status) async {
          await _updateOrderStatus(order, status);
          if (mounted && context.mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _updateOrderStatus(
      StoreOrder order, StoreOrderStatus status) async {
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) {
        if (mounted) context.showError('Erro ao acessar a loja');
        return;
      }
      final academyId = currentUser!.academyId!;

      // Map legacy StoreOrderStatus → ApiOrderStatus for the Tatami endpoint.
      final apiStatus = _toApiStatus(status);
      await ref
          .read(storeRepoProvider)
          .updateOrderStatus(academyId, order.id, apiStatus);

      ref.invalidate(ordersProvider);
      ref.invalidate(storeStatsProvider);
      if (mounted) {
        context.showSuccess('Status atualizado para ${status.label}');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao atualizar: $e');
      }
    }
  }

  /// Converts legacy [StoreOrderStatus] to the wire [ApiOrderStatus] expected
  /// by [StoreRemoteRepo.updateOrderStatus].
  static ApiOrderStatus _toApiStatus(StoreOrderStatus s) {
    switch (s) {
      case StoreOrderStatus.pendingPayment:
        return ApiOrderStatus.pending_payment;
      case StoreOrderStatus.paid:
        return ApiOrderStatus.paid;
      case StoreOrderStatus.preparing:
        return ApiOrderStatus.preparing;
      case StoreOrderStatus.ready:
        return ApiOrderStatus.ready;
      case StoreOrderStatus.delivered:
        return ApiOrderStatus.delivered;
      case StoreOrderStatus.cancelled:
        return ApiOrderStatus.cancelled;
    }
  }
}
