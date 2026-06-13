import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/meso.dart';

void main() {
  final start = DateTime(2026, 6, 1); // Monday

  group('currentMesoWeek', () {
    test('null when no start date or no weeks', () {
      expect(currentMesoWeek(null, DateTime(2026, 6, 10), 6), isNull);
      expect(currentMesoWeek(start, DateTime(2026, 6, 10), 0), isNull);
    });
    test('day 0 -> week 1', () {
      expect(currentMesoWeek(start, DateTime(2026, 6, 1), 6), 1);
    });
    test('within week 1 (days 0-6)', () {
      expect(currentMesoWeek(start, DateTime(2026, 6, 7), 6), 1);
    });
    test('day 7 -> week 2', () {
      expect(currentMesoWeek(start, DateTime(2026, 6, 8), 6), 2);
    });
    test('day 21 -> week 4', () {
      expect(currentMesoWeek(start, DateTime(2026, 6, 22), 6), 4);
    });
    test('before start -> clamped to week 1', () {
      expect(currentMesoWeek(start, DateTime(2026, 5, 20), 6), 1);
    });
    test('past the end -> clamped to last week', () {
      expect(currentMesoWeek(start, DateTime(2026, 9, 1), 6), 6);
    });
  });
}
