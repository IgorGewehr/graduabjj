import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/competition_photo.dart';
import '../models/public_student_profile.dart';
import '../models/ranking_entry.dart';
import '../services/achievement_service.dart';
import '../services/competition_photo_service.dart';
import '../services/competition_service.dart';
import '../services/ranking_service.dart';
import '../services/student_service.dart';
import 'auth_provider.dart';

/// Ranking service bound to the current user's academy (null when unauthed
/// or before an academy is resolved). Mirrors the other `*ServiceProvider`s.
final rankingServiceProvider = Provider<RankingService?>((ref) {
  final currentUser = ref.watch(currentUserProvider).valueOrNull;
  if (currentUser?.academyId == null) return null;
  return RankingService(currentUser!.academyId!);
});

/// Attendance ranking for a class over a period.
final classRankingProvider = FutureProvider.family<List<RankingEntry>,
    ({String classId, RankingPeriod period})>((ref, args) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return const [];
  return RankingService(currentUser!.academyId!).getRanking(
    classId: args.classId,
    period: args.period,
  );
});

/// 1-based rank of a student in a class ranking (null if no attendance).
final studentRankProvider = FutureProvider.family<int?,
    ({String classId, String studentId, RankingPeriod period})>(
        (ref, args) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser?.academyId == null) return null;
  return RankingService(currentUser!.academyId!).getStudentRank(
    classId: args.classId,
    studentId: args.studentId,
    period: args.period,
  );
});

/// Composed public profile for a student, viewed from inside the portal.
///
/// All portal users are academy members, so members always see the profile;
/// the `student.isProfilePublic` flag only gates non-member (web/public)
/// access elsewhere. Returns null only when the student does not exist.
///
/// Each sub-fetch is wrapped so a single failing/empty source degrades to []
/// instead of nulling the whole profile.
final publicStudentProfileProvider = FutureProvider.family<
    PublicStudentProfile?, ({String academyId, String studentId})>(
        (ref, args) async {
  // Read the privacy-correct mirror (publicProfiles) instead of the PII-laden
  // student doc, so a member viewing a peer never hits sensitive data. If the
  // mirror is missing (legacy/not-yet-synced student), the profile is not
  // available → return null.
  final student =
      await StudentService(args.academyId).getPublicProfile(args.studentId);
  if (student == null) return null;

  final achievements = await AchievementService(args.academyId)
      .getPublic(args.studentId)
      .catchError((_) => <Achievement>[]);

  final competitionResults = await CompetitionService(args.academyId)
      .getResultsForStudent(args.studentId)
      .catchError((_) => <CompetitionResult>[]);

  final photos = await CompetitionPhotoService()
      .getPhotosByStudent(
        academyId: args.academyId,
        studentId: args.studentId,
      )
      .catchError((_) => <CompetitionPhoto>[]);

  return PublicStudentProfile(
    student: student,
    achievements: achievements,
    competitionResults: competitionResults,
    photos: photos,
  );
});
