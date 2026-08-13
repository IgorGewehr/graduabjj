import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/core/navigation/nav_catalog.dart';
import 'package:graduabjj/core/navigation/nav_resolver.dart';
import 'package:graduabjj/models/user.dart';
import 'package:graduabjj/services/settings_service.dart';

// QA — CORE pilar: navegação (descoberta/bloqueio + gating).
// Ancorado em lib/core/navigation/nav_catalog.dart + nav_resolver.dart.

AcademySettings _settings({
  bool storeEnabled = false,
  bool rankingVisibleToStudents = true,
  bool journalVisibleToStudents = true,
  bool autoGraduationEnabled = false,
  bool mpConnected = false,
  bool abacatePayEnabled = false,
  bool asaasEnabled = false,
  bool workoutPlansEnabled = true,
  bool trainingVideosEnabled = true,
}) {
  return AcademySettings(
    name: 'Test',
    storeEnabled: storeEnabled,
    rankingVisibleToStudents: rankingVisibleToStudents,
    journalVisibleToStudents: journalVisibleToStudents,
    autoGraduationEnabled: autoGraduationEnabled,
    mpConnected: mpConnected,
    abacatePayEnabled: abacatePayEnabled,
    asaasEnabled: asaasEnabled,
    workoutPlansEnabled: workoutPlansEnabled,
    trainingVideosEnabled: trainingVideosEnabled,
  );
}
AppUser _user({
  required UserRole role,
  List<String> extraPermissions = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return AppUser(
    id: 'u1',
    email: 'u@test.com',
    displayName: 'U',
    role: role,
    academyId: 'a1',
    extraPermissions: extraPermissions,
    createdAt: now,
    updatedAt: now,
  );
}

ResolvedNavEntry _find(List<ResolvedNavEntry> list, String key) =>
    list.firstWhere((r) => r.entry.key == key);

void main() {
  group('FeatureId.fromId / id round-trip (deep-link contract)', () {
    test('every FeatureId.id is stable and round-trips', () {
      for (final f in FeatureId.values) {
        expect(FeatureIdX.fromId(f.id), f,
            reason: 'deep-link feature=${f.id} must resolve back to $f');
        // The id is the enum name (the deep-link query string contract).
        expect(f.id, f.name);
      }
    });

    test('fromId is null-tolerant and rejects unknown ids', () {
      expect(FeatureIdX.fromId(null), isNull);
      expect(FeatureIdX.fromId(''), isNull);
      expect(FeatureIdX.fromId('not_a_feature'), isNull);
      // Case sensitivity: must match exactly.
      expect(FeatureIdX.fromId('Store'), isNull);
    });

    test('settingsDeepLinkFor builds the canonical highlight URL', () {
      expect(settingsDeepLinkFor(FeatureId.store),
          '/admin/configuracoes?feature=store');
      expect(settingsDeepLinkFor(FeatureId.payments),
          '/admin/configuracoes?feature=payments');
    });
  });

  group('isFeatureEnabled defaults & flags', () {
    test('null settings → safe defaults', () {
      // OFF-by-default features (opt-in).
      expect(isFeatureEnabled(FeatureId.store, null), isFalse);
      expect(isFeatureEnabled(FeatureId.graduation, null), isFalse);
      expect(isFeatureEnabled(FeatureId.payments, null), isFalse);
      // workouts/videos/evolution are opt-in: OFF until the academy enables
      // them (a backfill turns workouts/videos on where data already exists).
      expect(isFeatureEnabled(FeatureId.workouts, null), isFalse);
      expect(isFeatureEnabled(FeatureId.videos, null), isFalse);
      expect(isFeatureEnabled(FeatureId.evolution, null), isFalse);
      // ON-by-default features.
      expect(isFeatureEnabled(FeatureId.ranking, null), isTrue);
      expect(isFeatureEnabled(FeatureId.journal, null), isTrue);
      // musculacao defaults on (master flag, default true).
      expect(isFeatureEnabled(FeatureId.musculacao, null), isTrue);
    });

    test('payments is enabled when ANY payment provider is connected', () {
      expect(isFeatureEnabled(FeatureId.payments, _settings(mpConnected: true)),
          isTrue);
      expect(
          isFeatureEnabled(
              FeatureId.payments, _settings(abacatePayEnabled: true)),
          isTrue);
      expect(
          isFeatureEnabled(FeatureId.payments, _settings(asaasEnabled: true)),
          isTrue);
      expect(isFeatureEnabled(FeatureId.payments, _settings()), isFalse);
    });

    test('every FeatureId is handled (exhaustive switch, no throw)', () {
      final s = _settings();
      for (final f in FeatureId.values) {
        expect(() => isFeatureEnabled(f, s), returnsNormally);
      }
    });
  });

  group('resolveAdminCatalog — precedence: permission > feature > lockable', () {
    test('admin: lockable feature OFF becomes locked, not hidden', () {
      final admin = _user(role: UserRole.admin);
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(storeEnabled: false),
        user: admin,
      );
      // admin_loja: feature store, lockable true, no permission.
      expect(_find(resolved, 'admin_loja').state, NavEntryState.locked);
    });

    test('admin: lockable feature ON becomes visible', () {
      final admin = _user(role: UserRole.admin);
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(storeEnabled: true),
        user: admin,
      );
      expect(_find(resolved, 'admin_loja').state, NavEntryState.visible);
    });

    test('non-lockable feature OFF is hidden (admin_musculacao is always on)',
        () {
      // musculacao has no flag and lockable:false → always visible.
      final admin = _user(role: UserRole.admin);
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(),
        user: admin,
      );
      expect(_find(resolved, 'admin_musculacao').state, NavEntryState.visible);
    });

    test('entry with no feature is always visible for permitted user', () {
      final admin = _user(role: UserRole.admin);
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(),
        user: admin,
      );
      expect(_find(resolved, 'admin_dashboard').state, NavEntryState.visible);
      expect(_find(resolved, 'admin_turmas').state, NavEntryState.visible);
    });

    test(
        'DOCUMENTS real behavior: admin.hasPermission()==true for all perms, '
        'so adminBypassesPermission=false does NOT hide graduacao from admin',
        () {
      // admin_graduacao has adminBypassesPermission=false, but AppUser.admin
      // returns true from hasPermission() for ANY permission string. Net effect:
      // admin still sees it. Pinned so a future change can't silently flip it.
      final admin = _user(role: UserRole.admin);
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(autoGraduationEnabled: true),
        user: admin,
      );
      expect(_find(resolved, 'admin_graduacao').state, NavEntryState.visible);
    });

    test(
        'SECURITY: instructor WITHOUT graduation:manage → graduacao hidden even when feature ON',
        () {
      final instr = _user(role: UserRole.instructor);
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(autoGraduationEnabled: true),
        user: instr,
      );
      // adminBypassesPermission=false and instructor lacks the perm → hidden.
      expect(_find(resolved, 'admin_graduacao').state, NavEntryState.hidden);
    });

    test(
        'instructor WITH graduation:manage extra perm → graduacao visible when ON',
        () {
      final instr = _user(
        role: UserRole.instructor,
        extraPermissions: ['graduation:manage'],
      );
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(autoGraduationEnabled: true),
        user: instr,
      );
      expect(_find(resolved, 'admin_graduacao').state, NavEntryState.visible);
    });

    test(
        'instructor WITH graduation:manage but feature OFF → locked (lockable discovery)',
        () {
      final instr = _user(
        role: UserRole.instructor,
        extraPermissions: ['graduation:manage'],
      );
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(autoGraduationEnabled: false),
        user: instr,
      );
      expect(_find(resolved, 'admin_graduacao').state, NavEntryState.locked);
    });

    test('SECURITY: financial:view gate — instructor without perm hidden', () {
      final instr = _user(role: UserRole.instructor);
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(),
        user: instr,
      );
      // admin_cobranca requires financial:view, adminBypasses=false.
      expect(_find(resolved, 'admin_cobranca').state, NavEntryState.hidden);
      // admin_relatorios requires reports:view.
      expect(_find(resolved, 'admin_relatorios').state, NavEntryState.hidden);
    });

    test('requiresAnyPermission: any of the set satisfies (admin_alunos)', () {
      final instrCreate = _user(
        role: UserRole.instructor,
        extraPermissions: ['students:create'],
      );
      final instrDelete = _user(
        role: UserRole.instructor,
        extraPermissions: ['students:delete'],
      );
      final instrNone = _user(role: UserRole.instructor);

      final rCreate = resolveAdminCatalog(
          catalog: kAdminNavCatalog, settings: _settings(), user: instrCreate);
      final rDelete = resolveAdminCatalog(
          catalog: kAdminNavCatalog, settings: _settings(), user: instrDelete);
      final rNone = resolveAdminCatalog(
          catalog: kAdminNavCatalog, settings: _settings(), user: instrNone);

      expect(_find(rCreate, 'admin_alunos').state, NavEntryState.visible);
      expect(_find(rDelete, 'admin_alunos').state, NavEntryState.visible);
      expect(_find(rNone, 'admin_alunos').state, NavEntryState.hidden);
    });

    test('adminOnly entry hidden for instructor, visible for admin', () {
      final admin = _user(role: UserRole.admin);
      final instr = _user(role: UserRole.instructor);
      final rAdmin = resolveAdminCatalog(
          catalog: kAdminNavCatalog, settings: _settings(), user: admin);
      final rInstr = resolveAdminCatalog(
          catalog: kAdminNavCatalog, settings: _settings(), user: instr);
      expect(_find(rAdmin, 'admin_config').state, NavEntryState.visible);
      expect(_find(rInstr, 'admin_config').state, NavEntryState.hidden);
      expect(_find(rInstr, 'admin_codigo_equipe').state, NavEntryState.hidden);
    });

    test('SECURITY: null user → everything permission-gated is hidden', () {
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(storeEnabled: true),
        user: null,
      );
      // Unconditional entries still visible (no permission needed).
      expect(_find(resolved, 'admin_dashboard').state, NavEntryState.visible);
      // Permission-gated entries hidden.
      expect(_find(resolved, 'admin_cobranca').state, NavEntryState.hidden);
      expect(_find(resolved, 'admin_config').state, NavEntryState.hidden);
    });

    test('result length equals catalog length and preserves order', () {
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: _settings(),
        user: _user(role: UserRole.admin),
      );
      expect(resolved.length, kAdminNavCatalog.length);
      for (var i = 0; i < resolved.length; i++) {
        expect(resolved[i].entry.key, kAdminNavCatalog[i].key);
      }
    });

    test('REGRESSION: no admin entry collapses to an unreachable state', () {
      // Admin with full perms + all features ON should see every gateable
      // entry as visible (never silently hidden → dead route).
      final admin = _user(role: UserRole.admin);
      final allOn = _settings(
        storeEnabled: true,
        autoGraduationEnabled: true,
        mpConnected: true,
        journalVisibleToStudents: true,
        workoutPlansEnabled: true,
        trainingVideosEnabled: true,
      );
      final resolved =
          resolveAdminCatalog(catalog: kAdminNavCatalog, settings: allOn, user: admin);
      // Admin bypasses permission everywhere admin.hasPermission()==true.
      for (final r in resolved) {
        expect(r.state, isNot(NavEntryState.locked),
            reason: '${r.entry.key} should not be locked with all features ON');
      }
    });
  });

  group('resolvePortalCatalog — simple gate (never locked)', () {
    PortalNavContext ctx({
      bool isKids = false,
      bool isMonitorOrAttendance = false,
      bool hasPlan = true,
      bool storePublished = true,
      bool graduationProgressVisible = true,
    }) =>
        PortalNavContext(
          isKids: isKids,
          isMonitorOrAttendance: isMonitorOrAttendance,
          hasPlan: hasPlan,
          storePublished: storePublished,
          graduationProgressVisible: graduationProgressVisible,
        );

    test('portal never returns locked — only visible/hidden', () {
      final resolved = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(storeEnabled: false),
        ctx: ctx(),
      );
      expect(resolved.any((r) => r.state == NavEntryState.locked), isFalse);
    });

    test('feature OFF → hidden (ranking when rankingVisibleToStudents=false)',
        () {
      final resolved = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(rankingVisibleToStudents: false),
        ctx: ctx(),
      );
      expect(_find(resolved, 'portal_ranking').state, NavEntryState.hidden);
    });

    test('feature ON → visible (ranking default)', () {
      final resolved = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(rankingVisibleToStudents: true),
        ctx: ctx(),
      );
      expect(_find(resolved, 'portal_ranking').state, NavEntryState.visible);
    });

    test('hideForMonitor: horarios hidden for monitor/attendance staff', () {
      final asMonitor = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(),
        ctx: ctx(isMonitorOrAttendance: true),
      );
      final asStudent = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(),
        ctx: ctx(isMonitorOrAttendance: false),
      );
      expect(_find(asMonitor, 'portal_horarios').state, NavEntryState.hidden);
      expect(_find(asStudent, 'portal_horarios').state, NavEntryState.visible);
    });

    test('kidsOnly: comportamento only for kids', () {
      final kid = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(),
        ctx: ctx(isKids: true),
      );
      final adult = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(),
        ctx: ctx(isKids: false),
      );
      expect(_find(kid, 'portal_comportamento').state, NavEntryState.visible);
      expect(_find(adult, 'portal_comportamento').state, NavEntryState.hidden);
    });

    test('hasPlan: financeiro hidden without a plan', () {
      final withPlan = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(),
        ctx: ctx(hasPlan: true),
      );
      final noPlan = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(),
        ctx: ctx(hasPlan: false),
      );
      expect(_find(withPlan, 'portal_financeiro').state, NavEntryState.visible);
      expect(_find(noPlan, 'portal_financeiro').state, NavEntryState.hidden);
    });

    test('storePublished: loja hidden until store published', () {
      final pub = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(storeEnabled: true),
        ctx: ctx(storePublished: true),
      );
      final unpub = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(storeEnabled: true),
        ctx: ctx(storePublished: false),
      );
      expect(_find(pub, 'portal_loja').state, NavEntryState.visible);
      expect(_find(unpub, 'portal_loja').state, NavEntryState.hidden);
    });

    test('special-case portal_graduacao gates on graduationProgressVisible', () {
      final vis = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(),
        ctx: ctx(graduationProgressVisible: true),
      );
      final hid = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(),
        ctx: ctx(graduationProgressVisible: false),
      );
      expect(_find(vis, 'portal_graduacao').state, NavEntryState.visible);
      expect(_find(hid, 'portal_graduacao').state, NavEntryState.hidden);
    });

    test('portal_treinos / portal_videos gate on their features', () {
      final off = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(workoutPlansEnabled: false, trainingVideosEnabled: false),
        ctx: ctx(),
      );
      expect(_find(off, 'portal_treinos').state, NavEntryState.hidden);
      expect(_find(off, 'portal_videos').state, NavEntryState.hidden);
    });

    test('catalog order/length preserved', () {
      final resolved = resolvePortalCatalog(
        catalog: kPortalNavCatalog,
        settings: _settings(),
        ctx: ctx(),
      );
      expect(resolved.length, kPortalNavCatalog.length);
      for (var i = 0; i < resolved.length; i++) {
        expect(resolved[i].entry.key, kPortalNavCatalog[i].key);
      }
    });
  });

  group('catalog integrity (deep-link / routing contract)', () {
    test('every admin entry has a unique key and a non-empty route', () {
      final keys = kAdminNavCatalog.map((e) => e.key).toList();
      expect(keys.toSet().length, keys.length, reason: 'duplicate admin keys');
      for (final e in kAdminNavCatalog) {
        expect(e.route, startsWith('/'));
        expect(e.route, isNotEmpty);
      }
    });

    test('every portal entry has a unique key and a non-empty route', () {
      final keys = kPortalNavCatalog.map((e) => e.key).toList();
      expect(keys.toSet().length, keys.length, reason: 'duplicate portal keys');
      for (final e in kPortalNavCatalog) {
        expect(e.route, startsWith('/'));
      }
    });

    test('admin routes are unique (no two entries fight over a route)', () {
      final routes = kAdminNavCatalog.map((e) => e.route).toList();
      expect(routes.toSet().length, routes.length,
          reason: 'duplicate admin routes');
    });

    test(
        'REGRESSION fence: the journey/timeline route in the catalog is the '
        'canonical /portal/linha-do-tempo (NOT the broken /portal/timeline used '
        'by RecentMilestonesStrip)', () {
      final jornada =
          kPortalNavCatalog.firstWhere((e) => e.key == 'portal_jornada');
      // app.dart registers ONLY /portal/linha-do-tempo for the TimelineScreen.
      // recent_milestones_strip.dart navigates to /portal/timeline, which is
      // unregistered → lands on the "Pagina nao encontrada" error scaffold.
      expect(jornada.route, '/portal/linha-do-tempo');
      expect(jornada.route, isNot('/portal/timeline'));
    });
  });
}
