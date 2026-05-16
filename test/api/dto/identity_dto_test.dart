import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/api/dto/identity_dto.dart';

void main() {
  group('ApiGlobalUser.fromJson', () {
    test('parses full payload', () {
      final j = <String, dynamic>{
        'uid': 'firebase-uid-1',
        'email': 'igor@example.com',
        'display_name': 'Igor Gewehr',
        'photo_url': 'https://cdn.example/avatar.jpg',
        'phone': '+5511999999999',
        'birth_date': '1990-04-23',
        'cpf': '000.000.000-00',
        'weight_kg': 78.5,
        'account_type': 'linked',
        'jiujitsu_start_date': '2010-01-01',
        'highest_belt': 'black',
        'highest_stripes': 1,
        'is_profile_public': true,
        'created_at': '2025-01-01T10:00:00Z',
        'updated_at': '2026-05-16T08:00:00Z',
      };
      final u = ApiGlobalUser.fromJson(j);
      expect(u.uid, 'firebase-uid-1');
      expect(u.email, 'igor@example.com');
      expect(u.displayName, 'Igor Gewehr');
      expect(u.photoUrl, 'https://cdn.example/avatar.jpg');
      expect(u.accountType, ApiAccountType.linked);
      expect(u.birthDate, DateTime(1990, 4, 23));
      expect(u.weightKg, 78.5);
      expect(u.highestBelt, 'black');
      expect(u.highestStripes, 1);
      expect(u.isProfilePublic, isTrue);
    });

    test('defaults to free account when account_type is missing or invalid', () {
      final u1 =
          ApiGlobalUser.fromJson({'uid': 'a', 'email': 'a@b.com'});
      expect(u1.accountType, ApiAccountType.free);
      final u2 = ApiGlobalUser.fromJson(
          {'uid': 'a', 'email': 'a@b.com', 'account_type': 'unknown'});
      expect(u2.accountType, ApiAccountType.free);
    });

    test('handles minimum-required payload (no optionals)', () {
      final u = ApiGlobalUser.fromJson({
        'uid': 'x',
        'email': 'x@y.com',
        'account_type': 'free',
      });
      expect(u.displayName, isNull);
      expect(u.birthDate, isNull);
      expect(u.weightKg, isNull);
      expect(u.isProfilePublic, isFalse);
    });
  });

  group('ApiMembership.fromJson', () {
    test('parses active membership with extra_permissions', () {
      final m = ApiMembership.fromJson({
        'uid': 'firebase-uid-1',
        'academy_id': '00000000-0000-0000-0000-000000000001',
        'role': 'instructor',
        'status': 'active',
        'student_id': null,
        'joined_at': '2025-06-15T12:00:00Z',
        'extra_permissions': ['attendance.write', 'students.read'],
      });
      expect(m.role, ApiRole.instructor);
      expect(m.status, ApiMembershipStatus.active);
      expect(m.isActive, isTrue);
      expect(m.studentId, isNull);
      expect(m.extraPermissions, hasLength(2));
      expect(m.extraPermissions.first, 'attendance.write');
    });

    test('recognises monitor role added by Sprint H', () {
      final m = ApiMembership.fromJson({
        'uid': 'a',
        'academy_id': 'aid',
        'role': 'monitor',
        'status': 'active',
      });
      expect(m.role, ApiRole.monitor);
    });

    test('unknown role degrades to student (least privilege)', () {
      final m = ApiMembership.fromJson({
        'uid': 'a',
        'academy_id': 'aid',
        'role': 'super-admin',
        'status': 'active',
      });
      expect(m.role, ApiRole.student);
    });

    test('unknown status treated as removed (safe default)', () {
      final m = ApiMembership.fromJson({
        'uid': 'a',
        'academy_id': 'aid',
        'role': 'student',
        'status': 'deactivated',
      });
      expect(m.status, ApiMembershipStatus.removed);
      expect(m.isActive, isFalse);
    });
  });

  group('CurrentUserResponse', () {
    test('parses user + memberships + primary_academy_id', () {
      final j = <String, dynamic>{
        'user': {
          'uid': 'u1',
          'email': 'u@x.com',
          'account_type': 'linked',
        },
        'memberships': [
          {
            'uid': 'u1',
            'academy_id': 'aid-1',
            'role': 'student',
            'status': 'active',
          },
          {
            'uid': 'u1',
            'academy_id': 'aid-2',
            'role': 'admin',
            'status': 'active',
          },
        ],
        'primary_academy_id': 'aid-2',
      };
      final r = CurrentUserResponse.fromJson(j);
      expect(r.user.uid, 'u1');
      expect(r.memberships, hasLength(2));
      expect(r.primaryAcademyId, 'aid-2');
    });

    test('activeMemberships filters out removed/suspended', () {
      final r = CurrentUserResponse.fromJson({
        'user': {'uid': 'u', 'email': 'u@x.com', 'account_type': 'linked'},
        'memberships': [
          {
            'uid': 'u',
            'academy_id': 'a-active',
            'role': 'student',
            'status': 'active'
          },
          {
            'uid': 'u',
            'academy_id': 'a-removed',
            'role': 'student',
            'status': 'removed'
          },
          {
            'uid': 'u',
            'academy_id': 'a-suspended',
            'role': 'student',
            'status': 'suspended'
          },
        ],
      });
      expect(r.activeMemberships, hasLength(1));
      expect(r.activeMemberships.first.academyId, 'a-active');
    });

    test('activeMemberships puts primary academy first', () {
      final r = CurrentUserResponse.fromJson({
        'user': {'uid': 'u', 'email': 'u@x.com', 'account_type': 'linked'},
        'memberships': [
          {'uid': 'u', 'academy_id': 'a', 'role': 'student', 'status': 'active'},
          {'uid': 'u', 'academy_id': 'b', 'role': 'admin', 'status': 'active'},
          {'uid': 'u', 'academy_id': 'c', 'role': 'student', 'status': 'active'},
        ],
        'primary_academy_id': 'b',
      });
      expect(r.activeMemberships.first.academyId, 'b');
    });

    test('handles empty memberships (new free user)', () {
      final r = CurrentUserResponse.fromJson({
        'user': {'uid': 'u', 'email': 'u@x.com', 'account_type': 'free'},
        'memberships': [],
      });
      expect(r.activeMemberships, isEmpty);
      expect(r.primaryAcademyId, isNull);
    });
  });

  group('UpdateUserRequest.toJson', () {
    test('omits null fields (semantic PATCH)', () {
      const r = UpdateUserRequest(displayName: 'Novo Nome');
      expect(r.toJson(), {'display_name': 'Novo Nome'});
    });

    test('formats birth_date as YYYY-MM-DD', () {
      final r = UpdateUserRequest(birthDate: DateTime(2010, 1, 5));
      expect(r.toJson()['birth_date'], '2010-01-05');
    });

    test('serializes all fields when present', () {
      final r = UpdateUserRequest(
        displayName: 'X',
        phone: '+5511',
        photoUrl: 'https://e.com/p.jpg',
        birthDate: DateTime(1995, 12, 31),
        weightKg: 70.0,
        isProfilePublic: true,
      );
      final m = r.toJson();
      expect(m, {
        'display_name': 'X',
        'phone': '+5511',
        'photo_url': 'https://e.com/p.jpg',
        'birth_date': '1995-12-31',
        'weight_kg': 70.0,
        'is_profile_public': true,
      });
    });
  });
}
