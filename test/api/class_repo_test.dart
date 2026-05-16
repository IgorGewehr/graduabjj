import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/class_repo.dart';
import 'package:graduabjj/api/dto/class_dto.dart';
import 'package:graduabjj/api/dto/student_dto.dart' show ApiBelt;
import 'package:graduabjj/api/idempotency.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ClassRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = ClassRemoteRepo(client);
  });

  Map<String, dynamic> classJson({
    String id = 'c-1',
    String name = 'BJJ Adulto Noite',
    String category = 'adult',
  }) =>
      {
        'id': id,
        'academy_id': 'aid',
        'name': name,
        'category': category,
        'sport': 'bjj',
        'schedule': [
          {'day_of_week': 1, 'start_time': '19:00', 'end_time': '20:30'},
          {'day_of_week': 3, 'start_time': '19:00', 'end_time': '20:30'},
        ],
        'max_students': 0,
        'weight': '1.000',
        'is_active': true,
        'student_ids': ['s-1', 's-2'],
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

  group('list / parsing', () {
    test('parses schedule + isUnlimited', () async {
      adapter.onGet(
        '/v1/academies/aid/classes',
        (s) => s.reply(200, {
          'items': [classJson()],
          'has_more': false,
        }),
        queryParameters: {'limit': 50},
      );
      final page = await repo.list('aid');
      expect(page.items, hasLength(1));
      final c = page.items.first;
      expect(c.name, 'BJJ Adulto Noite');
      expect(c.schedule, hasLength(2));
      expect(c.schedule.first.dayOfWeek, 1);
      expect(c.schedule.first.startTime, '19:00');
      expect(c.isUnlimited, isTrue);
      expect(c.weight, '1.000');
      expect(c.category, ApiClassCategory.adult);
    });

    test('passa is_active=true como query param', () async {
      adapter.onGet(
        '/v1/academies/aid/classes',
        (s) => s.reply(200, {'items': [], 'has_more': false}),
        queryParameters: {'limit': 25, 'is_active': true},
      );
      final page = await repo.list('aid', limit: 25, isActive: true);
      expect(page.items, isEmpty);
    });
  });

  group('create', () {
    test('serializa schedule + min_belt/max_belt', () async {
      adapter.onPost(
        '/v1/academies/aid/classes',
        (s) => s.reply(201, {
          ...classJson(id: 'c-new', name: 'Kids'),
          'category': 'kids',
          'min_belt': 'kids_grey',
          'max_belt': 'kids_green',
        }),
        data: {
          'name': 'Kids',
          'category': 'kids',
          'schedule': [
            {'day_of_week': 2, 'start_time': '17:00', 'end_time': '18:00'},
          ],
          'min_belt': 'kids_grey',
          'max_belt': 'kids_green',
          'max_students': 20,
        },
      );

      final c = await repo.create(
        'aid',
        const CreateClassRequest(
          name: 'Kids',
          category: ApiClassCategory.kids,
          schedule: [
            ApiScheduleEntry(
                dayOfWeek: 2, startTime: '17:00', endTime: '18:00'),
          ],
          minBelt: ApiBelt.kids_grey,
          maxBelt: ApiBelt.kids_green,
          maxStudents: 20,
        ),
        idempotencyKey: IdempotencyKey.fromString(
            '66666666-6666-4666-8666-666666666666'),
      );
      expect(c.name, 'Kids');
      expect(c.minBelt, ApiBelt.kids_grey);
      expect(c.maxBelt, ApiBelt.kids_green);
    });
  });

  group('update', () {
    test('PATCH apenas com is_active=false', () async {
      adapter.onPatch(
        '/v1/academies/aid/classes/c-1',
        (s) => s.reply(200, {...classJson(), 'is_active': false}),
        data: {'is_active': false},
      );
      final c = await repo.update(
        'aid',
        'c-1',
        const UpdateClassRequest(isActive: false),
      );
      expect(c.isActive, isFalse);
    });
  });

  group('roster', () {
    test('addStudent POST', () async {
      adapter.onPost(
        '/v1/academies/aid/classes/c-1/students',
        (s) => s.reply(204, null),
        data: {'student_id': 's-9'},
      );
      await repo.addStudent('aid', 'c-1', 's-9');
    });

    test('removeStudent DELETE', () async {
      adapter.onDelete(
        '/v1/academies/aid/classes/c-1/students/s-9',
        (s) => s.reply(204, null),
      );
      await repo.removeStudent('aid', 'c-1', 's-9');
    });

    test('removeStudent 404 quando aluno não está na turma', () async {
      adapter.onDelete(
        '/v1/academies/aid/classes/c-1/students/missing',
        (s) => s.reply(404, {
          'type': 'https://tatami.dev/errors/not-found',
          'title': 'Not found',
          'status': 404,
        }),
      );
      try {
        await repo.removeStudent('aid', 'c-1', 'missing');
        fail('expected 404');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isNotFound, isTrue);
      }
    });
  });

  group('delete', () {
    test('204 retorna void', () async {
      adapter.onDelete(
        '/v1/academies/aid/classes/c-1',
        (s) => s.reply(204, null),
      );
      await repo.delete('aid', 'c-1');
    });
  });
}
