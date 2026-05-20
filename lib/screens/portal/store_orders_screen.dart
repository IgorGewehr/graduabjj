import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/store_provider.dart';
import '../../services/store_service.dart';
import 'store_orders/order_card.dart';
import 'store_orders/order_details_sheet.dart';

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
                        child: OrderCard(
                          order: orders[index],
                          onTap: () => _showOrderDetails(
                            context,
                            orders[index],
                            isAdminView: isAdminOrInstructor,
                          ),
                          showStudentName: isAdminOrInstructor,
                        ),
                      )
                          .animate(delay: (index * 50).ms)
                          .fadeIn(duration: 200.ms)
                          .slideY(begin: 0.08),
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
                      child: OrderCardSkeleton(),
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
          OrderDetailsSheet(order: order, isAdminView: isAdminView),
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
            Icon(
              LucideIcons.packageSearch,
              size: 64,
              color: AppTheme.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum registro encontrado',
              style: AppTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Seus pedidos aparecerao aqui apos a primeira compra',
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/portal/loja'),
              icon: const Icon(LucideIcons.store),
              label: const Text('Ir para Loja'),
            ),
          ],
        ).animate().fadeIn(duration: 600.ms).scale(
              begin: const Offset(0.8, 0.8),
            ),
      ),
    );
  }
}
