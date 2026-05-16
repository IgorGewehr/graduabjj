import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/settings_repo.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late SettingsRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = SettingsRemoteRepo(client);
  });

  group('getAll', () {
    test('aceita lista direta', () async {
      adapter.onGet(
        '/v1/academies/aid/settings',
        (s) => s.reply(200, [
          {
            'academy_id': 'aid',
            'key': 'auto_graduation_enabled',
            'value': true,
            'updated_at': '2026-05-01T10:00:00Z',
          },
          {
            'academy_id': 'aid',
            'key': 'auto_graduation_attendances',
            'value': 40,
          },
          {
            'academy_id': 'aid',
            'key': 'pix_key',
            'value': '12345678900',
          },
        ]),
      );
      final m = await repo.getAll('aid');
      expect(m, hasLength(3));
      expect(m['auto_graduation_enabled']!.asBool, isTrue);
      expect(m['auto_graduation_attendances']!.asInt, 40);
      expect(m['pix_key']!.asString, '12345678900');
    });

    test('aceita envelope { items: [...] }', () async {
      adapter.onGet(
        '/v1/academies/aid/settings',
        (s) => s.reply(200, {
          'items': [
            {'academy_id': 'aid', 'key': 'k1', 'value': 'v1'},
          ],
        }),
      );
      final m = await repo.getAll('aid');
      expect(m, hasLength(1));
      expect(m['k1']!.asString, 'v1');
    });

    test('lista vazia retorna mapa vazio', () async {
      adapter.onGet(
        '/v1/academies/aid/settings',
        (s) => s.reply(200, <dynamic>[]),
      );
      final m = await repo.getAll('aid');
      expect(m, isEmpty);
    });
  });

  group('set (PUT)', () {
    test('aceita value boolean', () async {
      adapter.onPut(
        '/v1/academies/aid/settings/auto_graduation_enabled',
        (s) => s.reply(200, {
          'academy_id': 'aid',
          'key': 'auto_graduation_enabled',
          'value': false,
        }),
        data: {'value': false},
      );
      final s = await repo.set('aid', 'auto_graduation_enabled', false);
      expect(s.key, 'auto_graduation_enabled');
      expect(s.asBool, isFalse);
    });

    test('aceita value inteiro', () async {
      adapter.onPut(
        '/v1/academies/aid/settings/auto_graduation_attendances',
        (s) => s.reply(200, {
          'academy_id': 'aid',
          'key': 'auto_graduation_attendances',
          'value': 60,
        }),
        data: {'value': 60},
      );
      final s = await repo.set('aid', 'auto_graduation_attendances', 60);
      expect(s.asInt, 60);
    });

    test('aceita value como objeto JSON arbitrário', () async {
      adapter.onPut(
        '/v1/academies/aid/settings/billing_config',
        (s) => s.reply(200, {
          'academy_id': 'aid',
          'key': 'billing_config',
          'value': {'currency': 'BRL', 'late_fee_percent': 2.0},
        }),
        data: {
          'value': {'currency': 'BRL', 'late_fee_percent': 2.0},
        },
      );
      final s = await repo.set('aid', 'billing_config', {
        'currency': 'BRL',
        'late_fee_percent': 2.0,
      });
      expect(s.value, isA<Map>());
      expect((s.value as Map)['currency'], 'BRL');
    });

    test('422 quando chave inválida', () async {
      adapter.onPut(
        '/v1/academies/aid/settings/bad_key',
        (s) => s.reply(422, {
          'type': 'https://tatami.dev/errors/validation',
          'title': 'Validation failed',
          'status': 422,
          'errors': [
            {'field': 'key', 'message': 'key not in allowed catalog'},
          ],
        }),
        data: {'value': 'x'},
      );
      try {
        await repo.set('aid', 'bad_key', 'x');
        fail('expected 422');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isValidation, isTrue);
      }
    });
  });
}
