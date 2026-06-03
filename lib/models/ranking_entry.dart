/// Period over which a class attendance ranking is computed.
enum RankingPeriod {
  /// Current week, Monday 00:00 (local) through "now".
  week,

  /// Current month, day 1 00:00 (local) through "now".
  month,
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
