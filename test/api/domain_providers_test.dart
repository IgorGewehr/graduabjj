// ignore_for_file: deprecated_member_use_from_same_package

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/domain_providers.dart';
import 'package:graduabjj/api/dto/financial_dto.dart';
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
    TatamiFlags flags = TatamiFlags.allOn,
  }) =>
      ProviderContainer(
        overrides: [
          tatamiClientProvider.overrideWithValue(client),
          tatamiFlagsProvider.overrideWith((ref) => flags),
        ],
      );

  group('pós-Fase 1: providers Tatami funcionam sem flag-gating', () {
    test('currentTatamiUserProvider carrega /v1/me sem flag explícita',
        () async {
      adapter.onGet(
        '/v1/me',
        (s) => s.reply(200, {
          'user': {
            'uid': 'u-0',
            'email': 'u@x.com',
            'account_type': 'linked',
          },
          'memberships': [],
        }),
      );

      // Container sem override de flags = default allOn (Tatami sempre on).
      final c = ProviderContainer(
        overrides: [tatamiClientProvider.overrideWithValue(client)],
      );
      addTearDown(c.dispose);

      final cu = await c.read(currentTatamiUserProvider.future);
      expect(cu.user.uid, 'u-0');
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
    test('adapta DTO → modelo legacy', () async {
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

  group('monthlyReportToLegacyMap (ApiMonthlyReport adapter)', () {
    test('mapeia counts e converte decimal strings para double', () {
      final r = ApiMonthlyReport.fromJson({
        'month': '2026-05',
        'total_revenue': '1500.00',
        'outstanding': '500.00',
        'overdue_count': 2,
        'paid_count': 10,
        'pending_count': 3,
        'cancelled_count': 1,
      });
      final m = monthlyReportToLegacyMap(r);
      expect(m['referenceMonth'], '2026-05');
      expect(m['totalExpected'], 2000.0);
      expect((m['paid'] as Map)['value'], 1500.0);
      expect((m['paid'] as Map)['count'], 10);
      // outstanding = pending + overdue combinado → entra em pending.value
      expect((m['pending'] as Map)['value'], 500.0);
      expect((m['pending'] as Map)['count'], 3);
      expect((m['overdue'] as Map)['value'], 0.0);
      expect((m['overdue'] as Map)['count'], 2);
      expect(m['cancelled'], 1);
      expect(m['collectionRate'], 75.0); // 1500 / 2000 * 100
    });

    test('collectionRate = 0 quando totalExpected = 0', () {
      final r = ApiMonthlyReport.fromJson({
        'month': '2026-01',
        'total_revenue': '0',
        'outstanding': '0',
        'overdue_count': 0,
        'paid_count': 0,
        'pending_count': 0,
        'cancelled_count': 0,
      });
      final m = monthlyReportToLegacyMap(r);
      expect(m['collectionRate'], 0.0);
      expect(m['totalExpected'], 0.0);
    });

    test('tatamiMonthlyReportLegacyProvider devolve Map adaptado', () async {
      adapter.onGet(
        '/v1/academies/aid/financials/reports/monthly',
        (s) => s.reply(200, {
          'month': '2026-05',
          'total_revenue': '3000.00',
          'outstanding': '1000.00',
          'overdue_count': 1,
          'paid_count': 20,
          'pending_count': 5,
          'cancelled_count': 0,
        }),
        queryParameters: {'month': '2026-05'},
      );
      final c = container(
        flags: TatamiFlags.allOff.copyWith(useTatamiFinancials: true),
      );
      addTearDown(c.dispose);

      final m = await c.read(
        tatamiMonthlyReportLegacyProvider(
          const AcademyMonth(academyId: 'aid', month: '2026-05'),
        ).future,
      );
      expect(m['referenceMonth'], '2026-05');
      expect(m['totalExpected'], 4000.0);
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
