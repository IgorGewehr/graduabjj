import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/widgets/payment_sheets.dart';

void main() {
  testWidgets('shows personal PIX only after gateway generation fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixPaymentSheet(
            amount: 150,
            description: 'Mensalidade',
            manualPixFallbackKey: 'pix@academia.com',
            onRegenerate: (_) async => null,
          ),
        ),
      ),
    );

    expect(find.text('Copiar chave PIX pessoal'), findsNothing);
    await tester.tap(find.text('Gerar PIX'));
    await tester.pumpAndSettle();

    expect(find.text('Ou pague com a chave PIX da academia'), findsOneWidget);
    expect(find.text('Copiar chave PIX pessoal'), findsOneWidget);
    expect(
      find.textContaining('A confirmacao deste pagamento e manual'),
      findsOneWidget,
    );
  });
}
