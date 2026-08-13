import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/screens/admin/widgets/attendance_class_selector.dart';
import 'package:graduabjj/services/class_service.dart';

BJJClass buildClass(String id, {List<ClassSchedule> schedule = const []}) {
  return BJJClass(
    id: id,
    name: id,
    schedule: schedule,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  test('selects class happening now before merely nearby classes', () {
    final now = DateTime(2026, 8, 13, 19, 10); // Thursday
    final result = selectBestAttendanceClass([
      buildClass(
        'later',
        schedule: [
          ClassSchedule(dayOfWeek: 4, startTime: '20:00', endTime: '21:00'),
        ],
      ),
      buildClass(
        'current',
        schedule: [
          ClassSchedule(dayOfWeek: 4, startTime: '19:00', endTime: '20:00'),
        ],
      ),
    ], now);

    expect(result?.id, 'current');
  });

  test('selects closest class scheduled for today', () {
    final now = DateTime(2026, 8, 13, 16, 0);
    final result = selectBestAttendanceClass([
      buildClass(
        'morning',
        schedule: [
          ClassSchedule(dayOfWeek: 4, startTime: '08:00', endTime: '09:00'),
        ],
      ),
      buildClass(
        'evening',
        schedule: [
          ClassSchedule(dayOfWeek: 4, startTime: '18:00', endTime: '19:00'),
        ],
      ),
    ], now);

    expect(result?.id, 'evening');
  });

  test(
    'ignores malformed schedules and only preselects an unambiguous class',
    () {
      final now = DateTime(2026, 8, 13, 16, 0);
      final malformed = buildClass(
        'only',
        schedule: [
          ClassSchedule(dayOfWeek: 4, startTime: 'xx', endTime: '19:00'),
        ],
      );

      expect(selectBestAttendanceClass([malformed], now)?.id, 'only');
      expect(
        selectBestAttendanceClass([malformed, buildClass('other')], now),
        isNull,
      );
    },
  );
}
