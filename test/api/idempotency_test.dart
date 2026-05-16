import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/api/idempotency.dart';

void main() {
  group('IdempotencyKey', () {
    test('generate() yields a UUIDv4 (36-char hyphenated)', () {
      final key = IdempotencyKey.generate();
      expect(key.value, hasLength(36));
      expect(
        key.value,
        matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        )),
      );
    });

    test('two generate() calls produce different values', () {
      expect(
        IdempotencyKey.generate().value,
        isNot(equals(IdempotencyKey.generate().value)),
      );
    });

    test('fromString() preserves the exact value (persistence + retry)', () {
      const v = '11111111-1111-4111-8111-111111111111';
      final key = IdempotencyKey.fromString(v);
      expect(key.value, v);
      expect(key.toString(), v);
    });
  });
}
