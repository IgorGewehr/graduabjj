/// Defines which payment instruction should be offered in student charges.
///
/// Legacy academies that do not have this field persisted default to Mercado
/// Pago, while the backend may still fall back to the academy's personal PIX.
enum BillingPaymentPreference { mercadoPago, manualPix, none }

/// Ordem efetiva de tentativa. A preferencia `none` e deliberada e, por isso,
/// nunca faz fallback para uma forma de pagamento.
List<BillingPaymentPreference> billingPaymentFallbackOrder(
  BillingPaymentPreference preference,
) {
  switch (preference) {
    case BillingPaymentPreference.mercadoPago:
      return const [
        BillingPaymentPreference.mercadoPago,
        BillingPaymentPreference.manualPix,
      ];
    case BillingPaymentPreference.manualPix:
      return const [
        BillingPaymentPreference.manualPix,
        BillingPaymentPreference.mercadoPago,
      ];
    case BillingPaymentPreference.none:
      return const [BillingPaymentPreference.none];
  }
}

/// Resolve a forma exibida quando a disponibilidade das duas opcoes ja e
/// conhecida. O envio pelo app usa a mesma ordem, mas ainda pode cair do
/// Mercado Pago para o PIX pessoal caso a geracao da cobranca falhe.
BillingPaymentPreference resolveBillingPaymentMode({
  required BillingPaymentPreference preference,
  required bool mercadoPagoAvailable,
  required String? manualPixKey,
}) {
  final hasManualPix = manualPixKey?.trim().isNotEmpty ?? false;
  for (final candidate in billingPaymentFallbackOrder(preference)) {
    if (candidate == BillingPaymentPreference.none) {
      return BillingPaymentPreference.none;
    }
    if (candidate == BillingPaymentPreference.mercadoPago &&
        mercadoPagoAvailable) {
      return candidate;
    }
    if (candidate == BillingPaymentPreference.manualPix && hasManualPix) {
      return candidate;
    }
  }
  return BillingPaymentPreference.none;
}

/// Dados finais que entram no template oficial de cobranca.
class BillingPaymentInstruction {
  final BillingPaymentPreference mode;
  final String paymentValue;
  final String ticketUrl;

  const BillingPaymentInstruction._({
    required this.mode,
    this.paymentValue = '',
    this.ticketUrl = '',
  });

  const BillingPaymentInstruction.none()
    : this._(mode: BillingPaymentPreference.none);

  const BillingPaymentInstruction.manualPix(String pixKey)
    : this._(
        mode: BillingPaymentPreference.manualPix,
        paymentValue: pixKey,
      );

  const BillingPaymentInstruction.mercadoPago({
    required String pixCode,
    String ticketUrl = '',
  }) : this._(
         mode: BillingPaymentPreference.mercadoPago,
         paymentValue: pixCode,
         ticketUrl: ticketUrl,
       );

  bool get hasPayment =>
      mode != BillingPaymentPreference.none && paymentValue.isNotEmpty;
}

extension BillingPaymentPreferenceExtension on BillingPaymentPreference {
  String get value {
    switch (this) {
      case BillingPaymentPreference.mercadoPago:
        return 'mercado_pago';
      case BillingPaymentPreference.manualPix:
        return 'manual_pix';
      case BillingPaymentPreference.none:
        return 'none';
    }
  }

  String get label {
    switch (this) {
      case BillingPaymentPreference.mercadoPago:
        return 'Mercado Pago';
      case BillingPaymentPreference.manualPix:
        return 'PIX pessoal';
      case BillingPaymentPreference.none:
        return 'Não enviar forma de pagamento';
    }
  }

  String get description {
    switch (this) {
      case BillingPaymentPreference.mercadoPago:
        return 'Mercado Pago é o principal. Se estiver indisponível, usa o PIX pessoal.';
      case BillingPaymentPreference.manualPix:
        return 'O PIX pessoal é o principal. Se não estiver configurado, tenta o Mercado Pago.';
      case BillingPaymentPreference.none:
        return 'As cobranças são enviadas sem chave ou código de pagamento.';
    }
  }

  static BillingPaymentPreference fromString(String? value) {
    switch (value) {
      case 'manual_pix':
        return BillingPaymentPreference.manualPix;
      case 'none':
        return BillingPaymentPreference.none;
      case 'mercado_pago':
      default:
        return BillingPaymentPreference.mercadoPago;
    }
  }
}
