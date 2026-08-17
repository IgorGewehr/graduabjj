import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/billing_reminder_service.dart';

void main() {
  group('StudentContact.effectiveCpf', () {
    test('adult uses student cpf', () {
      final contact = StudentContact(
        studentId: 's1',
        studentName: 'Adult Student',
        category: 'adult',
        cpf: '111',
        guardianCpf: '222',
      );

      expect(contact.effectiveCpf, '111');
    });

    test('kids uses guardian cpf', () {
      final contact = StudentContact(
        studentId: 's2',
        studentName: 'Kid Student',
        category: 'kids',
        cpf: '111',
        guardianCpf: '222',
      );

      expect(contact.effectiveCpf, '222');
    });

    test('kids falls back to the student cpf when guardian cpf is absent', () {
      final contact = StudentContact(
        studentId: 's3',
        studentName: 'Kid Student No Guardian',
        category: 'kids',
        cpf: '111',
        guardianCpf: null,
      );

      expect(contact.effectiveCpf, '111');
    });

    test('Mercado Pago requires valid CPF and an email source', () {
      final ready = StudentContact(
        studentId: 's4',
        studentName: 'Ready',
        cpf: '52998224725',
        email: 'ready@example.com',
      );
      final missingEmail = StudentContact(
        studentId: 's5',
        studentName: 'Missing email',
        cpf: '52998224725',
      );
      final linked = StudentContact(
        studentId: 's6',
        studentName: 'Linked account',
        cpf: '52998224725',
        linkedUserId: 'uid-1',
      );

      expect(ready.canGenerateMercadoPagoPix, isTrue);
      expect(missingEmail.canGenerateMercadoPagoPix, isFalse);
      expect(linked.canGenerateMercadoPagoPix, isTrue);
    });
  });
}
