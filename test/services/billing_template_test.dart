import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/billing_payment_preference.dart';
import 'package:graduabjj/services/billing_reminder_service.dart';

void main() {
  final service = BillingNotificationService(
    academyId: 'acad-1',
    academyName: 'Academia Teste',
  );

  group('injectPaymentInfo', () {
    test('substitutes {pix}/{link} and strips markers when PIX present', () {
      final out = service.injectPaymentInfo(
        'a [[PIX]]code:{pix} link:{link}[[/PIX]] b',
        pixCode: '00020',
        ticketUrl: 'https://mpago.me/x',
      );
      expect(out, contains('00020'));
      expect(out, contains('https://mpago.me/x'));
      expect(out, isNot(contains('[[PIX]]')));
      expect(out, isNot(contains('[[/PIX]]')));
      expect(out, isNot(contains('{pix}')));
      expect(out, isNot(contains('{link}')));
    });

    test('removes the whole block when PIX absent', () {
      final out = service.injectPaymentInfo(
        'a [[PIX]]code:{pix}[[/PIX]] b',
        pixCode: '',
        ticketUrl: '',
      );
      expect(out, equals('a  b'));
      expect(out, isNot(contains('[[PIX]]')));
      expect(out, isNot(contains('[[/PIX]]')));
      expect(out, isNot(contains('{pix}')));
      expect(out, isNot(contains('{link}')));
      expect(out, isNot(contains('code:')));
    });
  });

  group('official Meta template selection', () {
    test('selects Mercado Pago, personal PIX and no-payment variants', () {
      expect(
        service.templateNameForStage(
          BillingStage.d7,
          paymentMode: BillingPaymentPreference.mercadoPago,
        ),
        'cobranca_d7',
      );
      expect(
        service.templateNameForStage(
          BillingStage.d7,
          paymentMode: BillingPaymentPreference.manualPix,
        ),
        'cobranca_d7_pix_manual',
      );
      expect(
        service.templateNameForStage(
          BillingStage.d7,
          paymentMode: BillingPaymentPreference.none,
        ),
        'cobranca_d7_sempix',
      );
    });

    test('does not silently substitute an unapproved stage', () {
      expect(
        service.templateNameForStage(
          BillingStage.created,
          paymentMode: BillingPaymentPreference.none,
        ),
        isNull,
      );
      expect(
        service.templateNameForStage(
          BillingStage.upcoming,
          paymentMode: BillingPaymentPreference.mercadoPago,
        ),
        isNull,
      );
    });

    test('legacy academy WhatsApp text is discarded on read and save', () {
      final templates = BillingMessageTemplates.fromMap({
        'whatsapp': {'D+1': 'texto personalizado obsoleto'},
        'emailSubject': {'D+1': 'Assunto permitido'},
        'emailBody': {'D+1': 'Corpo permitido'},
      });

      expect(templates.toMap(), isNot(contains('whatsapp')));
      expect(templates.emailSubject['D+1'], 'Assunto permitido');
      expect(templates.emailBody['D+1'], 'Corpo permitido');
    });

    test('personal PIX preview matches the approved D+30 template', () {
      final preview = service.generateOfficialWhatsAppPreview(
        stage: BillingStage.d30,
        paymentMode: BillingPaymentPreference.manualPix,
        studentName: 'Gustavo',
        amount: 10,
        dueDate: DateTime(2026, 6, 30),
        paymentValue: '99999999',
      );

      expect(
        preview,
        matches(
          RegExp(
            r'A cobrança de R\$\s10,00 da Academia Teste, com vencimento em 30/06/2026, está em aberto há mais de 30 dias\.',
          ),
        ),
      );
      expect(preview, contains('Chave PIX para pagamento:\n99999999'));
      expect(preview, isNot(contains('infelizmente precisaremos')));
      expect(preview, isNot(contains('{{')));
    });

    test('Mercado Pago preview shows the approved template and deferred PIX', () {
      final preview = service.generateOfficialWhatsAppPreview(
        stage: BillingStage.d30,
        paymentMode: BillingPaymentPreference.mercadoPago,
        studentName: 'Gustavo',
        amount: 10,
        dueDate: DateTime(2026, 6, 30),
        paymentValue: '[PIX Mercado Pago gerado no envio]',
      );

      expect(
        preview,
        matches(
          RegExp(
            r'sua mensalidade de R\$\s10,00 da Academia Teste \(vencimento 30/06/2026\) está com mais de 30 dias de atraso\.',
          ),
        ),
      );
      expect(preview, contains('[PIX Mercado Pago gerado no envio]'));
      expect(preview, isNot(contains('{{')));
    });

    test('every approved stage and payment mode has a complete preview', () {
      const stages = [
        BillingStage.d0,
        BillingStage.d1,
        BillingStage.d3,
        BillingStage.d7,
        BillingStage.d15,
        BillingStage.d30,
      ];
      for (final stage in stages) {
        for (final mode in BillingPaymentPreference.values) {
          final preview = service.generateOfficialWhatsAppPreview(
            stage: stage,
            paymentMode: mode,
            studentName: 'Aluno',
            amount: 100,
            dueDate: DateTime(2026, 8, 17),
            paymentValue: mode == BillingPaymentPreference.none
                ? ''
                : 'pagamento',
          );
          expect(preview, isNotNull, reason: '${stage.value}/${mode.value}');
          expect(preview, isNot(contains('{{')));
        }
      }
    });
  });

  group('send error presentation', () {
    test('hides the Firebase stack trace for authentication failures', () {
      final message = BillingNotificationService.readableSendError(
        '[firebase_functions/unauthenticated] UNAUTHENTICATED\n#0 CloudFunctionsHostApi.call',
      );

      expect(message, contains('Nao foi possivel autenticar o envio'));
      expect(message, isNot(contains('#0')));
      expect(message, isNot(contains('CloudFunctionsHostApi')));
    });
  });

  group('generateWhatsAppMessage per stage', () {
    final dueDate = DateTime(2026, 6, 1);

    for (final stage in BillingStage.values) {
      test('${stage.value}: no pix args strips all markers/placeholders', () {
        final msg = service.generateWhatsAppMessage(
          stage: stage,
          studentName: 'Joao',
          amount: 150.0,
          dueDate: dueDate,
          daysOverdue: 5,
        );
        expect(msg, isNot(contains('[[PIX]]')));
        expect(msg, isNot(contains('[[/PIX]]')));
        expect(msg, isNot(contains('{pix}')));
        expect(msg, isNot(contains('{link}')));
      });

      test('${stage.value}: with pix args contains the code', () {
        final msg = service.generateWhatsAppMessage(
          stage: stage,
          studentName: 'Joao',
          amount: 150.0,
          dueDate: dueDate,
          daysOverdue: 5,
          pixCode: '00020PIXCODE',
          ticketUrl: 'https://mpago.me/abc',
        );
        expect(msg, contains('00020PIXCODE'));
        expect(msg, isNot(contains('[[PIX]]')));
        expect(msg, isNot(contains('[[/PIX]]')));
        expect(msg, isNot(contains('{pix}')));
        expect(msg, isNot(contains('{link}')));
      });
    }

    test('upcoming template uses a positive days-until-due value', () {
      final msg = service.generateWhatsAppMessage(
        stage: BillingStage.upcoming,
        studentName: 'Joao',
        amount: 150,
        dueDate: dueDate,
        daysOverdue: -7,
      );
      expect(msg, contains('7 dia(s)'));
      expect(msg, isNot(contains('-7')));
      expect(msg, isNot(contains('{diasAteVencimento}')));
    });

    test('created template clearly says the installment is available', () {
      final msg = service.generateWhatsAppMessage(
        stage: BillingStage.created,
        studentName: 'Maria',
        amount: 120,
        dueDate: dueDate,
        daysOverdue: 0,
      );
      expect(msg, contains('ja esta disponivel'));
      expect(msg, contains('Maria'));
    });
  });

  group('BillingNotificationSettings.includePaymentLink', () {
    test('defaults to true (back-compat for existing academies)', () {
      final settings = BillingNotificationSettings(
        whatsappEnabled: true,
        emailEnabled: false,
      );
      expect(settings.includePaymentLink, isTrue);
    });

    test('honors explicit false', () {
      final settings = BillingNotificationSettings(includePaymentLink: false);
      expect(settings.includePaymentLink, isFalse);
    });

    test('automation defaults are safe and include useful due moments', () {
      final settings = BillingNotificationSettings();
      expect(settings.notifyOnCreation, isFalse);
      expect(settings.dueSoonOffsets, containsAll([7, 3, 1, 0]));
    });
  });
}
