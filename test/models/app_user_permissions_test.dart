import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/user.dart';

/// PILLAR: Team configuration — role/permission model (AppUser.hasPermission,
/// AcademyDetail parsing, role round-trips). These pin who can do what.

AppUser _u(UserRole role, {List<String> extra = const []}) => AppUser(
      id: 'u',
      email: 'e',
      displayName: 'd',
      role: role,
      extraPermissions: extra,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('hasPermission — privilege boundary', () {
    test('admin can do everything (arbitrary permission string)', () {
      final a = _u(UserRole.admin);
      expect(a.hasPermission('financial:view'), isTrue);
      expect(a.hasPermission('students:delete'), isTrue);
      expect(a.hasPermission('literally:anything'), isTrue);
      expect(a.hasPermission(''), isTrue);
    });

    test('student can never do anything, even if extraPermissions are set', () {
      // SECURITY: extraPermissions must be inert for non-instructors. A demoted
      // user whose mapping still carries stale extraPermissions must not retain
      // capabilities through the student role.
      final s = _u(UserRole.student, extra: ['financial:view', 'admin']);
      expect(s.hasPermission('financial:view'), isFalse);
      expect(s.hasPermission('admin'), isFalse);
    });

    test('guardian can never do anything', () {
      final g = _u(UserRole.guardian, extra: ['financial:view']);
      expect(g.hasPermission('financial:view'), isFalse);
    });

    test('instructor gets ONLY default perms + explicit extras', () {
      final i = _u(UserRole.instructor, extra: ['financial:view']);
      // default permission
      expect(i.hasPermission('events:manage'), isTrue);
      // granted extra
      expect(i.hasPermission('financial:view'), isTrue);
      // NOT granted
      expect(i.hasPermission('students:delete'), isFalse);
      expect(i.hasPermission('reports:view'), isFalse);
      expect(i.hasPermission('graduation:manage'), isFalse);
    });

    test('plain instructor (no extras) has exactly the default set', () {
      final i = _u(UserRole.instructor);
      expect(i.hasPermission('events:manage'), isTrue);
      // Everything else is denied for a plain instructor.
      for (final p in [
        'financial:view',
        'financial:create',
        'students:create',
        'students:delete',
        'reports:view',
        'competitions:create',
        'graduation:manage',
        'attendance:take',
        'students:manage',
      ]) {
        expect(i.hasPermission(p), isFalse, reason: '$p should be denied');
      }
    });

    test('instructor cannot self-grant the admin sentinel via extras', () {
      // hasPermission has no wildcard — granting "admin"/"*" as an extra perm
      // only matches a literal permission of that exact string, never elevates
      // to the admin role branch.
      final i = _u(UserRole.instructor, extra: ['admin', '*']);
      expect(i.isAdmin, isFalse);
      // hasPermission('admin') matches literally because it's in extras, but
      // that's a meaningless string permission — no nav entry keys off it.
      expect(i.hasPermission('financial:view'), isFalse);
      expect(i.hasPermission('reports:view'), isFalse);
    });
  });

  group('role helpers', () {
    test('isInstructor is true for admin AND instructor, false otherwise', () {
      expect(_u(UserRole.admin).isInstructor, isTrue);
      expect(_u(UserRole.instructor).isInstructor, isTrue);
      expect(_u(UserRole.student).isInstructor, isFalse);
      expect(_u(UserRole.guardian).isInstructor, isFalse);
    });
    test('isAdmin only for admin', () {
      expect(_u(UserRole.admin).isAdmin, isTrue);
      expect(_u(UserRole.instructor).isAdmin, isFalse);
    });
  });

  group('UserRole.fromString — unknown/garbage falls back to student', () {
    test('valid values round-trip', () {
      for (final r in UserRole.values) {
        expect(UserRoleExtension.fromString(r.value), r);
      }
    });
    test('unknown role string => student (fail closed)', () {
      // SECURITY: an unrecognised/tampered role must default to the LEAST
      // privileged role, never to admin/instructor.
      expect(UserRoleExtension.fromString('superadmin'), UserRole.student);
      expect(UserRoleExtension.fromString(''), UserRole.student);
      expect(UserRoleExtension.fromString('owner'), UserRole.student);
    });
  });

  group('AcademyDetail.fromMap — extraPermissions parsing', () {
    test('reads extraPermissions list', () {
      final d = AcademyDetail.fromMap({
        'role': 'instructor',
        'extraPermissions': ['financial:view', 'reports:view'],
      });
      expect(d.role, UserRole.instructor);
      expect(d.extraPermissions, ['financial:view', 'reports:view']);
    });

    test('missing extraPermissions => empty list (not null)', () {
      final d = AcademyDetail.fromMap({'role': 'instructor'});
      expect(d.extraPermissions, isEmpty);
    });

    test('non-list extraPermissions ignored (defensive)', () {
      final d = AcademyDetail.fromMap({
        'role': 'instructor',
        'extraPermissions': 'financial:view', // wrong type
      });
      expect(d.extraPermissions, isEmpty);
    });

    test('toMap omits extraPermissions when empty', () {
      final d = AcademyDetail(role: UserRole.student, joinedAt: DateTime(2026));
      expect(d.toMap().containsKey('extraPermissions'), isFalse);
    });
  });

  group('AppUser.fromMap — extraPermissions are preserved (bug 7 fixed)', () {
    // AppUser.fromMap (used by AppUser.fromFirestore) now reads the
    // 'extraPermissions' field, so any code path that builds the user via
    // fromMap/fromFirestore keeps an instructor's granted permissions instead
    // of silently dropping them.
    test('fromMap reads the extraPermissions field', () {
      final u = AppUser.fromMap('id', {
        'role': 'instructor',
        'extraPermissions': ['financial:view', 'reports:view'],
      });
      expect(u.role, UserRole.instructor);
      expect(u.extraPermissions, ['financial:view', 'reports:view']);
      expect(u.hasPermission('financial:view'), isTrue);
      expect(u.hasPermission('reports:view'), isTrue);
    });

    test('fromMap defaults extraPermissions to empty when absent', () {
      final u = AppUser.fromMap('id', {'role': 'instructor'});
      expect(u.extraPermissions, isEmpty);
    });

    test(
        'parity: fromGlobalAndAcademy and fromMap both preserve extras',
        () {
      // Same logical instructor + same extraPermissions, two deserializers.
      // Both now keep the granted permissions — the prior source-of-truth gap
      // (fromMap silently dropping them) is closed.
      final global = GlobalUser(
        id: 'u',
        email: 'e',
        displayName: 'd',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final viaMapping = AppUser.fromGlobalAndAcademy(
        globalUser: global,
        academyId: 'a',
        role: UserRole.instructor,
        extraPermissions: const ['financial:view'],
      );
      final viaFirestore = AppUser.fromMap('u', {
        'role': 'instructor',
        'extraPermissions': const ['financial:view'],
      });

      expect(viaMapping.hasPermission('financial:view'), isTrue);
      expect(viaFirestore.hasPermission('financial:view'), isTrue);
    });
  });
}
