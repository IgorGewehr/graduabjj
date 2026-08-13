import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/ranking_service.dart';
import 'package:graduabjj/models/ranking_entry.dart';

void main() {
  group('RankingService.rankFromPairs', () {
    test('counts attendances per student and assigns 1-based ranks', () {
      final pairs = [
        (studentId: 'a', date: DateTime(2026, 6, 1)),
        (studentId: 'a', date: DateTime(2026, 6, 2)),
        (studentId: 'a', date: DateTime(2026, 6, 3)),
        (studentId: 'b', date: DateTime(2026, 6, 1)),
      ];

      final ranked = RankingService.rankFromPairs(pairs);

      expect(ranked.length, 2);
      expect(ranked[0].studentId, 'a');
      expect(ranked[0].attendanceCount, 3);
      expect(ranked[0].rank, 1);
      expect(ranked[0].mostRecentAttendance, DateTime(2026, 6, 3));
      expect(ranked[1].studentId, 'b');
      expect(ranked[1].rank, 2);
    });

    test('breaks count ties by most-recent attendance (desc)', () {
      final pairs = [
        (studentId: 'older', date: DateTime(2026, 6, 1)),
        (studentId: 'older', date: DateTime(2026, 6, 2)),
        (studentId: 'newer', date: DateTime(2026, 6, 3)),
        (studentId: 'newer', date: DateTime(2026, 6, 5)),
      ];

      final ranked = RankingService.rankFromPairs(pairs);

      expect(ranked.map((e) => e.studentId).toList(), ['newer', 'older']);
      expect(ranked[0].rank, 1);
      expect(ranked[1].rank, 2);
    });

    test('returns empty for no pairs', () {
      expect(RankingService.rankFromPairs(const []), isEmpty);
    });

    test('rank order is stable and contiguous', () {
      final pairs = [
        (studentId: 'a', date: DateTime(2026, 6, 4)),
        (studentId: 'a', date: DateTime(2026, 6, 5)),
        (studentId: 'b', date: DateTime(2026, 6, 6)),
        (studentId: 'b', date: DateTime(2026, 6, 7)),
        (studentId: 'c', date: DateTime(2026, 6, 1)),
      ];

      final ranked = RankingService.rankFromPairs(pairs);

      // a & b tie on count(2); b is more recent → b#1, a#2; c#3.
      expect(ranked.map((e) => e.studentId).toList(), ['b', 'a', 'c']);
      expect(ranked.map((e) => e.rank).toList(), [1, 2, 3]);
    });
  });

  group('RankingService.periodRange', () {
    test('week is a rolling seven-day window', () {
      final now = DateTime(2026, 6, 3, 14, 30);
      final (start, end) = RankingService.periodRange(RankingPeriod.week, now);
      expect(start, DateTime(2026, 5, 28));
      expect(end, now);
    });

    test('week remains rolling when today is Monday', () {
      final now = DateTime(2026, 6, 1, 9);
      final (start, _) = RankingService.periodRange(RankingPeriod.week, now);
      expect(start, DateTime(2026, 5, 26));
    });

    test('month is a rolling thirty-day window', () {
      final now = DateTime(2026, 6, 17, 8);
      final (start, end) = RankingService.periodRange(RankingPeriod.month, now);
      expect(start, DateTime(2026, 5, 19));
      expect(end, now);
    });
  });
}
