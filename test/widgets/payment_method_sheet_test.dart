import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/abacate_pay_service.dart' show PaymentLink;
import 'package:graduabjj/services/payment/payment_gateway_resolver.dart';
import 'package:graduabjj/widgets/payment/payment_method_sheet.dart';
import 'package:graduabjj/widgets/payment/payment_target.dart';

/// Pillar: FINANCEIRO / PAGAMENTOS — the card-gate is the single most
/// money-sensitive UI rule:
///
///   _cardEnabled = (target.isOrder ? storeCreditCardEnabled : true)
///                  && gateway.cardSupported
///
/// Regressions here let the store card option appear with the academy flag OFF
/// (or hide it for tuition), so the full truth table is pumped through the real
/// widget and asserted on the rendered "Cartao de credito" tile.

PaymentTarget _tuition() => PaymentTarget.tuition(
      financialId: 'fin_1',
      amount: 89.0,
      description: 'Mensalidade',
      studentId: 'stu_1',
      studentName: 'Aluno',
    );

PaymentTarget _order() => PaymentTarget.order(
      orderId: 'order_1',
      amount: 150.0,
      description: 'Pedido',
      studentId: 'stu_1',
      studentName: 'Aluno',
    );

Future<void> _pump(
  WidgetTester tester, {
  required PaymentTarget target,
  required PaymentGateway gateway,
  required bool storeCreditCardEnabled,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PaymentMethodSheet(
          target: target,
          gateway: gateway,
          storeCreditCardEnabled: storeCreditCardEnabled,
          createPix: (_) async => PaymentLink(
            pixCode: 'x',
            qrCodeUrl: 'q',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

bool _cardShown() => find.text('Cartao de credito').evaluate().isNotEmpty;
bool _pixShown() => find.text('PIX').evaluate().isNotEmpty;

void main() {
  group('PIX is offered whenever a gateway can charge (the sheet only opens then)', () {
    testWidgets('PIX tile always present for MP tuition', (tester) async {
      await _pump(tester,
          target: _tuition(),
          gateway: PaymentGateway.mercadoPago,
          storeCreditCardEnabled: false);
      expect(_pixShown(), isTrue);
    });
  });

  group('TUITION card gate: never gated by the store flag', () {
    testWidgets('MP tuition shows card even with storeCreditCardEnabled=false',
        (tester) async {
      await _pump(tester,
          target: _tuition(),
          gateway: PaymentGateway.mercadoPago,
          storeCreditCardEnabled: false);
      expect(_cardShown(), isTrue);
    });

    testWidgets('Asaas tuition hides card (Asaas cannot charge a card)',
        (tester) async {
      await _pump(tester,
          target: _tuition(),
          gateway: PaymentGateway.asaas,
          storeCreditCardEnabled: true);
      expect(_cardShown(), isFalse);
    });

    testWidgets('AbacatePay tuition hides card', (tester) async {
      await _pump(tester,
          target: _tuition(),
          gateway: PaymentGateway.abacatePay,
          storeCreditCardEnabled: true);
      expect(_cardShown(), isFalse);
    });
  });

  group('ORDER card gate: requires BOTH storeCreditCardEnabled AND MP', () {
    testWidgets('MP order + flag ON shows card', (tester) async {
      await _pump(tester,
          target: _order(),
          gateway: PaymentGateway.mercadoPago,
          storeCreditCardEnabled: true);
      expect(_cardShown(), isTrue);
    });

    testWidgets('SECURITY: MP order + flag OFF hides card', (tester) async {
      await _pump(tester,
          target: _order(),
          gateway: PaymentGateway.mercadoPago,
          storeCreditCardEnabled: false);
      expect(_cardShown(), isFalse,
          reason: 'store card must not appear when storeCreditCardEnabled is off');
    });

    testWidgets('Asaas order + flag ON still hides card (no MP)', (tester) async {
      await _pump(tester,
          target: _order(),
          gateway: PaymentGateway.asaas,
          storeCreditCardEnabled: true);
      expect(_cardShown(), isFalse);
    });
  });

  group('default storeCreditCardEnabled is the safe value (false)', () {
    testWidgets('order with MP and the default ctor flag hides the card',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentMethodSheet(
              target: _order(),
              gateway: PaymentGateway.mercadoPago,
              // storeCreditCardEnabled omitted -> defaults to false (safe).
              createPix: (_) async => null,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(_cardShown(), isFalse);
    });
  });
}
