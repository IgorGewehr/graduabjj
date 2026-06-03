import '../services/achievement_service.dart' show Achievement;
import '../services/competition_service.dart' show CompetitionResult;
import '../models/competition_photo.dart';
import '../models/student.dart';

/// Aggregated, read-only view of a student composed for the social/ranking
/// surfaces. Built by `publicStudentProfileProvider`; each sub-list is fetched
/// independently and defaults to const [] when its source is empty/unavailable.
class PublicStudentProfile {
  final Student student;
  final List<Achievement> achievements;
  final List<CompetitionResult> competitionResults;
  final List<CompetitionPhoto> photos;

  const PublicStudentProfile({
    required this.student,
    this.achievements = const [],
    this.competitionResults = const [],
    this.photos = const [],
  });
}
