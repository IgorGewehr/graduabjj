import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/attendance_dto.dart';
import 'package:graduabjj/models/checkin.dart';

void main() {
  ApiAttendance mk({
    String id = 'att-1',
    String studentId = 's-1',
    String classId = 'c-1',
    String date = '2026-05-16',
    String verifiedBy = 'uid-instr',
    String? createdAt = '2026-05-16T19:00:00Z',
  }) =>
      ApiAttendance.fromJson({
        'id': id,
        'academy_id': 'aid',
        'student_id': studentId,
        'class_id': classId,
        'date': date,
        'verified_by_uid': verifiedBy,
        'weight': '1.000',
        if (createdAt != null) 'created_at': createdAt,
      });

  group('Checkin.fromApi', () {
    test('mapeamento dos campos principais', () {
      final c = Checkin.fromApi(mk());
      expect(c.id, 'att-1');
      expect(c.studentId, 's-1');
      expect(c.classId, 'c-1');
      expect(c.scheduleDate, DateTime(2026, 5, 16));
      expect(c.checkinTime, DateTime.parse('2026-05-16T19:00:00Z'));
      expect(c.confirmedBy, 'uid-instr');
      expect(c.confirmedAt, DateTime.parse('2026-05-16T19:00:00Z'));
    });

    test(
        'status sempre confirmed — Tatami self-checkin já é uma attendance',
        () {
      final c = Checkin.fromApi(mk());
      expect(c.status, CheckinStatus.confirmed);
    });

    test('nomes ausentes viram empty string (legacy non-null)', () {
      final c = Checkin.fromApi(mk());
      expect(c.studentName, '');
      expect(c.className, '');
      expect(c.scheduleStartTime, '');
      expect(c.scheduleEndTime, '');
      expect(c.scheduleDayOfWeek, 0);
    });

    test('nomes via parâmetro (denormalização local opcional)', () {
      final c = Checkin.fromApi(
        mk(),
        studentName: 'João Silva',
        className: 'BJJ Adulto Noite',
        scheduleDayOfWeek: 1,
        scheduleStartTime: '19:00',
        scheduleEndTime: '20:30',
        confirmedByName: 'Prof. Carlos',
      );
      expect(c.studentName, 'João Silva');
      expect(c.className, 'BJJ Adulto Noite');
      expect(c.scheduleDayOfWeek, 1);
      expect(c.scheduleStartTime, '19:00');
      expect(c.scheduleEndTime, '20:30');
      expect(c.confirmedByName, 'Prof. Carlos');
    });

    test('createdAt ausente faz fallback pra now (não nulo)', () {
      final c = Checkin.fromApi(mk(createdAt: null));
      // Não conseguimos testar igualdade temporal; só validamos que existe
      // e está próximo do agora (não é DateTime epoch).
      expect(c.checkinTime, isNotNull);
      expect(c.createdAt, isNotNull);
      expect(
        c.checkinTime.isAfter(DateTime(2025, 1, 1)),
        isTrue,
      );
    });

    test('confirmedBy = verified_by_uid', () {
      final c = Checkin.fromApi(mk(verifiedBy: 'uid-aluno-self'));
      expect(c.confirmedBy, 'uid-aluno-self');
    });

    test('confirmedByName é opcional e fica null quando não passado', () {
      final c = Checkin.fromApi(mk());
      expect(c.confirmedByName, isNull);
    });
  });
}
