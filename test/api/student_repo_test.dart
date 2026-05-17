import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/student_dto.dart';
import 'package:graduabjj/api/student_repo.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late TatamiClient client;
  late StudentRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = StudentRemoteRepo(client);
  });

  Map<String, dynamic> studentJson({
    String id = 'sid-1',
    String fullName = 'Aluno Teste',
    String belt = 'white',
    String status = 'active',
  }) =>
      {
        'id': id,
        'academy_id': 'aid-1',
        'full_name': fullName,
        'current_belt': belt,
        'current_stripes': 0,
        'category': 'adult',
        'status': status,
        'attendance_count': 0,
        'is_profile_public': false,
        'primary_sport': 'bjj',
        'sports_list': ['bjj'],
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

  group('list', () {
    test('passes filter query params and parses items', () async {
      adapter.onGet(
        '/v1/academies/aid-1/students',
        (server) => server.reply(200, {
          'items': [studentJson(id: 'a'), studentJson(id: 'b')],
          'next_cursor': 'cursor-x',
          'has_more': true,
        }),
        queryParameters: {
          'limit': 25,
          'status': 'active',
          'belt': 'blue',
          'q': 'joão',
        },
      );

      final page = await repo.list(
        'aid-1',
        filter: const StudentFilter(
          status: ApiStudentStatus.active,
          belt: ApiBelt.blue,
          q: 'joão',
          limit: 25,
        ),
      );
      expect(page.items, hasLength(2));
      expect(page.items.first.id, 'a');
      expect(page.nextCursor, 'cursor-x');
      expect(page.hasMore, isTrue);
    });

    test('default filter sends only limit', () async {
      adapter.onGet(
        '/v1/academies/aid-1/students',
        (server) => server.reply(200, {'items': [], 'has_more': false}),
        queryParameters: {'limit': 50},
      );

      final page = await repo.list('aid-1');
      expect(page.items, isEmpty);
    });

    test('403 forbidden surfaces as TatamiException.isForbidden', () async {
      adapter.onGet(
        '/v1/academies/aid-1/students',
        (server) => server.reply(403, {
          'type': 'https://tatami.dev/errors/forbidden',
          'title': 'Forbidden',
          'status': 403,
        }),
        queryParameters: {'limit': 50},
      );

      try {
        await repo.list('aid-1');
        fail('expected 403');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isForbidden, isTrue);
      }
    });
  });

  group('getById', () {
    test('returns parsed student', () async {
      adapter.onGet(
        '/v1/academies/aid/students/sid-1',
        (server) => server.reply(200, studentJson(fullName: 'Foo Bar', belt: 'purple')),
      );
      final s = await repo.getById('aid', 'sid-1');
      expect(s.fullName, 'Foo Bar');
      expect(s.currentBelt, ApiBelt.purple);
    });

    test('404 surfaces as isNotFound', () async {
      adapter.onGet(
        '/v1/academies/aid/students/missing',
        (server) => server.reply(404, {
          'type': 'https://tatami.dev/errors/not-found',
          'title': 'Not found',
          'status': 404,
        }),
      );
      try {
        await repo.getById('aid', 'missing');
        fail('expected 404');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isNotFound, isTrue);
      }
    });
  });

  group('getStats', () {
    test('parses dashboard stats payload', () async {
      adapter.onGet(
        '/v1/academies/aid/students/stats',
        (server) => server.reply(200, {
          'total': 50,
          'by_status': {
            'active': 40,
            'injured': 2,
            'inactive': 5,
            'suspended': 1,
            'removed': 2,
          },
          'by_category': {'adults': 35, 'kids': 15},
          'by_belt': [
            {'belt': 'white', 'category': 'adult', 'total': 15},
          ],
        }),
      );

      final s = await repo.getStats('aid');
      expect(s.total, 50);
      expect(s.activeCount, 40);
      expect(s.kidsCount, 15);
      expect(s.byBelt.first.belt, ApiBelt.white);
    });
  });

  group('getEligibility', () {
    test('parses eligibility view', () async {
      adapter.onGet(
        '/v1/academies/aid/students/sid/graduation-eligibility',
        (server) => server.reply(200, {
          'eligible': true,
          'current_belt': 'blue',
          'current_stripes': 4,
          'next_belt': 'purple',
          'next_stripes': 0,
          'current_count': 50,
          'required_count': 40,
          'auto_enabled': true,
          'last_promotion_date': '2024-06-01',
        }),
      );
      final e = await repo.getEligibility('aid', 'sid');
      expect(e.eligible, isTrue);
      expect(e.attendancesNeeded, 0);
      expect(e.nextBelt, ApiBelt.purple);
    });

    test('parses reason when not eligible', () async {
      adapter.onGet(
        '/v1/academies/aid/students/sid/graduation-eligibility',
        (server) => server.reply(200, {
          'eligible': false,
          'reason': 'needs 12 more classes',
          'current_belt': 'blue',
          'current_stripes': 2,
          'current_count': 28,
          'required_count': 40,
          'auto_enabled': true,
        }),
      );
      final e = await repo.getEligibility('aid', 'sid');
      expect(e.eligible, isFalse);
      expect(e.reason, 'needs 12 more classes');
      expect(e.attendancesNeeded, 12);
    });
  });

  group('listBeltProgressions', () {
    test('passes cursor and parses items', () async {
      adapter.onGet(
        '/v1/academies/aid/students/sid/belt-progressions',
        (server) => server.reply(200, {
          'items': [
            {
              'id': 'bp-1',
              'student_id': 'sid',
              'sport': 'bjj',
              'previous_belt': 'white',
              'previous_stripes': 4,
              'new_belt': 'blue',
              'new_stripes': 0,
              'promotion_date': '2024-12-01',
              'total_classes': 80,
              'effective_count_at_promotion': 60,
              'promoted_by_uid': 'inst-1',
              'notes': 'Bem merecido.',
              'created_at': '2024-12-01T10:00:00Z',
            },
          ],
          'has_more': false,
        }),
        queryParameters: {'limit': 20, 'cursor': 'c-prev'},
      );
      final page = await repo.listBeltProgressions(
        'aid',
        'sid',
        cursor: 'c-prev',
      );
      expect(page.items, hasLength(1));
      expect(page.items.first.newBelt, ApiBelt.blue);
      expect(page.items.first.previousBelt, ApiBelt.white);
      expect(page.items.first.notes, 'Bem merecido.');
    });
  });

  group('listAssessments', () {
    test('parses scores + notes', () async {
      adapter.onGet(
        '/v1/academies/aid/students/sid/assessments',
        (server) => server.reply(200, {
          'items': [
            {
              'id': 'as-1',
              'student_id': 'sid',
              'date': '2026-04-10',
              'evaluated_by_uid': 'inst-1',
              'scores': {
                'respeito': 5,
                'disciplina': 4,
                'pontualidade': 5,
                'tecnica': 3,
                'esforco': 4,
              },
              'notes': 'Bom evolução.',
              'created_at': '2026-04-10T18:00:00Z',
            },
          ],
          'has_more': false,
        }),
        queryParameters: {'limit': 20},
      );
      final page = await repo.listAssessments('aid', 'sid');
      expect(page.items, hasLength(1));
      expect(page.items.first.scores.respeito, 5);
      expect(page.items.first.scores.average, closeTo(4.2, 1e-9));
    });
  });
}
