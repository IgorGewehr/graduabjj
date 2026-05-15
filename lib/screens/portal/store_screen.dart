import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../services/store_service.dart';
import '../../providers/store_provider.dart';
import '../../providers/portal_providers.dart';
import '../../providers/selected_academy_provider.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/skeletons/skeletons.dart';

/// Portal Store Screen - Product Catalog for Students
class PortalStoreScreen extends ConsumerStatefulWidget {
  const PortalStoreScreen({super.key});

  @override
  ConsumerState<PortalStoreScreen> createState() => _PortalStoreScreenState();
}

class _PortalStoreScreenState extends ConsumerState<PortalStoreScreen> {
  String _searchQuery = '';
  StoreProductCategory? _categoryFilter;

  /// 300ms debounce timer for the product search input. Without this, every
  /// keystroke triggered a full sliver rebuild + filter pass — typing "joao"
  /// caused 4 setStates. Now we batch into a single setState 300ms after the
  /// user stops typing.
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
            const SliverToBoxAdapter(child: _AcademyIndicator()),

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
                      _FilterChip(
                        label: 'Todos',
                        isSelected: _categoryFilter == null,
                        onTap: () => setState(() => _categoryFilter = null),
                      ),
                      ...StoreProductCategory.values.map(
                        (cat) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _FilterChip(
                            label: cat.label,
                            isSelected: _categoryFilter == cat,
                            onTap: () => setState(() => _categoryFilter = cat),
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

                // Apply search
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

                // Apply category filter
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
                      (context, index) => _ProductCard(
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

            // Bottom padding for cart FAB
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      // Floating cart button — animate the show/hide and count changes so
      // adding/removing items feels reactive instead of a flicker swap.
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
    // Capture parent context before showing bottom sheet
    final parentContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ProductDetailsSheet(
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

/// Filter Chip Widget
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.labelMedium.copyWith(
            color: isSelected ? Colors.white : AppTheme.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Product Card Widget
class _ProductCard extends StatelessWidget {
  final StoreProduct product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOutOfStock =
        product.stockType == StoreStockType.inStock &&
        (product.stockQuantity ?? 0) == 0;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: InkWell(
        onTap: isOutOfStock ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: isOutOfStock ? 0.6 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: product.mainImageUrl != null
                          ? AppCachedImage(
                              imageUrl: product.mainImageUrl,
                              fit: BoxFit.cover,
                              errorIcon: const Center(
                                child: Icon(
                                  LucideIcons.package,
                                  size: 40,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(
                                LucideIcons.package,
                                size: 40,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                    ),
                    if (isOutOfStock)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.error,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Esgotado',
                            style: AppTheme.labelSmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Product Info
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          product.formattedPrice,
                          style: AppTheme.titleMedium.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (product.stockType == StoreStockType.inStock &&
                            !isOutOfStock)
                          Text(
                            '${product.stockQuantity} disp.',
                            style: AppTheme.labelSmall.copyWith(
                              color: (product.stockQuantity ?? 0) <= 3
                                  ? AppTheme.warning
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Product Details Bottom Sheet
class _ProductDetailsSheet extends StatefulWidget {
  final StoreProduct product;
  final void Function(StoreOrderItem) onAddToCart;

  const _ProductDetailsSheet({
    required this.product,
    required this.onAddToCart,
  });

  @override
  State<_ProductDetailsSheet> createState() => _ProductDetailsSheetState();
}

class _ProductDetailsSheetState extends State<_ProductDetailsSheet> {
  int _quantity = 1;
  String? _selectedSize;
  String? _selectedColor;
  int _currentImageIndex = 0;
  late final PageController _imagePageController = PageController();

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final hasVariants =
        (product.sizes?.isNotEmpty ?? false) ||
        (product.colors?.isNotEmpty ?? false);
    final maxQuantity = product.stockType == StoreStockType.inStock
        ? (product.stockQuantity ?? 0)
        : 99;

    final canAddToCart =
        !hasVariants ||
        ((product.sizes?.isEmpty ?? true) || _selectedSize != null) &&
            ((product.colors?.isEmpty ?? true) || _selectedColor != null);

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
            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Image(s)
                    if (product.imageUrls.isNotEmpty)
                      Container(
                        height: 250,
                        width: double.infinity,
                        margin: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            PageView.builder(
                              controller: _imagePageController,
                              itemCount: product.imageUrls.length,
                              onPageChanged: (index) =>
                                  setState(() => _currentImageIndex = index),
                              itemBuilder: (_, index) => AppCachedImage(
                                imageUrl: product.imageUrls[index],
                                fit: BoxFit.cover,
                                errorIcon: const Center(
                                  child: Icon(
                                    LucideIcons.package,
                                    size: 64,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            if (product.imageUrls.length > 1)
                              Positioned(
                                bottom: 10,
                                left: 0,
                                right: 0,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(
                                    product.imageUrls.length,
                                    (i) => AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      width: i == _currentImageIndex ? 16 : 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: i == _currentImageIndex
                                            ? Colors.white
                                            : Colors.white54,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    // Product Info
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: AppTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text(
                            product.formattedPrice,
                            style: AppTheme.headlineMedium.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          // Stock info
                          if (product.stockType == StoreStockType.inStock) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: (product.stockQuantity ?? 0) <= 3
                                    ? AppTheme.warningLight
                                    : AppTheme.successLight,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: (product.stockQuantity ?? 0) <= 3
                                      ? AppTheme.warning
                                      : AppTheme.success,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.package,
                                    size: 14,
                                    color: (product.stockQuantity ?? 0) <= 3
                                        ? AppTheme.warning
                                        : AppTheme.success,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${product.stockQuantity} ${(product.stockQuantity ?? 0) == 1 ? 'unidade disponível' : 'unidades disponíveis'}',
                                    style: AppTheme.labelSmall.copyWith(
                                      color: (product.stockQuantity ?? 0) <= 3
                                          ? AppTheme.warning
                                          : AppTheme.success,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.infoLight,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppTheme.info,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    LucideIcons.clock,
                                    size: 14,
                                    color: AppTheme.info,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Feito sob encomenda',
                                    style: AppTheme.labelSmall.copyWith(
                                      color: AppTheme.info,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (product.description != null &&
                              product.description!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              product.description!,
                              style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                          // Size Selection
                          if (product.sizes?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 24),
                            Text('Tamanho', style: AppTheme.titleSmall),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: product.sizes!
                                  .map(
                                    (size) => ChoiceChip(
                                      label: Text(size),
                                      selected: _selectedSize == size,
                                      onSelected: (selected) {
                                        setState(() {
                                          _selectedSize = selected
                                              ? size
                                              : null;
                                        });
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          // Color Selection
                          if (product.colors?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 24),
                            Text('Cor', style: AppTheme.titleSmall),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: product.colors!
                                  .map(
                                    (color) => ChoiceChip(
                                      label: Text(color),
                                      selected: _selectedColor == color,
                                      onSelected: (selected) {
                                        setState(() {
                                          _selectedColor = selected
                                              ? color
                                              : null;
                                        });
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          // Quantity Selection
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Text('Quantidade', style: AppTheme.titleSmall),
                              const Spacer(),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppTheme.divider),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      onPressed: _quantity > 1
                                          ? () => setState(() => _quantity--)
                                          : null,
                                      icon: const Icon(
                                        LucideIcons.minus,
                                        size: 18,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 40,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$_quantity',
                                        style: AppTheme.titleMedium.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _quantity < maxQuantity
                                          ? () => setState(() => _quantity++)
                                          : null,
                                      icon: const Icon(
                                        LucideIcons.plus,
                                        size: 18,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Add to Cart Button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canAddToCart
                        ? () {
                            widget.onAddToCart(
                              StoreOrderItem(
                                productId: product.id,
                                productName: product.name,
                                price: product.price,
                                quantity: _quantity,
                                size: _selectedSize,
                                color: _selectedColor,
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(LucideIcons.shoppingCart),
                    label: Text(
                      'Adicionar R\$ ${(product.priceInReais * _quantity).toStringAsFixed(2)}',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.store, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loja de',
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
