import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/domain_providers.dart';
import 'package:graduabjj/api/dto/student_dto.dart';
import 'package:graduabjj/api/feature_flags.dart';
import 'package:graduabjj/providers/api_provider.dart';
import 'package:graduabjj/api/tatami_client.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late TatamiClient client;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
  });

  ProviderContainer container({
    TatamiFlags flags = TatamiFlags.allOff,
  }) =>
      ProviderContainer(
        overrides: [
          tatamiClientProvider.overrideWithValue(client),
          tatamiFlagsProvider.overrideWith((ref) => flags),
        ],
      );

  group('flag disabled → TatamiFlagDisabledError', () {
    test('currentTatamiUserProvider explode quando flag off', () async {
      final c = container();
      addTearDown(c.dispose);
      expect(
        () => c.read(currentTatamiUserProvider.future),
        throwsA(isA<TatamiFlagDisabledError>()),
      );
    });

    test('tatamiStudentsProvider explode quando flag off', () async {
      final c = container();
      addTearDown(c.dispose);
      expect(
        () => c.read(
          tatamiStudentsProvider(const StudentsQuery(academyId: 'aid'))
              .future,
        ),
        throwsA(isA<TatamiFlagDisabledError>()),
      );
    });
  });

  group('flag enabled → fluxo real (via http_mock_adapter)', () {
    test('currentTatamiUserProvider carrega /v1/me', () async {
      adapter.onGet(
        '/v1/me',
        (s) => s.reply(200, {
          'user': {
            'uid': 'u-1',
            'email': 'u@x.com',
            'account_type': 'linked',
          },
          'memberships': [],
        }),
      );

      final c = container(
        flags: TatamiFlags.allOff.copyWith(useTatamiIdentity: true),
      );
      addTearDown(c.dispose);

      final cu = await c.read(currentTatamiUserProvider.future);
      expect(cu.user.uid, 'u-1');
    });

    test('tatamiStudentsProvider passa filter como query params', () async {
      adapter.onGet(
        '/v1/academies/aid-1/students',
        (s) => s.reply(200, {
          'items': [
            {
              'id': 's-1',
              'academy_id': 'aid-1',
              'full_name': 'Test',
              'current_belt': 'white',
              'current_stripes': 0,
              'category': 'adult',
              'status': 'active',
              'attendance_count': 0,
              'is_profile_public': false,
              'primary_sport': 'bjj',
              'sports_list': [],
              'created_at': '2025-01-01T00:00:00Z',
              'updated_at': '2025-01-01T00:00:00Z',
            },
          ],
          'has_more': false,
        }),
        queryParameters: {'limit': 20, 'q': 'joão'},
      );

      final c = container(
        flags: TatamiFlags.allOff.copyWith(useTatamiReads: true),
      );
      addTearDown(c.dispose);

      final page = await c.read(
        tatamiStudentsProvider(
          const StudentsQuery(
            academyId: 'aid-1',
            filter: StudentFilter(q: 'joão', limit: 20),
          ),
        ).future,
      );
      expect(page.items, hasLength(1));
      expect(page.items.first.fullName, 'Test');
    });

    test('tatamiStudentStatsProvider carrega KPIs', () async {
      adapter.onGet(
        '/v1/academies/aid/students/stats',
        (s) => s.reply(200, {
          'total': 10,
          'by_status': {
            'active': 8,
            'injured': 1,
            'inactive': 1,
            'suspended': 0,
            'removed': 0,
          },
          'by_category': {'adults': 7, 'kids': 3},
          'by_belt': [],
        }),
      );

      final c = container(
        flags: TatamiFlags.allOff.copyWith(useTatamiReads: true),
      );
      addTearDown(c.dispose);

      final stats = await c.read(tatamiStudentStatsProvider('aid').future);
      expect(stats.total, 10);
      expect(stats.activeCount, 8);
    });
  });

  group('tatamiBeltProgressionsLegacyProvider', () {
    test('flag off explode com TatamiFlagDisabledError', () async {
      final c = container();
      addTearDown(c.dispose);
      expect(
        () => c.read(
          tatamiBeltProgressionsLegacyProvider(studentRef('aid', 's-1')).future,
        ),
        throwsA(isA<TatamiFlagDisabledError>()),
      );
    });

    test('flag on adapta DTO → modelo legacy', () async {
      adapter.onGet(
        '/v1/academies/aid/students/s-1/belt-progressions',
        (s) => s.reply(200, {
          'items': [
            {
              'id': 'bp-1',
              'student_id': 's-1',
              'sport': 'bjj',
              'previous_belt': 'white',
              'previous_stripes': 3,
              'new_belt': 'blue',
              'new_stripes': 0,
              'promotion_date': '2026-05-16T00:00:00Z',
              'total_classes': 82,
              'effective_count_at_promotion': 80,
              'promoted_by_uid': 'uid-instr',
              'created_at': '2026-05-16T19:00:00Z',
            },
          ],
          'has_more': false,
        }),
        queryParameters: {'limit': 20},
      );

      final c = container(
        flags: TatamiFlags.allOff.copyWith(useTatamiReads: true),
      );
      addTearDown(c.dispose);

      final list = await c.read(
        tatamiBeltProgressionsLegacyProvider(studentRef('aid', 's-1')).future,
      );
      expect(list, hasLength(1));
      expect(list.first.id, 'bp-1');
      expect(list.first.newBelt, 'blue');
      expect(list.first.promotedBy, 'uid-instr');
      expect(list.first.promotedByName, isNull);
    });
  });

  group('StudentsQuery equality (Riverpod family cache key)', () {
    test('mesmo academy + filter = mesma chave', () {
      const a = StudentsQuery(
        academyId: 'aid',
        filter: StudentFilter(q: 'joão', limit: 20),
      );
      const b = StudentsQuery(
        academyId: 'aid',
        filter: StudentFilter(q: 'joão', limit: 20),
      );
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('filter diferente = chave diferente', () {
      const a = StudentsQuery(
        academyId: 'aid',
        filter: StudentFilter(q: 'a'),
      );
      const b = StudentsQuery(
        academyId: 'aid',
        filter: StudentFilter(q: 'b'),
      );
      expect(a == b, isFalse);
    });
  });
}
