import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/student_dto.dart';
import 'package:graduabjj/api/idempotency.dart';
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
    String id = 'sid-new',
    String fullName = 'Aluno Novo',
  }) => {
    'id': id,
    'academy_id': 'aid-1',
    'full_name': fullName,
    'current_belt': 'white',
    'current_stripes': 0,
    'category': 'adult',
    'status': 'active',
    'attendance_count': 0,
    'is_profile_public': false,
    'primary_sport': 'bjj',
    'sports_list': ['bjj'],
    'created_at': '2026-05-16T10:00:00Z',
    'updated_at': '2026-05-16T10:00:00Z',
  };

  group('create', () {
    test('POST sends body + Idempotency-Key header, parses response', () async {
      final key = IdempotencyKey.fromString(
        '11111111-1111-4111-8111-111111111111',
      );

      adapter.onPost(
        '/v1/academies/aid-1/students',
        (server) => server.reply(201, studentJson(fullName: 'João')),
        data: {'full_name': 'João'},
        headers: {'Idempotency-Key': key.value},
      );

      final s = await repo.create(
        'aid-1',
        const CreateStudentRequest(fullName: 'João'),
        idempotencyKey: key,
      );
      expect(s.fullName, 'João');
      expect(s.id, 'sid-new');
    });

    test('auto-generates idempotency key when omitted', () async {
      // Match any Idempotency-Key header — we just verify the request happens.
      adapter.onPost(
        '/v1/academies/aid-1/students',
        (server) => server.reply(201, studentJson()),
        data: Matchers.any,
      );

      final s = await repo.create(
        'aid-1',
        const CreateStudentRequest(fullName: 'Aluno Novo'),
      );
      expect(s.id, 'sid-new');
    });

    test('serializes nested address + guardian + dates', () async {
      adapter.onPost(
        '/v1/academies/aid-1/students',
        (server) => server.reply(201, studentJson()),
        data: {
          'full_name': 'Criança',
          'birth_date': '2015-06-15',
          'category': 'kids',
          'address': {'city': 'São Paulo', 'state': 'SP'},
          'guardian': {'name': 'Mãe', 'phone': '+5511'},
        },
      );

      final s = await repo.create(
        'aid-1',
        CreateStudentRequest(
          fullName: 'Criança',
          birthDate: DateTime(2015, 6, 15),
          category: ApiStudentCategory.kids,
          address: const ApiAddress(city: 'São Paulo', state: 'SP'),
          guardian: const ApiGuardian(name: 'Mãe', phone: '+5511'),
        ),
        idempotencyKey: IdempotencyKey.fromString(
          '22222222-2222-4222-8222-222222222222',
        ),
      );
      expect(s.id, 'sid-new');
    });

    test('422 validation surfaces field errors', () async {
      adapter.onPost(
        '/v1/academies/aid-1/students',
        (server) => server.reply(422, {
          'type': 'https://tatami.dev/errors/validation',
          'title': 'Validation failed',
          'status': 422,
          'errors': [
            {'field': 'full_name', 'message': 'must not be empty'},
          ],
        }),
        data: Matchers.any,
      );

      try {
        await repo.create('aid-1', const CreateStudentRequest(fullName: ''));
        fail('expected 422');
      } on DioException catch (e) {
        final t = e.error as TatamiException;
        expect(t.isValidation, isTrue);
        expect(t.errors.first.field, 'full_name');
      }
    });
  });

  group('update', () {
    test('PATCH sends only present fields', () async {
      adapter.onPatch(
        '/v1/academies/aid-1/students/sid',
        (server) =>
            server.reply(200, studentJson(id: 'sid', fullName: 'Novo Nome')),
        data: {'full_name': 'Novo Nome', 'status': 'inactive'},
      );

      final s = await repo.update(
        'aid-1',
        'sid',
        const UpdateStudentRequest(
          fullName: 'Novo Nome',
          status: ApiStudentStatus.inactive,
        ),
      );
      expect(s.fullName, 'Novo Nome');
    });

    test(
      'PATCH sends sports_list for multi-sport attendance recovery',
      () async {
        adapter.onPatch(
          '/v1/academies/aid-1/students/sid',
          (server) => server.reply(200, {
            ...studentJson(id: 'sid'),
            'sports_list': ['bjj', 'judo'],
          }),
          data: {
            'sports_list': ['bjj', 'judo'],
          },
        );

        final s = await repo.update(
          'aid-1',
          'sid',
          const UpdateStudentRequest(sportsList: ['bjj', 'judo']),
        );
        expect(s.sportsList, ['bjj', 'judo']);
      },
    );

    test('PATCH empty body when nothing to update', () async {
      adapter.onPatch(
        '/v1/academies/aid-1/students/sid',
        (server) => server.reply(200, studentJson(id: 'sid')),
        data: <String, dynamic>{},
      );

      final s = await repo.update('aid-1', 'sid', const UpdateStudentRequest());
      expect(s.id, 'sid');
    });
  });

  group('delete (soft)', () {
    test('returns void on 204', () async {
      adapter.onDelete(
        '/v1/academies/aid-1/students/sid',
        (server) => server.reply(204, null),
      );
      await repo.delete('aid-1', 'sid');
    });

    test('404 surfaces as isNotFound', () async {
      adapter.onDelete(
        '/v1/academies/aid-1/students/missing',
        (server) => server.reply(404, {
          'type': 'https://tatami.dev/errors/not-found',
          'title': 'Not found',
          'status': 404,
        }),
      );
      try {
        await repo.delete('aid-1', 'missing');
        fail('expected 404');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isNotFound, isTrue);
      }
    });
  });

  group('createBeltProgression', () {
    test('POSTs promotion with sport override', () async {
      adapter.onPost(
        '/v1/academies/aid/students/sid/belt-progressions',
        (server) => server.reply(201, {
          'id': 'bp-new',
          'student_id': 'sid',
          'sport': 'judo',
          'previous_belt': 'white',
          'previous_stripes': 0,
          'new_belt': 'kids_yellow',
          'new_stripes': 0,
          'promotion_date': '2026-05-16',
          'total_classes': 30,
          'effective_count_at_promotion': 30,
          'promoted_by_uid': 'inst-1',
          'created_at': '2026-05-16T12:00:00Z',
        }),
        data: {
          'new_belt': 'kids_yellow',
          'new_stripes': 0,
          'promotion_date': '2026-05-16',
          'sport': 'judo',
        },
      );

      final bp = await repo.createBeltProgression(
        'aid',
        'sid',
        CreateBeltProgressionRequest(
          newBelt: ApiBelt.kids_yellow,
          newStripes: 0,
          promotionDate: DateTime(2026, 5, 16),
          sport: ApiSport.judo,
        ),
        idempotencyKey: IdempotencyKey.fromString(
          '33333333-3333-4333-8333-333333333333',
        ),
      );
      expect(bp.id, 'bp-new');
      expect(bp.sport, ApiSport.judo);
      expect(bp.newBelt, ApiBelt.kids_yellow);
    });
  });

  group('createAssessment', () {
    test('POSTs kids assessment with full scores', () async {
      adapter.onPost(
        '/v1/academies/aid/students/sid/assessments',
        (server) => server.reply(201, {
          'id': 'as-new',
          'student_id': 'sid',
          'date': '2026-05-10',
          'evaluated_by_uid': 'inst-1',
          'scores': {
            'respeito': 5,
            'disciplina': 5,
            'pontualidade': 4,
            'tecnica': 4,
            'esforco': 5,
          },
          'notes': 'Muito bom',
          'created_at': '2026-05-10T18:00:00Z',
        }),
        data: {
          'date': '2026-05-10',
          'scores': {
            'respeito': 5,
            'disciplina': 5,
            'pontualidade': 4,
            'tecnica': 4,
            'esforco': 5,
          },
          'notes': 'Muito bom',
        },
      );

      final a = await repo.createAssessment(
        'aid',
        'sid',
        CreateAssessmentRequest(
          date: DateTime(2026, 5, 10),
          scores: const ApiAssessmentScores(
            respeito: 5,
            disciplina: 5,
            pontualidade: 4,
            tecnica: 4,
            esforco: 5,
          ),
          notes: 'Muito bom',
        ),
        idempotencyKey: IdempotencyKey.fromString(
          '44444444-4444-4444-8444-444444444444',
        ),
      );
      expect(a.id, 'as-new');
      expect(a.scores.average, closeTo(4.6, 1e-9));
    });
  });
}
