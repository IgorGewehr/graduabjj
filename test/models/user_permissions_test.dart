import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/user.dart';

/// Tests for [AppUser.hasPermission] + [TatamiPermissions] catalog.
///
/// O contrato espelhado pelo BE em `internal/identity/domain/permission.go`.
/// Cada role tem um conjunto fixo de defaults; `extraPermissions` na
/// membership somam em cima do default (NUNCA subtrai).
AppUser _user(
  UserRole role, {
  List<String> extras = const [],
}) =>
    AppUser(
      id: 'u1',
      email: 'x@y.com',
      displayName: 'X',
      role: role,
      extraPermissions: extras,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

void main() {
  group('TatamiPermissions catalog', () {
    test('exposes all expected permission strings', () {
      expect(TatamiPermissions.attendanceRead, 'attendance.read');
      expect(TatamiPermissions.attendanceWrite, 'attendance.write');
      expect(TatamiPermissions.financialRead, 'financial.read');
      expect(TatamiPermissions.financialWrite, 'financial.write');
      expect(TatamiPermissions.studentsRead, 'students.read');
      expect(TatamiPermissions.studentsWrite, 'students.write');
      expect(TatamiPermissions.storeRead, 'store.read');
      expect(TatamiPermissions.storeWrite, 'store.write');
      expect(TatamiPermissions.notificationsSend, 'notifications.send');
    });

    test('all permissions appear in `all`', () {
      expect(TatamiPermissions.all, hasLength(9));
      expect(TatamiPermissions.all, contains(TatamiPermissions.financialWrite));
      expect(TatamiPermissions.all, contains(TatamiPermissions.storeRead));
      expect(
        TatamiPermissions.all,
        contains(TatamiPermissions.notificationsSend),
      );
    });
  });

  group('AppUser.hasPermission — admin role', () {
    final admin = _user(UserRole.admin);

    test('admin has every permission in the catalog', () {
      for (final p in TatamiPermissions.all) {
        expect(
          admin.hasPermission(p),
          isTrue,
          reason: 'admin should have $p by default',
        );
      }
    });

    test('admin still false for unknown permission strings', () {
      expect(admin.hasPermission('billing.refund'), isFalse);
      expect(admin.hasPermission(''), isFalse);
    });
  });

  group('AppUser.hasPermission — instructor role', () {
    final instructor = _user(UserRole.instructor);

    test('instructor has attendance.read/write by default', () {
      expect(
        instructor.hasPermission(TatamiPermissions.attendanceRead),
        isTrue,
      );
      expect(
        instructor.hasPermission(TatamiPermissions.attendanceWrite),
        isTrue,
      );
    });

    test('instructor has students.read/write + financial.read + store.read', () {
      expect(instructor.hasPermission(TatamiPermissions.studentsRead), isTrue);
      expect(instructor.hasPermission(TatamiPermissions.studentsWrite), isTrue);
      expect(instructor.hasPermission(TatamiPermissions.financialRead), isTrue);
      expect(instructor.hasPermission(TatamiPermissions.storeRead), isTrue);
    });

    test('instructor has notifications.send by default', () {
      expect(
        instructor.hasPermission(TatamiPermissions.notificationsSend),
        isTrue,
      );
    });

    test('instructor does NOT have financial.write / store.write by default',
        () {
      expect(
        instructor.hasPermission(TatamiPermissions.financialWrite),
        isFalse,
      );
      expect(instructor.hasPermission(TatamiPermissions.storeWrite), isFalse);
    });

    test(
        'instructor with extraPermissions["financial.write"] gains financial.write',
        () {
      final withExtra = _user(
        UserRole.instructor,
        extras: const [TatamiPermissions.financialWrite],
      );
      expect(
        withExtra.hasPermission(TatamiPermissions.financialWrite),
        isTrue,
      );
      // defaults preservados:
      expect(withExtra.hasPermission(TatamiPermissions.financialRead), isTrue);
    });

    test('extraPermissions can ADD store.write to an instructor', () {
      final withExtra = _user(
        UserRole.instructor,
        extras: const [TatamiPermissions.storeWrite],
      );
      expect(withExtra.hasPermission(TatamiPermissions.storeWrite), isTrue);
    });
  });

  group('AppUser.hasPermission — student/guardian roles', () {
    final student = _user(UserRole.student);
    final guardian = _user(UserRole.guardian);

    test('student has only attendance.read + students.read by default', () {
      expect(student.hasPermission(TatamiPermissions.attendanceRead), isTrue);
      expect(student.hasPermission(TatamiPermissions.studentsRead), isTrue);
      // tudo o resto = false
      expect(
        student.hasPermission(TatamiPermissions.attendanceWrite),
        isFalse,
      );
      expect(student.hasPermission(TatamiPermissions.financialRead), isFalse);
      expect(student.hasPermission(TatamiPermissions.financialWrite), isFalse);
      expect(student.hasPermission(TatamiPermissions.studentsWrite), isFalse);
      expect(student.hasPermission(TatamiPermissions.storeRead), isFalse);
      expect(student.hasPermission(TatamiPermissions.storeWrite), isFalse);
      expect(
        student.hasPermission(TatamiPermissions.notificationsSend),
        isFalse,
      );
    });

    test('guardian has only attendance.read + students.read by default', () {
      expect(guardian.hasPermission(TatamiPermissions.attendanceRead), isTrue);
      expect(guardian.hasPermission(TatamiPermissions.studentsRead), isTrue);
      expect(guardian.hasPermission(TatamiPermissions.financialRead), isFalse);
      expect(guardian.hasPermission(TatamiPermissions.studentsWrite), isFalse);
    });

    test('a student with extras["notifications.send"] can send notifications',
        () {
      final paidStudent = _user(
        UserRole.student,
        extras: const [TatamiPermissions.notificationsSend],
      );
      expect(
        paidStudent.hasPermission(TatamiPermissions.notificationsSend),
        isTrue,
      );
    });
  });

  group('AppUser.hasPermission — edge cases', () {
    test('empty role + empty extras → everything false', () {
      // simula um corner-case onde defaultPermissionsByRole não cobre o role
      // (não acontece hoje, mas o método deve devolver false defensivamente)
      final u = _user(UserRole.student);
      expect(u.hasPermission('arbitrary.permission'), isFalse);
    });

    test('extras add to defaults — both pass', () {
      final u = _user(
        UserRole.instructor,
        extras: const [
          TatamiPermissions.financialWrite,
          TatamiPermissions.storeWrite,
        ],
      );
      // defaults
      expect(u.hasPermission(TatamiPermissions.attendanceWrite), isTrue);
      // extras
      expect(u.hasPermission(TatamiPermissions.financialWrite), isTrue);
      expect(u.hasPermission(TatamiPermissions.storeWrite), isTrue);
    });

    test('hasPermission is null-safe for unknown perms even with extras', () {
      final u = _user(UserRole.admin, extras: const ['custom.flag']);
      expect(u.hasPermission('custom.flag'), isTrue);
      expect(u.hasPermission('billing.refund'), isFalse);
    });
  });
}
