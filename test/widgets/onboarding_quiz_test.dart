import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/widgets/onboarding/quiz_card_option.dart';
import 'package:graduabjj/widgets/onboarding/quiz_decision_bridge.dart';
import 'package:graduabjj/widgets/onboarding/quiz_header.dart';
import 'package:graduabjj/widgets/onboarding/steps/quiz_step_sandbox.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
  group('Onboarding Quiz Components Tests', () {
    testWidgets('QuizCardOption renders title, subtitle and fires onTap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuizCardOption(
              title: 'Jiu-Jitsu',
              subtitle: 'Treinos e graduação',
              icon: LucideIcons.shield,
              badgeText: 'Mais Popular',
              isSelected: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jiu-Jitsu'), findsOneWidget);
      expect(find.text('Treinos e graduação'), findsOneWidget);
      expect(find.text('Mais Popular'), findsOneWidget);

      await tester.tap(find.text('Jiu-Jitsu'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('QuizHeader displays progress and handles skip and back', (tester) async {
      bool skipped = false;
      bool backed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuizHeader(
              currentStep: 2,
              totalSteps: 5,
              stageTitle: 'Setup Essencial',
              onBack: () => backed = true,
              onSkip: () => skipped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SETUP ESSENCIAL'), findsOneWidget);
      expect(find.text('Passo 2 de 5'), findsOneWidget);
      expect(find.text('Pular etapa'), findsOneWidget);

      await tester.tap(find.text('Pular etapa'));
      await tester.pumpAndSettle();
      expect(skipped, isTrue);

      await tester.tap(find.byIcon(LucideIcons.arrowLeft));
      await tester.pumpAndSettle();
      expect(backed, isTrue);
    });

    testWidgets('QuizStepSandbox allows tapping a student to simulate check-in', (tester) async {
      bool nextCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuizStepSandbox(
              onNext: () => nextCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Veja como é rápido na prática!'), findsOneWidget);
      expect(find.text('Lucas Silva'), findsOneWidget);
      expect(find.text('Amanda Costa'), findsOneWidget);

      // Tap on Lucas Silva to mark presence
      await tester.tap(find.text('Lucas Silva'));
      await tester.pumpAndSettle();

      expect(find.text('Presença computada!'), findsOneWidget);
      expect(find.text('Concluir e Continuar'), findsOneWidget);

      final continueButton = find.text('Concluir e Continuar');
      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      expect(nextCalled, isTrue);
    });

    testWidgets('QuizDecisionBridge fires onProceedToLevel2 and onGoToDashboard', (tester) async {
      bool level2Clicked = false;
      bool dashboardClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuizDecisionBridge(
              onProceedToLevel2: () => level2Clicked = true,
              onGoToDashboard: () => dashboardClicked = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sua academia está pronta!'), findsOneWidget);

      final proceedButton = find.text('Ativar Superpoderes (+1 min)');
      await tester.ensureVisible(proceedButton);
      await tester.tap(proceedButton);
      await tester.pumpAndSettle();
      expect(level2Clicked, isTrue);

      final dashboardButton = find.text('Ir para o Painel Principal agora');
      await tester.ensureVisible(dashboardButton);
      await tester.tap(dashboardButton);
      await tester.pumpAndSettle();
      expect(dashboardClicked, isTrue);
    });
  });
}
