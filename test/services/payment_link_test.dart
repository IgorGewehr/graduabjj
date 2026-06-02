import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/abacate_pay_service.dart';

void main() {
  group('PaymentLink.fromMap', () {
    test('carries pixCode and ticketUrl from the map', () {
      final link = PaymentLink.fromMap({
        'pixCode': 'abc',
        'qrCodeUrl': 'q',
        'ticketUrl': 'https://mpago.me/x',
        'expiresAt': DateTime.now().toIso8601String(),
      });

      expect(link.pixCode, 'abc');
      expect(link.ticketUrl, 'https://mpago.me/x');
    });

    test('ticketUrl is null when absent from the map', () {
      final link = PaymentLink.fromMap({
        'pixCode': 'abc',
        'expiresAt': DateTime.now().toIso8601String(),
      });

      expect(link.ticketUrl, isNull);
    });
  });
}
