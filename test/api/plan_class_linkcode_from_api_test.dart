import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/academy_dto.dart';
import 'package:graduabjj/api/dto/class_dto.dart';
import 'package:graduabjj/api/dto/plan_dto.dart';
import 'package:graduabjj/api/dto/student_dto.dart' show ApiBelt;
import 'package:graduabjj/models/student.dart' show StudentCategory;
import 'package:graduabjj/services/class_service.dart' show BJJClass;
import 'package:graduabjj/services/link_code_service.dart' show LinkCode;
import 'package:graduabjj/services/plan_service.dart' show Plan;

void main() {
  group('Plan.fromApi', () {
    test('monthlyValue decimal-string → double; classes_per_week=0 → null', () {
      final p = Plan.fromApi(ApiPlan.fromJson({
        'id': 'p1',
        'academy_id': 'aid',
        'name': 'Ilimitado',
        'monthly_value': '350.00',
        'default_due_day': 5,
        'classes_per_week': 0,
        'is_active': true,
      }));
      expect(p.id, 'p1');
      expect(p.monthlyValue, 350.0);
      expect(p.classesPerWeek, isNull);
      expect(p.defaultDueDay, 5);
    });

    test('customValues e customDueDays preservados', () {
      final p = Plan.fromApi(ApiPlan.fromJson({
        'id': 'p1',
        'academy_id': 'aid',
        'name': 'Custom',
        'monthly_value': '200.00',
        'default_due_day': 10,
        'classes_per_week': 3,
        'is_active': true,
        'custom_values': {'s-1': '150.00', 's-2': '120.50'},
        'custom_due_days': {'s-1': 15},
      }));
      expect(p.customValues['s-1'], 150.0);
      expect(p.customValues['s-2'], 120.50);
      expect(p.customDueDays['s-1'], 15);
      expect(p.classesPerWeek, 3);
    });

    test('monthlyValue inválido → 0.0 (defensivo)', () {
      final p = Plan.fromApi(ApiPlan.fromJson({
        'id': 'p1',
        'academy_id': 'aid',
        'name': 'X',
        'monthly_value': 'not-a-number',
        'default_due_day': 5,
        'is_active': true,
      }));
      expect(p.monthlyValue, 0.0);
    });
  });

  group('BJJClass.fromApi', () {
    test('schedule + weight + roster', () {
      final c = BJJClass.fromApi(ApiClass.fromJson({
        'id': 'c1',
        'academy_id': 'aid',
        'name': 'BJJ Noite',
        'category': 'adult',
        'sport': 'bjj',
        'schedule': [
          {'day_of_week': 1, 'start_time': '19:00', 'end_time': '20:30'},
          {'day_of_week': 3, 'start_time': '19:00', 'end_time': '20:30'},
        ],
        'max_students': 0,
        'weight': '1.250',
        'is_active': true,
        'student_ids': ['s-1', 's-2'],
      }));
      expect(c.id, 'c1');
      expect(c.name, 'BJJ Noite');
      expect(c.category, StudentCategory.adult);
      expect(c.weight, closeTo(1.250, 1e-6));
      expect(c.maxStudents, isNull); // 0 → null (legacy nullable)
      expect(c.schedule, hasLength(2));
      expect(c.schedule.first.dayOfWeek, 1);
      expect(c.studentIds, ['s-1', 's-2']);
    });

    test('category mixed → null no legacy (kids/adult only)', () {
      final c = BJJClass.fromApi(ApiClass.fromJson({
        'id': 'c1',
        'academy_id': 'aid',
        'name': 'Mixed',
        'category': 'mixed',
        'sport': 'bjj',
        'schedule': [],
        'max_students': 0,
        'weight': '1.000',
        'is_active': true,
        'student_ids': [],
      }));
      expect(c.category, isNull);
    });

    test('min_belt/max_belt mapeiam para wire string', () {
      final c = BJJClass.fromApi(ApiClass.fromJson({
        'id': 'c1',
        'academy_id': 'aid',
        'name': 'Faixas avançadas',
        'category': 'adult',
        'sport': 'bjj',
        'schedule': [],
        'min_belt': 'blue',
        'max_belt': 'black',
        'max_students': 30,
        'weight': '1.000',
        'is_active': true,
        'student_ids': [],
      }));
      expect(c.minBelt, 'blue');
      expect(c.maxBelt, 'black');
      expect(c.maxStudents, 30);
    });

    test('weight inválido → 1.0 default', () {
      final c = BJJClass.fromApi(ApiClass.fromJson({
        'id': 'c1',
        'academy_id': 'aid',
        'name': 'X',
        'category': 'adult',
        'sport': 'bjj',
        'schedule': [],
        'max_students': 0,
        'weight': 'garbage',
        'is_active': true,
        'student_ids': [],
      }));
      expect(c.weight, 1.0);
    });

    // Sanity: ApiBelt.kids_grey vira 'kids_grey'.
    test('kids_grey min_belt converte para wire snake_case', () {
      final c = BJJClass.fromApi(ApiClass.fromJson({
        'id': 'c1',
        'academy_id': 'aid',
        'name': 'Kids',
        'category': 'kids',
        'sport': 'bjj',
        'schedule': [],
        'min_belt': 'kids_grey',
        'max_belt': 'kids_green',
        'max_students': 20,
        'weight': '1.000',
        'is_active': true,
        'student_ids': [],
      }));
      expect(c.minBelt, ApiBelt.kids_grey.name);
      expect(c.maxBelt, ApiBelt.kids_green.name);
    });
  });

  group('LinkCode.fromApi', () {
    test('campos básicos + studentName=empty default', () {
      final lc = LinkCode.fromApi(ApiLinkCode.fromJson({
        'id': 'lc-1',
        'academy_id': 'aid',
        'code': 'ABC123',
        'role': 'student',
        'student_id': 's-1',
        'expires_at': '2026-05-20T10:00:00Z',
        'created_at': '2026-05-19T10:00:00Z',
        'created_by_uid': 'admin-1',
      }));
      expect(lc.code, 'ABC123');
      expect(lc.studentId, 's-1');
      expect(lc.academyId, 'aid');
      expect(lc.createdBy, 'admin-1');
      expect(lc.studentName, '');
    });

    test('studentName override', () {
      final lc = LinkCode.fromApi(
        ApiLinkCode.fromJson({
          'id': 'lc-1',
          'academy_id': 'aid',
          'code': 'ABC123',
          'role': 'student',
          'student_id': 's-1',
          'expires_at': '2026-05-20T10:00:00Z',
        }),
        studentName: 'João',
      );
      expect(lc.studentName, 'João');
    });

    test('null student_id vira string vazia (legacy é non-null)', () {
      final lc = LinkCode.fromApi(ApiLinkCode.fromJson({
        'id': 'lc-1',
        'academy_id': 'aid',
        'code': 'X',
        'role': 'instructor',
        'expires_at': '2026-05-20T10:00:00Z',
      }));
      expect(lc.studentId, '');
    });
  });
}
