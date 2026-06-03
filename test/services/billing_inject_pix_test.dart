import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/billing_reminder_service.dart';

/// Screen-composition level tests for how the billing screens wire PIX into
/// the WhatsApp message that gets sent (manual _executeSend preview + bulk
/// _executeBulkSendNew per-item personalization). The composition reduces to
/// the pure functions [BillingNotificationService.applyMessageTemplate] and
/// [BillingNotificationService.generateWhatsAppMessage] being called with
/// optional pixCode/ticketUrl, plus the includePaymentLink gate.
void main() {
  final service = BillingNotificationService(
    academyId: 'acad-1',
    academyName: 'Academia Teste',
  );

  final dueDate = DateTime(2026, 6, 1);

  const template =
      'Ola {nome}! Voce deve {valor}.[[PIX]]\n\nPIX: {pix}\n\nLink: {link}[[/PIX]]';

  group('bulk per-item injection (applyMessageTemplate with pix args)', () {
    test('injects copia-e-cola + link when PIX present', () {
      final out = service.applyMessageTemplate(
        template,
        'Joao',
        150.0,
        dueDate,
        5,
        pixCode: '00020PIXCOPIACOLA',
        ticketUrl: 'https://mpago.me/abc',
      );
      expect(out, contains('Joao'));
      expect(out, contains('00020PIXCOPIACOLA'));
      expect(out, contains('https://mpago.me/abc'));
      expect(out, isNot(contains('[[PIX]]')));
      expect(out, isNot(contains('[[/PIX]]')));
      expect(out, isNot(contains('{pix}')));
      expect(out, isNot(contains('{link}')));
    });

    test('strips the whole PIX block when PIX absent (failed generation)', () {
      final out = service.applyMessageTemplate(
        template,
        'Joao',
        150.0,
        dueDate,
        5,
      );
      expect(out, contains('Joao'));
      expect(out, isNot(contains('PIX:')));
      expect(out, isNot(contains('Link:')));
      expect(out, isNot(contains('[[PIX]]')));
      expect(out, isNot(contains('[[/PIX]]')));
      expect(out, isNot(contains('{pix}')));
      expect(out, isNot(contains('{link}')));
    });

    test('empty pixCode behaves like absent (graceful degradation)', () {
      final out = service.applyMessageTemplate(
        template,
        'Joao',
        150.0,
        dueDate,
        5,
        pixCode: '',
        ticketUrl: '',
      );
      expect(out, isNot(contains('PIX:')));
      expect(out, isNot(contains('{pix}')));
      expect(out, isNot(contains('{link}')));
    });

    test('does NOT re-run name/amount substitution incorrectly on re-call',
        () {
      // The bulk path personalizes once with the raw template (still holding
      // {nome}/{valor}), so a single applyMessageTemplate call must resolve
      // both the placeholders and the PIX block in one pass.
      final out = service.applyMessageTemplate(
        template,
        'Maria',
        90.0,
        dueDate,
        2,
        pixCode: 'CODE123',
        ticketUrl: 'https://mpago.me/x',
      );
      expect(out, contains('Maria'));
      expect(out, isNot(contains('{nome}')));
      expect(out, isNot(contains('{valor}')));
      expect(out, contains('CODE123'));
    });
  });

  group('manual preview injection (generateWhatsAppMessage)', () {
    test('preview shows real copia-e-cola + link when PIX present', () {
      final msg = service.generateWhatsAppMessage(
        stage: BillingStage.d1,
        studentName: 'Joao',
        amount: 150.0,
        dueDate: dueDate,
        daysOverdue: 5,
        pixCode: '00020REAL',
        ticketUrl: 'https://mpago.me/real',
      );
      expect(msg, contains('00020REAL'));
      expect(msg, contains('https://mpago.me/real'));
      expect(msg, isNot(contains('[[PIX]]')));
      expect(msg, isNot(contains('{pix}')));
      expect(msg, isNot(contains('{link}')));
    });

    test('preview is clean (no markers/placeholders) when PIX unavailable', () {
      final msg = service.generateWhatsAppMessage(
        stage: BillingStage.d1,
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
  });

  group('includePaymentLink gate semantics', () {
    test('gate off => caller passes no pix args => clean message', () {
      // Simulates the screen gate evaluating to false: no ensureValidPix call,
      // message built with no pix args.
      final settings = BillingNotificationSettings(includePaymentLink: false);
      expect(settings.includePaymentLink, isFalse);

      final msg = service.generateWhatsAppMessage(
        stage: BillingStage.d3,
        studentName: 'Joao',
        amount: 200.0,
        dueDate: dueDate,
        daysOverdue: 10,
      );
      expect(msg, isNot(contains('{pix}')));
      expect(msg, isNot(contains('{link}')));
    });
  });
}
