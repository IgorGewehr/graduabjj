import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/gamification.dart';

void main() {
  group('effectiveMonthlyGoal', () {
    test('student override wins when > 0', () {
      expect(effectiveMonthlyGoal(8, 12), 8);
    });
    test('falls back to academy default', () {
      expect(effectiveMonthlyGoal(null, 12), 12);
      expect(effectiveMonthlyGoal(0, 12), 12);
    });
    test('returns 0 (off) when neither set', () {
      expect(effectiveMonthlyGoal(null, 0), 0);
      expect(effectiveMonthlyGoal(0, 0), 0);
    });
  });

  group('monthlyGoalProgress', () {
    test('partial progress', () {
      final p = monthlyGoalProgress(6, 12);
      expect(p.pct, closeTo(0.5, 0.0001));
      expect(p.reached, isFalse);
      expect(p.remaining, 6);
    });
    test('reached and capped at 1.0', () {
      final p = monthlyGoalProgress(15, 12);
      expect(p.pct, 1.0);
      expect(p.reached, isTrue);
      expect(p.remaining, 0);
    });
    test('exactly reached', () {
      final p = monthlyGoalProgress(12, 12);
      expect(p.reached, isTrue);
      expect(p.remaining, 0);
    });
    test('goal 0 -> no progress', () {
      final p = monthlyGoalProgress(5, 0);
      expect(p.pct, 0);
      expect(p.reached, isFalse);
    });
    test('negative count clamps to 0', () {
      final p = monthlyGoalProgress(-3, 10);
      expect(p.pct, 0);
      expect(p.remaining, 10);
    });
  });
}
