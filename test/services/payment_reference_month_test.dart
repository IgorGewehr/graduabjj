import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/payment_service.dart';

void main() {
  test('deriva o mês financeiro do vencimento para qualquer cobrança', () {
    expect(paymentReferenceMonth(DateTime(2026, 8, 31)), '2026-08');
    expect(paymentReferenceMonth(DateTime(2027, 1, 1)), '2027-01');
  });
}
