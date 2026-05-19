// Shared helpers and small model used across the classes sub-screens.
import 'package:flutter/material.dart';

/// Convert dayOfWeek int (0=Dom … 6=Sab) to a short label.
String getDayLabel(int dayOfWeek) {
  const days = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab'];
  return days[dayOfWeek % 7];
}

String formatTimeOfDay(TimeOfDay t) {
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

TimeOfDay parseTimeString(String time) {
  final parts = time.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

/// Mutable schedule entry used during form editing.
class ScheduleEntry {
  int dayOfWeek;
  String startTime;
  String endTime;

  ScheduleEntry({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toMap() => {
    'dayOfWeek': dayOfWeek,
    'startTime': startTime,
    'endTime': endTime,
  };
}
