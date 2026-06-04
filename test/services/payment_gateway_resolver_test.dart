import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/payment/payment_gateway_resolver.dart';

/// Pillar: FINANCEIRO / PAGAMENTOS.
///
/// Capability flags are the single source of truth that the UI (PaymentMethodSheet)
/// and the tuition checkout (financial_screen) consume to decide:
///   * whether a card can be charged    (cardSupported  -> MP only)
///   * whether a PIX CPF must be captured (requireCpf    -> MP only)
///   * whether PIX is offered at all      (pixEnabled    -> any connected gateway)
///
/// A regression in any of these flags directly changes what payment surface a
/// real user sees (e.g. card shown for a gateway that cannot charge it, or PIX
/// hidden when a gateway IS connected), so they are locked down exhaustively.
void main() {
  group('PaymentGatewayCapabilities.cardSupported', () {
    test('only Mercado Pago can charge a card', () {
      expect(PaymentGateway.mercadoPago.cardSupported, isTrue);
      expect(PaymentGateway.asaas.cardSupported, isFalse);
      expect(PaymentGateway.abacatePay.cardSupported, isFalse);
      expect(PaymentGateway.none.cardSupported, isFalse);
    });
  });

  group('PaymentGatewayCapabilities.requireCpf', () {
    test('only Mercado Pago requires the payer CPF for PIX', () {
      expect(PaymentGateway.mercadoPago.requireCpf, isTrue);
      expect(PaymentGateway.asaas.requireCpf, isFalse);
      expect(PaymentGateway.abacatePay.requireCpf, isFalse);
      expect(PaymentGateway.none.requireCpf, isFalse);
    });
  });

  group('PaymentGatewayCapabilities.pixEnabled', () {
    test('every connected gateway can generate a PIX link', () {
      expect(PaymentGateway.mercadoPago.pixEnabled, isTrue);
      expect(PaymentGateway.asaas.pixEnabled, isTrue);
      expect(PaymentGateway.abacatePay.pixEnabled, isTrue);
    });

    test('none means no charge surface (no PIX)', () {
      expect(PaymentGateway.none.pixEnabled, isFalse);
    });
  });

  group('flag invariants (audit lock-downs)', () {
    test('cardSupported never exceeds pixEnabled (card implies PIX gateway)', () {
      for (final g in PaymentGateway.values) {
        if (g.cardSupported) {
          expect(g.pixEnabled, isTrue,
              reason: '$g supports card but is not pixEnabled — impossible state');
        }
      }
    });

    test('requireCpf is exactly the card-supporting (MP) gateway today', () {
      for (final g in PaymentGateway.values) {
        expect(g.requireCpf, g.cardSupported,
            reason: 'requireCpf and cardSupported diverged for $g');
      }
    });

    test('none gateway exposes no capability at all', () {
      expect(PaymentGateway.none.cardSupported, isFalse);
      expect(PaymentGateway.none.requireCpf, isFalse);
      expect(PaymentGateway.none.pixEnabled, isFalse);
    });
  });
}
