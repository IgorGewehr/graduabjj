import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/widgets/payment/payment_target.dart';

/// Pillar: FINANCEIRO / PAGAMENTOS.
///
/// PaymentTarget is the unified descriptor passed to PaymentMethodSheet. The
/// load-bearing invariant the card-gate relies on is `isOrder`/`isTuition` and
/// the financialId/orderId routing (one is always null), because the wrong doc
/// id would attach the charge to the wrong record (or none).
void main() {
  group('PaymentTarget.tuition', () {
    final t = PaymentTarget.tuition(
      financialId: 'fin_1',
      amount: 89.0,
      description: 'Mensalidade - 2026/06',
      studentId: 'stu_1',
      studentName: 'Aluno',
    );

    test('is a tuition, not an order', () {
      expect(t.isTuition, isTrue);
      expect(t.isOrder, isFalse);
      expect(t.kind, PaymentTargetKind.tuition);
    });

    test('exposes the financials doc id and a null orderId', () {
      expect(t.financialId, 'fin_1');
      expect(t.orderId, isNull);
      expect(t.id, 'fin_1');
    });

    test('carries the amount in reais and payer identity verbatim', () {
      expect(t.amount, 89.0);
      expect(t.studentId, 'stu_1');
      expect(t.studentName, 'Aluno');
    });
  });

  group('PaymentTarget.order', () {
    final o = PaymentTarget.order(
      orderId: 'order_1',
      amount: 150.0,
      description: 'Pedido #ABC123',
      studentId: 'stu_2',
      studentName: 'Comprador',
    );

    test('is an order, not a tuition', () {
      expect(o.isOrder, isTrue);
      expect(o.isTuition, isFalse);
      expect(o.kind, PaymentTargetKind.order);
    });

    test('exposes the storeOrders doc id and a null financialId', () {
      expect(o.orderId, 'order_1');
      expect(o.financialId, isNull);
      expect(o.id, 'order_1');
    });
  });

  test('the two doc-id getters are mutually exclusive for every kind', () {
    final t = PaymentTarget.tuition(
      financialId: 'f',
      amount: 1,
      description: 'd',
      studentId: 's',
      studentName: 'n',
    );
    final o = PaymentTarget.order(
      orderId: 'o',
      amount: 1,
      description: 'd',
      studentId: 's',
      studentName: 'n',
    );
    // Exactly one of (financialId, orderId) is non-null per target.
    expect([t.financialId, t.orderId].where((x) => x != null).length, 1);
    expect([o.financialId, o.orderId].where((x) => x != null).length, 1);
  });
}
