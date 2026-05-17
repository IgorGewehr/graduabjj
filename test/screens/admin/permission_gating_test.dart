import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/models/user.dart';
import 'package:graduabjj/providers/auth_provider.dart';
import 'package:graduabjj/providers/portal_providers.dart';
import 'package:graduabjj/screens/admin/admin_shell.dart';
import 'package:graduabjj/services/settings_service.dart';

/// Widget tests para a matriz de gating no AdminSidebar.
///
/// O sidebar é rebuilt com base em `currentUserProvider` + a settings da
/// academia. Aqui usamos overrides do Riverpod para fixar o user em cada
/// cenário e checamos quais labels aparecem na lista de NavItems.
///
/// As checagens são por `findsOneWidget` / `findsNothing` de Text() —
/// barato e estável (não depende de pixels). Os labels podem repetir
/// entre sidebar (desktop) e bottom nav (mobile); aqui forçamos viewport
/// desktop (≥ 768px) pra isolar o sidebar.

AppUser _user(
  UserRole role, {
  String academyId = 'aid-1',
  List<String> extras = const [],
}) =>
    AppUser(
      id: 'u-${role.value}',
      email: '${role.value}@x.com',
      displayName: role.label,
      role: role,
      academyId: academyId,
      extraPermissions: extras,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

ProviderContainer _container(
  AppUser user, {
  bool storeEnabled = true,
}) {
  return ProviderContainer(
    overrides: [
      currentUserProvider.overrideWith((ref) async => user),
      academySettingsProvider.overrideWith(
        (ref) async => AcademySettings(
          name: 'Test Academy',
          storeEnabled: storeEnabled,
        ),
      ),
      // Notification bell ignora se o stream nunca emite — sidebar não
      // depende deste provider, é o AppBar (que só aparece em mobile).
    ],
  );
}

Widget _wrap(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  // Força viewport desktop pra renderizar AdminSidebar (≥ 768px).
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .views.first;
    // Altura generosa pra não cortar nenhum item da sidebar.
    view.physicalSize = const Size(1024, 2000);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> pumpSidebar(
    WidgetTester tester,
    AppUser user, {
    bool storeEnabled = true,
  }) async {
    final container = _container(user, storeEnabled: storeEnabled);
    // Pré-aquece os providers async pra evitar frame de loading no pump.
    await container.read(currentUserProvider.future);
    await container.read(academySettingsProvider.future);
    await tester.pumpWidget(
      _wrap(container, const AdminSidebar(currentPath: '/admin')),
    );
    await tester.pump();
  }

  group('AdminSidebar gating — admin', () {
    testWidgets('admin sees every nav item', (tester) async {
      await pumpSidebar(tester, _user(UserRole.admin));

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Alunos'), findsOneWidget);
      expect(find.text('Chamada'), findsOneWidget);
      expect(find.text('Turmas'), findsOneWidget);
      expect(find.text('Campeonatos'), findsOneWidget);
      expect(find.text('Financeiro'), findsOneWidget);
      expect(find.text('Cobranca'), findsOneWidget);
      expect(find.text('Relatorios'), findsOneWidget);
      expect(find.text('Loja'), findsOneWidget);
      expect(find.text('Equipe'), findsOneWidget);
      expect(find.text('Configurações'), findsOneWidget);
      expect(find.text('Código de equipe'), findsOneWidget);
    });
  });

  group('AdminSidebar gating — instructor (defaults)', () {
    testWidgets('instructor sees attendance/students/financial.read but '
        'NOT financial.write / store / settings', (tester) async {
      await pumpSidebar(tester, _user(UserRole.instructor));

      // Visíveis: tem attendance.read, students.read, financial.read,
      // notifications.send + isInstructor (Campeonatos)
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Alunos'), findsOneWidget);
      expect(find.text('Chamada'), findsOneWidget);
      expect(find.text('Turmas'), findsOneWidget);
      expect(find.text('Campeonatos'), findsOneWidget);
      expect(find.text('Financeiro'), findsOneWidget,
          reason: 'instructor tem financial.read → vê Financeiro (read-only)');
      expect(find.text('Relatorios'), findsOneWidget,
          reason: 'instructor tem financial.read → vê Relatórios');

      // Escondidos: não tem financial.write nem store.write nem isAdmin
      expect(find.text('Cobranca'), findsNothing,
          reason: 'Cobrança exige financial.write');
      expect(find.text('Loja'), findsNothing,
          reason: 'Loja exige store.write (instructor não tem)');
      expect(find.text('Equipe'), findsNothing,
          reason: 'Equipe é admin-only');
      expect(find.text('Configurações'), findsNothing,
          reason: 'Settings é admin-only');
      expect(find.text('Código de equipe'), findsNothing,
          reason: 'Código de equipe é admin-only');
    });
  });

  group('AdminSidebar gating — instructor + extras', () {
    testWidgets('instructor + extras[financial.write] sees Cobrança',
        (tester) async {
      await pumpSidebar(
        tester,
        _user(
          UserRole.instructor,
          extras: const [TatamiPermissions.financialWrite],
        ),
      );

      expect(find.text('Financeiro'), findsOneWidget);
      expect(find.text('Cobranca'), findsOneWidget,
          reason: 'extras["financial.write"] desbloqueia Cobrança');
      // Mas continua sem store.write nem isAdmin
      expect(find.text('Loja'), findsNothing);
      expect(find.text('Equipe'), findsNothing);
    });

    testWidgets('instructor + extras[store.write] sees Loja',
        (tester) async {
      await pumpSidebar(
        tester,
        _user(
          UserRole.instructor,
          extras: const [TatamiPermissions.storeWrite],
        ),
      );

      expect(find.text('Loja'), findsOneWidget,
          reason: 'extras["store.write"] desbloqueia Loja');
    });
  });

  group('AdminSidebar gating — student (low-privilege fallthrough)', () {
    testWidgets('student sees only Dashboard + Alunos + Chamada/Turmas',
        (tester) async {
      // student NÃO é um role admin esperado neste shell — mas se cair
      // aqui (deep-link errado), o gating tem que continuar funcionando.
      await pumpSidebar(tester, _user(UserRole.student));

      expect(find.text('Dashboard'), findsOneWidget);
      // students.read default → Alunos visível
      expect(find.text('Alunos'), findsOneWidget);
      // attendance.read default → Chamada/Turmas visíveis
      expect(find.text('Chamada'), findsOneWidget);
      expect(find.text('Turmas'), findsOneWidget);

      // Tudo o resto escondido
      expect(find.text('Financeiro'), findsNothing);
      expect(find.text('Cobranca'), findsNothing);
      expect(find.text('Relatorios'), findsNothing);
      expect(find.text('Loja'), findsNothing);
      expect(find.text('Campeonatos'), findsNothing,
          reason: 'student não é isInstructor');
      expect(find.text('Equipe'), findsNothing);
      expect(find.text('Configurações'), findsNothing);
    });
  });

  group('AdminSidebar gating — loja respeita storeEnabled', () {
    testWidgets('admin com storeEnabled=false NÃO vê Loja', (tester) async {
      await pumpSidebar(
        tester,
        _user(UserRole.admin),
        storeEnabled: false,
      );

      expect(find.text('Loja'), findsNothing,
          reason: 'Loja respeita o setting storeEnabled mesmo para admin');
      // Outros admin-only continuam visíveis:
      expect(find.text('Configurações'), findsOneWidget);
      expect(find.text('Equipe'), findsOneWidget);
    });
  });
}
