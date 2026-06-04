import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/graduation_factors.dart';

void main() {
  group('computeSkillFactors', () {
    test('informative: nunca bloqueia, mas calcula o %', () {
      final f = computeSkillFactors(
        dominatedCount: 3,
        totalForGrade: 10,
        policy: graduationSkillInformative,
        minSkillPct: 80,
      );
      expect(f.done, 3);
      expect(f.total, 10);
      expect(f.pct, 30);
      expect(f.required, isFalse);
      expect(f.met, isTrue);
    });

    test('required: bloqueia abaixo do mínimo', () {
      final f = computeSkillFactors(
        dominatedCount: 7,
        totalForGrade: 10,
        policy: graduationSkillRequired,
        minSkillPct: 80,
      );
      expect(f.pct, 70);
      expect(f.required, isTrue);
      expect(f.met, isFalse);
    });

    test('required: atende no mínimo (>=)', () {
      final f = computeSkillFactors(
        dominatedCount: 8,
        totalForGrade: 10,
        policy: graduationSkillRequired,
        minSkillPct: 80,
      );
      expect(f.pct, 80);
      expect(f.met, isTrue);
    });

    test('required sem currículo (total 0) não bloqueia', () {
      final f = computeSkillFactors(
        dominatedCount: 0,
        totalForGrade: 0,
        policy: graduationSkillRequired,
        minSkillPct: 80,
      );
      expect(f.pct, isNull);
      expect(f.total, 0);
      expect(f.met, isTrue);
    });

    test('dominated é limitado ao total', () {
      final f = computeSkillFactors(
        dominatedCount: 12,
        totalForGrade: 10,
        policy: graduationSkillInformative,
        minSkillPct: 80,
      );
      expect(f.done, 10);
      expect(f.pct, 100);
    });
  });

  group('daysInBelt', () {
    final now = DateTime(2026, 6, 4);
    test('usa última promoção quando há', () {
      expect(
        daysInBelt(
            lastPromotion: DateTime(2026, 5, 5),
            startDate: DateTime(2020, 1, 1),
            now: now),
        30,
      );
    });

    test('cai para startDate sem promoção', () {
      expect(
        daysInBelt(lastPromotion: null, startDate: DateTime(2026, 5, 5), now: now),
        30,
      );
    });

    test('null quando não há datas; nunca negativo', () {
      expect(daysInBelt(now: now), isNull);
      expect(
        daysInBelt(lastPromotion: DateTime(2026, 7, 1), now: now),
        0,
      );
    });
  });
}
