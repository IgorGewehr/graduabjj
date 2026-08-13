import '../../../core/sports.dart';
import '../../../services/achievement_service.dart';
import '../../../services/belt_progression_service.dart';

/// Identifica o registro de conquista criado como espelho de uma progressão.
/// A Jornada exibe a progressão, que é a fonte técnica da faixa/grau, uma vez.
bool isMirroredProgressionAchievement(
  Achievement achievement,
  Iterable<BeltProgression> progressions,
) {
  final isGraduation = achievement.type == AchievementType.graduation;
  final isStripe = achievement.type == AchievementType.stripe;
  if (!isGraduation && !isStripe) return false;

  final achievementSport = SportId.fromString(achievement.sport ?? 'bjj');
  return progressions.any((progression) {
    final sameDay =
        progression.promotionDate.year == achievement.date.year &&
        progression.promotionDate.month == achievement.date.month &&
        progression.promotionDate.day == achievement.date.day;
    if (!sameDay || progression.getSport() != achievementSport) return false;

    return isGraduation
        ? achievement.toBelt == progression.newBelt
        : achievement.toStripes == progression.newStripes;
  });
}
