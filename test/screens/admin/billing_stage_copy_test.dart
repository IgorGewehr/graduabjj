import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/billing_payment_preference.dart';
import 'package:graduabjj/screens/admin/widgets/billing_stage_copy.dart';
import 'package:graduabjj/services/billing_reminder_service.dart';

void main() {
  final service = BillingNotificationService(
    academyId: 'acad-1',
    academyName: 'Academia Teste',
  );

  BillingStage stageEnum(BillingStageCopy copy) =>
      BillingStage.values.firstWhere((b) => b.value == copy.key);

  group('kBillingStageCopies acompanha o serviço', () {
    test('toda etapa tem assunto e corpo de e-mail padrão', () {
      for (final stage in kBillingStageCopies) {
        expect(
          BillingNotificationService.defaultEmailSubjectTemplates,
          contains(stage.key),
          reason: 'sem assunto padrão para ${stage.key}',
        );
        expect(
          BillingNotificationService.defaultEmailBodyTemplates,
          contains(stage.key),
          reason: 'sem corpo padrão para ${stage.key}',
        );
      }
    });

    test('nenhuma etapa dos templates ficou de fora da lista', () {
      final keys = kBillingStageCopies.map((s) => s.key).toSet();
      expect(
        BillingNotificationService.defaultEmailSubjectTemplates.keys.toSet(),
        keys,
      );
    });

    test('toda chave é uma etapa real da régua (BillingStage)', () {
      for (final stage in kBillingStageCopies) {
        expect(
          BillingStage.values.where((b) => b.value == stage.key),
          hasLength(1),
          reason: stage.key,
        );
      }
    });

    test('rótulos não expõem a sigla interna (D+7, CREATED...)', () {
      for (final stage in kBillingStageCopies) {
        expect(stage.label, isNot(contains('D+')));
        expect(stage.label, isNot(equals(stage.key)));
        expect(stage.label, isNot(contains('CREATED')));
        expect(stage.label, isNot(contains('UPCOMING')));
      }
    });
  });

  group('prévia oficial do WhatsApp (mesma chamada do diálogo)', () {
    String? preview(BillingStageCopy copy, BillingPaymentPreference mode) =>
        service.generateOfficialWhatsAppPreview(
          stage: stageEnum(copy),
          paymentMode: mode,
          studentName: 'Maria',
          amount: 150,
          dueDate: DateTime(2026, 10, 1),
          paymentValue: '(código)',
          daysOverdue: copy.sampleDaysOverdue,
        );

    test('só "Parcela criada" fica sem modelo aprovado', () {
      for (final copy in kBillingStageCopies) {
        final p = preview(copy, BillingPaymentPreference.mercadoPago);
        if (copy.key == 'CREATED') {
          expect(p, isNull, reason: 'CREATED não tem modelo aprovado');
        } else {
          expect(p, isNotNull, reason: '${copy.key} deveria ter modelo');
        }
      }
    });

    test('"A vencer" tem modelo (regressão Lobisomens, 03/set/2026)', () {
      final upcoming = kBillingStageCopies.firstWhere(
        (s) => s.key == 'UPCOMING',
      );
      expect(preview(upcoming, BillingPaymentPreference.mercadoPago), isNotNull);
    });

    test('nunca deixa {{n}} sem preencher, em nenhuma forma de pagamento', () {
      for (final copy in kBillingStageCopies) {
        for (final mode in BillingPaymentPreference.values) {
          final text = preview(copy, mode);
          if (text == null) continue;
          expect(text, isNot(contains('{{')), reason: '${copy.key}/$mode');
          expect(text, contains('Maria'), reason: '${copy.key}/$mode');
          expect(text, contains('Academia Teste'), reason: '${copy.key}/$mode');
        }
      }
    });
  });

  group('billingTemplateVariablesHint', () {
    BillingStageCopy stage(String key) =>
        kBillingStageCopies.firstWhere((s) => s.key == key);

    test('só cita {dias} em etapa de atraso', () {
      expect(billingTemplateVariablesHint(stage('D+7')), contains('{dias}'));
      expect(
        billingTemplateVariablesHint(stage('D+0')),
        isNot(contains('{dias}')),
      );
    });

    test('só cita {diasAteVencimento} antes do vencimento', () {
      expect(
        billingTemplateVariablesHint(stage('UPCOMING')),
        contains('{diasAteVencimento}'),
      );
      expect(
        billingTemplateVariablesHint(stage('D+3')),
        isNot(contains('{diasAteVencimento}')),
      );
    });
  });
}
