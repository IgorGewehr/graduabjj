import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/store_service.dart';
import '../services/firebase_service.dart';

/// Store Service Provider
final storeServiceProvider = Provider<StoreService>((ref) {
  return StoreService(FirebaseService.academyId);
});

/// Products Provider
final productsProvider = FutureProvider<List<StoreProduct>>((ref) async {
  final service = ref.watch(storeServiceProvider);
  return service.getProducts();
});

/// Active Products Provider (for portal)
final activeProductsProvider = FutureProvider<List<StoreProduct>>((ref) async {
  final service = ref.watch(storeServiceProvider);
  return service.getActiveProducts();
});

/// Orders Provider
final ordersProvider = FutureProvider<List<StoreOrder>>((ref) async {
  final service = ref.watch(storeServiceProvider);
  return service.getOrders();
});

/// Student Orders Provider
final studentOrdersProvider = FutureProvider.family<List<StoreOrder>, String>((ref, studentId) async {
  final service = ref.watch(storeServiceProvider);
  return service.getOrdersByStudent(studentId);
});

/// Pending Orders Provider
final pendingOrdersProvider = FutureProvider<List<StoreOrder>>((ref) async {
  final service = ref.watch(storeServiceProvider);
  return service.getPendingOrders();
});

/// Store Stats Provider
final storeStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(storeServiceProvider);
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

  double get total => state.fold(0, (sum, item) => sum + item.subtotal);
  int get itemCount => state.fold(0, (sum, item) => sum + item.quantity);
}

/// Cart Provider
final cartProvider = StateNotifierProvider<CartNotifier, List<StoreOrderItem>>((ref) {
  return CartNotifier();
});
