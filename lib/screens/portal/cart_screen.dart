import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../services/store_service.dart';
import '../../providers/store_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/loading_button.dart';
import '../../widgets/polish/polish.dart';

/// Portal Cart Screen
class PortalCartScreen extends ConsumerStatefulWidget {
  const PortalCartScreen({super.key});

  @override
  ConsumerState<PortalCartScreen> createState() => _PortalCartScreenState();
}

class _PortalCartScreenState extends ConsumerState<PortalCartScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: cart.isEmpty
          ? _buildEmptyCart()
          : CustomScrollView(
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
                              Text('Carrinho', style: AppTheme.headlineMedium),
                              Text(
                                '${cartNotifier.itemCount} itens',
                                style: AppTheme.bodyMedium.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            cartNotifier.clear();
                          },
                          child: const Text('Limpar'),
                        ),
                      ],
                    ),
                  ),
                ),

                // Cart Items — keep each item keyed so the list animates
                // adds/removes via the implicit AnimatedSwitcher below.
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        key: ValueKey(
                          '${cart[index].productId}-${cart[index].size ?? ''}-${cart[index].color ?? ''}',
                        ),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: _CartItemCard(
                            item: cart[index],
                            onUpdateQuantity: (qty) {
                              HapticFeedback.selectionClick();
                              cartNotifier.updateQuantity(index, qty);
                            },
                            onRemove: () {
                              HapticFeedback.lightImpact();
                              cartNotifier.removeItem(index);
                            },
                          ).entrance(index: index),
                        ),
                      ),
                      childCount: cart.length,
                    ),
                  ),
                ),

                // Summary
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Itens (${cartNotifier.itemCount})',
                                style: AppTheme.bodyMedium.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              Text(
                                cartNotifier.formattedTotal,
                                style: AppTheme.bodyMedium,
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Estimado',
                                style: AppTheme.titleMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                cartNotifier.formattedTotal,
                                style: AppTheme.headlineSmall.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Precos e disponibilidade confirmados no pedido.',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Checkout Button — uses LoadingButton helper for consistent
                // inline spinner + disabled state.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: LoadingButton(
                        isLoading: _isLoading,
                        onPressed: _checkout,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(LucideIcons.shoppingBag),
                            SizedBox(width: 8),
                            Text('Finalizar Pedido'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom padding
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
    );
  }

  Widget _buildEmptyCart() {
    return PolishedEmptyState(
      icon: LucideIcons.shoppingCart,
      title: 'Carrinho vazio',
      subtitle: 'Adicione produtos para continuar',
      actionLabel: 'Ver Produtos',
      onAction: () => context.pop(),
    );
  }

  Future<void> _checkout() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final cart = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    if (currentUser == null || currentUser.studentId == null) {
      context.showWarning('Voce precisa estar vinculado a um aluno');
      return;
    }

    if (cart.isEmpty) {
      context.showWarning('Seu carrinho esta vazio');
      return;
    }

    HapticFeedback.selectionClick();
    setState(() => _isLoading = true);

    try {
      final service = ref.read(storeServiceProvider);
      if (service == null) {
        context.showError('Erro ao acessar a loja');
        return;
      }
      // Server validates prices and stock
      await service.createOrder(
        studentId: currentUser.studentId!,
        studentName: currentUser.displayName,
        items: cart,
      );

      // Clear cart after successful order
      cartNotifier.clear();

      // Show success and navigate to orders
      if (mounted) {
        HapticFeedback.heavyImpact();
        Celebration.confetti(context);
        context.showSuccess('Pedido criado com sucesso!');
        context.push('/portal/loja/pedidos');
      }
    } catch (e) {
      if (mounted) {
        // Show specific error from server validation
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        context.showError(errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

/// Cart Item Card Widget
class _CartItemCard extends StatelessWidget {
  final StoreOrderItem item;
  final void Function(int) onUpdateQuantity;
  final VoidCallback onRemove;

  const _CartItemCard({
    required this.item,
    required this.onUpdateQuantity,
    required this.onRemove,
  });

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image Placeholder
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.package,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.size != null || item.color != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [item.size, item.color].whereType<String>().join(' - '),
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${item.formattedPrice} cada',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.primary),
                ),
              ],
            ),
          ),
          // Quantity and Actions
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Remove Button
              IconButton(
                onPressed: onRemove,
                icon: const Icon(LucideIcons.trash2, size: 18),
                style: IconButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              // Quantity
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.divider),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: item.quantity > 1
                          ? () => onUpdateQuantity(item.quantity - 1)
                          : onRemove,
                      icon: const Icon(LucideIcons.minus, size: 14),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                    Text(
                      '${item.quantity}',
                      style: AppTheme.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: () => onUpdateQuantity(item.quantity + 1),
                      icon: const Icon(LucideIcons.plus, size: 14),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Subtotal
              Text(
                item.formattedSubtotal,
                style: AppTheme.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
