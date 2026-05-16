import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/academy_dto.dart';
import 'package:graduabjj/api/idempotency.dart';
import 'package:graduabjj/api/link_code_repo.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late LinkCodeRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = LinkCodeRemoteRepo(client);
  });

  group('createForStudent', () {
    test('default body inclui role=student', () async {
      adapter.onPost(
        '/v1/academies/aid/link-codes',
        (s) => s.reply(201, {
          'id': 'lc-1',
          'academy_id': 'aid',
          'code': 'ABC12345',
          'role': 'student',
          'student_id': 's-1',
          'expires_at': '2026-05-17T10:00:00Z',
          'created_at': '2026-05-16T10:00:00Z',
          'created_by_uid': 'admin-1',
        }),
        data: {'role': 'student', 'student_id': 's-1'},
      );
      final lc = await repo.createForStudent(
        'aid',
        studentId: 's-1',
        idempotencyKey: IdempotencyKey.fromString(
            '77777777-7777-4777-8777-777777777777'),
      );
      expect(lc.code, 'ABC12345');
      expect(lc.role, ApiLinkCodeRole.student);
      expect(lc.studentId, 's-1');
      expect(lc.isUsed, isFalse);
    });

    test('TTL custom inclui ttl_seconds', () async {
      adapter.onPost(
        '/v1/academies/aid/link-codes',
        (s) => s.reply(201, {
          'id': 'lc-2',
          'academy_id': 'aid',
          'code': 'SHORT',
          'role': 'student',
          'expires_at': '2026-05-16T11:00:00Z',
        }),
        data: {'role': 'student', 'ttl_seconds': 3600},
      );
      final lc = await repo.createForStudent(
        'aid',
        ttlSeconds: 3600,
        idempotencyKey: IdempotencyKey.fromString(
            '88888888-8888-4888-8888-888888888888'),
      );
      expect(lc.code, 'SHORT');
    });
  });

  group('createForInstructor', () {
    test('cria com body vazio', () async {
      adapter.onPost(
        '/v1/academies/aid/instructor-link-codes',
        (s) => s.reply(201, {
          'id': 'ilc-1',
          'academy_id': 'aid',
          'code': '8CHARCOD',
          'expires_at': '2026-05-16T10:30:00Z',
          'created_at': '2026-05-16T10:00:00Z',
          'created_by_uid': 'admin-1',
        }),
        data: <String, dynamic>{},
      );
      final ilc = await repo.createForInstructor(
        'aid',
        idempotencyKey: IdempotencyKey.fromString(
            '99999999-9999-4999-8999-999999999999'),
      );
      expect(ilc.code.length, 8);
    });
  });

  group('redeem', () {
    test('200 retorna academy + role + student_id', () async {
      adapter.onPost(
        '/v1/link-codes/ABC12345/redeem',
        (s) => s.reply(200, {
          'academy_id': 'aid',
          'role': 'student',
          'student_id': 's-1',
        }),
        data: <String, dynamic>{},
      );
      final r = await repo.redeem('ABC12345');
      expect(r.academyId, 'aid');
      expect(r.role, ApiLinkCodeRole.student);
      expect(r.studentId, 's-1');
    });

    test('com perfil de novo aluno (full_name + birth_date)', () async {
      adapter.onPost(
        '/v1/link-codes/NEWUSER1/redeem',
        (s) => s.reply(200, {
          'academy_id': 'aid',
          'role': 'student',
          'student_id': 's-auto',
        }),
        data: {
          'full_name': 'Pedro Novo',
          'birth_date': '2015-08-20',
          'phone': '+5511',
        },
      );
      final r = await repo.redeem(
        'NEWUSER1',
        profile: RedeemLinkCodeRequest(
          fullName: 'Pedro Novo',
          birthDate: DateTime(2015, 8, 20),
          phone: '+5511',
        ),
      );
      expect(r.studentId, 's-auto');
    });

    test('409 quando já resgatado (race com outro device)', () async {
      adapter.onPost(
        '/v1/link-codes/USEDONCE/redeem',
        (s) => s.reply(409, {
          'type': 'https://tatami.dev/errors/link-code-already-used',
          'title': 'Link code already used',
          'status': 409,
          'detail': 'redeemed at 2026-05-16T10:00:00Z',
        }),
        data: <String, dynamic>{},
      );
      try {
        await repo.redeem('USEDONCE');
        fail('expected 409');
      } on DioException catch (e) {
        final t = e.error as TatamiException;
        expect(t.isConflict, isTrue);
        expect(t.type, contains('link-code-already-used'));
      }
    });

    test('410 quando expirado', () async {
      adapter.onPost(
        '/v1/link-codes/EXPIRED1/redeem',
        (s) => s.reply(410, {
          'type': 'https://tatami.dev/errors/link-code-expired',
          'title': 'Link code expired',
          'status': 410,
        }),
        data: <String, dynamic>{},
      );
      try {
        await repo.redeem('EXPIRED1');
        fail('expected 410');
      } on DioException catch (e) {
        final t = e.error as TatamiException;
        expect(t.status, 410);
      }
    });
  });

  group('ApiLinkCode helpers', () {
    test('isExpired true quando expires_at no passado', () {
      final lc = ApiLinkCode.fromJson({
        'id': 'x',
        'academy_id': 'a',
        'code': 'C',
        'role': 'student',
        'expires_at': DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String(),
      });
      expect(lc.isExpired, isTrue);
      expect(lc.isActive, isFalse);
    });

    test('isUsed true quando used_at presente', () {
      final lc = ApiLinkCode.fromJson({
        'id': 'x',
        'academy_id': 'a',
        'code': 'C',
        'role': 'student',
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
        'used_at': '2026-05-15T10:00:00Z',
        'used_by_uid': 'uid-1',
      });
      expect(lc.isUsed, isTrue);
      expect(lc.isActive, isFalse);
    });
  });
}
