import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/financial_dto.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/wallet_repo.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late WalletRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = WalletRemoteRepo(client);
  });

  test('get wallet retorna balance decimal-string', () async {
    adapter.onGet(
      '/v1/academies/aid/wallet',
      (s) => s.reply(200, {
        'academy_id': 'aid',
        'balance': '12345.67',
        'last_updated_at': '2026-05-16T10:00:00Z',
      }),
    );
    final w = await repo.get('aid');
    expect(w.balance, '12345.67');
  });

  group('listTransactions', () {
    test('parses credit + debit + financial_id link', () async {
      adapter.onGet(
        '/v1/academies/aid/wallet/transactions',
        (s) => s.reply(200, {
          'items': [
            {
              'id': 'tx-1',
              'academy_id': 'aid',
              'financial_id': 'f-1',
              'external_id': 'asaas-123',
              'kind': 'credit',
              'amount': '200.00',
              'description': 'Mensalidade João - 2026-05',
              'created_at': '2026-05-10T15:00:00Z',
            },
            {
              'id': 'tx-2',
              'academy_id': 'aid',
              'kind': 'payout',
              'amount': '-1000.00',
              'created_at': '2026-05-11T09:00:00Z',
            },
          ],
          'next_cursor': 'cur-2',
          'has_more': true,
        }),
        queryParameters: {'limit': 50},
      );
      final page = await repo.listTransactions('aid');
      expect(page.items, hasLength(2));
      expect(page.items.first.kind, ApiWalletTxnKind.credit);
      expect(page.items.first.financialId, 'f-1');
      expect(page.items[1].kind, ApiWalletTxnKind.payout);
      expect(page.items[1].financialId, isNull);
      expect(page.nextCursor, 'cur-2');
    });

    test('filtra por kind=refund', () async {
      adapter.onGet(
        '/v1/academies/aid/wallet/transactions',
        (s) => s.reply(200, {'items': [], 'has_more': false}),
        queryParameters: {'limit': 25, 'kind': 'refund'},
      );
      final page = await repo.listTransactions(
        'aid',
        kind: ApiWalletTxnKind.refund,
        limit: 25,
      );
      expect(page.items, isEmpty);
    });
  });
}
