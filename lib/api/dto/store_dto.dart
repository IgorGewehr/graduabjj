// DTOs do contexto Store, alinhados 1:1 com api/openapi/store.yaml.

// ignore_for_file: constant_identifier_names

enum ApiOrderStatus {
  pending_payment,
  paid,
  preparing,
  ready,
  delivered,
  cancelled,
}

extension ApiOrderStatusX on ApiOrderStatus {
  String get wire => name;
  static ApiOrderStatus fromWire(String? value) {
    for (final s in ApiOrderStatus.values) {
      if (s.name == value) return s;
    }
    return ApiOrderStatus.pending_payment;
  }
}

enum ApiStorePaymentMethod { pix, credit_card, boleto, manual }

extension ApiStorePaymentMethodX on ApiStorePaymentMethod {
  String get wire => name;
  static ApiStorePaymentMethod fromWire(String? value) {
    for (final m in ApiStorePaymentMethod.values) {
      if (m.name == value) return m;
    }
    return ApiStorePaymentMethod.manual;
  }
}

class ApiProduct {
  const ApiProduct({
    required this.id,
    required this.academyId,
    required this.name,
    required this.price,
    required this.stockQuantity,
    required this.isActive,
    this.description,
    this.images = const [],
    this.category,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String academyId;
  final String name;
  final String? description;
  final String price;
  final List<String> images;
  final String? category;
  final int stockQuantity;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get outOfStock => stockQuantity == 0;

  factory ApiProduct.fromJson(Map<String, dynamic> j) => ApiProduct(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        price: j['price'] as String,
        images:
            (j['images'] as List?)?.whereType<String>().toList() ?? const [],
        category: j['category'] as String?,
        stockQuantity: (j['stock_quantity'] as num?)?.toInt() ?? 0,
        isActive: j['is_active'] as bool? ?? true,
        createdAt: _parseDate(j['created_at']),
        updatedAt: _parseDate(j['updated_at']),
      );
}

class ProductsPage {
  const ProductsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiProduct> items;
  final String? nextCursor;
  final bool hasMore;

  factory ProductsPage.fromJson(Map<String, dynamic> j) => ProductsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiProduct.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class CreateProductRequest {
  const CreateProductRequest({
    required this.name,
    required this.price,
    this.description,
    this.images,
    this.category,
    this.stockQuantity,
  });

  final String name;
  final String price;
  final String? description;
  final List<String>? images;
  final String? category;
  final int? stockQuantity;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'name': name, 'price': price};
    if (description != null) m['description'] = description;
    if (images != null) m['images'] = images;
    if (category != null) m['category'] = category;
    if (stockQuantity != null) m['stock_quantity'] = stockQuantity;
    return m;
  }
}

class UpdateProductRequest {
  const UpdateProductRequest({
    this.name,
    this.description,
    this.price,
    this.images,
    this.category,
    this.stockQuantity,
    this.isActive,
  });

  final String? name;
  final String? description;
  final String? price;
  final List<String>? images;
  final String? category;
  final int? stockQuantity;
  final bool? isActive;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (name != null) m['name'] = name;
    if (description != null) m['description'] = description;
    if (price != null) m['price'] = price;
    if (images != null) m['images'] = images;
    if (category != null) m['category'] = category;
    if (stockQuantity != null) m['stock_quantity'] = stockQuantity;
    if (isActive != null) m['is_active'] = isActive;
    return m;
  }
}

class ApiOrderItem {
  const ApiOrderItem({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.name,
  });

  final String productId;
  final int quantity;
  final String unitPrice;
  final String name;

  factory ApiOrderItem.fromJson(Map<String, dynamic> j) => ApiOrderItem(
        productId: j['product_id'] as String,
        quantity: (j['quantity'] as num).toInt(),
        unitPrice: j['unit_price'] as String,
        name: j['name'] as String,
      );
}

class ApiOrder {
  const ApiOrder({
    required this.id,
    required this.academyId,
    required this.studentId,
    required this.items,
    required this.total,
    required this.status,
    required this.createdAt,
    this.paymentMethod,
    this.abacatepayTransactionId,
    this.asaasPaymentId,
    this.paidAt,
    this.deliveredAt,
    this.updatedAt,
  });

  final String id;
  final String academyId;
  final String studentId;
  final List<ApiOrderItem> items;
  final String total;
  final ApiOrderStatus status;
  final ApiStorePaymentMethod? paymentMethod;
  final String? abacatepayTransactionId;
  final String? asaasPaymentId;
  final DateTime? paidAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isPaid => status == ApiOrderStatus.paid ||
      status == ApiOrderStatus.preparing ||
      status == ApiOrderStatus.ready ||
      status == ApiOrderStatus.delivered;

  factory ApiOrder.fromJson(Map<String, dynamic> j) => ApiOrder(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        studentId: j['student_id'] as String,
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiOrderItem.fromJson)
            .toList(),
        total: j['total'] as String,
        status: ApiOrderStatusX.fromWire(j['status'] as String?),
        paymentMethod: j['payment_method'] == null
            ? null
            : ApiStorePaymentMethodX.fromWire(j['payment_method'] as String?),
        abacatepayTransactionId: j['abacatepay_transaction_id'] as String?,
        asaasPaymentId: j['asaas_payment_id'] as String?,
        paidAt: _parseDate(j['paid_at']),
        deliveredAt: _parseDate(j['delivered_at']),
        createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
        updatedAt: _parseDate(j['updated_at']),
      );
}

class OrdersPage {
  const OrdersPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiOrder> items;
  final String? nextCursor;
  final bool hasMore;

  factory OrdersPage.fromJson(Map<String, dynamic> j) => OrdersPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiOrder.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class OrderLineRequest {
  const OrderLineRequest({required this.productId, required this.quantity});
  final String productId;
  final int quantity;

  Map<String, dynamic> toJson() =>
      {'product_id': productId, 'quantity': quantity};
}

class CreateOrderRequest {
  const CreateOrderRequest({
    required this.studentId,
    required this.items,
    this.paymentMethod,
  });

  final String studentId;
  final List<OrderLineRequest> items;
  final ApiStorePaymentMethod? paymentMethod;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'student_id': studentId,
      'items': items.map((i) => i.toJson()).toList(),
    };
    if (paymentMethod != null) m['payment_method'] = paymentMethod!.wire;
    return m;
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
