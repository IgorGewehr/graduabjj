import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/billing_payment_preference.dart';

void main() {
  group('BillingPaymentPreference', () {
    test('missing and invalid values preserve the Mercado Pago default', () {
      expect(
        BillingPaymentPreferenceExtension.fromString(null),
        BillingPaymentPreference.mercadoPago,
      );
      expect(
        BillingPaymentPreferenceExtension.fromString('unexpected'),
        BillingPaymentPreference.mercadoPago,
      );
    });

    test('stored values round-trip', () {
      for (final preference in BillingPaymentPreference.values) {
        expect(
          BillingPaymentPreferenceExtension.fromString(preference.value),
          preference,
        );
      }
    });

    test('Mercado Pago preferred falls back to personal PIX', () {
      expect(
        resolveBillingPaymentMode(
          preference: BillingPaymentPreference.mercadoPago,
          mercadoPagoAvailable: false,
          manualPixKey: 'pix@academia.com',
        ),
        BillingPaymentPreference.manualPix,
      );
    });

    test('personal PIX preferred falls back to Mercado Pago', () {
      expect(
        resolveBillingPaymentMode(
          preference: BillingPaymentPreference.manualPix,
          mercadoPagoAvailable: true,
          manualPixKey: ' ',
        ),
        BillingPaymentPreference.mercadoPago,
      );
    });

    test('no available method resolves to none', () {
      expect(
        resolveBillingPaymentMode(
          preference: BillingPaymentPreference.mercadoPago,
          mercadoPagoAvailable: false,
          manualPixKey: null,
        ),
        BillingPaymentPreference.none,
      );
    });

    test('explicit none never falls back', () {
      expect(
        resolveBillingPaymentMode(
          preference: BillingPaymentPreference.none,
          mercadoPagoAvailable: true,
          manualPixKey: 'pix@academia.com',
        ),
        BillingPaymentPreference.none,
      );
    });
  });
}
