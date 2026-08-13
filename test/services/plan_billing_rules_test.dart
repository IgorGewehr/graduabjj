import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/plan_service.dart';

Plan buildPlan({
  DateTime? createdAt,
  List<String> studentIds = const ['a'],
  Map<String, double> customValues = const {},
  Map<String, DateTime> studentAddedAt = const {},
}) {
  return Plan(
    id: 'plan',
    name: 'Plano',
    monthlyValue: 100,
    studentIds: studentIds,
    customValues: customValues,
    studentAddedAt: studentAddedAt,
    createdAt: createdAt ?? DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );
}

void main() {
  test('plan and membership created on due date are eligible', () {
    final plan = buildPlan(
      createdAt: DateTime(2026, 8, 10, 23),
      studentAddedAt: {'a': DateTime(2026, 8, 10, 23, 59)},
    );

    expect(
      plan.isStudentEligibleForMonth('a', year: 2026, month: 8, dueDay: 10),
      isTrue,
    );
  });

  test('plan or membership created after due date is deferred', () {
    expect(
      buildPlan(
        createdAt: DateTime(2026, 8, 11),
      ).isStudentEligibleForMonth('a', year: 2026, month: 8, dueDay: 10),
      isFalse,
    );
    expect(
      buildPlan(
        studentAddedAt: {'a': DateTime(2026, 8, 11)},
      ).isStudentEligibleForMonth('a', year: 2026, month: 8, dueDay: 10),
      isFalse,
    );
  });

  test('expected revenue counts active roster and custom values exactly', () {
    final plan = buildPlan(
      studentIds: const ['a', 'b', 'inactive'],
      customValues: const {'b': 80, 'removed': 999},
    );

    expect(plan.expectedPeriodRevenue({'a', 'b'}), 180);
    expect(plan.activeStudentIds({'a', 'b'}), unorderedEquals(['a', 'b']));
  });
}
