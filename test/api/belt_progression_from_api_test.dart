import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/student_dto.dart';
import 'package:graduabjj/services/belt_progression_service.dart';

void main() {
  ApiBeltProgression mk({
    String id = 'bp-1',
    String studentId = 's-1',
    String sport = 'bjj',
    String previousBelt = 'white',
    int previousStripes = 3,
    String newBelt = 'blue',
    int newStripes = 0,
    String promotionDate = '2026-05-16T00:00:00Z',
    int totalClasses = 82,
    int effective = 80,
    String promotedByUid = 'uid-instr',
    String? notes,
    String? createdAt = '2026-05-16T19:00:00Z',
  }) =>
      ApiBeltProgression.fromJson({
        'id': id,
        'student_id': studentId,
        'sport': sport,
        'previous_belt': previousBelt,
        'previous_stripes': previousStripes,
        'new_belt': newBelt,
        'new_stripes': newStripes,
        'promotion_date': promotionDate,
        'total_classes': totalClasses,
        'effective_count_at_promotion': effective,
        'promoted_by_uid': promotedByUid,
        if (notes != null) 'notes': notes,
        if (createdAt != null) 'created_at': createdAt,
      });

  group('BeltProgression.fromApi', () {
    test('mapeamento 1:1 dos campos principais (snake_case → camelCase)', () {
      final bp = BeltProgression.fromApi(mk());
      expect(bp.id, 'bp-1');
      expect(bp.studentId, 's-1');
      expect(bp.previousBelt, 'white');
      expect(bp.previousStripes, 3);
      expect(bp.newBelt, 'blue');
      expect(bp.newStripes, 0);
      expect(bp.totalClasses, 82);
      expect(bp.effectiveCountAtPromotion, 80);
      expect(bp.promotedBy, 'uid-instr');
      expect(bp.sport, 'bjj');
      expect(bp.promotionDate, DateTime.parse('2026-05-16T00:00:00Z'));
      expect(bp.createdAt, DateTime.parse('2026-05-16T19:00:00Z'));
    });

    test('promotedByName sempre null — BE só expõe promotedByUid', () {
      final bp = BeltProgression.fromApi(mk(promotedByUid: 'uid-x'));
      expect(bp.promotedByName, isNull);
      // promotedBy carrega o UID; nome deve ser denormalizado no caller.
      expect(bp.promotedBy, 'uid-x');
    });

    test('createdAt ausente faz fallback para promotionDate', () {
      final bp = BeltProgression.fromApi(mk(
        promotionDate: '2026-04-01T00:00:00Z',
        createdAt: null,
      ));
      expect(bp.createdAt, DateTime.parse('2026-04-01T00:00:00Z'));
    });
  });
}
