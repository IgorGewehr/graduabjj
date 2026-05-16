import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/store_dto.dart';
import 'package:graduabjj/api/idempotency.dart';
import 'package:graduabjj/api/store_repo.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late StoreRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = StoreRemoteRepo(client);
  });

  Map<String, dynamic> productJson({
    String id = 'p-1',
    int stock = 10,
    bool active = true,
  }) =>
      {
        'id': id,
        'academy_id': 'aid',
        'name': 'Kimono Branco',
        'price': '450.00',
        'stock_quantity': stock,
        'is_active': active,
        'images': ['https://e.com/k.jpg'],
      };

  group('products', () {
    test('list paginado', () async {
      adapter.onGet(
        '/v1/academies/aid/store/products',
        (s) => s.reply(200, {
          'items': [productJson()],
          'next_cursor': 'cur',
          'has_more': true,
        }),
        queryParameters: {'limit': 50, 'active_only': true},
      );
      final page = await repo.listProducts('aid', activeOnly: true);
      expect(page.items, hasLength(1));
      expect(page.items.first.outOfStock, isFalse);
    });

    test('out-of-stock helper', () async {
      adapter.onGet(
        '/v1/academies/aid/store/products/p-1',
        (s) => s.reply(200, productJson(stock: 0)),
      );
      final p = await repo.getProduct('aid', 'p-1');
      expect(p.outOfStock, isTrue);
    });

    test('create com idempotency-key', () async {
      adapter.onPost(
        '/v1/academies/aid/store/products',
        (s) => s.reply(201, productJson(id: 'p-new')),
        data: {
          'name': 'Kimono Branco',
          'price': '450.00',
          'stock_quantity': 10,
        },
      );
      final p = await repo.createProduct(
        'aid',
        const CreateProductRequest(
          name: 'Kimono Branco',
          price: '450.00',
          stockQuantity: 10,
        ),
        idempotencyKey: IdempotencyKey.fromString(
            'ffffffff-ffff-4fff-8fff-ffffffffffff'),
      );
      expect(p.id, 'p-new');
    });

    test('update PATCH parcial', () async {
      adapter.onPatch(
        '/v1/academies/aid/store/products/p-1',
        (s) => s.reply(200, {...productJson(), 'stock_quantity': 5}),
        data: {'stock_quantity': 5},
      );
      final p = await repo.updateProduct(
        'aid',
        'p-1',
        const UpdateProductRequest(stockQuantity: 5),
      );
      expect(p.stockQuantity, 5);
    });

    test('delete 204', () async {
      adapter.onDelete(
        '/v1/academies/aid/store/products/p-1',
        (s) => s.reply(204, null),
      );
      await repo.deleteProduct('aid', 'p-1');
    });
  });

  group('orders', () {
    Map<String, dynamic> orderJson({
      String id = 'o-1',
      String status = 'pending_payment',
    }) =>
        {
          'id': id,
          'academy_id': 'aid',
          'student_id': 's-1',
          'items': [
            {
              'product_id': 'p-1',
              'quantity': 1,
              'unit_price': '450.00',
              'name': 'Kimono Branco',
            },
          ],
          'total': '450.00',
          'status': status,
          'created_at': '2026-05-16T10:00:00Z',
        };

    test('list filtra por status', () async {
      adapter.onGet(
        '/v1/academies/aid/store/orders',
        (s) => s.reply(200, {
          'items': [orderJson(status: 'paid')],
          'has_more': false,
        }),
        queryParameters: {'limit': 50, 'status': 'paid'},
      );
      final page = await repo.listOrders(
        'aid',
        status: ApiOrderStatus.paid,
      );
      expect(page.items, hasLength(1));
      expect(page.items.first.isPaid, isTrue);
    });

    test('create com decremento atômico server-side', () async {
      adapter.onPost(
        '/v1/academies/aid/store/orders',
        (s) => s.reply(201, orderJson(id: 'o-new')),
        data: {
          'student_id': 's-1',
          'items': [
            {'product_id': 'p-1', 'quantity': 1},
          ],
        },
      );
      final o = await repo.createOrder(
        'aid',
        const CreateOrderRequest(
          studentId: 's-1',
          items: [OrderLineRequest(productId: 'p-1', quantity: 1)],
        ),
        idempotencyKey: IdempotencyKey.fromString(
            '00000000-1111-4111-8111-000000000001'),
      );
      expect(o.id, 'o-new');
      expect(o.items, hasLength(1));
    });

    test('create 409 out-of-stock (race com outro cliente)', () async {
      adapter.onPost(
        '/v1/academies/aid/store/orders',
        (s) => s.reply(409, {
          'type': 'https://tatami.dev/errors/out-of-stock',
          'title': 'Product out of stock',
          'status': 409,
          'detail': 'p-1 has 0 units remaining',
        }),
        data: {
          'student_id': 's-1',
          'items': [
            {'product_id': 'p-1', 'quantity': 1},
          ],
        },
      );
      try {
        await repo.createOrder(
          'aid',
          const CreateOrderRequest(
            studentId: 's-1',
            items: [OrderLineRequest(productId: 'p-1', quantity: 1)],
          ),
          idempotencyKey: IdempotencyKey.fromString(
              '00000000-1111-4111-8111-000000000002'),
        );
        fail('expected 409');
      } on DioException catch (e) {
        final t = e.error as TatamiException;
        expect(t.isConflict, isTrue);
        expect(t.type, contains('out-of-stock'));
      }
    });

    test('updateOrderStatus transição válida', () async {
      adapter.onPatch(
        '/v1/academies/aid/store/orders/o-1',
        (s) => s.reply(200, orderJson(status: 'preparing')),
        data: {'status': 'preparing'},
      );
      final o = await repo.updateOrderStatus(
        'aid',
        'o-1',
        ApiOrderStatus.preparing,
      );
      expect(o.status, ApiOrderStatus.preparing);
    });

    test('422 transição inválida', () async {
      adapter.onPatch(
        '/v1/academies/aid/store/orders/o-1',
        (s) => s.reply(422, {
          'type': 'https://tatami.dev/errors/validation',
          'title': 'Invalid status transition',
          'status': 422,
          'errors': [
            {
              'field': 'status',
              'message': 'cannot go from delivered → pending_payment',
            },
          ],
        }),
        data: {'status': 'pending_payment'},
      );
      try {
        await repo.updateOrderStatus(
          'aid',
          'o-1',
          ApiOrderStatus.pending_payment,
        );
        fail('expected 422');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isValidation, isTrue);
      }
    });
  });
}
