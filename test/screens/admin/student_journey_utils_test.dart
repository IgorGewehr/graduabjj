import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/screens/admin/widgets/student_journey_utils.dart';
import 'package:graduabjj/services/achievement_service.dart';
import 'package:graduabjj/services/belt_progression_service.dart';

void main() {
  final promotedAt = DateTime(2026, 8, 10, 9);
  final progression = BeltProgression(
    id: 'progression-1',
    studentId: 'student-1',
    previousBelt: 'white',
    previousStripes: 4,
    newBelt: 'blue',
    newStripes: 0,
    promotionDate: promotedAt,
    totalClasses: 120,
    sport: 'bjj',
    createdAt: promotedAt,
  );

  Achievement achievement({
    AchievementType type = AchievementType.graduation,
    DateTime? date,
    String? sport = 'bjj',
    String? toBelt = 'blue',
    int? toStripes,
  }) {
    return Achievement(
      id: 'achievement-1',
      studentId: 'student-1',
      studentName: 'Aluno',
      type: type,
      title: 'Graduação para faixa azul',
      date: date ?? promotedAt,
      sport: sport,
      toBelt: toBelt,
      toStripes: toStripes,
      isPublic: true,
      createdAt: promotedAt,
    );
  }

  test('oculta conquista que espelha a mesma graduação', () {
    expect(
      isMirroredProgressionAchievement(achievement(), [progression]),
      isTrue,
    );
  });

  test('mantém conquista de faixa em data ou modalidade diferente', () {
    expect(
      isMirroredProgressionAchievement(
        achievement(date: DateTime(2026, 8, 11)),
        [progression],
      ),
      isFalse,
    );
    expect(
      isMirroredProgressionAchievement(achievement(sport: 'judo'), [
        progression,
      ]),
      isFalse,
    );
  });

  test('nunca trata marco comum como progressão espelhada', () {
    expect(
      isMirroredProgressionAchievement(
        achievement(type: AchievementType.milestone, toBelt: null),
        [progression],
      ),
      isFalse,
    );
  });
}
