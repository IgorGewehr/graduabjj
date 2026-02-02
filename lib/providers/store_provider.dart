import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/store_service.dart';
import 'auth_provider.dart';

/// Store Service Provider - uses current user's academyId for multi-tenant support
final storeServiceProvider = Provider<StoreService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;

  if (currentUser?.academyId == null) return null;

  return StoreService(currentUser!.academyId!);
});

/// Products Provider
final productsProvider = FutureProvider<List<StoreProduct>>((ref) async {
  final service = ref.watch(storeServiceProvider);
  if (service == null) return [];
  return service.getProducts();
});

/// Active Products Provider (for portal)
final activeProductsProvider = FutureProvider<List<StoreProduct>>((ref) async {
  final service = ref.watch(storeServiceProvider);
  if (service == null) return [];
  return service.getActiveProducts();
});

/// Orders Provider (Real-time Stream)
final ordersProvider = StreamProvider<List<StoreOrder>>((ref) {
  final service = ref.watch(storeServiceProvider);
  if (service == null) return const Stream.empty();
  return service.streamOrders();
});

/// Student Orders Provider (Real-time Stream)
final studentOrdersProvider = StreamProvider.family<List<StoreOrder>, String>((ref, studentId) {
  final service = ref.watch(storeServiceProvider);
  if (service == null) return const Stream.empty();
  return service.streamOrdersByStudent(studentId);
});

/// Pending Orders Provider (Real-time Stream)
final pendingOrdersProvider = StreamProvider<List<StoreOrder>>((ref) {
  final service = ref.watch(storeServiceProvider);
  if (service == null) return const Stream.empty();
  return service.streamPendingOrders();
});

/// Store Stats Provider
final storeStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(storeServiceProvider);
  if (service == null) return {};
  return service.getOrderStats();
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
