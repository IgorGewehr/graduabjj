import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/achievement_service.dart';

// fake_cloud_firestore is NOT a dev_dependency in this repo and
// DocumentSnapshot is sealed, so we exercise the pure parsing seam
// Achievement.fromMap (which Achievement.fromFirestore delegates to).
// Covers: legacy docs (no gamification fields) and new docs (all fields).
void main() {
  group('AchievementType enum back-compat', () {
    test('round-trips every value via value/fromString', () {
      for (final t in AchievementType.values) {
        expect(AchievementTypeExtension.fromString(t.value), t);
      }
    });

    test('new gamification values serialize stably', () {
      expect(AchievementType.attendanceStreak.value, 'attendanceStreak');
      expect(AchievementType.rankingPosition.value, 'rankingPosition');
      expect(AchievementType.trainingPr.value, 'trainingPr');
    });

    test('unknown/legacy values fall back to milestone', () {
      expect(AchievementTypeExtension.fromString(''), AchievementType.milestone);
      expect(AchievementTypeExtension.fromString('bogus'),
          AchievementType.milestone);
      // Pre-existing docs already stored these — must keep parsing.
      expect(AchievementTypeExtension.fromString('graduation'),
          AchievementType.graduation);
    });
  });

  group('Achievement.fromMap — legacy doc (no gamification fields)', () {
    test('parses without errors and leaves new fields null', () {
      final legacy = <String, dynamic>{
        'studentId': 'stu-1',
        'studentName': 'Aluno Teste',
        'type': 'milestone',
        'title': '100 Treinos!',
        'milestone': 'attendance_100',
        'date': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        // isPublic intentionally absent → defaults to true (existing behavior).
      };

      final a = Achievement.fromMap('ach-legacy', legacy);

      expect(a.id, 'ach-legacy');
      expect(a.type, AchievementType.milestone);
      expect(a.milestone, 'attendance_100');
      expect(a.isPublic, isTrue);
      // New gamification fields default to null on legacy docs.
      expect(a.streakDays, isNull);
      expect(a.rankingScope, isNull);
      expect(a.rankingRank, isNull);
      expect(a.prMetric, isNull);
      expect(a.prValue, isNull);
      expect(a.prUnit, isNull);
      expect(a.iconKey, isNull);
      expect(a.autoKey, isNull);
    });
  });

  group('Achievement.fromMap — new gamification docs', () {
    test('attendanceStreak parses streakDays + autoKey + iconKey', () {
      final data = <String, dynamic>{
        'studentId': 'stu-2',
        'studentName': 'Streaker',
        'type': 'attendanceStreak',
        'title': 'Sequência de 30 dias',
        'streakDays': 30,
        'autoKey': 'streak_30',
        'iconKey': 'flame',
        'isPublic': true,
        'date': Timestamp.fromDate(DateTime.utc(2026, 2, 1)),
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 2, 1)),
      };

      final a = Achievement.fromMap('ach-streak', data);

      expect(a.type, AchievementType.attendanceStreak);
      expect(a.streakDays, 30);
      expect(a.autoKey, 'streak_30');
      expect(a.iconKey, 'flame');
      expect(a.isPublic, isTrue);
    });

    test('rankingPosition parses rankingScope + rankingRank', () {
      final data = <String, dynamic>{
        'studentId': 'stu-3',
        'studentName': 'Ranker',
        'type': 'rankingPosition',
        'title': 'Top 3 da academia',
        'rankingScope': 'academy',
        'rankingRank': 3,
        'autoKey': 'rank_academy_3',
        'isPublic': true,
        'date': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
      };

      final a = Achievement.fromMap('ach-rank', data);

      expect(a.type, AchievementType.rankingPosition);
      expect(a.rankingScope, 'academy');
      expect(a.rankingRank, 3);
      expect(a.autoKey, 'rank_academy_3');
    });

    test('trainingPr parses prMetric/prValue/prUnit and is private by default',
        () {
      final data = <String, dynamic>{
        'studentId': 'stu-4',
        'studentName': 'Lifter',
        'type': 'trainingPr',
        'title': 'Novo PR de supino',
        'prMetric': 'supino',
        'prValue': 102.5,
        'prUnit': 'kg',
        'autoKey': 'pr_supino',
        // Owner decision: PRs nascem isPublic=false (privados).
        'isPublic': false,
        'date': Timestamp.fromDate(DateTime.utc(2026, 4, 1)),
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 4, 1)),
      };

      final a = Achievement.fromMap('ach-pr', data);

      expect(a.type, AchievementType.trainingPr);
      expect(a.prMetric, 'supino');
      expect(a.prValue, 102.5);
      expect(a.prUnit, 'kg');
      expect(a.isPublic, isFalse);
    });

    test('numeric fields tolerate int-or-double from Firestore', () {
      final data = <String, dynamic>{
        'studentId': 'stu-5',
        'studentName': 'Coerce',
        'type': 'trainingPr',
        'title': 'PR',
        // Firestore may hand back num as int for whole values.
        'prValue': 100,
        'rankingRank': 2,
        'streakDays': 7,
        'date': Timestamp.fromDate(DateTime.utc(2026, 5, 1)),
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 1)),
      };

      final a = Achievement.fromMap('ach-num', data);

      expect(a.prValue, 100);
      expect(a.rankingRank, 2);
      expect(a.streakDays, 7);
    });
  });
}
