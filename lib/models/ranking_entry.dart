/// Period over which a class attendance ranking is computed.
enum RankingPeriod {
  /// Current week, Monday 00:00 (local) through "now".
  week,

  /// Current month, day 1 00:00 (local) through "now".
  month,
}

/// Audience filter for the attendance ranking.
///
/// Grouping is by the *class* category ([BJJClass.category]): kids and adult
/// classes are distinct classes, so this matches the student's age category in
/// practice. Classes with no category set (legacy) fall into the [adult]
/// bucket (most academies are adult-default).
enum RankingCategory {
  /// Every class in the academy.
  general,

  /// Only classes tagged `StudentCategory.adult`.
  adult,

  /// Only classes tagged `StudentCategory.kids`.
  kids,
}

extension RankingCategoryExtension on RankingCategory {
  String get label {
    switch (this) {
      case RankingCategory.general:
        return 'Geral';
      case RankingCategory.adult:
        return 'Adulto';
      case RankingCategory.kids:
        return 'Kids';
    }
  }
}

/// A single row in a class attendance ranking.
///
/// Plain value object built by [RankingService] from grouped attendance
/// records — there is no Firestore parsing here.
class RankingEntry {
  final String studentId;
  final String studentName;
  final String? photoUrl;

  /// Number of attendance records for this student within the period.
  final int attendanceCount;

  /// 1-based position in the ranking (1 = top).
  final int rank;

  /// Most recent attendance date within the period, used as the tie-break.
  final DateTime? mostRecentAttendance;

  const RankingEntry({
    required this.studentId,
    required this.studentName,
    this.photoUrl,
    required this.attendanceCount,
    required this.rank,
    this.mostRecentAttendance,
  });
}
