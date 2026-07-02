import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/sports.dart';
import '../models/student.dart';

/// Shared, side-effect-free logic for enrolling a student in a sport.
///
/// This is the single source of truth for *seeding* the multi-sport data on a
/// student doc: it adds the sport to `sports`, seeds `sportData[sport]` with the
/// lowest-rank grade for that sport (resolving the Muay Thai ladder variant from
/// the academy settings), and sets `primarySport` when the student doesn't have
/// one yet.
///
/// It is consumed both by `ClassService` (enrollment as a side-effect of joining
/// a class) and by manual sport management in the student's Profile (enrollment
/// without a class). The caller is responsible for the actual Firestore write —
/// this helper only computes the field updates.
class SportEnrollment {
  const SportEnrollment._();

  /// Computes the Firestore field updates needed to enroll a student in [sport].
  ///
  /// Idempotent: only the missing pieces are returned, so calling it for a
  /// sport the student is already enrolled in yields an empty map.
  ///
  /// - [academySettings] is the academy document data, used to resolve the Muay
  ///   Thai grade ladder variant (`muaythaiGradeSystem`). Pass an empty map when
  ///   not relevant.
  /// - [studentData] is the current student document data, read to decide what
  ///   is already present and to preserve legacy BJJ belt/stripes.
  /// - [classCategory] is the originating class category, when enrolling via a
  ///   class; falls back to the student's `category` (then `adult`).
  ///
  /// The returned map never includes `updatedAt` — the caller adds its own
  /// server timestamp alongside the write.
  static Map<String, dynamic> seedSportData(
    SportId sport, {
    required Map<String, dynamic> academySettings,
    required Map<String, dynamic> studentData,
    StudentCategory? classCategory,
  }) {
    final sportValue = sport.value;

    final existingSports =
        (studentData['sports'] as List?)?.cast<String>() ?? const [];
    final existingSportData =
        (studentData['sportData'] as Map?)?.cast<String, dynamic>() ?? const {};
    final existingPrimary = studentData['primarySport'] as String?;

    final updates = <String, dynamic>{};

    if (!existingSports.contains(sportValue)) {
      updates['sports'] = FieldValue.arrayUnion([sportValue]);
    }

    if (!existingSportData.containsKey(sportValue)) {
      final category = classCategory?.value ??
          (studentData['category'] as String?) ??
          'adult';
      // Muay Thai's starting grade depends on the academy's chosen ladder.
      String? muaythaiVariant;
      if (sport == SportId.muaythai) {
        muaythaiVariant = academySettings['muaythaiGradeSystem'] as String?;
      }
      final grades = getGradesForSport(
        sport,
        category: category,
        muaythaiVariant: muaythaiVariant,
      );
      final defaultGrade = grades.isNotEmpty ? grades.first.id : 'white';

      // For BJJ the legacy `currentBelt`/`currentStripes` fields already hold
      // the grade — preserve them so we don't downgrade existing students.
      final isLegacyBjj =
          sport == SportId.bjj && studentData['currentBelt'] != null;
      updates['sportData.$sportValue'] = {
        'currentGrade': isLegacyBjj ? studentData['currentBelt'] : defaultGrade,
        'currentStripes': isLegacyBjj ? (studentData['currentStripes'] ?? 0) : 0,
      };
    }

    if (existingPrimary == null || existingPrimary.isEmpty) {
      updates['primarySport'] = sportValue;
    }

    return updates;
  }
}
