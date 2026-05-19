import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/repositories.dart';
import '../services/store_service.dart';
import 'auth_provider.dart';

/// Products Provider — reads from Tatami REST via [storeRepoProvider].
final productsProvider = FutureProvider<List<StoreProduct>>((ref) async {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return [];
  final page = await ref
      .watch(storeRepoProvider)
      .listProducts(currentUser!.academyId!);
  return page.items.map(StoreProduct.fromApi).toList();
});

/// Active Products Provider (for portal) — reads from Tatami REST via
/// [storeRepoProvider] with [activeOnly] filter pushed to the server.
final activeProductsProvider = FutureProvider<List<StoreProduct>>((ref) async {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return [];
  final page = await ref
      .watch(storeRepoProvider)
      .listProducts(currentUser!.academyId!, activeOnly: true);
  return page.items.map(StoreProduct.fromApi).toList();
});

/// Orders Provider — reads from Tatami REST via [storeRepoProvider].
/// Pull-to-refresh via `ref.invalidate(ordersProvider)`.
final ordersProvider = FutureProvider<List<StoreOrder>>((ref) async {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return [];
  final page = await ref
      .watch(storeRepoProvider)
      .listOrders(currentUser!.academyId!);
  return page.items.map(StoreOrder.fromApi).toList();
});

/// Student Orders Provider — filtered by studentId via Tatami REST.
/// Pull-to-refresh via `ref.invalidate(studentOrdersProvider(studentId))`.
final studentOrdersProvider =
    FutureProvider.family<List<StoreOrder>, String>((ref, studentId) async {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return [];
  final page = await ref
      .watch(storeRepoProvider)
      .listOrders(currentUser!.academyId!, studentId: studentId);
  return page.items.map(StoreOrder.fromApi).toList();
});

/// Pending Orders Provider — filters active orders client-side from
/// [ordersProvider] (pending_payment, paid, preparing, ready).
final pendingOrdersProvider = FutureProvider<List<StoreOrder>>((ref) async {
  final orders = await ref.watch(ordersProvider.future);
  return orders
      .where((o) =>
          o.status == StoreOrderStatus.pendingPayment ||
          o.status == StoreOrderStatus.paid ||
          o.status == StoreOrderStatus.preparing ||
          o.status == StoreOrderStatus.ready)
      .toList();
});

/// Store Stats Provider — derived from Tatami orders list.
final storeStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final orders = await ref.watch(ordersProvider.future);

  int pendingCount = 0;
  int paidCount = 0;
  int preparingCount = 0;
  int readyCount = 0;
  int deliveredCount = 0;
  double totalRevenue = 0;

  for (final order in orders) {
    switch (order.status) {
      case StoreOrderStatus.pendingPayment:
        pendingCount++;
        break;
      case StoreOrderStatus.paid:
        paidCount++;
        totalRevenue += order.total;
        break;
      case StoreOrderStatus.preparing:
        preparingCount++;
        totalRevenue += order.total;
        break;
      case StoreOrderStatus.ready:
        readyCount++;
        totalRevenue += order.total;
        break;
      case StoreOrderStatus.delivered:
        deliveredCount++;
        totalRevenue += order.total;
        break;
      case StoreOrderStatus.cancelled:
        break;
    }
  }

  return {
    'pending': pendingCount,
    'paid': paidCount,
    'preparing': preparingCount,
    'ready': readyCount,
    'delivered': deliveredCount,
    'totalOrders': orders.length,
    'totalRevenue': totalRevenue,
  };
});

/// Cart State Notifier
class CartNotifier extends StateNotifier<List<StoreOrderItem>> {
  CartNotifier() : super([]);

  void addItem(StoreOrderItem item) {
    // Check if item with same product, size, and color exists
    final existingIndex = state.indexWhere((i) =>
        i.productId == item.productId &&
        i.size == item.size &&
        i.color == item.color);

    if (existingIndex >= 0) {
      // Update quantity
      state = [
        ...state.sublist(0, existingIndex),
        StoreOrderItem(
          productId: item.productId,
          productName: item.productName,
          price: item.price,
          quantity: state[existingIndex].quantity + item.quantity,
          size: item.size,
          color: item.color,
        ),
        ...state.sublist(existingIndex + 1),
      ];
    } else {
      state = [...state, item];
    }
  }

  void updateQuantity(int index, int quantity) {
    if (quantity <= 0) {
      removeItem(index);
      return;
    }
    state = [
      ...state.sublist(0, index),
      StoreOrderItem(
        productId: state[index].productId,
        productName: state[index].productName,
        price: state[index].price,
        quantity: quantity,
        size: state[index].size,
        color: state[index].color,
      ),
      ...state.sublist(index + 1),
    ];
  }

  void removeItem(int index) {
    state = [...state.sublist(0, index), ...state.sublist(index + 1)];
  }

  void clear() {
    state = [];
  }

  /// Total in Reais
  double get total => state.fold(0, (sum, item) => sum + item.subtotal);

  /// Total in Reais
  double get totalInReais => total;

  /// Formatted total in Reais
  String get formattedTotal => 'R\$ ${total.toStringAsFixed(2)}';

  int get itemCount => state.fold(0, (sum, item) => sum + item.quantity);
}

/// Cart Provider
final cartProvider = StateNotifierProvider<CartNotifier, List<StoreOrderItem>>((ref) {
  return CartNotifier();
});
