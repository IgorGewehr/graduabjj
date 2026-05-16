import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/plan_dto.dart';
import 'package:graduabjj/api/idempotency.dart';
import 'package:graduabjj/api/plan_repo.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PlanRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = PlanRemoteRepo(client);
  });

  Map<String, dynamic> planJson({
    String id = 'p-1',
    String name = 'Mensal',
    String monthlyValue = '200.00',
  }) =>
      {
        'id': id,
        'academy_id': 'aid',
        'name': name,
        'monthly_value': monthlyValue,
        'default_due_day': 5,
        'classes_per_week': 3,
        'is_active': true,
        'student_ids': ['s-1', 's-2'],
      };

  group('list', () {
    test('aceita resposta como lista direta', () async {
      adapter.onGet(
        '/v1/academies/aid/plans',
        (s) => s.reply(200, [planJson(id: 'p-1'), planJson(id: 'p-2')]),
      );
      final plans = await repo.list('aid');
      expect(plans, hasLength(2));
      expect(plans.first.id, 'p-1');
    });

    test('aceita envelope { items: [...] }', () async {
      adapter.onGet(
        '/v1/academies/aid/plans',
        (s) => s.reply(200, {'items': [planJson()]}),
      );
      final plans = await repo.list('aid');
      expect(plans, hasLength(1));
    });
  });

  group('getById + parsing', () {
    test('parses plan with custom_values / custom_due_days', () async {
      adapter.onGet(
        '/v1/academies/aid/plans/p-1',
        (s) => s.reply(200, {
          ...planJson(),
          'description': 'Plano padrão',
          'custom_values': {'s-3': '150.00'},
          'custom_due_days': {'s-3': 10},
        }),
      );
      final p = await repo.getById('aid', 'p-1');
      expect(p.description, 'Plano padrão');
      expect(p.customValues['s-3'], '150.00');
      expect(p.customDueDays['s-3'], 10);
      expect(p.isUnlimited, isFalse);
      expect(p.classesPerWeek, 3);
    });

    test('classes_per_week=0 → isUnlimited true', () async {
      adapter.onGet(
        '/v1/academies/aid/plans/p-unlim',
        (s) => s.reply(200, {
          ...planJson(),
          'classes_per_week': 0,
        }),
      );
      final p = await repo.getById('aid', 'p-unlim');
      expect(p.isUnlimited, isTrue);
    });
  });

  group('create', () {
    test('POST com idempotency-key explícita', () async {
      final key = IdempotencyKey.fromString(
          '55555555-5555-4555-8555-555555555555');
      adapter.onPost(
        '/v1/academies/aid/plans',
        (s) => s.reply(201, planJson(id: 'p-new', name: 'Novo')),
        data: {
          'name': 'Novo',
          'monthly_value': '300.00',
          'default_due_day': 1,
        },
      );

      final p = await repo.create(
        'aid',
        const CreatePlanRequest(
          name: 'Novo',
          monthlyValue: '300.00',
          defaultDueDay: 1,
        ),
        idempotencyKey: key,
      );
      expect(p.id, 'p-new');
      expect(p.name, 'Novo');
    });
  });

  group('update', () {
    test('PATCH semântico (só fields presentes)', () async {
      adapter.onPatch(
        '/v1/academies/aid/plans/p-1',
        (s) => s.reply(200, {...planJson(), 'monthly_value': '250.00'}),
        data: {'monthly_value': '250.00'},
      );
      final p = await repo.update(
        'aid',
        'p-1',
        const UpdatePlanRequest(monthlyValue: '250.00'),
      );
      expect(p.monthlyValue, '250.00');
    });
  });

  group('delete', () {
    test('204 retorna void', () async {
      adapter.onDelete(
        '/v1/academies/aid/plans/p-1',
        (s) => s.reply(204, null),
      );
      await repo.delete('aid', 'p-1');
    });

    test('409 quando plano tem alunos ativos', () async {
      adapter.onDelete(
        '/v1/academies/aid/plans/p-1',
        (s) => s.reply(409, {
          'type': 'https://tatami.dev/errors/plan-in-use',
          'title': 'Plan in use',
          'status': 409,
          'detail': '5 students still assigned',
        }),
      );
      try {
        await repo.delete('aid', 'p-1');
        fail('expected 409');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isConflict, isTrue);
      }
    });
  });

  group('assignStudents / unassignStudent', () {
    test('assign envia student_ids em uma chamada', () async {
      adapter.onPost(
        '/v1/academies/aid/plans/p-1/students',
        (s) => s.reply(204, null),
        data: {
          'student_ids': ['s-1', 's-2', 's-3']
        },
      );
      await repo.assignStudents('aid', 'p-1', ['s-1', 's-2', 's-3']);
    });

    test('unassign DELETE no /students/{sid}', () async {
      adapter.onDelete(
        '/v1/academies/aid/plans/p-1/students/s-2',
        (s) => s.reply(204, null),
      );
      await repo.unassignStudent('aid', 'p-1', 's-2');
    });
  });
}
