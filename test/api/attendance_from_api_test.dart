import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/attendance_dto.dart';
import 'package:graduabjj/services/attendance_service.dart';

void main() {
  ApiAttendance mk({String id = 'a1', String weight = '1.000'}) =>
      ApiAttendance.fromJson({
        'id': id,
        'academy_id': 'aid',
        'student_id': 's-1',
        'class_id': 'c-1',
        'date': '2026-05-16',
        'verified_by_uid': 'inst-1',
        'weight': weight,
        'created_at': '2026-05-16T19:00:00Z',
      });

  group('Attendance.fromApi', () {
    test('mapeia ids + weight string → double', () {
      final a = Attendance.fromApi(mk());
      expect(a.id, 'a1');
      expect(a.studentId, 's-1');
      expect(a.classId, 'c-1');
      expect(a.verifiedBy, 'inst-1');
      expect(a.weight, 1.0);
      expect(a.date, DateTime(2026, 5, 16));
    });

    test('weight não-padrão preserva precisão', () {
      final a = Attendance.fromApi(mk(weight: '1.500'));
      expect(a.weight, closeTo(1.5, 1e-9));
    });

    test('weight inválido vira null', () {
      final a = Attendance.fromApi(mk(weight: 'garbage'));
      expect(a.weight, isNull);
    });

    test('nomes via param (denorm local opcional)', () {
      final a = Attendance.fromApi(
        mk(),
        studentName: 'João',
        className: 'BJJ Noite',
        verifiedByName: 'Prof. Silva',
      );
      expect(a.studentName, 'João');
      expect(a.className, 'BJJ Noite');
      expect(a.verifiedByName, 'Prof. Silva');
    });

    test('nomes ausentes viram empty string (legacy non-null)', () {
      final a = Attendance.fromApi(mk());
      expect(a.studentName, '');
      expect(a.className, '');
      expect(a.verifiedByName, '');
    });
  });
}
