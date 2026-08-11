import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/fixed_academy_qr_service.dart';

void main() {
  group('FixedAcademyQrPayload', () {
    test('round-trips the permanent academy payload', () {
      const original = FixedAcademyQrPayload(
        academyId: 'academy-a',
        code: 'abcdefghijklmnop123456',
      );
      final parsed = FixedAcademyQrPayload.tryParse(original.encode());
      expect(parsed, isNotNull);
      expect(parsed!.academyId, 'academy-a');
      expect(parsed.code, 'abcdefghijklmnop123456');
    });

    test('does not claim rotating, musculacao or malformed QR codes', () {
      expect(
        FixedAcademyQrPayload.tryParse(
          '{"v":1,"a":"academy-a","c":"class-a","t":1}',
        ),
        isNull,
      );
      expect(
        FixedAcademyQrPayload.tryParse(
          '{"v":1,"a":"academy-a","k":"musculacao"}',
        ),
        isNull,
      );
      expect(FixedAcademyQrPayload.tryParse('garbage'), isNull);
    });
  });

  test('session maps only valid map entries and preserves schedule', () {
    final session = FixedAcademyQrSession.fromMap({
      'academyId': 'academy-a',
      'academyName': 'Dojo',
      'classes': [
        {
          'id': 'class-a',
          'name': 'BJJ Noite',
          'sport': 'bjj',
          'startTime': '19:00',
          'endTime': '20:00',
        },
        'invalid',
      ],
    });
    expect(session.academyName, 'Dojo');
    expect(session.classes, hasLength(1));
    expect(session.classes.single.id, 'class-a');
    expect(session.classes.single.startTime, '19:00');
  });
}
