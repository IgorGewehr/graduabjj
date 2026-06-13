import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/striking_timer.dart';

void main() {
  group('fmtMmss', () {
    test('pads minutes and seconds', () {
      expect(fmtMmss(0), '00:00');
      expect(fmtMmss(5), '00:05');
      expect(fmtMmss(65), '01:05');
      expect(fmtMmss(180), '03:00');
    });
    test('minutes not capped at 59', () {
      expect(fmtMmss(3700), '61:40');
    });
    test('negative clamps to zero', () {
      expect(fmtMmss(-10), '00:00');
    });
  });

  group('buildPhases', () {
    test('3x3min with 1min rest -> round,rest,round,rest,round (no trailing rest)',
        () {
      final p = buildPhases(rounds: 3, roundSec: 180, restSec: 60);
      expect(p.length, 5);
      expect(p.map((x) => x.kind).toList(), [
        TimerPhaseKind.round,
        TimerPhaseKind.rest,
        TimerPhaseKind.round,
        TimerPhaseKind.rest,
        TimerPhaseKind.round,
      ]);
      expect(p.first.seconds, 180);
      expect(p[1].seconds, 60);
      expect(p.last.isRound, isTrue);
      expect(p.last.round, 3);
    });

    test('rest <= 0 -> only rounds', () {
      final p = buildPhases(rounds: 3, roundSec: 120, restSec: 0);
      expect(p.length, 3);
      expect(p.every((x) => x.isRound), isTrue);
    });

    test('single round -> no rest', () {
      final p = buildPhases(rounds: 1, roundSec: 90, restSec: 60);
      expect(p.length, 1);
      expect(p.single.isRound, isTrue);
    });

    test('non-positive inputs -> empty', () {
      expect(buildPhases(rounds: 0, roundSec: 180, restSec: 60), isEmpty);
      expect(buildPhases(rounds: 3, roundSec: 0, restSec: 60), isEmpty);
    });

    test('rest phase carries the round it follows', () {
      final p = buildPhases(rounds: 2, roundSec: 180, restSec: 60);
      expect(p[1].kind, TimerPhaseKind.rest);
      expect(p[1].round, 1);
    });
  });

  group('totalSessionSeconds', () {
    test('rounds + rests', () {
      // 3x180 + 2x60 = 540 + 120 = 660
      expect(
          totalSessionSeconds(rounds: 3, roundSec: 180, restSec: 60), 660);
    });
    test('no rest', () {
      expect(totalSessionSeconds(rounds: 4, roundSec: 120, restSec: 0), 480);
    });
  });

  group('totalRoundMinutes', () {
    test('floor of active minutes', () {
      expect(totalRoundMinutes(rounds: 3, roundSec: 180), 9);
      expect(totalRoundMinutes(rounds: 5, roundSec: 100), 8); // 500s -> 8.33
      expect(totalRoundMinutes(rounds: 0, roundSec: 180), 0);
    });
  });
}
