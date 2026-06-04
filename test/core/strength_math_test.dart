import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/strength_math.dart';

void main() {
  group('epley1RM', () {
    test('reps 1 = a própria carga', () {
      expect(epley1RM(100, 1), 100);
    });
    test('Epley para reps > 1', () {
      // 60 × (1 + 10/30) = 60 × 1.3333 = 80
      expect(epley1RM(60, 10), closeTo(80, 0.001));
    });
    test('inválidos → 0', () {
      expect(epley1RM(0, 5), 0);
      expect(epley1RM(50, 0), 0);
      expect(epley1RM(-10, 5), 0);
    });
  });

  group('bestLoad / best1RM / sessionVolume', () {
    final sets = <SetTuple>[
      (reps: 12, load: 50),
      (reps: 8, load: 70),
      (reps: 5, load: 80),
    ];

    test('bestLoad = maior carga', () {
      expect(bestLoad(sets), 80);
      expect(bestLoad(const []), 0);
    });

    test('best1RM = maior Epley', () {
      // 50×(1+12/30)=70 ; 70×(1+8/30)=88.67 ; 80×(1+5/30)=93.33 → 93.33
      expect(best1RM(sets), closeTo(93.333, 0.01));
      expect(best1RM(const []), 0);
    });

    test('sessionVolume = Σ reps×load', () {
      // 12×50 + 8×70 + 5×80 = 600 + 560 + 400 = 1560
      expect(sessionVolume(sets), 1560);
      expect(sessionVolume(const []), 0);
    });
  });
}
