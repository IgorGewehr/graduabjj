import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/instructor_link_code_service.dart';
import 'package:graduabjj/services/team_service.dart';

/// PILLAR: Team configuration — parsing/shaping seams of the membership layer
/// (AcademyMembers grouping, InstructorLinkCode expiry/used flags, grantable
/// permission allowlist). Pure logic only; the CF round-trip is exercised
/// server-side.

void main() {
  group('AcademyMembers.fromMap grouping', () {
    test('groups by role and parses extraPermissions', () {
      final m = AcademyMembers.fromMap({
        'admins': [
          {'userId': 'a1', 'displayName': 'Adm', 'role': 'admin'},
        ],
        'instructors': [
          {
            'userId': 'i1',
            'displayName': 'Ins',
            'role': 'instructor',
            'extraPermissions': ['financial:view'],
          },
        ],
        'students': [
          {'userId': 's1', 'displayName': 'Stu', 'role': 'student'},
        ],
      });
      expect(m.admins.single.userId, 'a1');
      expect(m.instructors.single.extraPermissions, ['financial:view']);
      expect(m.students.single.role, 'student');
    });

    test('missing groups => empty lists (no crash)', () {
      final m = AcademyMembers.fromMap({});
      expect(m.admins, isEmpty);
      expect(m.instructors, isEmpty);
      expect(m.students, isEmpty);
    });

    test('non-list / malformed entries are skipped, not fatal', () {
      final m = AcademyMembers.fromMap({
        'admins': 'oops',
        'instructors': [42, 'bad', {'userId': 'i1', 'role': 'instructor'}],
      });
      expect(m.admins, isEmpty);
      expect(m.instructors.single.userId, 'i1');
    });

    test('AcademyMember.fromMap defaults role to student when absent', () {
      // SECURITY-adjacent: a member entry missing its role must NOT default to
      // a privileged role.
      final mem = AcademyMember.fromMap({'userId': 'x'});
      expect(mem.role, 'student');
      expect(mem.extraPermissions, isEmpty);
    });
  });

  group('InstructorLinkCode expiry/used invariants', () {
    InstructorLinkCode code({
      DateTime? expiresAt,
      DateTime? usedAt,
      List<String> extra = const [],
    }) =>
        InstructorLinkCode(
          id: 'ABCD1234',
          code: 'ABCD1234',
          createdBy: 'admin',
          createdByName: 'Admin',
          createdAt: DateTime(2026, 1, 1),
          expiresAt: expiresAt ?? DateTime(2999),
          extraPermissions: extra,
          usedAt: usedAt,
        );

    test('fresh code is neither used nor expired', () {
      final c = code();
      expect(c.isUsed, isFalse);
      expect(c.isExpired, isFalse);
    });

    test('past expiry => isExpired true', () {
      final c = code(expiresAt: DateTime(2000));
      expect(c.isExpired, isTrue);
    });

    test('usedAt set => isUsed true (single-use enforcement client side)', () {
      final c = code(usedAt: DateTime(2026, 1, 2));
      expect(c.isUsed, isTrue);
    });

    test('carries its permission snapshot', () {
      final c = code(extra: ['financial:view', 'reports:view']);
      expect(c.extraPermissions, ['financial:view', 'reports:view']);
    });
  });

  group('Grantable permission allowlist (kGrantableExtraPermissions)', () {
    final grantable =
        kGrantableExtraPermissions.map((g) => g.permission).toSet();

    test('does NOT expose an "admin" or wildcard grant', () {
      // The UI must never offer an owner a way to mint a second admin or a
      // wildcard via the extra-permissions picker.
      expect(grantable.contains('admin'), isFalse);
      expect(grantable.contains('*'), isFalse);
      expect(grantable.any((p) => p.contains('admin')), isFalse);
    });

    test('all grantable entries are namespaced "domain:action" strings', () {
      for (final p in grantable) {
        expect(p.contains(':'), isTrue, reason: '$p not namespaced');
      }
    });

    test('includes the permissions the nav catalog actually gates on', () {
      // Drift guard: every permission the admin nav requires (and that an
      // instructor could plausibly need) should be grantable, otherwise an
      // owner can never unlock that screen for a professor.
      for (final p in [
        'attendance:take',
        'financial:view',
        'students:create',
        'students:delete',
        'reports:view',
        'competitions:create',
        'graduation:manage',
      ]) {
        expect(grantable.contains(p), isTrue, reason: '$p missing from picker');
      }
    });
  });
}
