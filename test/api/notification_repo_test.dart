import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/notification_dto.dart';
import 'package:graduabjj/api/idempotency.dart';
import 'package:graduabjj/api/notification_repo.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late NotificationRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = NotificationRemoteRepo(client);
  });

  Map<String, dynamic> notifJson({
    String id = 'n-1',
    String type = 'payment_due',
    String? readAt,
  }) =>
      {
        'id': id,
        'academy_id': 'aid',
        'recipient_uid': 'uid-1',
        'type': type,
        'title': 'Você tem uma cobrança',
        'body': 'R\$ 200,00 vence em 5 dias',
        'channels': ['inbox', 'push'],
        'created_at': '2026-05-15T08:00:00Z',
        if (readAt != null) 'read_at': readAt,
      };

  group('list + filters', () {
    test('unread_only + type + academy_id como query params', () async {
      adapter.onGet(
        '/v1/me/notifications',
        (s) => s.reply(200, {
          'items': [notifJson()],
          'has_more': false,
        }),
        queryParameters: {
          'limit': 20,
          'unread_only': true,
          'type': 'payment_due',
          'academy_id': 'aid-1',
        },
      );
      final page = await repo.list(
        filter: const NotificationsFilter(
          unreadOnly: true,
          type: ApiNotificationType.payment_due,
          academyId: 'aid-1',
          limit: 20,
        ),
      );
      expect(page.items, hasLength(1));
      expect(page.items.first.isUnread, isTrue);
      expect(page.items.first.type, ApiNotificationType.payment_due);
      expect(page.items.first.channels, contains(ApiNotificationChannel.push));
    });
  });

  group('getUnreadCount', () {
    test('retorna número direto', () async {
      adapter.onGet(
        '/v1/me/notifications/unread-count',
        (s) => s.reply(200, {'unread_count': 7}),
      );
      final n = await repo.getUnreadCount();
      expect(n, 7);
    });

    test('filtra por academy_id', () async {
      adapter.onGet(
        '/v1/me/notifications/unread-count',
        (s) => s.reply(200, {'unread_count': 3}),
        queryParameters: {'academy_id': 'aid-2'},
      );
      final n = await repo.getUnreadCount(academyId: 'aid-2');
      expect(n, 3);
    });
  });

  group('markRead', () {
    test('default read=true', () async {
      adapter.onPatch(
        '/v1/me/notifications/n-1',
        (s) => s.reply(200, notifJson(readAt: '2026-05-16T10:00:00Z')),
        data: {'read': true},
      );
      final n = await repo.markRead('n-1');
      expect(n.isRead, isTrue);
    });

    test('read=false para desfazer', () async {
      adapter.onPatch(
        '/v1/me/notifications/n-1',
        (s) => s.reply(200, notifJson()),
        data: {'read': false},
      );
      final n = await repo.markRead('n-1', read: false);
      expect(n.isUnread, isTrue);
    });

    test('404 quando notification não pertence ao caller', () async {
      adapter.onPatch(
        '/v1/me/notifications/other',
        (s) => s.reply(404, {
          'type': 'https://tatami.dev/errors/not-found',
          'title': 'Not found',
          'status': 404,
        }),
        data: {'read': true},
      );
      try {
        await repo.markRead('other');
        fail('expected 404');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isNotFound, isTrue);
      }
    });
  });

  group('markAllRead', () {
    test('sem academy_id → escopo total', () async {
      adapter.onPost(
        '/v1/me/notifications/mark-all-read',
        (s) => s.reply(200, {'updated_count': 12}),
        data: <String, dynamic>{},
      );
      final n = await repo.markAllRead();
      expect(n, 12);
    });

    test('com academy_id → escopo restrito', () async {
      adapter.onPost(
        '/v1/me/notifications/mark-all-read',
        (s) => s.reply(200, {'updated_count': 4}),
        data: {'academy_id': 'aid-1'},
      );
      final n = await repo.markAllRead(academyId: 'aid-1');
      expect(n, 4);
    });
  });

  group('delete', () {
    test('204 retorna void', () async {
      adapter.onDelete(
        '/v1/me/notifications/n-1',
        (s) => s.reply(204, null),
      );
      await repo.delete('n-1');
    });
  });

  group('FCM tokens', () {
    test('register POST idempotente em (uid, token)', () async {
      adapter.onPost(
        '/v1/me/fcm-tokens',
        (s) => s.reply(201, {
          'token': 'eYzABC...',
          'platform': 'android',
          'app_version': '1.10.0',
          'locale': 'pt-BR',
          'registered_at': '2026-05-16T10:00:00Z',
          'last_seen_at': '2026-05-16T10:00:00Z',
        }),
        data: {
          'token': 'eYzABC...',
          'platform': 'android',
          'app_version': '1.10.0',
          'locale': 'pt-BR',
        },
      );
      final t = await repo.registerFcmToken(
        const RegisterFcmTokenRequest(
          token: 'eYzABC...',
          platform: ApiDevicePlatform.android,
          appVersion: '1.10.0',
          locale: 'pt-BR',
        ),
      );
      expect(t.platform, ApiDevicePlatform.android);
      expect(t.appVersion, '1.10.0');
    });

    test('deregister DELETE com token codificado', () async {
      const token = 'token:with/special&chars';
      final encoded = Uri.encodeComponent(token);
      adapter.onDelete(
        '/v1/me/fcm-tokens/$encoded',
        (s) => s.reply(204, null),
      );
      await repo.deregisterFcmToken(token);
    });

    test('deregister 404 token desconhecido', () async {
      adapter.onDelete(
        '/v1/me/fcm-tokens/missing',
        (s) => s.reply(404, {
          'type': 'https://tatami.dev/errors/not-found',
          'title': 'Not found',
          'status': 404,
        }),
      );
      try {
        await repo.deregisterFcmToken('missing');
        fail('expected 404');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isNotFound, isTrue);
      }
    });
  });

  group('broadcast', () {
    test('admin broadcast com filtro role + idempotency key', () async {
      adapter.onPost(
        '/v1/academies/aid/notifications/broadcast',
        (s) => s.reply(202, {
          'broadcast_id': '11111111-1111-4111-8111-111111111111',
          'queued_count': 47,
        }),
        data: {
          'type': 'competition_announcement',
          'title': 'Open de São Paulo',
          'body': 'Inscrições abertas até dia 30',
          'recipients': {
            'role': ['student'],
          },
        },
      );
      final r = await repo.broadcast(
        'aid',
        const BroadcastRequest(
          type: ApiNotificationType.competition_announcement,
          title: 'Open de São Paulo',
          body: 'Inscrições abertas até dia 30',
          recipients:
              BroadcastRecipientsFilter(role: ['student']),
        ),
        idempotencyKey: IdempotencyKey.fromString(
            'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
      );
      expect(r.queuedCount, 47);
    });

    test('broadcast vazio = todos os membros ativos', () async {
      adapter.onPost(
        '/v1/academies/aid/notifications/broadcast',
        (s) => s.reply(202, {
          'broadcast_id': '22222222-2222-4222-8222-222222222222',
          'queued_count': 200,
        }),
        data: {
          'type': 'generic',
          'title': 'Aviso geral',
        },
      );
      final r = await repo.broadcast(
        'aid',
        const BroadcastRequest(
          type: ApiNotificationType.generic,
          title: 'Aviso geral',
        ),
        idempotencyKey: IdempotencyKey.fromString(
            'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
      );
      expect(r.queuedCount, 200);
    });

    test('403 quando caller não é admin', () async {
      adapter.onPost(
        '/v1/academies/aid/notifications/broadcast',
        (s) => s.reply(403, {
          'type': 'https://tatami.dev/errors/forbidden',
          'title': 'Forbidden',
          'status': 403,
        }),
        data: {'type': 'generic', 'title': 'x'},
      );
      try {
        await repo.broadcast(
          'aid',
          const BroadcastRequest(
            type: ApiNotificationType.generic,
            title: 'x',
          ),
        );
        fail('expected 403');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isForbidden, isTrue);
      }
    });
  });
}
