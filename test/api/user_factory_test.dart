import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/api/dto/identity_dto.dart';
import 'package:graduabjj/models/user.dart';

void main() {
  CurrentUserResponse mkResponse({
    String? primary,
    List<Map<String, dynamic>> memberships = const [],
    String accountType = 'linked',
    String? displayName = 'Igor',
  }) =>
      CurrentUserResponse.fromJson({
        'user': {
          'uid': 'u-1',
          'email': 'i@x.com',
          'account_type': accountType,
          if (displayName != null) 'display_name': displayName,
        },
        'memberships': memberships,
        if (primary != null) 'primary_academy_id': primary,
      });

  group('AppUser.fromCurrentUserResponse', () {
    test('null quando não há membership ativa', () {
      final cu = mkResponse(memberships: const []);
      expect(AppUser.fromCurrentUserResponse(cu), isNull);
    });

    test('null quando todas memberships são removed', () {
      final cu = mkResponse(memberships: [
        {
          'uid': 'u-1',
          'academy_id': 'a-1',
          'role': 'student',
          'status': 'removed',
        },
      ]);
      expect(AppUser.fromCurrentUserResponse(cu), isNull);
    });

    test('seleciona primary_academy_id quando disponível', () {
      final cu = mkResponse(
        primary: 'a-2',
        memberships: [
          {
            'uid': 'u-1',
            'academy_id': 'a-1',
            'role': 'student',
            'status': 'active',
          },
          {
            'uid': 'u-1',
            'academy_id': 'a-2',
            'role': 'admin',
            'status': 'active',
          },
        ],
      );
      final app = AppUser.fromCurrentUserResponse(cu);
      expect(app, isNotNull);
      expect(app!.academyId, 'a-2');
      expect(app.role, UserRole.admin);
    });

    test('cai na primeira active quando não há primary', () {
      final cu = mkResponse(memberships: [
        {
          'uid': 'u-1',
          'academy_id': 'a-1',
          'role': 'student',
          'status': 'active',
          'student_id': 's-1',
        },
        {
          'uid': 'u-1',
          'academy_id': 'a-2',
          'role': 'admin',
          'status': 'active',
        },
      ]);
      final app = AppUser.fromCurrentUserResponse(cu);
      expect(app!.academyId, 'a-1');
      expect(app.studentId, 's-1');
    });

    test('activeAcademyId override sobrescreve primary', () {
      final cu = mkResponse(
        primary: 'a-2',
        memberships: [
          {
            'uid': 'u-1',
            'academy_id': 'a-1',
            'role': 'instructor',
            'status': 'active',
          },
          {
            'uid': 'u-1',
            'academy_id': 'a-2',
            'role': 'admin',
            'status': 'active',
          },
        ],
      );
      final app = AppUser.fromCurrentUserResponse(cu, activeAcademyId: 'a-1');
      expect(app!.academyId, 'a-1');
      expect(app.role, UserRole.instructor);
    });

    test('monitor role mapeia para instructor (compat legacy)', () {
      final cu = mkResponse(memberships: [
        {
          'uid': 'u-1',
          'academy_id': 'a-1',
          'role': 'monitor',
          'status': 'active',
        },
      ]);
      final app = AppUser.fromCurrentUserResponse(cu);
      expect(app!.role, UserRole.instructor);
    });

    test('account_type=free propaga', () {
      final cu = mkResponse(accountType: 'free', memberships: [
        {
          'uid': 'u-1',
          'academy_id': 'a-1',
          'role': 'student',
          'status': 'active',
        },
      ]);
      final app = AppUser.fromCurrentUserResponse(cu);
      expect(app!.accountType, AccountType.free);
    });

    test('displayName ausente vira string vazia (não null)', () {
      final cu = mkResponse(displayName: null, memberships: [
        {
          'uid': 'u-1',
          'academy_id': 'a-1',
          'role': 'student',
          'status': 'active',
        },
      ]);
      final app = AppUser.fromCurrentUserResponse(cu);
      expect(app!.displayName, '');
    });
  });
}
