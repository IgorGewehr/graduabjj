import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/number_format.dart';

void main() {
  group('fmtNum (pt-BR)', () {
    test('comma decimal, trims trailing zeros', () {
      expect(fmtNum(82.5), '82,5');
      expect(fmtNum(78.0), '78');
      expect(fmtNum(24.0), '24');
    });

    test('rounds to maxDecimals (default 1)', () {
      expect(fmtNum(13.61), '13,6');
      expect(fmtNum(27.34), '27,3');
    });

    test('thousands separator', () {
      expect(fmtNum(2500), '2.500');
    });

    test('maxDecimals override', () {
      expect(fmtNum(18.25, maxDecimals: 2), '18,25');
      expect(fmtNum(18.0, maxDecimals: 0), '18');
    });
  });

  group('fmtMeasure', () {
    test('appends unit; empty unit → no suffix', () {
      expect(fmtMeasure(82.5, 'kg'), '82,5 kg');
      expect(fmtMeasure(24.1, ''), '24,1');
    });
  });
}
