import '../abacate_pay_service.dart';
import '../asaas_payment_service.dart';
import '../mercado_pago_service.dart';

/// The payment gateway connected for an academy, resolved in precedence order.
///
/// Precedence (highest first): Mercado Pago > Asaas > AbacatePay. [none] means
/// no gateway is connected, so payment must be arranged directly with the
/// academy (never a dead-end charge attempt).
enum PaymentGateway { mercadoPago, asaas, abacatePay, none }

/// Single source of truth for the connected payment gateway of an academy and
/// the capability flags derived from it.
///
/// This consolidates the precedence logic that used to be triplicated across
/// `financial_screen.dart` (`abacatePayEnabledProvider` + the inline resolution
/// in `_showPixPaymentDialog`) and `store_orders_screen.dart`
/// (`_resolveGateway`/`_Gateway`). Capability flags expose the behaviour each
/// call site reconstructed by hand:
///
/// * [cardSupported] — only Mercado Pago can charge a card.
/// * [requireCpf] — only Mercado Pago needs the payer CPF for PIX.
/// * [pixEnabled] — any connected gateway can generate a PIX link.
class PaymentGatewayResolver {
  const PaymentGatewayResolver._();

  /// Resolves the connected gateway for [academyId] following the
  /// MP > Asaas > AbacatePay precedence. Any resolution failure degrades to
  /// [PaymentGateway.none] (safe default: no charge surface).
  static Future<PaymentGateway> resolve(String academyId) async {
    try {
      if (await MercadoPagoService(academyId).isEnabled()) {
        return PaymentGateway.mercadoPago;
      }
      if (await AsaasPaymentService(academyId).isEnabled()) {
        return PaymentGateway.asaas;
      }
      if (await AbacatePayService(academyId).isEnabled()) {
        return PaymentGateway.abacatePay;
      }
      return PaymentGateway.none;
    } catch (_) {
      return PaymentGateway.none;
    }
  }
}

/// Capability flags derived from a resolved [PaymentGateway].
extension PaymentGatewayCapabilities on PaymentGateway {
  /// Whether the gateway can charge a credit card. Only Mercado Pago can.
  bool get cardSupported => this == PaymentGateway.mercadoPago;

  /// Whether the gateway requires the payer CPF to generate a PIX link. Only
  /// Mercado Pago does; Asaas/AbacatePay create the PIX without it.
  bool get requireCpf => this == PaymentGateway.mercadoPago;

  /// Whether a PIX link can be generated, i.e. some gateway is connected.
  bool get pixEnabled => this != PaymentGateway.none;
}
