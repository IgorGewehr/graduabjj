import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

/// Product Category
enum StoreProductCategory { uniform, equipment, accessory, other }

extension StoreProductCategoryExtension on StoreProductCategory {
  String get value {
    switch (this) {
      case StoreProductCategory.uniform:
        return 'uniform';
      case StoreProductCategory.equipment:
        return 'equipment';
      case StoreProductCategory.accessory:
        return 'accessory';
      case StoreProductCategory.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case StoreProductCategory.uniform:
        return 'Uniforme';
      case StoreProductCategory.equipment:
        return 'Equipamento';
      case StoreProductCategory.accessory:
        return 'Acessorio';
      case StoreProductCategory.other:
        return 'Outro';
    }
  }

  static StoreProductCategory fromString(String value) {
    switch (value) {
      case 'uniform':
        return StoreProductCategory.uniform;
      case 'equipment':
        return StoreProductCategory.equipment;
      case 'accessory':
        return StoreProductCategory.accessory;
      default:
        return StoreProductCategory.other;
    }
  }
}

/// Stock Type
enum StoreStockType { inStock, onDemand }

extension StoreStockTypeExtension on StoreStockType {
  String get value {
    switch (this) {
      case StoreStockType.inStock:
        return 'in_stock';
      case StoreStockType.onDemand:
        return 'on_demand';
    }
  }

  String get label {
    switch (this) {
      case StoreStockType.inStock:
        return 'Em Estoque';
      case StoreStockType.onDemand:
        return 'Sob Demanda';
    }
  }

  static StoreStockType fromString(String value) {
    return value == 'in_stock' ? StoreStockType.inStock : StoreStockType.onDemand;
  }
}

/// Order Status
enum StoreOrderStatus {
  pendingPayment,
  paid,
  preparing,
  ready,
  delivered,
  cancelled
}

extension StoreOrderStatusExtension on StoreOrderStatus {
  String get value {
    switch (this) {
      case StoreOrderStatus.pendingPayment:
        return 'pending_payment';
      case StoreOrderStatus.paid:
        return 'paid';
      case StoreOrderStatus.preparing:
        return 'preparing';
      case StoreOrderStatus.ready:
        return 'ready';
      case StoreOrderStatus.delivered:
        return 'delivered';
      case StoreOrderStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case StoreOrderStatus.pendingPayment:
        return 'Aguardando Pagamento';
      case StoreOrderStatus.paid:
        return 'Pago';
      case StoreOrderStatus.preparing:
        return 'Preparando';
      case StoreOrderStatus.ready:
        return 'Pronto para Retirada';
      case StoreOrderStatus.delivered:
        return 'Entregue';
      case StoreOrderStatus.cancelled:
        return 'Cancelado';
    }
  }

  static StoreOrderStatus fromString(String value) {
    switch (value) {
      case 'pending_payment':
        return StoreOrderStatus.pendingPayment;
      case 'paid':
        return StoreOrderStatus.paid;
      case 'preparing':
        return StoreOrderStatus.preparing;
      case 'ready':
        return StoreOrderStatus.ready;
      case 'delivered':
        return StoreOrderStatus.delivered;
      case 'cancelled':
        return StoreOrderStatus.cancelled;
      default:
        return StoreOrderStatus.pendingPayment;
    }
  }
}

/// Store Product Model
class StoreProduct {
  final String id;
  final String name;
  final String? description;
  final double price;
  final StoreProductCategory category;
  final List<String> imageUrls;
  final StoreStockType stockType;
  final int? stockQuantity;
  final List<String>? sizes;
  final List<String>? colors;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  StoreProduct({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    required this.category,
    this.imageUrls = const [],
    this.stockType = StoreStockType.inStock,
    this.stockQuantity,
    this.sizes,
    this.colors,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StoreProduct.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StoreProduct(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      price: (data['price'] ?? 0).toDouble(),
      category: StoreProductCategoryExtension.fromString(data['category'] ?? 'other'),
      imageUrls: data['imageUrls'] != null
          ? List<String>.from(data['imageUrls'])
          : [],
      stockType: StoreStockTypeExtension.fromString(data['stockType'] ?? 'in_stock'),
      stockQuantity: data['stockQuantity'],
      sizes: data['sizes'] != null ? List<String>.from(data['sizes']) : null,
      colors: data['colors'] != null ? List<String>.from(data['colors']) : null,
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Computed properties
  bool get isInStock =>
      stockType == StoreStockType.onDemand ||
      (stockQuantity != null && stockQuantity! > 0);
  String get formattedPrice => 'R\$ ${price.toStringAsFixed(2)}';
  String? get mainImageUrl => imageUrls.isNotEmpty ? imageUrls.first : null;
}

/// Store Order Item
class StoreOrderItem {
  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final String? size;
  final String? color;

  StoreOrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.size,
    this.color,
  });

  factory StoreOrderItem.fromMap(Map<String, dynamic> map) {
    return StoreOrderItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      quantity: map['quantity'] ?? 1,
      size: map['size'],
      color: map['color'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'size': size,
      'color': color,
    };
  }

  double get subtotal => price * quantity;
}

/// Store Order Model
class StoreOrder {
  final String id;
  final String studentId;
  final String studentName;
  final List<StoreOrderItem> items;
  final double total;
  final StoreOrderStatus status;
  final String? notes;
  final String? pixCode;
  final String? pixQrCode;
  final String? externalPaymentId;
  final DateTime? paidAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  StoreOrder({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.items,
    required this.total,
    required this.status,
    this.notes,
    this.pixCode,
    this.pixQrCode,
    this.externalPaymentId,
    this.paidAt,
    this.deliveredAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StoreOrder.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StoreOrder(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      items: data['items'] != null
          ? (data['items'] as List)
              .map((item) => StoreOrderItem.fromMap(item))
              .toList()
          : [],
      total: (data['total'] ?? 0).toDouble(),
      status: StoreOrderStatusExtension.fromString(data['status'] ?? 'pending_payment'),
      notes: data['notes'],
      pixCode: data['pixCode'],
      pixQrCode: data['pixQrCode'],
      externalPaymentId: data['externalPaymentId'],
      paidAt: data['paidAt'] != null
          ? (data['paidAt'] as Timestamp).toDate()
          : null,
      deliveredAt: data['deliveredAt'] != null
          ? (data['deliveredAt'] as Timestamp).toDate()
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Computed properties
  int get itemCount => items.fold(0, (acc, item) => acc + item.quantity);
  String get formattedTotal => 'R\$ ${total.toStringAsFixed(2)}';
  bool get isPending => status == StoreOrderStatus.pendingPayment;
  bool get isPaid => status == StoreOrderStatus.paid ||
      status == StoreOrderStatus.preparing ||
      status == StoreOrderStatus.ready ||
      status == StoreOrderStatus.delivered;
}

/// Store Service - Multi-tenant store management
class StoreService {
  final String academyId;
  late final Collections _collections;

  StoreService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _productsRef => _collections.storeProducts;
  CollectionReference get _ordersRef => _collections.storeOrders;

  // ============================================
  // PRODUCTS - READ OPERATIONS
  // ============================================

  /// Get all products
  Future<List<StoreProduct>> getProducts() async {
    final snapshot = await _productsRef.get();
    var products = snapshot.docs.map((doc) => StoreProduct.fromFirestore(doc)).toList();
    products.sort((a, b) => a.name.compareTo(b.name));
    return products;
  }

  /// Get active products only
  Future<List<StoreProduct>> getActiveProducts() async {
    final products = await getProducts();
    return products.where((p) => p.isActive).toList();
  }

  /// Get product by ID
  Future<StoreProduct?> getProductById(String id) async {
    final doc = await _productsRef.doc(id).get();
    if (!doc.exists) return null;
    return StoreProduct.fromFirestore(doc);
  }

  /// Get products by category
  Future<List<StoreProduct>> getProductsByCategory(StoreProductCategory category) async {
    final products = await getActiveProducts();
    return products.where((p) => p.category == category).toList();
  }

  // ============================================
  // PRODUCTS - WRITE OPERATIONS
  // ============================================

  /// Create product
  Future<StoreProduct> createProduct({
    required String name,
    String? description,
    required double price,
    required StoreProductCategory category,
    List<String>? imageUrls,
    StoreStockType stockType = StoreStockType.inStock,
    int? stockQuantity,
    List<String>? sizes,
    List<String>? colors,
  }) async {
    final docRef = await _productsRef.add({
      'name': name,
      'description': description,
      'price': price,
      'category': category.value,
      'imageUrls': imageUrls ?? [],
      'stockType': stockType.value,
      'stockQuantity': stockQuantity,
      'sizes': sizes,
      'colors': colors,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final doc = await docRef.get();
    return StoreProduct.fromFirestore(doc);
  }

  /// Update product
  Future<StoreProduct> updateProduct(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _productsRef.doc(id).update(data);
    final doc = await _productsRef.doc(id).get();
    return StoreProduct.fromFirestore(doc);
  }

  /// Delete product (soft delete)
  Future<void> deleteProduct(String id) async {
    await _productsRef.doc(id).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update stock quantity
  Future<void> updateStock(String id, int quantity) async {
    await _productsRef.doc(id).update({
      'stockQuantity': quantity,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Decrement stock
  Future<void> decrementStock(String id, int amount) async {
    await _productsRef.doc(id).update({
      'stockQuantity': FieldValue.increment(-amount),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // ORDERS - READ OPERATIONS
  // ============================================

  /// Get all orders
  Future<List<StoreOrder>> getOrders() async {
    final snapshot = await _ordersRef.get();
    var orders = snapshot.docs.map((doc) => StoreOrder.fromFirestore(doc)).toList();
    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return orders;
  }

  /// Get orders by status
  Future<List<StoreOrder>> getOrdersByStatus(StoreOrderStatus status) async {
    final orders = await getOrders();
    return orders.where((o) => o.status == status).toList();
  }

  /// Get orders by student
  Future<List<StoreOrder>> getOrdersByStudent(String studentId) async {
    final query = await _ordersRef
        .where('studentId', isEqualTo: studentId)
        .get();
    var orders = query.docs.map((doc) => StoreOrder.fromFirestore(doc)).toList();
    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return orders;
  }

  /// Stream orders by student (Real-time updates)
  Stream<List<StoreOrder>> streamOrdersByStudent(String studentId) {
    return _ordersRef
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
      var orders = snapshot.docs.map((doc) => StoreOrder.fromFirestore(doc)).toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  /// Stream all orders (Real-time updates)
  Stream<List<StoreOrder>> streamOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      var orders = snapshot.docs.map((doc) => StoreOrder.fromFirestore(doc)).toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  /// Stream pending orders (Real-time updates)
  Stream<List<StoreOrder>> streamPendingOrders() {
    return streamOrders().map((orders) {
      return orders.where((o) =>
          o.status == StoreOrderStatus.pendingPayment ||
          o.status == StoreOrderStatus.paid ||
          o.status == StoreOrderStatus.preparing ||
          o.status == StoreOrderStatus.ready
      ).toList();
    });
  }

  /// Get order by ID
  Future<StoreOrder?> getOrderById(String id) async {
    final doc = await _ordersRef.doc(id).get();
    if (!doc.exists) return null;
    return StoreOrder.fromFirestore(doc);
  }

  /// Get pending orders
  Future<List<StoreOrder>> getPendingOrders() async {
    final orders = await getOrders();
    return orders.where((o) =>
        o.status == StoreOrderStatus.pendingPayment ||
        o.status == StoreOrderStatus.paid ||
        o.status == StoreOrderStatus.preparing ||
        o.status == StoreOrderStatus.ready
    ).toList();
  }

  // ============================================
  // ORDERS - WRITE OPERATIONS
  // ============================================

  /// Create order
  Future<StoreOrder> createOrder({
    required String studentId,
    required String studentName,
    required List<StoreOrderItem> items,
    String? notes,
  }) async {
    final total = items.fold<double>(0, (acc, item) => acc + item.subtotal);

    final docRef = await _ordersRef.add({
      'studentId': studentId,
      'studentName': studentName,
      'items': items.map((i) => i.toMap()).toList(),
      'total': total,
      'status': StoreOrderStatus.pendingPayment.value,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final doc = await docRef.get();
    return StoreOrder.fromFirestore(doc);
  }

  /// Update order status
  Future<StoreOrder> updateOrderStatus(String id, StoreOrderStatus status) async {
    final data = <String, dynamic>{
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status == StoreOrderStatus.paid) {
      data['paidAt'] = FieldValue.serverTimestamp();
    } else if (status == StoreOrderStatus.delivered) {
      data['deliveredAt'] = FieldValue.serverTimestamp();
    }

    await _ordersRef.doc(id).update(data);
    final doc = await _ordersRef.doc(id).get();
    return StoreOrder.fromFirestore(doc);
  }

  /// Cancel order
  Future<StoreOrder> cancelOrder(String id) async {
    final order = await getOrderById(id);
    if (order == null) throw Exception('Pedido nao encontrado');

    // If order was not pending payment, restore stock
    if (order.status != StoreOrderStatus.pendingPayment) {
      for (final item in order.items) {
        final product = await getProductById(item.productId);
        if (product != null && product.stockType == StoreStockType.inStock) {
          await updateStock(item.productId, (product.stockQuantity ?? 0) + item.quantity);
        }
      }
    }

    return updateOrderStatus(id, StoreOrderStatus.cancelled);
  }

  /// Mark order as paid
  Future<StoreOrder> markOrderAsPaid(String id, {String? transactionId}) async {
    final order = await getOrderById(id);
    if (order == null) throw Exception('Pedido nao encontrado');

    // Decrement stock for in-stock items
    for (final item in order.items) {
      final product = await getProductById(item.productId);
      if (product != null && product.stockType == StoreStockType.inStock) {
        await decrementStock(item.productId, item.quantity);
      }
    }

    final data = <String, dynamic>{
      'status': StoreOrderStatus.paid.value,
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (transactionId != null) {
      data['externalPaymentId'] = transactionId;
    }

    await _ordersRef.doc(id).update(data);
    final doc = await _ordersRef.doc(id).get();
    return StoreOrder.fromFirestore(doc);
  }

  // ============================================
  // STATS
  // ============================================

  /// Get order stats
  Future<Map<String, dynamic>> getOrderStats() async {
    final orders = await getOrders();

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
  }
}

// ============================================
// Factory Function
// ============================================
StoreService createStoreService(String academyId) {
  return StoreService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
StoreService get storeService => StoreService(FirebaseService.academyId);
