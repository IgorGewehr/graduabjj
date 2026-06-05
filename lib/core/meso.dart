/// Pure helper for simple mesocycles (E1): which week is "current" given a
/// start date. No Flutter/Firestore deps (testable).
library;

/// 1-based current week of a mesocycle that started on [startDate], clamped to
/// `[1, totalWeeks]`. Returns null when there's no start date or no weeks
/// (then the UI just lists the weeks without a "current" highlight).
///
/// Before the start date → week 1; on/after the end → the last week.
int? currentMesoWeek(DateTime? startDate, DateTime now, int totalWeeks) {
  if (startDate == null || totalWeeks <= 0) return null;
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final today = DateTime(now.year, now.month, now.day);
  final elapsedDays = today.difference(start).inDays;
  final week = (elapsedDays ~/ 7) + 1;
  if (week < 1) return 1;
  if (week > totalWeeks) return totalWeeks;
  return week;
}
