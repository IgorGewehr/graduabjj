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

  group('billingPaymentSummary (card "Como você recebe")', () {
    String summary({
      bool include = true,
      BillingPaymentPreference pref = BillingPaymentPreference.mercadoPago,
      bool mp = true,
      String? pix,
    }) => billingPaymentSummary(
      includePaymentLink: include,
      preference: pref,
      mercadoPagoAvailable: mp,
      manualPixKey: pix,
    );

    test('Mercado Pago conectado e preferido: só o nome', () {
      expect(summary(), 'Mercado Pago');
    });

    test('mensagens sem forma de pagamento (toggle desligado)', () {
      expect(
        summary(include: false),
        'Desligado — as mensagens vão sem forma de pagamento',
      );
    });

    test('MP preferido mas desconectado, com PIX: avisa o fallback real', () {
      expect(
        summary(mp: false, pix: 'pix@academia.com'),
        'PIX pessoal (Mercado Pago não está disponível)',
      );
    });

    test('PIX preferido sem chave, MP conectado: cai no Mercado Pago', () {
      expect(
        summary(pref: BillingPaymentPreference.manualPix),
        'Mercado Pago (PIX pessoal não está disponível)',
      );
    });

    test('PIX preferido e cadastrado: só o nome', () {
      expect(
        summary(pref: BillingPaymentPreference.manualPix, pix: 'x'),
        'PIX pessoal',
      );
    });

    test('nada disponível: não promete uma forma que não existe', () {
      expect(summary(mp: false), 'Nenhuma configurada ainda');
    });

    test('"não enviar" escolhido é dito como escolha, não como falha', () {
      expect(
        summary(pref: BillingPaymentPreference.none, pix: 'x'),
        'Nenhuma — as mensagens vão sem chave ou código',
      );
    });
  });

  group('billingFallbackNotice (toast depois do envio)', () {
    String notice(String? reason, String? mode) =>
        billingFallbackNotice(reason: reason, paymentMode: mode);

    test('sem motivo de fallback não acrescenta nada', () {
      expect(notice(null, 'mercado_pago'), '');
      expect(notice('algo_desconhecido', 'manual_pix'), '');
    });

    test('Mercado Pago falhou e foi o PIX pessoal: diz isso', () {
      expect(
        notice('mercado_pago_unavailable', 'manual_pix'),
        ' Mercado Pago estava indisponível; a cobrança foi com o PIX pessoal.',
      );
    });

    test('Mercado Pago falhou e NÃO há PIX pessoal: não finge que houve', () {
      final text = notice('reconnect_required', 'none');
      expect(text, contains('reconectado'));
      expect(text, contains('sem forma de pagamento'));
      expect(text, isNot(contains('foi com o PIX pessoal')));
    });

    test('dados do pagador faltando orientam o que cadastrar', () {
      expect(notice('missing_payer_cpf', 'manual_pix'), contains('CPF válido'));
      expect(
        notice('missing_payer_email', 'manual_pix'),
        contains('e-mail válido'),
      );
      expect(
        notice('missing_payer_data', 'manual_pix'),
        contains('CPF e e-mail'),
      );
    });

    test('modo desconhecido/ausente fecha a frase sem inventar o desfecho', () {
      expect(
        notice('seller_pix_unavailable', null),
        ' A conta Mercado Pago não conseguiu gerar o PIX.',
      );
    });

    test('nunca expõe a palavra "fallback" ao usuário', () {
      for (final reason in [
        'missing_payer_cpf',
        'missing_payer_email',
        'missing_payer_data',
        'reconnect_required',
        'seller_pix_unavailable',
        'mercado_pago_unavailable',
      ]) {
        for (final mode in ['manual_pix', 'none', null]) {
          expect(
            notice(reason, mode).toLowerCase(),
            isNot(contains('fallback')),
          );
        }
      }
    });
  });
}
