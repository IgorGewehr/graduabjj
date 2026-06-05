import 'package:cloud_functions/cloud_functions.dart';

import '../models/ranking_entry.dart';
import '../models/student.dart';
import 'student_service.dart';

/// Computes attendance rankings over a [RankingPeriod], optionally scoped to a
/// set of classes (e.g. all kids classes, or all adult classes).
///
/// Data layer only — no UI. The ranking is derived from a single ranged,
/// date-only attendance query for the whole academy (range on `date`, served
/// by Firestore's auto single-field index), then filtered in memory to the
/// requested classes. A single window-bounded query keeps this to one round
/// trip whether the caller wants one category or everything.
class RankingService {
  final String academyId;
  final FirebaseFunctions _functions;

  RankingService(this.academyId, {FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Returns the ranking over [period], highest attendance first.
  ///
  /// [classIds] scopes which classes count: `null` aggregates every class in
  /// the academy (the "Geral" view); a set restricts to attendance in those
  /// classes (the "Adulto" / "Kids" views). An empty set yields no ranking.
  ///
  /// Period window (local time):
  /// - [RankingPeriod.week]  → current week, Monday 00:00 .. now.
  /// - [RankingPeriod.month] → current month, day 1 00:00 .. now.
  ///
  /// Students with zero attendance in the window are excluded. Ranks are
  /// 1-based, ties broken by most-recent attendance (desc). At most [limit]
  /// entries are returned.
  Future<List<RankingEntry>> getRanking({
    required RankingPeriod period,
    Set<String>? classIds,
    int limit = 100,
  }) async {
    if (classIds != null && classIds.isEmpty) return const [];

    final now = DateTime.now();
    final (start, end) = periodRange(period, now);

    // Ranking is computed SERVER-SIDE (getAttendanceRanking CF): a plain student
    // cannot read peers' raw attendance (staff/monitor-only by the Firestore
    // rules, since attendance carries weight/notes), so the function aggregates
    // it and returns only PII-light rows. We send the period window we already
    // computed so the server window matches the client's exactly (no TZ drift).
    final res = await _functions.httpsCallable('getAttendanceRanking').call({
      'academyId': academyId,
      'startMillis': start.millisecondsSinceEpoch,
      'endMillis': end.millisecondsSinceEpoch,
      if (classIds != null) 'classIds': classIds.toList(),
      'limit': limit,
    });

    final data = Map<String, dynamic>.from(res.data as Map);
    final rawEntries = (data['entries'] as List?) ?? const [];
    if (rawEntries.isEmpty) return const [];

    // Hydrate name/photo only for students that appear in the ranking. Read the
    // privacy-correct mirror (publicProfiles) — NEVER the PII-laden student doc.
    // A missing/denied mirror must never break the ranking: degrade to the
    // denormalized name returned by the function, else "Aluno", null photo.
    final studentService = StudentService(academyId);
    final hydrated = await Future.wait(
      rawEntries.map((raw) async {
        final m = Map<String, dynamic>.from(raw as Map);
        final studentId = m['studentId'] as String;
        final fallbackName = (m['studentName'] as String?) ?? '';
        final mostRecentMillis = (m['mostRecentMillis'] as num?)?.toInt() ?? 0;
        Student? profile;
        try {
          profile = await studentService.getPublicProfile(studentId);
        } catch (_) {
          profile = null;
        }
        return RankingEntry(
          studentId: studentId,
          studentName: profile?.displayName ??
              (fallbackName.isNotEmpty ? fallbackName : 'Aluno'),
          photoUrl: profile?.photoUrl,
          attendanceCount: (m['attendanceCount'] as num).toInt(),
          rank: (m['rank'] as num).toInt(),
          mostRecentAttendance: mostRecentMillis > 0
              ? DateTime.fromMillisecondsSinceEpoch(mostRecentMillis)
              : null,
        );
      }),
    );
    return hydrated;
  }

  /// 1-based rank of [studentId] in the ranking for [period] (scoped to
  /// [classIds], or every class when null), or null when the student has no
  /// attendance in the period.
  Future<int?> getStudentRank({
    required String studentId,
    required RankingPeriod period,
    Set<String>? classIds,
  }) async {
    // Use a large limit so the target student is never truncated out.
    final ranking = await getRanking(
      classIds: classIds,
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
