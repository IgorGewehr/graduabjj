import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/portal_providers.dart';
import '../../providers/store_provider.dart';
import '../../services/store_service.dart';
import '../../widgets/skeletons/skeletons.dart';
import 'store/product_card.dart';
import 'store/product_details_sheet.dart';
import 'store/store_academy_indicator.dart';
import 'store/store_filter_chip.dart';

/// Portal Store Screen - Product Catalog for Students
class PortalStoreScreen extends ConsumerStatefulWidget {
  const PortalStoreScreen({super.key});

  @override
  ConsumerState<PortalStoreScreen> createState() => _PortalStoreScreenState();
}

class _PortalStoreScreenState extends ConsumerState<PortalStoreScreen> {
  String _searchQuery = '';
  StoreProductCategory? _categoryFilter;

  /// 300ms debounce timer for the product search input.
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (_searchQuery == value) return;
      setState(() => _searchQuery = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(activeProductsProvider);
    final cart = ref.watch(cartProvider);
    final settingsAsync = ref.watch(academySettingsProvider);

    final settings = settingsAsync.valueOrNull;
    final isStorePublished = settings?.storePublished ?? false;
    final welcomeMessage = settings?.storeWelcomeMessage;

    if (!isStorePublished) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
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
                    LucideIcons.store,
                    size: 48,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Loja Indisponivel',
                  style: AppTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'A loja da academia esta temporariamente fechada.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          ref.invalidate(activeProductsProvider);
        },
        child: CustomScrollView(
          slivers: [
            // Academy indicator for multi-academy users
            const SliverToBoxAdapter(child: StoreAcademyIndicator()),

            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    if (welcomeMessage != null && welcomeMessage.isNotEmpty)
                      Expanded(
                        child: Text(
                          welcomeMessage,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      const Spacer(),
                    // Orders button
                    IconButton(
                      onPressed: () => context.push('/portal/loja/pedidos'),
                      icon: const Icon(LucideIcons.fileText),
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.surfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Cart button with badge
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          onPressed: () =>
                              context.push('/portal/loja/carrinho'),
                          icon: const Icon(LucideIcons.shoppingCart),
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.surfaceVariant,
                          ),
                        ),
                        if (cart.isNotEmpty)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${ref.read(cartProvider.notifier).itemCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Search
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar produtos...',
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
                  onChanged: _onSearchChanged,
                ),
              ),
            ),

            // Category Filters
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      StoreFilterChip(
                        label: 'Todos',
                        isSelected: _categoryFilter == null,
                        onTap: () => setState(() => _categoryFilter = null),
                      ),
                      ...StoreProductCategory.values.map(
                        (cat) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: StoreFilterChip(
                            label: cat.label,
                            isSelected: _categoryFilter == cat,
                            onTap: () =>
                                setState(() => _categoryFilter = cat),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Products Grid
            productsAsync.when(
              data: (products) {
                var filtered = products;

                if (_searchQuery.isNotEmpty) {
                  filtered = filtered.where((p) {
                    return p.name.toLowerCase().contains(
                          _searchQuery.toLowerCase(),
                        ) ||
                        (p.description?.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ) ??
                            false);
                  }).toList();
                }

                if (_categoryFilter != null) {
                  filtered = filtered
                      .where((p) => p.category == _categoryFilter)
                      .toList();
                }

                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              LucideIcons.package,
                              size: 48,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Nenhum produto encontrado'
                                  : 'Nenhum produto disponivel',
                              style: AppTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.75,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => ProductCard(
                        product: filtered[index],
                        onTap: () => _showProductDetails(filtered[index]),
                      ),
                      childCount: filtered.length,
                    ),
                  ),
                );
              },
              loading: () => SliverToBoxAdapter(
                child: SkeletonGrid(
                  itemCount: 6,
                  scrollable: false,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
                        'Erro ao carregar produtos',
                        style: AppTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(activeProductsProvider),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: cart.isEmpty
            ? const SizedBox.shrink(key: ValueKey('cart-empty'))
            : FloatingActionButton.extended(
                key: ValueKey(
                  'cart-${ref.read(cartProvider.notifier).itemCount}',
                ),
                onPressed: () => context.push('/portal/loja/carrinho'),
                icon: const Icon(LucideIcons.shoppingCart),
                label: Text(
                  'Carrinho (${ref.read(cartProvider.notifier).itemCount})',
                ),
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
      ),
    );
  }

  void _showProductDetails(StoreProduct product) {
    final parentContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ProductDetailsSheet(
        product: product,
        onAddToCart: (item) {
          ref.read(cartProvider.notifier).addItem(item);
          Navigator.pop(sheetContext);
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: const Text('Produto adicionado ao carrinho'),
              action: SnackBarAction(
                label: 'Ver Carrinho',
                onPressed: () => parentContext.push('/portal/loja/carrinho'),
              ),
            ),
          );
        },
      ),
    );
  }
}
