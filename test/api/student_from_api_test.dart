import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/student_dto.dart';
import 'package:graduabjj/models/student.dart';

void main() {
  ApiStudent mk({
    String id = 'sid',
    String belt = 'purple',
    int stripes = 2,
    String status = 'active',
    String category = 'adult',
    String? tuitionValue,
    int? tuitionDay,
    Map<String, dynamic>? address,
    Map<String, dynamic>? guardian,
    String? emergency,
  }) =>
      ApiStudent.fromJson({
        'id': id,
        'academy_id': 'aid',
        'full_name': 'João Silva',
        'nickname': 'Jão',
        'current_belt': belt,
        'current_stripes': stripes,
        'category': category,
        'status': status,
        'attendance_count': 50,
        'is_profile_public': false,
        'primary_sport': 'bjj',
        'sports_list': ['bjj', 'judo'],
        'created_at': '2025-01-01T10:00:00Z',
        'updated_at': '2026-05-01T08:00:00Z',
        if (tuitionValue != null) 'tuition_value': tuitionValue,
        if (tuitionDay != null) 'tuition_day': tuitionDay,
        if (address != null) 'address': address,
        if (guardian != null) 'guardian': guardian,
        if (emergency != null) 'emergency_contact': emergency,
      });

  group('Student.fromApi', () {
    test('mapeamento dos campos principais', () {
      final s = Student.fromApi(mk());
      expect(s.id, 'sid');
      expect(s.fullName, 'João Silva');
      expect(s.nickname, 'Jão');
      expect(s.currentBelt, 'purple');
      expect(s.currentStripes, 2);
      expect(s.category, StudentCategory.adult);
      expect(s.status, StudentStatus.active);
      expect(s.attendanceCount, 50);
      expect(s.sportsList, ['bjj', 'judo']);
      expect(s.primarySport, 'bjj');
    });

    test('removed status do Tatami vira inactive no legacy', () {
      final s = Student.fromApi(mk(status: 'removed'));
      expect(s.status, StudentStatus.inactive);
    });

    test('tuitionValue decimal-string → double', () {
      final s = Student.fromApi(mk(tuitionValue: '199.90'));
      expect(s.tuitionValue, 199.90);
    });

    test('tuitionValue null → 0.0 (legacy é non-null)', () {
      final s = Student.fromApi(mk());
      expect(s.tuitionValue, 0.0);
    });

    test('tuitionDay null → 10 (default legacy)', () {
      final s = Student.fromApi(mk());
      expect(s.tuitionDay, 10);
    });

    test('category kids', () {
      final s = Student.fromApi(mk(category: 'kids'));
      expect(s.category, StudentCategory.kids);
    });

    test('address opcional materializa Address legacy', () {
      final s = Student.fromApi(mk(address: {
        'street': 'Rua A',
        'city': 'São Paulo',
        'state': 'SP',
        'zip_code': '01000-000',
      }));
      expect(s.address, isNotNull);
      expect(s.address!.city, 'São Paulo');
      expect(s.address!.state, 'SP');
      expect(s.address!.zipCode, '01000-000');
    });

    test('address vazio (todos campos null) → null no legacy', () {
      final s = Student.fromApi(mk(address: {}));
      expect(s.address, isNull);
    });

    test('guardian opcional materializa Guardian legacy', () {
      final s = Student.fromApi(mk(guardian: {
        'name': 'Mãe da Criança',
        'phone': '+5511',
        'email': 'mae@x.com',
      }));
      expect(s.guardian, isNotNull);
      expect(s.guardian!.name, 'Mãe da Criança');
      expect(s.guardian!.email, 'mae@x.com');
    });

    test('emergency_contact como string vira EmergencyContact opaco', () {
      final s = Student.fromApi(mk(emergency: 'Tia Maria 11 99999'));
      expect(s.emergencyContact, isNotNull);
      expect(s.emergencyContact!.name, 'Tia Maria 11 99999');
      expect(s.emergencyContact!.relationship, 'emergency');
    });

    test('startDate cai pra createdAt quando ausente', () {
      final s = Student.fromApi(mk());
      // startDate não-nullable; usa createdAt como fallback.
      expect(s.startDate, DateTime.parse('2025-01-01T10:00:00Z'));
    });

    test('sportsList vazio → null no legacy (sentinela)', () {
      final s = Student.fromApi(ApiStudent.fromJson({
        'id': 'x',
        'academy_id': 'a',
        'full_name': 'X',
        'current_belt': 'white',
        'current_stripes': 0,
        'category': 'adult',
        'status': 'active',
        'attendance_count': 0,
        'is_profile_public': false,
        'primary_sport': 'bjj',
        'sports_list': [],
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      }));
      expect(s.sportsList, isNull);
    });
  });
}
