import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/competition_repo.dart';
import 'package:graduabjj/api/dto/competition_dto.dart';
import 'package:graduabjj/api/idempotency.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late CompetitionRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = CompetitionRemoteRepo(client);
  });

  Map<String, dynamic> competitionJson({
    String id = 'cp-1',
    String status = 'upcoming',
  }) =>
      {
        'id': id,
        'academy_id': 'aid',
        'name': 'Open SP 2026',
        'date': '2026-06-15T08:00:00Z',
        'status': status,
        'transport_capacity': 20,
        'transport_status': 'planned',
      };

  group('competitions CRUD', () {
    test('list filtra por status', () async {
      adapter.onGet(
        '/v1/academies/aid/competitions',
        (s) => s.reply(200, {
          'items': [competitionJson()],
          'has_more': false,
        }),
        queryParameters: {'limit': 50, 'status': 'upcoming'},
      );
      final page = await repo.list(
        'aid',
        status: ApiCompetitionStatus.upcoming,
      );
      expect(page.items, hasLength(1));
      expect(page.items.first.hasTransport, isTrue);
    });

    test('create idempotente', () async {
      adapter.onPost(
        '/v1/academies/aid/competitions',
        (s) => s.reply(201, competitionJson(id: 'cp-new')),
        data: {
          'name': 'Open SP 2026',
          'date': '2026-06-15T08:00:00.000Z',
          'transport_capacity': 20,
        },
      );
      final c = await repo.create(
        'aid',
        CreateCompetitionRequest(
          name: 'Open SP 2026',
          date: DateTime.utc(2026, 6, 15, 8, 0, 0),
          transportCapacity: 20,
        ),
        idempotencyKey: IdempotencyKey.fromString(
            '11111111-2222-4222-8222-111111111111'),
      );
      expect(c.id, 'cp-new');
    });

    test('update status para completed', () async {
      adapter.onPatch(
        '/v1/academies/aid/competitions/cp-1',
        (s) => s.reply(200, competitionJson(status: 'completed')),
        data: {'status': 'completed'},
      );
      final c = await repo.update(
        'aid',
        'cp-1',
        const UpdateCompetitionRequest(status: ApiCompetitionStatus.completed),
      );
      expect(c.status, ApiCompetitionStatus.completed);
    });

    test('delete 204', () async {
      adapter.onDelete(
        '/v1/academies/aid/competitions/cp-1',
        (s) => s.reply(204, null),
      );
      await repo.delete('aid', 'cp-1');
    });
  });

  group('enrollments', () {
    test('enroll com transport_preference + categorias', () async {
      adapter.onPost(
        '/v1/academies/aid/competitions/cp-1/enrollments',
        (s) => s.reply(201, {
          'id': 'e-1',
          'competition_id': 'cp-1',
          'student_id': 's-1',
          'age_category': 'adulto',
          'weight_category': '-76',
          'modality': 'gi',
          'transport_preference': 'need_transport',
          'enrolled_at': '2026-05-16T10:00:00Z',
        }),
        data: {
          'student_id': 's-1',
          'modality': 'gi',
          'age_category': 'adulto',
          'weight_category': '-76',
          'transport_preference': 'need_transport',
        },
      );
      final e = await repo.enroll(
        'aid',
        'cp-1',
        const CreateEnrollmentRequest(
          studentId: 's-1',
          modality: ApiModality.gi,
          ageCategory: 'adulto',
          weightCategory: '-76',
          transportPreference: ApiTransportPreference.need_transport,
        ),
        idempotencyKey: IdempotencyKey.fromString(
            '22222222-3333-4333-8333-222222222222'),
      );
      expect(e.modality, ApiModality.gi);
      expect(e.transportPreference, ApiTransportPreference.need_transport);
    });

    test('enroll 409 quando transport_capacity atingida', () async {
      adapter.onPost(
        '/v1/academies/aid/competitions/cp-1/enrollments',
        (s) => s.reply(409, {
          'type': 'https://tatami.dev/errors/transport-capacity-reached',
          'title': 'Transport capacity reached',
          'status': 409,
        }),
        data: {
          'student_id': 's-2',
          'modality': 'gi',
          'transport_preference': 'need_transport',
        },
      );
      try {
        await repo.enroll(
          'aid',
          'cp-1',
          const CreateEnrollmentRequest(
            studentId: 's-2',
            modality: ApiModality.gi,
            transportPreference: ApiTransportPreference.need_transport,
          ),
          idempotencyKey: IdempotencyKey.fromString(
              '33333333-4444-4444-8444-333333333333'),
        );
        fail('expected 409');
      } on DioException catch (e) {
        final t = e.error as TatamiException;
        expect(t.isConflict, isTrue);
        expect(t.type, contains('transport-capacity'));
      }
    });

    test('unenroll 204', () async {
      adapter.onDelete(
        '/v1/academies/aid/competitions/cp-1/enrollments/e-1',
        (s) => s.reply(204, null),
      );
      await repo.unenroll('aid', 'cp-1', 'e-1');
    });
  });

  group('results', () {
    test('record gold com categorias', () async {
      adapter.onPost(
        '/v1/academies/aid/competitions/cp-1/results',
        (s) => s.reply(201, {
          'id': 'r-1',
          'competition_id': 'cp-1',
          'student_id': 's-1',
          'position': 'gold',
          'belt_category': 'azul',
          'weight_category': '-76',
          'modality': 'gi',
          'recorded_at': '2026-06-15T18:00:00Z',
        }),
        data: {
          'student_id': 's-1',
          'position': 'gold',
          'modality': 'gi',
          'belt_category': 'azul',
          'weight_category': '-76',
        },
      );
      final r = await repo.recordResult(
        'aid',
        'cp-1',
        const CreateResultRequest(
          studentId: 's-1',
          position: ApiPosition.gold,
          modality: ApiModality.gi,
          beltCategory: 'azul',
          weightCategory: '-76',
        ),
        idempotencyKey: IdempotencyKey.fromString(
            '44444444-5555-4555-8555-444444444444'),
      );
      expect(r.position, ApiPosition.gold);
    });
  });

  group('photos (2-step upload)', () {
    test('passo 1: createPhotoUploadUrl retorna signed URL', () async {
      adapter.onPost(
        '/v1/academies/aid/competitions/cp-1/photos/upload-url',
        (s) => s.reply(200, {
          'upload_url': 'https://storage.example/aid/photo-uuid.jpg?sig=xyz',
          'storage_path': 'photos/aid/cp-1/photo-uuid.jpg',
          'expires_at': '2026-05-16T11:00:00Z',
        }),
        data: {
          'filename': 'finals.jpg',
          'content_type': 'image/jpeg',
          'student_id': 's-1',
        },
      );
      final url = await repo.createPhotoUploadUrl(
        'aid',
        'cp-1',
        const CreatePhotoUploadUrlRequest(
          filename: 'finals.jpg',
          contentType: 'image/jpeg',
          studentId: 's-1',
        ),
      );
      expect(url.uploadUrl, contains('sig='));
      expect(url.storagePath, 'photos/aid/cp-1/photo-uuid.jpg');
    });

    test('passo 2: createPhoto confirma com url+storage_path', () async {
      adapter.onPost(
        '/v1/academies/aid/competitions/cp-1/photos',
        (s) => s.reply(201, {
          'id': 'ph-1',
          'competition_id': 'cp-1',
          'url': 'https://cdn.example/aid/photo.jpg',
          'storage_path': 'photos/aid/cp-1/photo-uuid.jpg',
          'caption': 'Finals',
          'uploaded_at': '2026-05-16T10:30:00Z',
        }),
        data: {
          'url': 'https://cdn.example/aid/photo.jpg',
          'storage_path': 'photos/aid/cp-1/photo-uuid.jpg',
          'caption': 'Finals',
        },
      );
      final ph = await repo.createPhoto(
        'aid',
        'cp-1',
        const CreatePhotoRequest(
          url: 'https://cdn.example/aid/photo.jpg',
          storagePath: 'photos/aid/cp-1/photo-uuid.jpg',
          caption: 'Finals',
        ),
      );
      expect(ph.id, 'ph-1');
    });

    test('list photos filtra por student_id', () async {
      adapter.onGet(
        '/v1/academies/aid/competitions/cp-1/photos',
        (s) => s.reply(200, {
          'items': [
            {
              'id': 'ph-1',
              'competition_id': 'cp-1',
              'url': 'https://cdn.example/p1.jpg',
              'storage_path': 'p/p1.jpg',
              'student_id': 's-1',
              'uploaded_at': '2026-05-16T10:00:00Z',
            },
          ],
          'has_more': false,
        }),
        queryParameters: {'limit': 50, 'student_id': 's-1'},
      );
      final page = await repo.listPhotos('aid', 'cp-1', studentId: 's-1');
      expect(page.items, hasLength(1));
      expect(page.items.first.studentId, 's-1');
    });
  });

  group('achievements', () {
    test('lista timeline do aluno com graduation + competition', () async {
      adapter.onGet(
        '/v1/academies/aid/students/s-1/achievements',
        (s) => s.reply(200, {
          'items': [
            {
              'id': 'ach-1',
              'student_id': 's-1',
              'type': 'graduation',
              'from_belt': 'white',
              'to_belt': 'blue',
              'from_stripes': 4,
              'to_stripes': 0,
              'unlocked_at': '2025-12-01T10:00:00Z',
            },
            {
              'id': 'ach-2',
              'student_id': 's-1',
              'type': 'competition',
              'competition_id': 'cp-1',
              'position': 'gold',
              'unlocked_at': '2026-06-15T18:00:00Z',
            },
          ],
          'has_more': false,
        }),
        queryParameters: {'limit': 50},
      );
      final page = await repo.listAchievements('aid', 's-1');
      expect(page.items, hasLength(2));
      expect(page.items.first.type, ApiAchievementType.graduation);
      expect(page.items[1].position, ApiPosition.gold);
    });
  });
}
