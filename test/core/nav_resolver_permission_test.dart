import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/navigation/nav_catalog.dart';
import 'package:graduabjj/core/navigation/nav_resolver.dart';
import 'package:graduabjj/models/user.dart';
import 'package:graduabjj/services/settings_service.dart';

/// PILLAR: Team configuration — permission/role gating of the admin nav.
///
/// These tests pin the exact privilege boundaries enforced by
/// [resolveAdminCatalog] / `_permissionSatisfied`. They are the regression
/// fence for the "single source of navigation" refactor: an item that should
/// be hidden from an instructor must NOT leak, and an item that an instructor
/// is entitled to must NOT disappear.

AppUser _user({
  required UserRole role,
  List<String> extra = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return AppUser(
    id: 'u1',
    email: 'u@e.com',
    displayName: 'U',
    role: role,
    academyId: 'acad1',
    extraPermissions: extra,
    createdAt: now,
    updatedAt: now,
  );
}

NavEntry _entry(String key) =>
    kAdminNavCatalog.firstWhere((e) => e.key == key);

NavEntryState _stateFor(
  String key, {
  required AppUser? user,
  AcademySettings? settings,
}) {
  final resolved = resolveAdminCatalog(
    catalog: [_entry(key)],
    settings: settings ?? AcademySettings(name: 'A'),
    user: user,
  );
  return resolved.single.state;
}

void main() {
  final admin = _user(role: UserRole.admin);
  final plainInstructor = _user(role: UserRole.instructor);
  final student = _user(role: UserRole.student);

  group('adminOnly entries — only admin sees them', () {
    for (final key in ['admin_config', 'admin_codigo_equipe']) {
      test('$key hidden from plain instructor', () {
        expect(_stateFor(key, user: plainInstructor), NavEntryState.hidden);
      });
      test('$key hidden from student', () {
        expect(_stateFor(key, user: student), NavEntryState.hidden);
      });
      test('$key visible to admin', () {
        expect(_stateFor(key, user: admin), NavEntryState.visible);
      });
      test('$key hidden when no user (logged out / null)', () {
        expect(_stateFor(key, user: null), NavEntryState.hidden);
      });
      test('$key NOT bypassable by granting the route string as a permission',
          () {
        // adminOnly is absolute; an instructor with a wildcard extra perm must
        // still be locked out of Configurações / Código de equipe.
        final sneaky = _user(
          role: UserRole.instructor,
          extra: ['admin', '*', 'admin_config', 'config:manage'],
        );
        expect(_stateFor(key, user: sneaky), NavEntryState.hidden);
      });
    }
  });

  group('entries with adminBypassesPermission=false — admin still gated', () {
    // Cobrança/Carteira/Relatórios/Graduação/Jornal require the explicit
    // permission EVEN for admins per the refactor contract.
    test('admin_cobranca: admin WITHOUT financial:view ... admin bypasses? '
        'No — bypass disabled, but admin.hasPermission is always true', () {
      // CRITICAL nuance: adminBypassesPermission=false disables the *resolver*
      // shortcut, but AppUser.hasPermission('financial:view') returns true for
      // any admin (role==admin => true). So admin is still visible. This test
      // documents the real behavior so a future change can't silently flip it.
      expect(_stateFor('admin_cobranca', user: admin), NavEntryState.visible);
    });

    test('admin_cobranca hidden from instructor without financial:view', () {
      expect(
        _stateFor('admin_cobranca', user: plainInstructor),
        NavEntryState.hidden,
      );
    });

    test('admin_cobranca visible to instructor WITH financial:view', () {
      final fin = _user(role: UserRole.instructor, extra: ['financial:view']);
      expect(_stateFor('admin_cobranca', user: fin), NavEntryState.visible);
    });

    test('admin_relatorios hidden from instructor without reports:view', () {
      expect(
        _stateFor('admin_relatorios', user: plainInstructor),
        NavEntryState.hidden,
      );
    });

    test('admin_relatorios visible to instructor WITH reports:view', () {
      final rep = _user(role: UserRole.instructor, extra: ['reports:view']);
      expect(_stateFor('admin_relatorios', user: rep), NavEntryState.visible);
    });
  });

  group('Graduação (permission + feature gate interplay)', () {
    final on = AcademySettings(name: 'A', autoGraduationEnabled: true);
    final off = AcademySettings(name: 'A', autoGraduationEnabled: false);

    test('instructor WITHOUT graduation:manage -> hidden even if feature ON',
        () {
      expect(
        _stateFor('admin_graduacao', user: plainInstructor, settings: on),
        NavEntryState.hidden,
      );
    });

    test('instructor WITH graduation:manage + feature ON -> visible', () {
      final g = _user(role: UserRole.instructor, extra: ['graduation:manage']);
      expect(
        _stateFor('admin_graduacao', user: g, settings: on),
        NavEntryState.visible,
      );
    });

    test('instructor WITH graduation:manage + feature OFF -> locked (lockable)',
        () {
      final g = _user(role: UserRole.instructor, extra: ['graduation:manage']);
      expect(
        _stateFor('admin_graduacao', user: g, settings: off),
        NavEntryState.locked,
      );
    });

    test(
        'instructor WITHOUT graduation:manage + feature OFF -> hidden '
        '(permission loses before lockable matters)', () {
      // SECURITY: permission must be evaluated BEFORE the feature/lockable
      // branch, otherwise an unentitled instructor would see a "locked"
      // discovery teaser for a screen they can never open.
      expect(
        _stateFor('admin_graduacao', user: plainInstructor, settings: off),
        NavEntryState.hidden,
      );
    });
  });

  group('admin_jornal — events:manage is an instructor DEFAULT permission', () {
    final on = AcademySettings(name: 'A', journalVisibleToStudents: true);

    test('plain instructor gets Jornal (events:manage default) when feature ON',
        () {
      expect(
        _stateFor('admin_jornal', user: plainInstructor, settings: on),
        NavEntryState.visible,
      );
    });

    test('student never gets Jornal even with feature ON', () {
      expect(
        _stateFor('admin_jornal', user: student, settings: on),
        NavEntryState.hidden,
      );
    });
  });

  group('requiresAnyPermission (Alunos: create OR delete)', () {
    test('instructor with neither -> hidden', () {
      expect(
        _stateFor('admin_alunos', user: plainInstructor),
        NavEntryState.hidden,
      );
    });
    test('instructor with students:create -> visible', () {
      final c = _user(role: UserRole.instructor, extra: ['students:create']);
      expect(_stateFor('admin_alunos', user: c), NavEntryState.visible);
    });
    test('instructor with students:delete -> visible', () {
      final d = _user(role: UserRole.instructor, extra: ['students:delete']);
      expect(_stateFor('admin_alunos', user: d), NavEntryState.visible);
    });
    test('admin always visible (adminBypassesPermission default true)', () {
      expect(_stateFor('admin_alunos', user: admin), NavEntryState.visible);
    });
  });

  group('admin_chamada (attendance:take)', () {
    test('plain instructor hidden (NOT a default permission)', () {
      expect(
        _stateFor('admin_chamada', user: plainInstructor),
        NavEntryState.hidden,
      );
    });
    test('instructor WITH attendance:take visible', () {
      final a = _user(role: UserRole.instructor, extra: ['attendance:take']);
      expect(_stateFor('admin_chamada', user: a), NavEntryState.visible);
    });
  });

  group('unconditional entries (no permission, no feature)', () {
    for (final key in ['admin_dashboard', 'admin_turmas']) {
      test('$key visible to plain instructor', () {
        expect(_stateFor(key, user: plainInstructor), NavEntryState.visible);
      });
    }
  });

  group('full-catalog resolution: instructor sees exactly the right items', () {
    test('plain instructor admin menu has no admin-only / no unentitled items',
        () {
      final resolved = resolveAdminCatalog(
        catalog: kAdminNavCatalog,
        settings: AcademySettings(
          name: 'A',
          autoGraduationEnabled: true,
          journalVisibleToStudents: true,
        ),
        user: plainInstructor,
      );
      final visibleKeys = resolved
          .where((r) => r.isVisible)
          .map((r) => r.entry.key)
          .toSet();

      // Must NOT be visible to a plain instructor:
      expect(visibleKeys.contains('admin_config'), isFalse);
      expect(visibleKeys.contains('admin_codigo_equipe'), isFalse);
      expect(visibleKeys.contains('admin_cobranca'), isFalse);
      expect(visibleKeys.contains('admin_carteira'), isFalse);
      expect(visibleKeys.contains('admin_relatorios'), isFalse);
      expect(visibleKeys.contains('admin_graduacao'), isFalse);
      expect(visibleKeys.contains('admin_alunos'), isFalse);
      expect(visibleKeys.contains('admin_chamada'), isFalse);
      expect(visibleKeys.contains('admin_campeonatos'), isFalse);

      // Should be visible (defaults / unconditional / events default):
      expect(visibleKeys.contains('admin_dashboard'), isTrue);
      expect(visibleKeys.contains('admin_turmas'), isTrue);
      expect(visibleKeys.contains('admin_jornal'), isTrue);
    });
  });
}
