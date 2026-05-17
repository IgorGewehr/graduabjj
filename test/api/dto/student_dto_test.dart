import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/api/dto/student_dto.dart';

void main() {
  group('ApiStudent.fromJson', () {
    test('parses full payload', () {
      final j = <String, dynamic>{
        'id': 'sid-1',
        'academy_id': 'aid-1',
        'full_name': 'João Silva',
        'nickname': 'Jão',
        'birth_date': '1995-03-12',
        'cpf': '111.111.111-11',
        'phone': '+5511',
        'email': 'joao@x.com',
        'photo_url': 'https://e.com/j.jpg',
        'address': {
          'street': 'Rua A',
          'city': 'São Paulo',
          'state': 'SP',
          'zip_code': '01000-000',
        },
        'guardian': null,
        'jiujitsu_start_date': '2018-01-01',
        'current_belt': 'purple',
        'current_stripes': 2,
        'category': 'adult',
        'weight_kg': 80.0,
        'attendance_count': 320,
        'initial_attendance_count': 50,
        'status': 'active',
        'is_profile_public': false,
        'primary_sport': 'bjj',
        'sports_list': ['bjj'],
        'sport_data': {'bjj': {'current_grade': 'purple'}},
        'created_at': '2024-01-01T10:00:00Z',
        'updated_at': '2026-05-01T08:00:00Z',
      };

      final s = ApiStudent.fromJson(j);
      expect(s.id, 'sid-1');
      expect(s.fullName, 'João Silva');
      expect(s.nickname, 'Jão');
      expect(s.currentBelt, ApiBelt.purple);
      expect(s.currentStripes, 2);
      expect(s.category, ApiStudentCategory.adult);
      expect(s.status, ApiStudentStatus.active);
      expect(s.isActive, isTrue);
      expect(s.isKids, isFalse);
      expect(s.attendanceCount, 320);
      expect(s.address?.city, 'São Paulo');
      expect(s.guardian, isNull);
      expect(s.sportData?['bjj'], isA<Map>());
      expect(s.sportsList, ['bjj']);
    });

    test('handles minimum-required payload', () {
      final s = ApiStudent.fromJson({
        'id': 'sid',
        'academy_id': 'aid',
        'full_name': 'Aluno',
        'current_belt': 'white',
        'current_stripes': 0,
        'category': 'kids',
        'status': 'active',
        'attendance_count': 0,
        'is_profile_public': false,
        'primary_sport': 'bjj',
        'sports_list': [],
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });
      expect(s.category, ApiStudentCategory.kids);
      expect(s.isKids, isTrue);
      expect(s.address, isNull);
      expect(s.guardian, isNull);
      expect(s.sportData, isNull);
    });

    test('unknown belt degrades to white (safe default)', () {
      final s = ApiStudent.fromJson({
        'id': 'a',
        'academy_id': 'a',
        'full_name': 'X',
        'current_belt': 'mythril',
        'current_stripes': 0,
        'category': 'adult',
        'status': 'active',
        'attendance_count': 0,
        'is_profile_public': false,
        'primary_sport': 'bjj',
        'sports_list': [],
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });
      expect(s.currentBelt, ApiBelt.white);
    });
  });

  group('StudentsPage.fromJson', () {
    test('parses items + cursor + has_more', () {
      final page = StudentsPage.fromJson({
        'items': [
          {
            'id': 'a',
            'academy_id': 'aid',
            'full_name': 'A',
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
          },
        ],
        'next_cursor': 'opaque',
        'has_more': true,
      });
      expect(page.items, hasLength(1));
      expect(page.nextCursor, 'opaque');
      expect(page.hasMore, isTrue);
    });

    test('handles empty page (final page)', () {
      final page = StudentsPage.fromJson({'items': [], 'has_more': false});
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
    });
  });

  group('ApiEligibilityView.fromJson', () {
    test('computes attendancesNeeded correctly', () {
      final e = ApiEligibilityView.fromJson({
        'eligible': false,
        'current_belt': 'blue',
        'current_stripes': 2,
        'next_belt': 'blue',
        'next_stripes': 3,
        'current_count': 25,
        'required_count': 40,
        'auto_enabled': true,
      });
      expect(e.attendancesNeeded, 15);
      expect(e.eligible, isFalse);
    });

    test('eligible=true and attendancesNeeded clamps to 0', () {
      final e = ApiEligibilityView.fromJson({
        'eligible': true,
        'current_belt': 'blue',
        'current_stripes': 4,
        'next_belt': 'purple',
        'next_stripes': 0,
        'current_count': 50,
        'required_count': 40,
        'auto_enabled': true,
      });
      expect(e.attendancesNeeded, 0);
      expect(e.eligible, isTrue);
    });

    test('handles null next_belt (top of progression)', () {
      final e = ApiEligibilityView.fromJson({
        'eligible': false,
        'current_belt': 'black',
        'current_stripes': 6,
        'next_belt': null,
        'current_count': 100,
        'required_count': 40,
        'auto_enabled': false,
      });
      expect(e.nextBelt, isNull);
    });
  });

  group('ApiStudentStats.fromJson', () {
    test('parses full stats with by_belt rows', () {
      final s = ApiStudentStats.fromJson({
        'total': 120,
        'by_status': {
          'active': 100,
          'injured': 5,
          'inactive': 10,
          'suspended': 3,
          'removed': 2,
        },
        'by_category': {'adults': 90, 'kids': 30},
        'by_belt': [
          {'belt': 'white', 'category': 'adult', 'total': 30},
          {'belt': 'blue', 'category': 'adult', 'total': 25},
        ],
      });
      expect(s.total, 120);
      expect(s.activeCount, 100);
      expect(s.adultsCount, 90);
      expect(s.kidsCount, 30);
      expect(s.byBelt, hasLength(2));
      expect(s.byBelt.first.belt, ApiBelt.white);
      expect(s.byBelt.first.total, 30);
    });

    test('handles missing keys gracefully', () {
      final s = ApiStudentStats.fromJson({
        'total': 0,
        'by_status': {},
        'by_category': {},
        'by_belt': [],
      });
      expect(s.total, 0);
      expect(s.activeCount, 0);
      expect(s.byBelt, isEmpty);
    });
  });

  group('ApiAssessmentScores', () {
    test('average is computed correctly', () {
      const sc = ApiAssessmentScores(
        respeito: 5,
        disciplina: 4,
        pontualidade: 3,
        tecnica: 5,
        esforco: 4,
      );
      expect(sc.average, closeTo(4.2, 1e-9));
    });
  });

  group('StudentFilter.toQueryParameters', () {
    test('limit only when no filters set', () {
      const f = StudentFilter();
      expect(f.toQueryParameters(), {'limit': 50});
    });

    test('omits empty q string', () {
      const f = StudentFilter(q: '');
      expect(f.toQueryParameters().containsKey('q'), isFalse);
    });

    test('serializes all enum fields as wire strings', () {
      const f = StudentFilter(
        status: ApiStudentStatus.active,
        belt: ApiBelt.blue,
        category: ApiStudentCategory.kids,
        q: 'joão',
        sport: 'bjj',
        limit: 25,
        cursor: 'c-1',
      );
      expect(f.toQueryParameters(), {
        'limit': 25,
        'status': 'active',
        'belt': 'blue',
        'category': 'kids',
        'q': 'joão',
        'sport': 'bjj',
        'cursor': 'c-1',
      });
    });
  });
}
