import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/theme.dart';
import 'package:graduabjj/screens/admin/widgets/billing_payment_actions.dart';

void main() {
  Widget buildActions(double width, {bool includeEmail = true}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: BillingPaymentActions(
              primaryAction: ElevatedButton.icon(
                key: ValueKey('primary'),
                onPressed: () {},
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Cobrar aluno'),
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              emailAction: includeEmail
                  ? IconButton(
                      key: ValueKey('email'),
                      onPressed: () {},
                      icon: const Icon(Icons.email_outlined, size: 20),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                    )
                  : null,
              secondaryActions: [
                for (final entry in const [
                  ('phone', Icons.phone_outlined),
                  ('log', Icons.assignment_outlined),
                  ('confirm', Icons.verified_outlined),
                  ('delete', Icons.delete_outline),
                ])
                  IconButton(
                    key: ValueKey(entry.$1),
                    onPressed: () {},
                    icon: Icon(entry.$2, size: 20),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('quebra as acoes em duas linhas no card estreito', (
    tester,
  ) async {
    // 328 px reproduz a largura útil do card no Pixel 7 do relato.
    await tester.pumpWidget(buildActions(328));

    final primaryBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('primary')))
        .dy;
    final emailTop = tester.getTopLeft(find.byKey(const ValueKey('email'))).dy;

    expect(emailTop, greaterThanOrEqualTo(primaryBottom + 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mantem o mesmo botao largo quando o aluno nao tem email', (
    tester,
  ) async {
    await tester.pumpWidget(buildActions(328, includeEmail: false));

    final primaryFinder = find.byKey(const ValueKey('primary'));
    final primaryBottom = tester.getBottomLeft(primaryFinder).dy;
    final phoneTop = tester.getTopLeft(find.byKey(const ValueKey('phone'))).dy;

    expect(tester.getSize(primaryFinder).width, 328);
    expect(phoneTop, greaterThanOrEqualTo(primaryBottom + 4));
    expect(tester.takeException(), isNull);
  });
}
