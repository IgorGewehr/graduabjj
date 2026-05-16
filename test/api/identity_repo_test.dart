import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/identity_dto.dart';
import 'package:graduabjj/api/identity_repo.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late TatamiClient client;
  late IdentityRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = IdentityRemoteRepo(client);
  });

  group('getMe', () {
    test('parses a full /v1/me response', () async {
      adapter.onGet(
        '/v1/me',
        (server) => server.reply(200, {
          'user': {
            'uid': 'u1',
            'email': 'u@x.com',
            'display_name': 'User One',
            'account_type': 'linked',
          },
          'memberships': [
            {
              'uid': 'u1',
              'academy_id': 'aid-1',
              'role': 'student',
              'status': 'active',
              'student_id': 'sid-1',
            },
          ],
          'primary_academy_id': 'aid-1',
        }),
      );

      final r = await repo.getMe();
      expect(r.user.uid, 'u1');
      expect(r.user.displayName, 'User One');
      expect(r.memberships, hasLength(1));
      expect(r.memberships.first.role, ApiRole.student);
      expect(r.memberships.first.studentId, 'sid-1');
      expect(r.primaryAcademyId, 'aid-1');
    });

    test('401 surfaces as TatamiException with isUnauthorized', () async {
      adapter.onGet(
        '/v1/me',
        (server) => server.reply(401, {
          'type': 'https://tatami.dev/errors/unauthorized',
          'title': 'Unauthorized',
          'status': 401,
          'detail': 'missing or invalid token',
        }),
      );

      try {
        await repo.getMe();
        fail('expected DioException with TatamiException error');
      } on DioException catch (e) {
        expect(e.error, isA<TatamiException>());
        final t = e.error as TatamiException;
        expect(t.isUnauthorized, isTrue);
        expect(t.detail, 'missing or invalid token');
      }
    });
  });

  group('updateMe', () {
    test('sends only present fields in PATCH body', () async {
      adapter.onPatch(
        '/v1/me',
        (server) => server.reply(200, {
          'uid': 'u1',
          'email': 'u@x.com',
          'display_name': 'New Name',
          'account_type': 'linked',
        }),
        data: {'display_name': 'New Name'},
      );

      final u = await repo
          .updateMe(const UpdateUserRequest(displayName: 'New Name'));
      expect(u.displayName, 'New Name');
    });

    test('422 surfaces validation errors', () async {
      adapter.onPatch(
        '/v1/me',
        (server) => server.reply(422, {
          'type': 'https://tatami.dev/errors/validation',
          'title': 'Validation failed',
          'status': 422,
          'errors': [
            {
              'field': 'phone',
              'message': 'must be a valid phone',
              'code': 'invalid_format',
            },
          ],
        }),
        data: {'phone': 'not-a-phone'},
      );

      try {
        await repo.updateMe(const UpdateUserRequest(phone: 'not-a-phone'));
        fail('expected validation error');
      } on DioException catch (e) {
        final t = e.error as TatamiException;
        expect(t.isValidation, isTrue);
        expect(t.errors, hasLength(1));
        expect(t.errors.first.field, 'phone');
        expect(t.forUser(), 'must be a valid phone');
      }
    });
  });

  group('listMemberships', () {
    test('passes limit/role/cursor as query params', () async {
      adapter.onGet(
        '/v1/academies/aid-1/memberships',
        (server) => server.reply(200, {
          'items': [
            {
              'uid': 'u1',
              'academy_id': 'aid-1',
              'role': 'student',
              'status': 'active',
            },
          ],
          'next_cursor': 'opaque-cursor',
          'has_more': true,
        }),
        queryParameters: {
          'limit': 25,
          'role': 'student',
          'cursor': 'prev-cursor',
        },
      );

      final page = await repo.listMemberships(
        'aid-1',
        role: 'student',
        limit: 25,
        cursor: 'prev-cursor',
      );
      expect(page.items, hasLength(1));
      expect(page.nextCursor, 'opaque-cursor');
      expect(page.hasMore, isTrue);
    });

    test('handles empty page (no next_cursor)', () async {
      adapter.onGet(
        '/v1/academies/aid-1/memberships',
        (server) => server.reply(200, {
          'items': [],
          'has_more': false,
        }),
        queryParameters: {'limit': 50},
      );

      final page = await repo.listMemberships('aid-1');
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
    });
  });

  group('getUserByUid', () {
    test('returns parsed user', () async {
      adapter.onGet(
        '/v1/users/firebase-uid-2',
        (server) => server.reply(200, {
          'uid': 'firebase-uid-2',
          'email': 'other@x.com',
          'account_type': 'linked',
          'display_name': 'Other',
        }),
      );

      final u = await repo.getUserByUid('firebase-uid-2');
      expect(u.uid, 'firebase-uid-2');
      expect(u.displayName, 'Other');
    });

    test('404 surfaces as TatamiException.isNotFound', () async {
      adapter.onGet(
        '/v1/users/missing',
        (server) => server.reply(404, {
          'type': 'https://tatami.dev/errors/not-found',
          'title': 'Not found',
          'status': 404,
        }),
      );

      try {
        await repo.getUserByUid('missing');
        fail('expected 404');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isNotFound, isTrue);
      }
    });
  });
}
