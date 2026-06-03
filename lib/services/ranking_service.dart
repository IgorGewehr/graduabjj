import '../models/ranking_entry.dart';
import '../models/student.dart';
import 'attendance_service.dart';
import 'student_service.dart';

/// Computes per-class attendance rankings over a [RankingPeriod].
///
/// Data layer only — no UI. The ranking is derived from a single ranged
/// attendance query per class (equality on `classId` + range on `date`),
/// which uses the existing composite index `attendance (classId ASC,
/// date DESC)` declared in `firestore.indexes.json`.
class RankingService {
  final String academyId;

  RankingService(this.academyId);

  /// Returns the ranking for [classId] over [period], highest attendance first.
  ///
  /// Period window (local time):
  /// - [RankingPeriod.week]  → current week, Monday 00:00 .. now.
  /// - [RankingPeriod.month] → current month, day 1 00:00 .. now.
  ///
  /// Students with zero attendance in the window are excluded. Ranks are
  /// 1-based, ties broken by most-recent attendance (desc). At most [limit]
  /// entries are returned.
  Future<List<RankingEntry>> getRanking({
    required String classId,
    required RankingPeriod period,
    int limit = 100,
  }) async {
    final now = DateTime.now();
    final (start, end) = periodRange(period, now);

    // Single ranged query for the class: equality(classId) + range(date).
    final attendance = await AttendanceService(academyId).getByDateRange(
      start,
      end,
      classId: classId,
    );

    // Reduce to raw (studentId, date) pairs and rank in a pure, testable step.
    final ranked = rankFromPairs(
      attendance.map((a) => (studentId: a.studentId, date: a.date)).toList(),
    );
    if (ranked.isEmpty) return const [];

    // Denormalized name fallback carried on each attendance record. Used when
    // the public-profile mirror is missing (legacy / not-yet-synced student) so
    // the ranking still shows a name instead of always degrading to "Aluno".
    final fallbackNames = <String, String>{};
    for (final a in attendance) {
      if (a.studentName.isNotEmpty) {
        fallbackNames[a.studentId] = a.studentName;
      }
    }

    // Hydrate name/photo only for students that appear in the ranking. Read the
    // privacy-correct mirror (publicProfiles) — NEVER the PII-laden student doc.
    // A missing/denied mirror must never break the ranking: degrade to the
    // attendance-record name, else "Aluno", with a null photo.
    final studentService = StudentService(academyId);
    final hydrated = await Future.wait(
      ranked.take(limit).map((r) async {
        Student? profile;
        try {
          profile = await studentService.getPublicProfile(r.studentId);
        } catch (_) {
          // Missing/denied mirror — degrade gracefully (see fallback below).
          profile = null;
        }
        return RankingEntry(
          studentId: r.studentId,
          studentName: profile?.displayName ??
              fallbackNames[r.studentId] ??
              'Aluno',
          photoUrl: profile?.photoUrl,
          attendanceCount: r.attendanceCount,
          rank: r.rank,
          mostRecentAttendance: r.mostRecentAttendance,
        );
      }),
    );
    return hydrated;
  }

  /// 1-based rank of [studentId] in the [classId] ranking for [period], or
  /// null when the student has no attendance in the period.
  Future<int?> getStudentRank({
    required String classId,
    required String studentId,
    required RankingPeriod period,
  }) async {
    // Use a large limit so the target student is never truncated out.
    final ranking = await getRanking(
      classId: classId,
      period: period,
      limit: 100000,
    );
    for (final entry in ranking) {
      if (entry.studentId == studentId) return entry.rank;
    }
    return null;
  }

  /// Computes the [start, end] window for [period] relative to [now]
  /// (local time). Exposed for testing.
  static (DateTime, DateTime) periodRange(RankingPeriod period, DateTime now) {
    switch (period) {
      case RankingPeriod.week:
        // DateTime.weekday: Monday = 1 ... Sunday = 7.
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (monday, now);
      case RankingPeriod.month:
        return (DateTime(now.year, now.month, 1), now);
    }
  }

  /// Pure helper: groups raw (studentId, date) pairs into ranked entries.
  ///
  /// Counts per student, tracks the max date as `mostRecentAttendance`, sorts
  /// by count desc with most-recent-attendance desc as tie-break, then assigns
  /// 1-based ranks. Students with no pairs simply never appear. Exposed
  /// (static, no Firestore) so ranking math can be unit-tested in isolation.
  static List<({
    String studentId,
    int attendanceCount,
    int rank,
    DateTime? mostRecentAttendance,
  })> rankFromPairs(List<({String studentId, DateTime date})> pairs) {
    final counts = <String, int>{};
    final mostRecent = <String, DateTime>{};
    for (final p in pairs) {
      counts[p.studentId] = (counts[p.studentId] ?? 0) + 1;
      final cur = mostRecent[p.studentId];
      if (cur == null || p.date.isAfter(cur)) {
        mostRecent[p.studentId] = p.date;
      }
    }

    final entries = counts.keys.map((id) {
      return (
        studentId: id,
        attendanceCount: counts[id]!,
        mostRecentAttendance: mostRecent[id],
      );
    }).toList();

    entries.sort((a, b) {
      final byCount = b.attendanceCount.compareTo(a.attendanceCount);
      if (byCount != 0) return byCount;
      final ad = a.mostRecentAttendance;
      final bd = b.mostRecentAttendance;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    return [
      for (var i = 0; i < entries.length; i++)
        (
          studentId: entries[i].studentId,
          attendanceCount: entries[i].attendanceCount,
          rank: i + 1,
          mostRecentAttendance: entries[i].mostRecentAttendance,
        ),
    ];
  }
}
