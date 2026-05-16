import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/attendance_repo.dart';
import 'package:graduabjj/api/dto/attendance_dto.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AttendanceRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = AttendanceRemoteRepo(client);
  });

  Map<String, dynamic> attendanceJson({
    String id = 'a-1',
    String studentId = 's-1',
    String classId = 'c-1',
    String date = '2026-05-16',
  }) =>
      {
        'id': id,
        'academy_id': 'aid',
        'student_id': studentId,
        'class_id': classId,
        'date': date,
        'verified_by_uid': 'inst-1',
        'weight': '1.000',
        'created_at': '2026-05-16T19:00:00Z',
      };

  group('list', () {
    test('usa camelCase params (BE diverge do snake)', () async {
      adapter.onGet(
        '/v1/academies/aid/attendance',
        (s) => s.reply(200, {
          'items': [attendanceJson()],
          'has_more': false,
        }),
        queryParameters: {
          'limit': 50,
          'studentId': 's-1',
          'classId': 'c-1',
          'dateFrom': '2026-05-01',
          'dateTo': '2026-05-31',
        },
      );

      final page = await repo.list(
        'aid',
        filter: AttendanceFilter(
          studentId: 's-1',
          classId: 'c-1',
          dateFrom: DateTime(2026, 5, 1),
          dateTo: DateTime(2026, 5, 31),
        ),
      );
      expect(page.items, hasLength(1));
      expect(page.items.first.weight, '1.000');
    });
  });

  group('recordBulk', () {
    test('per-item results — recorded + duplicate no mesmo batch', () async {
      adapter.onPost(
        '/v1/academies/aid/attendance',
        (s) => s.reply(200, {
          'results': [
            {
              'status': 'recorded',
              'attendance': attendanceJson(id: 'a-new', studentId: 's-1'),
            },
            {
              'status': 'duplicate',
              'error': 'attendance already exists for (s-2, c-1, 2026-05-16)',
            },
            {
              'status': 'not_in_class',
              'error': 's-3 not on class roster',
            },
          ],
          'promotion_eligible_student_ids': ['s-1'],
        }),
        data: {
          'items': [
            {'student_id': 's-1', 'class_id': 'c-1', 'date': '2026-05-16'},
            {'student_id': 's-2', 'class_id': 'c-1', 'date': '2026-05-16'},
            {'student_id': 's-3', 'class_id': 'c-1', 'date': '2026-05-16'},
          ],
        },
      );

      final r = await repo.recordBulk(
        'aid',
        RecordAttendanceRequest(
          items: [
            AttendanceCheckin(
                studentId: 's-1', classId: 'c-1', date: DateTime(2026, 5, 16)),
            AttendanceCheckin(
                studentId: 's-2', classId: 'c-1', date: DateTime(2026, 5, 16)),
            AttendanceCheckin(
                studentId: 's-3', classId: 'c-1', date: DateTime(2026, 5, 16)),
          ],
        ),
      );

      expect(r.results, hasLength(3));
      expect(r.recordedCount, 1);
      expect(r.duplicateCount, 1);
      expect(r.results.first.isRecorded, isTrue);
      expect(r.results[1].isDuplicate, isTrue);
      expect(r.results[2].status, ApiAttendanceItemStatus.not_in_class);
      expect(r.promotionEligibleStudentIds, ['s-1']);
    });
  });

  group('selfCheckin (QR)', () {
    test('happy-path com qr_token', () async {
      adapter.onPost(
        '/v1/academies/aid/attendance/self-checkin',
        (s) => s.reply(201, attendanceJson()),
        data: {
          'class_id': 'c-1',
          'qr_token': 'PAYLOAD.SIGNATURE',
        },
      );
      final a = await repo.selfCheckin(
        'aid',
        const SelfCheckinRequest(classId: 'c-1', qrToken: 'PAYLOAD.SIGNATURE'),
      );
      expect(a.id, 'a-1');
    });

    test('410 quando token expirado (>60s)', () async {
      adapter.onPost(
        '/v1/academies/aid/attendance/self-checkin',
        (s) => s.reply(410, {
          'type': 'https://tatami.dev/errors/qr-expired',
          'title': 'QR token expired',
          'status': 410,
          'detail': 'Token TTL is 60s. Ask staff for a new QR.',
        }),
        data: {'class_id': 'c-1', 'qr_token': 'OLD'},
      );
      try {
        await repo.selfCheckin(
          'aid',
          const SelfCheckinRequest(classId: 'c-1', qrToken: 'OLD'),
        );
        fail('expected 410');
      } on DioException catch (e) {
        final t = e.error as TatamiException;
        expect(t.status, 410);
        expect(t.type, contains('qr-expired'));
      }
    });

    test('401 quando signature inválida (forgery attempt)', () async {
      adapter.onPost(
        '/v1/academies/aid/attendance/self-checkin',
        (s) => s.reply(401, {
          'type': 'https://tatami.dev/errors/qr-invalid-signature',
          'title': 'Invalid QR signature',
          'status': 401,
        }),
        data: {'class_id': 'c-1', 'qr_token': 'FORGED'},
      );
      try {
        await repo.selfCheckin(
          'aid',
          const SelfCheckinRequest(classId: 'c-1', qrToken: 'FORGED'),
        );
        fail('expected 401');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isUnauthorized, isTrue);
      }
    });

    test('403 quando caller não é student linked da turma', () async {
      adapter.onPost(
        '/v1/academies/aid/attendance/self-checkin',
        (s) => s.reply(403, {
          'type': 'https://tatami.dev/errors/self-checkin-not-allowed',
          'title': 'Not a linked student',
          'status': 403,
        }),
        data: {'class_id': 'c-other'},
      );
      try {
        await repo.selfCheckin(
          'aid',
          const SelfCheckinRequest(classId: 'c-other'),
        );
        fail('expected 403');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isForbidden, isTrue);
      }
    });

    test('409 quando já tem presença hoje', () async {
      adapter.onPost(
        '/v1/academies/aid/attendance/self-checkin',
        (s) => s.reply(409, {
          'type': 'https://tatami.dev/errors/attendance-duplicate',
          'title': 'Attendance already exists',
          'status': 409,
        }),
        data: {'class_id': 'c-1', 'qr_token': 'VALID'},
      );
      try {
        await repo.selfCheckin(
          'aid',
          const SelfCheckinRequest(classId: 'c-1', qrToken: 'VALID'),
        );
        fail('expected 409');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isConflict, isTrue);
      }
    });

    test('legacy path: sem qr_token usa body só com class_id', () async {
      adapter.onPost(
        '/v1/academies/aid/attendance/self-checkin',
        (s) => s.reply(201, attendanceJson()),
        data: {'class_id': 'c-1'},
      );
      final a = await repo.selfCheckin(
        'aid',
        const SelfCheckinRequest(classId: 'c-1'),
      );
      expect(a.id, 'a-1');
    });
  });

  group('issueQrToken', () {
    test('retorna token assinado + expires_at no futuro', () async {
      final futureExpiry = DateTime.now().add(const Duration(seconds: 60));
      adapter.onPost(
        '/v1/academies/aid/classes/c-1/qr-tokens',
        (s) => s.reply(200, {
          'token':
              'eyJhIjoiYWlkIiwiYyI6ImMtMSIsImV4cCI6MTcxNTg3ODM0MCwianRpIjoiMTIzIn0=.fakesignature',
          'expires_at': futureExpiry.toUtc().toIso8601String(),
        }),
      );
      final qr = await repo.issueQrToken('aid', 'c-1');
      expect(qr.token, contains('.'));
      expect(qr.isFresh, isTrue);
      expect(qr.secondsRemaining, greaterThan(0));
    });

    test('403 quando caller não tem CanWriteAttendance (staff-only)', () async {
      adapter.onPost(
        '/v1/academies/aid/classes/c-1/qr-tokens',
        (s) => s.reply(403, {
          'type': 'https://tatami.dev/errors/forbidden',
          'title': 'Forbidden',
          'status': 403,
        }),
      );
      try {
        await repo.issueQrToken('aid', 'c-1');
        fail('expected 403');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isForbidden, isTrue);
      }
    });
  });

  group('ApiClassQrToken helpers', () {
    test('isFresh=false quando expires_at no passado', () {
      final qr = ApiClassQrToken.fromJson({
        'token': 'X.Y',
        'expires_at': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toUtc()
            .toIso8601String(),
      });
      expect(qr.isFresh, isFalse);
      expect(qr.secondsRemaining, 0);
    });
  });

  group('delete', () {
    test('204 retorna void', () async {
      adapter.onDelete(
        '/v1/academies/aid/attendance/a-1',
        (s) => s.reply(204, null),
      );
      await repo.delete('aid', 'a-1');
    });
  });
}
