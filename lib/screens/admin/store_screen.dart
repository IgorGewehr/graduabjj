import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../services/services.dart';
import '../../services/store_service.dart';
import '../../providers/store_provider.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

/// Admin Store Screen - Product Management
class AdminStoreScreen extends ConsumerStatefulWidget {
  const AdminStoreScreen({super.key});

  @override
  ConsumerState<AdminStoreScreen> createState() => _AdminStoreScreenState();
}

class _AdminStoreScreenState extends ConsumerState<AdminStoreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  StoreProductCategory? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final statsAsync = ref.watch(storeStatsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(productsProvider);
          ref.invalidate(storeStatsProvider);
        },
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${productsAsync.valueOrNull?.length ?? 0} produtos',
                        style: AppTheme.labelMedium.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => context.push('/admin/loja/pedidos'),
                      icon: const Icon(LucideIcons.shoppingCart, size: 18),
                      label: const Text('Pedidos'),
                    ),
                  ],
                ),
              ),
            ),

            // Stats Cards (Carousel)
            SliverToBoxAdapter(
              child: statsAsync.when(
                data: (stats) {
                  final statsList = [
                    (
                      LucideIcons.package,
                      'Produtos',
                      productsAsync.valueOrNull?.length.toString() ?? '0',
                      AppTheme.primary,
                    ),
                    (
                      LucideIcons.clock,
                      'Pendentes',
                      '${stats['pending'] ?? 0}',
                      Colors.orange,
                    ),
                    (
                      LucideIcons.dollarSign,
                      'Receita',
                      'R\$ ${((stats['totalRevenue'] ?? 0) as double).toStringAsFixed(0)}',
                      Colors.green,
                    ),
                  ];
                  return SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: statsList.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final stat = statsList[index];
                        return _StatCard(
                          icon: stat.$1,
                          label: stat.$2,
                          value: stat.$3,
                          color: stat.$4,
                        ).entrance(index: index);
                      },
                    ),
                  );
                },
                loading: () => SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: 3,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, __) =>
                        PolishSkeleton.shimmer(child: const _StatCardSkeleton()),
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
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    // Category Filters
                    SingleChildScrollView(
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
                                onTap: () =>
                                    setState(() => _categoryFilter = cat),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Products List
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
                    child: _EmptyState(onAdd: () => _showProductForm()),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ProductCard(
                          product: filtered[index],
                          onTap: () =>
                              _showProductForm(product: filtered[index]),
                          onToggleActive: () =>
                              _toggleProductActive(filtered[index]),
                          onDelete: () => _deleteProduct(filtered[index]),
                        ).entrance(index: index),
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
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: PolishSkeleton.shimmer(
                        child: const _ProductCardSkeleton(),
                      ),
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
                        onPressed: () => ref.invalidate(productsProvider),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductForm(),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Novo Produto'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _showProductForm({StoreProduct? product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProductFormSheet(
        product: product,
        onSave: (data) async {
          final service = ref.read(storeServiceProvider);
          if (service == null) return;
          if (product != null) {
            await service.updateProduct(product.id, data);
          } else {
            await service.createProduct(
              name: data['name'],
              description: data['description'],
              price: data['price'],
              category: StoreProductCategoryExtension.fromString(
                data['category'],
              ),
              imageUrls: data['images'],
              stockType: StoreStockTypeExtension.fromString(data['stockType']),
              stockQuantity: data['stockQuantity'],
              sizes: data['sizes'],
              colors: data['colors'],
            );
          }
          ref.invalidate(productsProvider);
        },
      ),
    );
  }

  Future<void> _toggleProductActive(StoreProduct product) async {
    final service = ref.read(storeServiceProvider);
    if (service == null) return;
    await service.updateProduct(product.id, {'active': !product.isActive});
    ref.invalidate(productsProvider);
  }

  Future<void> _deleteProduct(StoreProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Produto'),
        content: Text('Deseja excluir "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final service = ref.read(storeServiceProvider);
      if (service == null) return;
      await service.deleteProduct(product.id);
      ref.invalidate(productsProvider);
    }
  }
}

/// Stats Card Widget for carousel
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 64) / 3;

    return Container(
      width: cardWidth.clamp(100.0, 140.0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 64) / 3;

    return Container(
      width: cardWidth.clamp(100.0, 140.0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 50,
                  height: 10,
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
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Product Image
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: product.mainImageUrl != null
                    ? AppCachedImage(
                        imageUrl: product.mainImageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorIcon: const Icon(
                          LucideIcons.package,
                          color: AppTheme.textSecondary,
                        ),
                      )
                    : const Icon(
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!product.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.errorLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Inativo',
                              style: AppTheme.labelSmall.copyWith(
                                color: AppTheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.formattedPrice,
                      style: AppTheme.titleSmall.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            product.category.label,
                            style: AppTheme.labelSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (product.stockType == StoreStockType.inStock)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: product.isInStock
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : AppTheme.errorLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${product.stockQuantity ?? 0} un.',
                              style: AppTheme.labelSmall.copyWith(
                                color: product.isInStock
                                    ? Colors.green
                                    : AppTheme.error,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Sob demanda',
                              style: AppTheme.labelSmall.copyWith(
                                color: Colors.blue,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 20),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onTap();
                      break;
                    case 'toggle':
                      onToggleActive();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(LucideIcons.edit, size: 18),
                        SizedBox(width: 12),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          product.isActive
                              ? LucideIcons.eyeOff
                              : LucideIcons.eye,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Text(product.isActive ? 'Desativar' : 'Ativar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.trash2,
                          size: 18,
                          color: AppTheme.error,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Excluir',
                          style: TextStyle(color: AppTheme.error),
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
    );
  }
}

class _ProductCardSkeleton extends StatelessWidget {
  const _ProductCardSkeleton();

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
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 40,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty State Widget
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return PolishedEmptyState(
      icon: LucideIcons.package,
      title: 'Nenhum produto cadastrado',
      subtitle: 'Adicione produtos para sua loja',
      actionLabel: 'Adicionar Produto',
      onAction: onAdd,
      accent: AppTheme.textSecondary,
    );
  }
}

/// Product Form Bottom Sheet
class _ProductFormSheet extends StatefulWidget {
  final StoreProduct? product;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _ProductFormSheet({this.product, required this.onSave});

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;
  late TextEditingController _sizesController;
  late TextEditingController _colorsController;

  StoreProductCategory _category = StoreProductCategory.other;
  StoreStockType _stockType = StoreStockType.inStock;
  bool _isLoading = false;
  bool _isUploadingImage = false;
  List<String> _imageUrls = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name);
    _descriptionController = TextEditingController(
      text: widget.product?.description,
    );
    _priceController = TextEditingController(
      text: widget.product?.price.toStringAsFixed(2),
    );
    _stockController = TextEditingController(
      text: widget.product?.stockQuantity?.toString(),
    );
    _sizesController = TextEditingController(
      text: widget.product?.sizes?.join(', '),
    );
    _colorsController = TextEditingController(
      text: widget.product?.colors?.join(', '),
    );

    if (widget.product != null) {
      _category = widget.product!.category;
      _stockType = widget.product!.stockType;
      _imageUrls = List<String>.from(widget.product!.imageUrls);
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Crop to 1:1 aspect ratio
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recortar Imagem',
            toolbarColor: AppTheme.textPrimary,
            toolbarWidgetColor: Colors.white,
            statusBarColor: AppTheme.textPrimary,
            backgroundColor: AppTheme.background,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: true,
            showCropGrid: true,
          ),
          IOSUiSettings(
            title: 'Recortar Imagem',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
            minimumAspectRatio: 1.0,
          ),
        ],
      );

      if (croppedFile == null) return;

      setState(() => _isUploadingImage = true);

      // Upload to Firebase Storage
      final file = File(croppedFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('academies')
          .child(FirebaseService.academyId)
          .child('products')
          .child('product_$timestamp.jpg');

      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      setState(() {
        _imageUrls.add(downloadUrl);
        _isUploadingImage = false;
      });
    } catch (e) {
      setState(() => _isUploadingImage = false);
      if (mounted) {
        context.showError('Erro ao fazer upload: $e');
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageUrls.removeAt(index);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _sizesController.dispose();
    _colorsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final sizes = _sizesController.text.isNotEmpty
          ? _sizesController.text.split(',').map((s) => s.trim()).toList()
          : <String>[];
      final colors = _colorsController.text.isNotEmpty
          ? _colorsController.text.split(',').map((s) => s.trim()).toList()
          : <String>[];

      final data = {
        'name': _nameController.text,
        'description': _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        'price': double.parse(_priceController.text.replaceAll(',', '.')),
        'category': _category.value,
        'stockType': _stockType.value,
        'stockQuantity': _stockType == StoreStockType.inStock
            ? int.tryParse(_stockController.text) ?? 0
            : null,
        'sizes': sizes.isEmpty ? null : sizes,
        'colors': colors.isEmpty ? null : colors,
        'images': _imageUrls,
      };

      await widget.onSave(data);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao salvar: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
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
                    child: Text(
                      widget.product != null
                          ? 'Editar Produto'
                          : 'Novo Produto',
                      style: AppTheme.headlineSmall,
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
            // Form
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Images Section
                      Text('Fotos do Produto', style: AppTheme.labelMedium),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 100,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            // Existing images
                            ..._imageUrls.asMap().entries.map((entry) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppTheme.divider,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: AppCachedImage(
                                        imageUrl: entry.value,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        errorIcon: const Icon(
                                          LucideIcons.imageOff,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => _removeImage(entry.key),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: AppTheme.error,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            LucideIcons.x,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (entry.key == 0)
                                      Positioned(
                                        bottom: 4,
                                        left: 4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Principal',
                                            style: AppTheme.labelSmall.copyWith(
                                              color: Colors.white,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                            // Add button
                            GestureDetector(
                              onTap: _isUploadingImage
                                  ? null
                                  : _pickAndUploadImage,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceVariant,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.divider,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: _isUploadingImage
                                    ? const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            LucideIcons.imagePlus,
                                            color: AppTheme.textSecondary,
                                            size: 24,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Adicionar',
                                            style: AppTheme.labelSmall.copyWith(
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Name
                      _ModernTextField(
                        controller: _nameController,
                        label: 'Nome do Produto',
                        validator: (v) =>
                            v?.isEmpty == true ? 'Campo obrigatorio' : null,
                      ),
                      const SizedBox(height: 16),
                      // Description
                      _ModernTextField(
                        controller: _descriptionController,
                        label: 'Descricao (opcional)',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      // Price
                      _ModernTextField(
                        controller: _priceController,
                        label: 'Preco (R\$)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v?.isEmpty == true) return 'Campo obrigatorio';
                          if (double.tryParse(v!.replaceAll(',', '.')) ==
                              null) {
                            return 'Valor invalido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Category
                      Text('Categoria', style: AppTheme.labelMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: StoreProductCategory.values.map((cat) {
                          return ChoiceChip(
                            label: Text(cat.label),
                            selected: _category == cat,
                            onSelected: (selected) {
                              if (selected) setState(() => _category = cat);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // Stock Type
                      Text('Tipo de Estoque', style: AppTheme.labelMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: StoreStockType.values.map((type) {
                          return ChoiceChip(
                            label: Text(type.label),
                            selected: _stockType == type,
                            onSelected: (selected) {
                              if (selected) setState(() => _stockType = type);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // Stock Quantity
                      if (_stockType == StoreStockType.inStock)
                        _ModernTextField(
                          controller: _stockController,
                          label: 'Quantidade em Estoque',
                          keyboardType: TextInputType.number,
                        ),
                      const SizedBox(height: 16),
                      // Sizes
                      _ModernTextField(
                        controller: _sizesController,
                        label: 'Tamanhos (separados por virgula)',
                        hint: 'Ex: P, M, G, GG',
                      ),
                      const SizedBox(height: 16),
                      // Colors
                      _ModernTextField(
                        controller: _colorsController,
                        label: 'Cores (separadas por virgula)',
                        hint: 'Ex: Branco, Azul, Preto',
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.product != null ? 'Salvar' : 'Criar Produto',
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

/// Modern Text Field
class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _ModernTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.labelMedium),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppTheme.surfaceVariant.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.error),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }
}
