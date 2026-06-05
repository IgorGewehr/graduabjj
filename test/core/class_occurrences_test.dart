import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/class_occurrences.dart';

void main() {
  // 2026-06-05 is a Friday (Dart weekday 5). weekdaySunZero -> 5.
  final friday = DateTime(2026, 6, 5, 8, 0); // Fri 08:00

  group('weekdaySunZero', () {
    test('Sunday -> 0, Saturday -> 6', () {
      expect(weekdaySunZero(DateTime(2026, 6, 7)), 0); // Sunday
      expect(weekdaySunZero(DateTime(2026, 6, 6)), 6); // Saturday
      expect(weekdaySunZero(DateTime(2026, 6, 5)), 5); // Friday
      expect(weekdaySunZero(DateTime(2026, 6, 8)), 1); // Monday
    });
  });

  group('yyyyMMdd', () {
    test('zero-pads month and day', () {
      expect(yyyyMMdd(DateTime(2026, 6, 5)), '20260605');
      expect(yyyyMMdd(DateTime(2026, 12, 31)), '20261231');
    });
  });

  group('parseHmToMinutes / hmCompact', () {
    test('parses HH:mm', () {
      expect(parseHmToMinutes('08:30'), 510);
      expect(parseHmToMinutes('00:00'), 0);
      expect(parseHmToMinutes('19:05'), 1145);
    });
    test('malformed -> 0', () {
      expect(parseHmToMinutes('abc'), 0);
      expect(parseHmToMinutes('8'), 0);
    });
    test('hmCompact strips colon and pads', () {
      expect(hmCompact('08:30'), '0830');
      expect(hmCompact('9:5'), '0905'.padLeft(4, '0'));
    });
  });

  group('occurrenceId / bookingId', () {
    test('single slot/day -> classId_yyyyMMdd', () {
      expect(occurrenceId('c1', DateTime(2026, 6, 5), '19:00'), 'c1_20260605');
    });
    test('multi slot/day -> suffix start time', () {
      expect(
        occurrenceId('c1', DateTime(2026, 6, 5), '19:00', multiPerDay: true),
        'c1_20260605_1900',
      );
    });
    test('bookingId is deterministic per student', () {
      expect(bookingId('c1_20260605', 's7'), 'c1_20260605__s7');
    });
  });

  group('withinWindow', () {
    test('future within 7 days passes', () {
      expect(withinWindow(DateTime(2026, 6, 5, 19), friday, 7), isTrue);
      expect(withinWindow(DateTime(2026, 6, 12, 8), friday, 7), isTrue); // day 7
    });
    test('past or now fails', () {
      expect(withinWindow(DateTime(2026, 6, 5, 7), friday, 7), isFalse);
      expect(withinWindow(friday, friday, 7), isFalse);
    });
    test('beyond window fails', () {
      expect(withinWindow(DateTime(2026, 6, 13, 8), friday, 7), isFalse);
    });
  });

  group('canCancel', () {
    final slot = DateTime(2026, 6, 5, 19, 0); // 19:00
    test('before cutoff allowed', () {
      expect(canCancel(slot, DateTime(2026, 6, 5, 17, 59), 60), isTrue);
    });
    test('at or past cutoff blocked', () {
      expect(canCancel(slot, DateTime(2026, 6, 5, 18, 0), 60), isFalse);
      expect(canCancel(slot, DateTime(2026, 6, 5, 18, 30), 60), isFalse);
    });
  });

  group('hasMultipleSlotsPerDay', () {
    test('detects two slots on same weekday', () {
      expect(
        hasMultipleSlotsPerDay(const [
          ScheduleSlot(dayOfWeek: 1, startTime: '07:00', endTime: '08:00'),
          ScheduleSlot(dayOfWeek: 1, startTime: '19:00', endTime: '20:00'),
        ]),
        isTrue,
      );
    });
    test('distinct weekdays -> false', () {
      expect(
        hasMultipleSlotsPerDay(const [
          ScheduleSlot(dayOfWeek: 1, startTime: '07:00', endTime: '08:00'),
          ScheduleSlot(dayOfWeek: 3, startTime: '07:00', endTime: '08:00'),
        ]),
        isFalse,
      );
    });
  });

  group('upcomingOccurrences', () {
    // Mon/Wed/Fri 19:00 class.
    const mwf = [
      ScheduleSlot(dayOfWeek: 1, startTime: '19:00', endTime: '20:00'),
      ScheduleSlot(dayOfWeek: 3, startTime: '19:00', endTime: '20:00'),
      ScheduleSlot(dayOfWeek: 5, startTime: '19:00', endTime: '20:00'),
    ];

    test('expands next 7 days sorted, includes today if still future', () {
      // from Fri 08:00 -> Fri 19:00 today, Mon, Wed, next Fri (day 7).
      final occ = upcomingOccurrences(mwf, from: friday, windowDays: 7);
      expect(occ.map((o) => yyyyMMdd(o.date)).toList(), [
        '20260605', // Fri (today, 19:00 still future)
        '20260608', // Mon
        '20260610', // Wed
        '20260612', // Fri (day 7, inclusive)
      ]);
      // sorted ascending
      for (var i = 1; i < occ.length; i++) {
        expect(occ[i].slotStart.isAfter(occ[i - 1].slotStart), isTrue);
      }
    });

    test('drops today slot once it is in the past', () {
      final afternoon = DateTime(2026, 6, 5, 20, 30); // after 19:00
      final occ = upcomingOccurrences(mwf, from: afternoon, windowDays: 7);
      expect(occ.first.date.day, 8); // Monday, not Friday
    });

    test('two slots same day both appear', () {
      const twoPerDay = [
        ScheduleSlot(dayOfWeek: 5, startTime: '07:00', endTime: '08:00'),
        ScheduleSlot(dayOfWeek: 5, startTime: '19:00', endTime: '20:00'),
      ];
      final occ = upcomingOccurrences(twoPerDay,
          from: DateTime(2026, 6, 5, 6, 0), windowDays: 1);
      expect(occ.length, 2);
      expect(occ[0].startTime, '07:00');
      expect(occ[1].startTime, '19:00');
    });
  });
}
