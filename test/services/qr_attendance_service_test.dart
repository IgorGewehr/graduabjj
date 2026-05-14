import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/qr_attendance_service.dart';

/// Tests for [QrPayload] parsing and TTL validation. These don't touch
/// Firestore — they cover the payload contract that other apps (web admin
/// generator + Flutter scanner) must agree on.
void main() {
  group('QrPayload.encode/parse round-trip', () {
    test('encodes and decodes a complete payload', () {
      final original = QrPayload(
        version: 1,
        academyId: 'acad-abc',
        classId: 'class-xyz',
        issuedAtSeconds: 1700000000,
      );
      final encoded = original.encode();
      final decoded = QrPayload.parse(encoded);
      expect(decoded.version, 1);
      expect(decoded.academyId, 'acad-abc');
      expect(decoded.classId, 'class-xyz');
      expect(decoded.issuedAtSeconds, 1700000000);
    });

    test('QrPayload.now stamps current time in seconds', () {
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = QrPayload.now(academyId: 'a', classId: 'c');
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(payload.issuedAtSeconds, greaterThanOrEqualTo(before));
      expect(payload.issuedAtSeconds, lessThanOrEqualTo(after));
      expect(payload.version, 1);
    });
  });

  group('QrPayload.parse validation', () {
    test('throws on empty input', () {
      expect(() => QrPayload.parse(''), throwsA(isA<FormatException>()));
      expect(() => QrPayload.parse('   '), throwsA(isA<FormatException>()));
    });

    test('throws on non-JSON garbage', () {
      expect(() => QrPayload.parse('not json'),
          throwsA(isA<FormatException>()));
    });

    test('throws on unsupported version', () {
      expect(
        () => QrPayload.parse('{"v":2,"a":"a","c":"c","t":1}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on missing academy', () {
      expect(
        () => QrPayload.parse('{"v":1,"c":"c","t":1}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on missing classId', () {
      expect(
        () => QrPayload.parse('{"v":1,"a":"a","t":1}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on missing timestamp', () {
      expect(
        () => QrPayload.parse('{"v":1,"a":"a","c":"c"}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on negative timestamp', () {
      expect(
        () => QrPayload.parse('{"v":1,"a":"a","c":"c","t":-1}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Token TTL', () {
    test('kQrTokenTtl is 60 seconds (must match web generator)', () {
      // The web rotation is 30s; TTL needs to be at least 2x to avoid races
      // where a student scans a token right as it's being replaced.
      expect(kQrTokenTtl.inSeconds, 60);
    });
  });
}
