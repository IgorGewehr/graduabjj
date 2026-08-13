import '../../../services/class_service.dart';

int? attendanceTimeToMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0].trim());
  final minute = int.tryParse(parts[1].trim());
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

/// Chooses the class that requires the least decision from the professor:
/// a class currently happening/starting within 30 minutes wins; otherwise the
/// closest class scheduled for today is selected. A sole schedule-less class
/// is also safe to preselect because there is no ambiguity.
BJJClass? selectBestAttendanceClass(List<BJJClass> classes, DateTime now) {
  if (classes.isEmpty) return null;
  final dayOfWeek = now.weekday % 7;
  final nowMinutes = now.hour * 60 + now.minute;
  final candidates = <({BJJClass item, int distance, bool active})>[];

  for (final item in classes) {
    for (final slot in item.schedule) {
      if (slot.dayOfWeek != dayOfWeek) continue;
      final start = attendanceTimeToMinutes(slot.startTime);
      final end = attendanceTimeToMinutes(slot.endTime);
      if (start == null || end == null) continue;
      candidates.add((
        item: item,
        distance: (start - nowMinutes).abs(),
        active: nowMinutes >= start - 30 && nowMinutes <= end,
      ));
    }
  }

  if (candidates.isEmpty) return classes.length == 1 ? classes.first : null;
  candidates.sort((a, b) {
    if (a.active != b.active) return a.active ? -1 : 1;
    return a.distance.compareTo(b.distance);
  });
  return candidates.first.item;
}

String? attendanceClassTimeForDate(BJJClass item, DateTime date) {
  final dayOfWeek = date.weekday % 7;
  for (final slot in item.schedule) {
    if (slot.dayOfWeek == dayOfWeek &&
        attendanceTimeToMinutes(slot.startTime) != null) {
      return slot.startTime;
    }
  }
  return null;
}
