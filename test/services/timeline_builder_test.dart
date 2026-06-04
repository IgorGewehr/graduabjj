import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/sports.dart';
import 'package:graduabjj/models/student.dart';
import 'package:graduabjj/services/achievement_service.dart';
import 'package:graduabjj/services/belt_progression_service.dart';
import 'package:graduabjj/services/timeline_builder.dart';

// Unit tests for the shared timeline motor extracted from timeline_screen.dart.
// No Firestore / widgets — buildTimelineEvents is pure, so we feed it synthetic
// students, progressions and achievements and assert ordering + filtering.

Student _student({
  DateTime? startDate,
  DateTime? jiujitsuStartDate,
  List<String>? sportsList,
  String? primarySport,
  Map<String, dynamic>? sportData,
}) {
  final now = DateTime.utc(2020, 1, 1);
  return Student(
    id: 'stu-1',
    fullName: 'Aluno Teste',
    startDate: startDate ?? DateTime.utc(2018, 1, 1),
    jiujitsuStartDate: jiujitsuStartDate,
    currentBelt: 'white',
    currentStripes: 0,
    category: StudentCategory.adult,
    status: StudentStatus.active,
    tuitionValue: 0,
    tuitionDay: 1,
    sportsList: sportsList,
    primarySport: primarySport,
    sportData: sportData,
    createdAt: now,
    updatedAt: now,
  );
}

BeltProgression _progression({
  required String id,
  required String previousBelt,
  required String newBelt,
  int newStripes = 0,
  required DateTime date,
  String? sport,
}) {
  return BeltProgression(
    id: id,
    studentId: 'stu-1',
    previousBelt: previousBelt,
    previousStripes: 0,
    newBelt: newBelt,
    newStripes: newStripes,
    promotionDate: date,
    totalClasses: 0,
    sport: sport,
    createdAt: date,
  );
}

Achievement _achievement({
  required String id,
  required AchievementType type,
  required String title,
  required DateTime date,
  String? sport,
  CompetitionPosition? position,
}) {
  return Achievement(
    id: id,
    studentId: 'stu-1',
    studentName: 'Aluno Teste',
    type: type,
    title: title,
    date: date,
    sport: sport,
    position: position,
    createdAt: date,
  );
}

void main() {
  group('buildTimelineEvents — synthetic start marker', () {
    test('always injects a start event tagged to the primary sport', () {
      final events = buildTimelineEvents(
        student: _student(startDate: DateTime.utc(2018, 6, 1)),
        achievements: const [],
        progressions: const [],
      );

      expect(events, hasLength(1));
      expect(events.single.type, TimelineEventType.start);
      expect(events.single.id, 'start');
      expect(events.single.date, DateTime.utc(2018, 6, 1));
      expect(events.single.sportId, SportId.bjj);
    });

    test('prefers jiujitsuStartDate over the generic startDate', () {
      final events = buildTimelineEvents(
        student: _student(
          startDate: DateTime.utc(2018, 1, 1),
          jiujitsuStartDate: DateTime.utc(2017, 3, 1),
        ),
        achievements: const [],
        progressions: const [],
      );

      expect(events.single.date, DateTime.utc(2017, 3, 1));
    });

    test('per-sport sportData startDate takes precedence for that sport', () {
      final student = _student(
        startDate: DateTime.utc(2018, 1, 1),
        sportsList: const ['bjj', 'muaythai'],
        primarySport: 'muaythai',
        sportData: {
          'muaythai': {'startDate': DateTime.utc(2019, 9, 1)},
        },
      );

      final events = buildTimelineEvents(
        student: student,
        achievements: const [],
        progressions: const [],
        sportFilter: SportId.muaythai,
      );

      final start = events.firstWhere((e) => e.type == TimelineEventType.start);
      expect(start.date, DateTime.utc(2019, 9, 1));
      expect(start.sportId, SportId.muaythai);
    });
  });

  group('buildTimelineEvents — ordering', () {
    test('events are sorted by date ascending (start, then chronological)', () {
      final student = _student(startDate: DateTime.utc(2018, 1, 1));

      final events = buildTimelineEvents(
        student: student,
        achievements: [
          _achievement(
            id: 'comp',
            type: AchievementType.competition,
            title: 'Open',
            date: DateTime.utc(2021, 5, 1),
          ),
        ],
        progressions: [
          _progression(
            id: 'p1',
            previousBelt: 'white',
            newBelt: 'blue',
            date: DateTime.utc(2019, 1, 1),
          ),
          _progression(
            id: 'p2',
            previousBelt: 'blue',
            newBelt: 'purple',
            date: DateTime.utc(2022, 1, 1),
          ),
        ],
      );

      expect(
        events.map((e) => e.date).toList(),
        [
          DateTime.utc(2018, 1, 1), // start
          DateTime.utc(2019, 1, 1), // blue
          DateTime.utc(2021, 5, 1), // competition
          DateTime.utc(2022, 1, 1), // purple
        ],
      );
      expect(events.first.type, TimelineEventType.start);
    });
  });

  group('buildTimelineEvents — event synthesis', () {
    test('belt change -> graduation, same belt -> stripe', () {
      final events = buildTimelineEvents(
        student: _student(),
        achievements: const [],
        progressions: [
          _progression(
            id: 'grad',
            previousBelt: 'white',
            newBelt: 'blue',
            date: DateTime.utc(2019, 1, 1),
          ),
          _progression(
            id: 'stripe',
            previousBelt: 'blue',
            newBelt: 'blue',
            newStripes: 2,
            date: DateTime.utc(2020, 1, 1),
          ),
        ],
      );

      final grad = events.firstWhere((e) => e.id == 'progression_grad');
      final stripe = events.firstWhere((e) => e.id == 'progression_stripe');
      expect(grad.type, TimelineEventType.graduation);
      expect(stripe.type, TimelineEventType.stripe);
      expect(stripe.title, '2o Grau');
    });

    test('graduation/stripe achievements are skipped (sourced from belts)', () {
      final events = buildTimelineEvents(
        student: _student(),
        achievements: [
          _achievement(
            id: 'gradAch',
            type: AchievementType.graduation,
            title: 'Faixa Azul',
            date: DateTime.utc(2019, 1, 1),
          ),
          _achievement(
            id: 'stripeAch',
            type: AchievementType.stripe,
            title: '1 Grau',
            date: DateTime.utc(2019, 6, 1),
          ),
        ],
        progressions: const [],
      );

      // Only the start marker survives.
      expect(events.where((e) => e.id.startsWith('achievement_')), isEmpty);
      expect(events, hasLength(1));
      expect(events.single.type, TimelineEventType.start);
    });

    test('gamification achievements map to their timeline types', () {
      final events = buildTimelineEvents(
        student: _student(),
        achievements: [
          _achievement(
            id: 'streak',
            type: AchievementType.attendanceStreak,
            title: 'Sequencia',
            date: DateTime.utc(2021, 1, 1),
          ),
          _achievement(
            id: 'rank',
            type: AchievementType.rankingPosition,
            title: 'Top 3',
            date: DateTime.utc(2021, 2, 1),
          ),
          _achievement(
            id: 'pr',
            type: AchievementType.trainingPr,
            title: 'PR Supino',
            date: DateTime.utc(2021, 3, 1),
          ),
          _achievement(
            id: 'milestone',
            type: AchievementType.milestone,
            title: '100 Treinos',
            date: DateTime.utc(2021, 4, 1),
          ),
        ],
        progressions: const [],
      );

      final byId = {for (final e in events) e.id: e.type};
      expect(byId['achievement_streak'], TimelineEventType.attendanceStreak);
      expect(byId['achievement_rank'], TimelineEventType.rankingPosition);
      expect(byId['achievement_pr'], TimelineEventType.trainingPr);
      expect(byId['achievement_milestone'], TimelineEventType.milestone);
    });

    test('competition position flows through to the event', () {
      final events = buildTimelineEvents(
        student: _student(),
        achievements: [
          _achievement(
            id: 'comp',
            type: AchievementType.competition,
            title: 'Open',
            date: DateTime.utc(2021, 5, 1),
            position: CompetitionPosition.gold,
          ),
        ],
        progressions: const [],
      );

      final comp = events.firstWhere((e) => e.id == 'achievement_comp');
      expect(comp.type, TimelineEventType.competition);
      expect(comp.position, CompetitionPosition.gold.value);
    });
  });

  group('buildTimelineEvents — sport filter', () {
    test('null filter keeps every sport (single-sport / unfiltered view)', () {
      final student = _student(sportsList: const ['bjj', 'muaythai']);
      final events = buildTimelineEvents(
        student: student,
        achievements: const [],
        progressions: [
          _progression(
            id: 'bjj',
            previousBelt: 'white',
            newBelt: 'blue',
            date: DateTime.utc(2019, 1, 1),
            sport: 'bjj',
          ),
          _progression(
            id: 'mt',
            previousBelt: 'white',
            newBelt: 'yellow',
            date: DateTime.utc(2020, 1, 1),
            sport: 'muaythai',
          ),
        ],
      );

      final sports = events.map((e) => e.sportId).toSet();
      expect(sports.contains(SportId.bjj), isTrue);
      expect(sports.contains(SportId.muaythai), isTrue);
    });

    test('non-null filter restricts to that sport (legacy null -> bjj)', () {
      final student = _student(
        sportsList: const ['bjj', 'muaythai'],
        primarySport: 'muaythai',
      );
      final events = buildTimelineEvents(
        student: student,
        achievements: [
          // Legacy achievement without a stored sport -> falls back to primary
          // sport (muaythai here) at synthesis time.
          _achievement(
            id: 'legacy',
            type: AchievementType.milestone,
            title: 'Legacy',
            date: DateTime.utc(2021, 1, 1),
          ),
        ],
        progressions: [
          _progression(
            id: 'bjj',
            previousBelt: 'white',
            newBelt: 'blue',
            date: DateTime.utc(2019, 1, 1),
            sport: 'bjj',
          ),
          _progression(
            id: 'mt',
            previousBelt: 'white',
            newBelt: 'yellow',
            date: DateTime.utc(2020, 1, 1),
            sport: 'muaythai',
          ),
        ],
        sportFilter: SportId.muaythai,
      );

      // Only muaythai events survive the filter; the bjj progression is gone.
      expect(events.every((e) => e.sportId == SportId.muaythai), isTrue);
      expect(events.any((e) => e.id == 'progression_mt'), isTrue);
      expect(events.any((e) => e.id == 'progression_bjj'), isFalse);
      // Legacy (sport-less) achievement defaulted to primary sport -> kept.
      expect(events.any((e) => e.id == 'achievement_legacy'), isTrue);
    });
  });
}
