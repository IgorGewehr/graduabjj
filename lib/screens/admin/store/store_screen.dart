import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/store_dto.dart';
import '../../../api/repositories.dart';
import '../../../api/tatami_exception.dart';
import '../../../core/theme.dart';
import '../../../models/user.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/store_provider.dart';
import '../../../services/store_service.dart';
import 'product_card.dart';
import 'product_form_sheet.dart';
import 'store_widgets.dart';

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
    // Loja inteira é admin-only via sidebar, mas o screen pode ser linkado
    // direto. Mantemos a guarda local: CRUD requer store.write.
    final user = ref.watch(currentUserProvider).valueOrNull;
    final canWrite =
        user?.hasPermission(TatamiPermissions.storeWrite) ?? false;

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
                        return StoreStatCard(
                          icon: stat.$1,
                          label: stat.$2,
                          value: stat.$3,
                          color: stat.$4,
                        );
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
                    itemBuilder: (_, __) => const StoreStatCardSkeleton(),
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
                          StoreCategoryFilterChip(
                            label: 'Todos',
                            isSelected: _categoryFilter == null,
                            onTap: () => setState(() => _categoryFilter = null),
                          ),
                          ...StoreProductCategory.values.map(
                            (cat) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: StoreCategoryFilterChip(
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
                    child: StoreEmptyState(onAdd: () => _showProductForm()),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ProductCard(
                          product: filtered[index],
                          // Sem store.write os cards viram read-only:
                          // toque abre apenas detalhes (form não), e o
                          // menu de toggle/delete some.
                          onTap: canWrite
                              ? () => _showProductForm(product: filtered[index])
                              : () {},
                          onToggleActive: canWrite
                              ? () => _toggleProductActive(filtered[index])
                              : null,
                          onDelete: canWrite
                              ? () => _deleteProduct(filtered[index])
                              : null,
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
                      child: ProductCardSkeleton(),
                    ),
                    childCount: 4,
                  ),
                ),
              ),
              error: (error, _) {
                final isStoreDisabled = error is TatamiException &&
                    error.isForbidden &&
                    (error.detail?.contains('store') == true ||
                        error.detail?.contains('not enabled') == true);
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isStoreDisabled
                              ? LucideIcons.shoppingBag
                              : LucideIcons.alertCircle,
                          size: 48,
                          color: isStoreDisabled
                              ? AppTheme.textSecondary
                              : AppTheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isStoreDisabled
                              ? 'Loja não habilitada'
                              : 'Erro ao carregar produtos',
                          style: AppTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (isStoreDisabled)
                          Text(
                            'A loja não está ativada para esta academia.',
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          )
                        else
                          TextButton(
                            onPressed: () => ref.invalidate(productsProvider),
                            child: const Text('Tentar novamente'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _showProductForm(),
              icon: const Icon(LucideIcons.plus),
              label: const Text('Novo Produto'),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  void _showProductForm({StoreProduct? product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductFormSheet(
        product: product,
        onSave: (data) async {
          final currentUser = ref.read(currentUserProvider).valueOrNull;
          if (currentUser?.academyId == null) return;
          final academyId = currentUser!.academyId!;
          final repo = ref.read(storeRepoProvider);

          if (product != null) {
            // UPDATE — build UpdateProductRequest from form data map.
            // price comes as double from the form; tatami expects a decimal
            // string (e.g. "79.90").
            final rawPrice = data['price'];
            final String? priceStr = rawPrice != null
                ? (rawPrice is double
                    ? rawPrice.toStringAsFixed(2)
                    : rawPrice.toString())
                : null;
            final req = UpdateProductRequest(
              name: data['name'] as String?,
              description: data['description'] as String?,
              price: priceStr,
              images: data['images'] != null
                  ? List<String>.from(data['images'] as List)
                  : null,
              category: data['category'] as String?,
              stockQuantity: data['stockQuantity'] as int?,
              isActive: data['active'] as bool?,
            );
            await repo.updateProduct(academyId, product.id, req);
          } else {
            // CREATE — build CreateProductRequest from form data map.
            final rawPrice = data['price'];
            final String priceStr = rawPrice is double
                ? rawPrice.toStringAsFixed(2)
                : rawPrice.toString();
            final req = CreateProductRequest(
              name: data['name'] as String,
              price: priceStr,
              description: data['description'] as String?,
              images: data['images'] != null
                  ? List<String>.from(data['images'] as List)
                  : null,
              category: data['category'] as String?,
              stockQuantity: data['stockQuantity'] as int?,
            );
            await repo.createProduct(academyId, req);
          }
          ref.invalidate(productsProvider);
        },
      ),
    );
  }

  Future<void> _toggleProductActive(StoreProduct product) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;
    final req = UpdateProductRequest(isActive: !product.isActive);
    await ref
        .read(storeRepoProvider)
        .updateProduct(currentUser!.academyId!, product.id, req);
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
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;
      await ref
          .read(storeRepoProvider)
          .deleteProduct(currentUser!.academyId!, product.id);
      ref.invalidate(productsProvider);
    }
  }
}
