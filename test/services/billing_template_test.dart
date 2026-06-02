import 'package:flutter_test/flutter_test.dart';
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
  });
}
