import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/store_service.dart';
import '../../../widgets/cached_image.dart';

/// Product Details Bottom Sheet
class ProductDetailsSheet extends StatefulWidget {
  final StoreProduct product;
  final void Function(StoreOrderItem) onAddToCart;

  const ProductDetailsSheet({
    super.key,
    required this.product,
    required this.onAddToCart,
  });

  @override
  State<ProductDetailsSheet> createState() => _ProductDetailsSheetState();
}

class _ProductDetailsSheetState extends State<ProductDetailsSheet> {
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
                                          _selectedSize =
                                              selected ? size : null;
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
                                          _selectedColor =
                                              selected ? color : null;
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
