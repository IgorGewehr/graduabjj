import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/cartel.dart';

({FightResult result, FightMethod method}) f(FightResult r, FightMethod m) =>
    (result: r, method: m);

void main() {
  group('enums', () {
    test('result tags', () {
      expect(FightResult.win.tag, 'V');
      expect(FightResult.loss.tag, 'D');
      expect(FightResult.draw.tag, 'E');
      expect(FightResult.nc.tag, 'NC');
    });
    test('knockout covers KO and TKO only', () {
      expect(FightMethod.ko.isKnockout, isTrue);
      expect(FightMethod.tko.isKnockout, isTrue);
      expect(FightMethod.decision.isKnockout, isFalse);
      expect(FightMethod.submission.isKnockout, isFalse);
    });
    test('fromString fallbacks', () {
      expect(FightResultX.fromString('loss'), FightResult.loss);
      expect(FightResultX.fromString('garbage'), FightResult.win);
      expect(FightMethodX.fromString('submission'), FightMethod.submission);
      expect(FightMethodX.fromString(null), FightMethod.other);
    });
  });

  group('summarizeCartel', () {
    test('counts each bucket + ko/sub subsets', () {
      final s = summarizeCartel([
        f(FightResult.win, FightMethod.ko),
        f(FightResult.win, FightMethod.tko),
        f(FightResult.win, FightMethod.submission),
        f(FightResult.win, FightMethod.decision),
        f(FightResult.loss, FightMethod.decision),
        f(FightResult.draw, FightMethod.decision),
        f(FightResult.nc, FightMethod.other),
      ]);
      expect(s.wins, 4);
      expect(s.losses, 1);
      expect(s.draws, 1);
      expect(s.nc, 1);
      expect(s.koWins, 2); // ko + tko
      expect(s.subWins, 1);
      expect(s.total, 7);
    });

    test('empty -> all zero', () {
      final s = summarizeCartel(const []);
      expect(s.total, 0);
      expect(s.record, '0V-0D-0E');
    });
  });

  group('record label', () {
    test('omits NC when zero', () {
      const s = CartelSummary(wins: 12, losses: 3, draws: 1);
      expect(s.record, '12V-3D-1E');
    });
    test('appends NC when present', () {
      const s = CartelSummary(wins: 12, losses: 3, draws: 1, nc: 2);
      expect(s.record, '12V-3D-1E-2NC');
    });
  });
}
