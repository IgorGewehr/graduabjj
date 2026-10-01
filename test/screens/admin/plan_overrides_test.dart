import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:graduabjj/models/student.dart';
import 'package:graduabjj/screens/admin/widgets/plan_override_dialog.dart';
import 'package:graduabjj/screens/admin/widgets/plan_overrides.dart';
import 'package:graduabjj/screens/admin/widgets/plan_overrides_sheet.dart';
import 'package:graduabjj/services/plan_service.dart';

Student _student(String id, String name) {
  final now = DateTime.utc(2026, 8, 10);
  return Student(
    id: id,
    fullName: name,
    startDate: now,
    currentBelt: 'white',
    currentStripes: 0,
    category: StudentCategory.adult,
    status: StudentStatus.active,
    tuitionValue: 0,
    tuitionDay: 10,
    createdAt: now,
    updatedAt: now,
  );
}

Plan _plan({
  List<String> studentIds = const ['a', 'b', 'c', 'd', 'gone'],
  Map<String, double> customValues = const {},
  Map<String, int> customDueDays = const {},
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Plan(
    id: 'p1',
    name: 'Mensal Adulto',
    monthlyValue: 200,
    defaultDueDay: 10,
    studentIds: studentIds,
    customValues: customValues,
    customDueDays: customDueDays,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('planOverrideIds', () {
    test('só alunos ativos e fora de conflito, por tipo', () {
      final plan = _plan(
        customValues: {'a': 150, 'b': 120, 'gone': 100},
        customDueDays: {'b': 15, 'c': 5},
      );
      final ids = planOverrideIds(
        plan,
        activeStudentIds: {'a', 'b', 'c', 'd'}, // 'gone' não está ativo
        conflictStudentIds: {'b'}, // 'b' cobrado em 2 planos: fora do cálculo
      );
      expect(ids.value, ['a']);
      expect(ids.dueDay, ['c']);
      expect(ids.of(PlanOverrideKind.value), ids.value);
      expect(ids.of(PlanOverrideKind.dueDay), ids.dueDay);
    });

    test('plano sem personalizações devolve listas vazias', () {
      final ids = planOverrideIds(
        _plan(),
        activeStudentIds: {'a', 'b'},
        conflictStudentIds: const {},
      );
      expect(ids.value, isEmpty);
      expect(ids.dueDay, isEmpty);
    });
  });

  group('showPlanOverridesSheet', () {
    final students = [
      _student('a', 'Carla'),
      _student('b', 'Ana'),
      _student('c', 'Bruno'),
      _student('d', 'Davi'),
    ];

    Future<void> open(
      WidgetTester tester, {
      required Plan plan,
      PlanOverrideKind kind = PlanOverrideKind.value,
      bool canEdit = true,
      Set<String> conflicts = const {},
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showPlanOverridesSheet(
                    context,
                    plan: plan,
                    students: students,
                    conflictStudentIds: conflicts,
                    initialKind: kind,
                    canEdit: canEdit,
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    final plan = _plan(
      customValues: {'a': 150, 'b': 120},
      customDueDays: {'c': 15},
    );

    testWidgets('abre na aba tocada, com contagens e valor vs padrão', (
      tester,
    ) async {
      await open(tester, plan: plan);

      expect(find.text('Valor · 2'), findsOneWidget);
      expect(find.text('Vencimento · 1'), findsOneWidget);
      // Alfabético: Ana antes de Carla; Bruno (só vencimento) não aparece.
      final ana = tester.getTopLeft(find.text('Ana')).dy;
      final carla = tester.getTopLeft(find.text('Carla')).dy;
      expect(ana, lessThan(carla));
      expect(find.text('Bruno'), findsNothing);
      expect(find.textContaining('R\$'), findsWidgets);
      expect(find.textContaining('padrão'), findsWidgets);
    });

    testWidgets('trocar para Vencimento mostra só quem tem data própria', (
      tester,
    ) async {
      await open(tester, plan: plan);
      await tester.tap(find.text('Vencimento · 1'));
      await tester.pumpAndSettle();

      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Ana'), findsNothing);
      expect(find.textContaining('Dia 15'), findsOneWidget);
      expect(find.textContaining('padrão dia 10'), findsOneWidget);
    });

    testWidgets('abre direto na aba de vencimento quando é o selo tocado', (
      tester,
    ) async {
      await open(tester, plan: plan, kind: PlanOverrideKind.dueDay);
      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Ana'), findsNothing);
    });

    testWidgets('conflito sai da lista (mesma regra do selo do card)', (
      tester,
    ) async {
      await open(tester, plan: plan, conflicts: {'a'});
      expect(find.text('Valor · 1'), findsOneWidget);
      expect(find.text('Carla'), findsNothing);
      expect(find.text('Ana'), findsOneWidget);
    });

    testWidgets('aba sem ninguém mostra estado vazio específico', (
      tester,
    ) async {
      await open(tester, plan: _plan(customValues: {'a': 150}));
      await tester.tap(find.text('Vencimento · 0'));
      await tester.pumpAndSettle();
      expect(
        find.text('Nenhum aluno com vencimento personalizado'),
        findsOneWidget,
      );
    });

    testWidgets('sem permissão: lista de leitura, sem lápis e com aviso', (
      tester,
    ) async {
      await open(tester, plan: plan, canEdit: false);
      expect(find.byIcon(LucideIcons.pencil), findsNothing);
      expect(find.text('Somente administradores podem editar.'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
    });

    testWidgets('admin vê um lápis por linha e nenhum aviso', (tester) async {
      await open(tester, plan: plan);
      expect(find.byIcon(LucideIcons.pencil), findsNWidgets(2));
      expect(find.text('Somente administradores podem editar.'), findsNothing);
    });
  });

  group('showPlanOverrideDialog (validação, sem tocar no Firestore)', () {
    final plan = _plan(customValues: {'a': 150}, customDueDays: {'a': 15});

    Future<Future<bool>> open(WidgetTester tester) async {
      late Future<bool> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => result = showPlanOverrideDialog(
                  context,
                  plan: plan,
                  studentId: 'a',
                  studentName: 'Carla',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('abre com os valores atuais e os botões de restaurar', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Carla'), findsOneWidget);
      expect(find.widgetWithText(TextField, '150.00'), findsOneWidget);
      expect(find.widgetWithText(TextField, '15'), findsOneWidget);
      expect(find.text('Restaurar valor do plano'), findsOneWidget);
      expect(find.text('Restaurar vencimento do plano'), findsOneWidget);
    });

    testWidgets('valor zerado e dia fora de 1-31 mostram erro e não fecham', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, '150.00'), '0');
      await tester.enterText(find.widgetWithText(TextField, '15'), '32');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe um valor maior que zero'), findsOneWidget);
      expect(find.text('Informe um dia de 1 a 31'), findsOneWidget);
      expect(find.text('Salvar'), findsOneWidget); // ainda aberto
    });

    testWidgets('sem alteração fecha devolvendo false (nada gravado)', (
      tester,
    ) async {
      final result = await open(tester);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Salvar'), findsNothing);
      expect(await result, isFalse);
    });

    testWidgets('Cancelar fecha devolvendo false', (tester) async {
      final result = await open(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });
}
