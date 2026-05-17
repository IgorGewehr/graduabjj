import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/financial_dto.dart';
import 'package:graduabjj/services/payment_service.dart';

void main() {
  ApiFinancial mk({
    String id = 'f1',
    String status = 'pending',
    String amount = '200.00',
    String? method,
    String? asaasId,
    String? abacateId,
    String? paymentDate,
  }) =>
      ApiFinancial.fromJson({
        'id': id,
        'academy_id': 'aid',
        'student_id': 's-1',
        'type': 'monthly_tuition',
        'amount': amount,
        'due_date': '2026-06-05',
        'status': status,
        'reference_month': '2026-06',
        if (method != null) 'method': method,
        if (asaasId != null) 'asaas_payment_id': asaasId,
        if (abacateId != null) 'abacatepay_transaction_id': abacateId,
        if (paymentDate != null) 'payment_date': paymentDate,
      });

  group('Payment.fromApi', () {
    test('mapeia campos principais + status', () {
      final p = Payment.fromApi(mk(status: 'paid', method: 'pix',
          paymentDate: '2026-06-04T10:00:00Z'));
      expect(p.id, 'f1');
      expect(p.studentId, 's-1');
      expect(p.value, 200.0);
      expect(p.status, PaymentStatus.paid);
      expect(p.method, PaymentMethod.pix);
      expect(p.paidAt, isNotNull);
      expect(p.isPaid, isTrue);
    });

    test('amount inválido → 0.0', () {
      final p = Payment.fromApi(mk(amount: 'garbage'));
      expect(p.value, 0.0);
    });

    test('overdue status mapeia', () {
      final p = Payment.fromApi(mk(status: 'overdue'));
      expect(p.status, PaymentStatus.overdue);
    });

    test('cancelled status mapeia', () {
      final p = Payment.fromApi(mk(status: 'cancelled'));
      expect(p.status, PaymentStatus.cancelled);
    });

    test('externalId prefere asaas → abacate', () {
      final p1 = Payment.fromApi(mk(asaasId: 'a-1', abacateId: 'b-1'));
      expect(p1.externalId, 'a-1');

      final p2 = Payment.fromApi(mk(abacateId: 'b-2'));
      expect(p2.externalId, 'b-2');

      final p3 = Payment.fromApi(mk());
      expect(p3.externalId, isNull);
    });

    test('credit_card mapeia para creditCard legacy', () {
      final p = Payment.fromApi(mk(method: 'credit_card'));
      expect(p.method, PaymentMethod.creditCard);
    });

    test('bank_transfer mapeia para bankTransfer legacy', () {
      final p = Payment.fromApi(mk(method: 'bank_transfer'));
      expect(p.method, PaymentMethod.bankTransfer);
    });

    test('method=other cai em pix (legacy não tem other)', () {
      final p = Payment.fromApi(mk(method: 'other'));
      expect(p.method, PaymentMethod.pix);
    });

    test('studentName override via parâmetro', () {
      final p = Payment.fromApi(mk(), studentName: 'Igor');
      expect(p.studentName, 'Igor');
    });

    test('planId override via parâmetro (não vem na resposta)', () {
      final p = Payment.fromApi(mk(), planId: 'plan-1');
      expect(p.planId, 'plan-1');
    });

    test('referenceMonth propaga (formato YYYY-MM)', () {
      final p = Payment.fromApi(mk());
      expect(p.referenceMonth, '2026-06');
    });
  });
}
