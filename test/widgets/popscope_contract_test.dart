import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Sprint B2 — child-PopScope contract.
//
// The real screens that carry a PopScope (admin/settings_screen.dart and
// admin/physical_assessment_form_screen.dart) are too heavy to pump in a unit
// test: they pull in Firebase (Firestore/Storage/Auth), Riverpod providers,
// image_picker and network calls. Faithfully booting them would test the
// infra, not the back-gesture contract.
//
// Instead we replicate the EXACT contract those screens implement on a minimal
// harness and assert it end-to-end:
//   - canPop is true ONLY when clean; false when dirty (gesture intercepted).
//   - onPopInvokedWithResult: if (didPop) return; if dirty -> discard dialog;
//     CONFIRM -> pop (leave); CANCEL -> stay; clean -> route pops, no dialog.
//   - never SystemNavigator.pop from the child; never canPop:true while dirty.
//
// A clean form back-press pops to the PARENT route (there is navigator history
// below), proving no app-exit falls through.

/// Minimal screen mirroring the child-PopScope contract under test.
class _ContractScreen extends StatefulWidget {
  const _ContractScreen();

  @override
  State<_ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<_ContractScreen> {
  // A trivial dirty flag: the field is "dirty" once non-empty.
  final _controller = TextEditingController();
  bool get _isDirty => _controller.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar alterações?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return; // clean form already popped to parent
        if (_isDirty) {
          final discard = await _confirmDiscard();
          if (!discard || !mounted) return; // CANCEL -> stay
        }
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('child')),
        body: TextField(
          controller: _controller,
          decoration: const InputDecoration(hintText: 'edit me'),
        ),
      ),
    );
  }
}

void main() {
  /// Pumps a parent route that pushes the contract screen, so there IS
  /// navigator history below — a clean back must pop to the parent, never exit.
  Future<NavigatorState> pumpWithParent(WidgetTester tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const _ContractScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('child'), findsOneWidget);
    return navKey.currentState!;
  }

  testWidgets('clean form: back pops to parent, no dialog', (tester) async {
    final nav = await pumpWithParent(tester);

    // Field is empty => clean => canPop true. Trigger a back intent.
    final popped = await nav.maybePop();
    await tester.pumpAndSettle();

    expect(popped, isTrue, reason: 'clean form pops normally');
    expect(find.text('Descartar alterações?'), findsNothing,
        reason: 'no confirm dialog for a clean form');
    expect(find.text('child'), findsNothing, reason: 'left the child screen');
    expect(find.text('open'), findsOneWidget, reason: 'back on the parent');
  });

  testWidgets('dirty form: back shows confirm dialog and stays on CANCEL',
      (tester) async {
    final nav = await pumpWithParent(tester);

    await tester.enterText(find.byType(TextField), 'unsaved');
    await tester.pump();

    await nav.maybePop();
    await tester.pumpAndSettle();

    // Dialog shown, still on the child screen.
    expect(find.text('Descartar alterações?'), findsOneWidget);
    expect(find.text('child'), findsOneWidget);

    // CANCEL -> stay.
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsNothing);
    expect(find.text('child'), findsOneWidget, reason: 'cancel keeps screen');
    expect(find.text('open'), findsNothing);
  });

  testWidgets('dirty form: CONFIRM discards and pops to parent',
      (tester) async {
    final nav = await pumpWithParent(tester);

    await tester.enterText(find.byType(TextField), 'unsaved');
    await tester.pump();

    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);

    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    expect(find.text('child'), findsNothing, reason: 'discarded and left');
    expect(find.text('open'), findsOneWidget, reason: 'back on the parent');
  });
}
