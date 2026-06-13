/// Pure, dependency-free helpers for class booking occurrences.
///
/// Classes are recurring weekly templates (`schedule: [{dayOfWeek, startTime,
/// endTime}]`). A *booking* targets a concrete dated *occurrence* of one of
/// those slots. We never materialize every occurrence; we expand the next N
/// days on demand from the schedule and persist only the ones that get a
/// reservation.
///
/// No Flutter/Firestore imports here so the booking-window / cancel-cutoff /
/// occurrence-id math stays unit-testable (mirrors `graduation_factors.dart`,
/// `strength_math.dart`).
library;

/// A weekly recurring slot, decoupled from the Firestore `ClassSchedule` model.
class ScheduleSlot {
  /// 0 = Sunday … 6 = Saturday (matches `ClassSchedule.dayOfWeek`).
  final int dayOfWeek;

  /// "HH:mm" 24h.
  final String startTime;
  final String endTime;

  const ScheduleSlot({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });
}

/// A concrete dated instance of a [ScheduleSlot].
class OccurrenceSlot {
  /// Calendar day at local midnight.
  final DateTime date;
  final int dayOfWeek;
  final String startTime;
  final String endTime;

  /// [date] combined with [startTime] — the moment the class begins.
  final DateTime slotStart;

  const OccurrenceSlot({
    required this.date,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.slotStart,
  });
}

/// Dart's `DateTime.weekday` is 1=Mon … 7=Sun. The schedule uses 0=Sun … 6=Sat,
/// so `weekday % 7` maps Sun(7)→0, Mon(1)→1 … Sat(6)→6 (mirrors `BJJClass`).
int weekdaySunZero(DateTime d) => d.weekday % 7;

/// "20260605" for 2026-06-05 — stable sortable day key used in document IDs.
String yyyyMMdd(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}$m$day';
}

/// Parses "HH:mm" to minutes-since-midnight. Returns 0 on malformed input.
int parseHmToMinutes(String hm) {
  final parts = hm.split(':');
  if (parts.length != 2) return 0;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  return h * 60 + m;
}

/// "HH:mm" -> "HHmm" for use inside a document id (no colon). Normalizes via
/// minute parsing so unpadded input ("9:5") still yields a stable "0905".
String hmCompact(String hm) {
  final mins = parseHmToMinutes(hm);
  final h = (mins ~/ 60).toString().padLeft(2, '0');
  final m = (mins % 60).toString().padLeft(2, '0');
  return '$h$m';
}

/// Deterministic occurrence id. One slot/day per class -> `{classId}_{yyyyMMdd}`.
/// When a class has more than one slot on the same weekday, callers pass
/// [multiPerDay] = true so the start time disambiguates them.
String occurrenceId(
  String classId,
  DateTime date,
  String startTime, {
  bool multiPerDay = false,
}) {
  final base = '${classId}_${yyyyMMdd(date)}';
  return multiPerDay ? '${base}_${hmCompact(startTime)}' : base;
}

/// Deterministic, idempotent booking id: one booking per student per occurrence.
String bookingId(String occId, String studentId) => '${occId}__$studentId';

/// True when [slotStart] lies in the future and no later than [windowDays] from
/// [now] (the booking window). Day-granular upper bound: includes the whole last
/// day of the window.
bool withinWindow(DateTime slotStart, DateTime now, int windowDays) {
  if (!slotStart.isAfter(now)) return false;
  final endOfWindow = DateTime(now.year, now.month, now.day)
      .add(Duration(days: windowDays + 1)); // exclusive midnight after last day
  return slotStart.isBefore(endOfWindow);
}

/// True when the student may still cancel: strictly before
/// `slotStart - cutoffMinutes`. Staff bypass this in the callable.
bool canCancel(DateTime slotStart, DateTime now, int cutoffMinutes) {
  final deadline = slotStart.subtract(Duration(minutes: cutoffMinutes));
  return now.isBefore(deadline);
}

/// Expands [schedule] into concrete occurrences within `[from, from+windowDays]`,
/// sorted by start time. Occurrences whose [slotStart] is already in the past
/// (earlier today) are dropped so students only see bookable sessions.
List<OccurrenceSlot> upcomingOccurrences(
  List<ScheduleSlot> schedule, {
  required DateTime from,
  int windowDays = 7,
}) {
  final out = <OccurrenceSlot>[];
  final startDay = DateTime(from.year, from.month, from.day);
  for (var i = 0; i <= windowDays; i++) {
    final day = startDay.add(Duration(days: i));
    final dow = weekdaySunZero(day);
    for (final s in schedule) {
      if (s.dayOfWeek != dow) continue;
      final mins = parseHmToMinutes(s.startTime);
      final slotStart =
          DateTime(day.year, day.month, day.day, mins ~/ 60, mins % 60);
      if (!slotStart.isAfter(from)) continue; // skip past/now slots
      if (!withinWindow(slotStart, from, windowDays)) continue;
      out.add(OccurrenceSlot(
        date: day,
        dayOfWeek: dow,
        startTime: s.startTime,
        endTime: s.endTime,
        slotStart: slotStart,
      ));
    }
  }
  out.sort((a, b) => a.slotStart.compareTo(b.slotStart));
  return out;
}

/// True when a class has 2+ slots on the same weekday (affects occurrence-id
/// disambiguation). Cheap pre-check callers run once per class.
bool hasMultipleSlotsPerDay(List<ScheduleSlot> schedule) {
  final seen = <int>{};
  for (final s in schedule) {
    if (!seen.add(s.dayOfWeek)) return true;
  }
  return false;
}
