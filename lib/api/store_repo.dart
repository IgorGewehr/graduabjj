import 'dto/store_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Store.
///
/// Endpoints: `/v1/academies/{id}/store/products*` + `/orders*`. O backend
/// faz o decremento atômico do estoque dentro da transação que cria o
/// order — race com 2 clientes comprando o último item retorna 409 para
/// o segundo (vide doc 06 §Fase 7).
class StoreRemoteRepo {
  StoreRemoteRepo(this._api);

  final TatamiClient _api;

  Future<ProductsPage> listProducts(
    String academyId, {
    int limit = 50,
    String? cursor,
    bool? activeOnly,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    if (activeOnly != null) params['active_only'] = activeOnly;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/store/products',
      queryParameters: params,
    );
    return ProductsPage.fromJson(json);
  }

  Future<ApiProduct> getProduct(String academyId, String productId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/store/products/$productId',
    );
    return ApiProduct.fromJson(json);
  }

  Future<ApiProduct> createProduct(
    String academyId,
    CreateProductRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/store/products',
      data: req.toJson(),
      key: key,
    );
    return ApiProduct.fromJson(json);
  }

  Future<ApiProduct> updateProduct(
    String academyId,
    String productId,
    UpdateProductRequest req,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/store/products/$productId',
      data: req.toJson(),
    );
    return ApiProduct.fromJson(json);
  }

  Future<void> deleteProduct(String academyId, String productId) async {
    await _api.delete('/v1/academies/$academyId/store/products/$productId');
  }

  Future<OrdersPage> listOrders(
    String academyId, {
    ApiOrderStatus? status,
    String? studentId,
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (status != null) params['status'] = status.wire;
    if (studentId != null) params['student_id'] = studentId;
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/store/orders',
      queryParameters: params,
    );
    return OrdersPage.fromJson(json);
  }

  Future<ApiOrder> getOrder(String academyId, String orderId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/store/orders/$orderId',
    );
    return ApiOrder.fromJson(json);
  }

  /// Idempotente — passe o mesmo Idempotency-Key em retries pra evitar
  /// duplicar pedido. Race de estoque: se 2 clientes comprarem o último
  /// item simultaneamente, um sucesso, outro 409 (out-of-stock).
  Future<ApiOrder> createOrder(
    String academyId,
    CreateOrderRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/store/orders',
      data: req.toJson(),
      key: key,
    );
    return ApiOrder.fromJson(json);
  }

  /// Transições de status do pedido (paid → preparing → ready → delivered,
  /// ou cancelled). Backend valida transições inválidas (422).
  Future<ApiOrder> updateOrderStatus(
    String academyId,
    String orderId,
    ApiOrderStatus newStatus,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/store/orders/$orderId',
      data: {'status': newStatus.wire},
    );
    return ApiOrder.fromJson(json);
  }
}
