import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/sports.dart';
import 'package:graduabjj/services/belt_progression_service.dart';

/// Pure-function tests for [BeltProgressionService.checkEligibility].
/// These don't touch Firestore — they exercise the eligibility math which
/// is the most regression-prone part of the graduation feature.
void main() {
  // We need an instance to call the method but never actually hit Firestore
  // since checkEligibility is sync and pure when given totalClasses.
  final svc = BeltProgressionService('test-academy');

  group('Single configurable threshold (autoGraduationAttendances)', () {
    test('eligible when totalClasses >= threshold', () {
      final r = svc.checkEligibility(
        currentBelt: 'white',
        currentStripes: 0,
        totalClasses: 75,
        config: const AcademyGraduationConfig(threshold: 75),
      );
      expect(r.eligible, isTrue);
      expect(r.requiredClasses, 75);
      expect(r.missingClasses, 0);
    });

    test('missingClasses = threshold - totalClasses when not eligible', () {
      final r = svc.checkEligibility(
        currentBelt: 'white',
        currentStripes: 0,
        totalClasses: 40,
        config: const AcademyGraduationConfig(threshold: 70),
      );
      expect(r.eligible, isFalse);
      expect(r.requiredClasses, 70);
      expect(r.missingClasses, 30);
    });

    test('over-attended (e.g. 82 vs threshold 75) is still eligible', () {
      final r = svc.checkEligibility(
        currentBelt: 'white',
        currentStripes: 0,
        totalClasses: 82,
        config: const AcademyGraduationConfig(threshold: 75),
      );
      expect(r.eligible, isTrue);
      expect(r.missingClasses, 0);
    });
  });

  group('Legacy fallback (no threshold configured)', () {
    test('uses STRIPE_REQUIREMENTS table for BJJ', () {
      final r = svc.checkEligibility(
        currentBelt: 'white',
        currentStripes: 0,
        totalClasses: 30,
        config: const AcademyGraduationConfig(),
      );
      // white belt 1st stripe needs 30 classes (legacy table)
      expect(r.eligible, isTrue);
      expect(r.requiredClasses, 30);
    });

    test('non-BJJ sport without threshold gets requiredClasses = 0', () {
      final r = svc.checkEligibility(
        currentBelt: 'white',
        currentStripes: 0,
        totalClasses: 5,
        sportId: SportId.muaythai,
        config: const AcademyGraduationConfig(),
      );
      expect(r.requiredClasses, 0);
      expect(r.eligible, isFalse);
    });
  });

  group('Weighted vs raw counts', () {
    test('message uses "pontos" when weighted', () {
      final r = svc.checkEligibility(
        currentBelt: 'white',
        currentStripes: 0,
        totalClasses: 40,
        config: const AcademyGraduationConfig(
          threshold: 70,
          useClassWeights: true,
        ),
      );
      expect(r.weighted, isTrue);
      expect(r.message, contains('pontos'));
    });

    test('message uses "aulas" when raw count', () {
      final r = svc.checkEligibility(
        currentBelt: 'white',
        currentStripes: 0,
        totalClasses: 40,
        config: const AcademyGraduationConfig(threshold: 70),
      );
      expect(r.weighted, isFalse);
      expect(r.message, contains('aulas'));
    });
  });

  group('Max grade reached', () {
    // Faixa preta adulta vai até o 6º grau (maxStripes: 6 em _bjjAdultGrades);
    // depois vem coral (aboveBlack, só manual). Então o grau máximo do fluxo
    // automático é preta + 6 graus — aí não há próxima promoção.
    test('black belt with 6 stripes (último grau) returns max-grade message', () {
      final r = svc.checkEligibility(
        currentBelt: 'black',
        currentStripes: 6,
        totalClasses: 9999,
        config: const AcademyGraduationConfig(threshold: 75),
      );
      expect(r.eligible, isFalse);
      expect(r.nextBelt, isNull);
      expect(r.message, contains('máximo'));
    });

    // Contraprova: preta com menos de 6 graus AINDA é promovível (5º grau),
    // não é grau máximo — garante que o teste acima não vire falso positivo
    // se um dia alguém reduzir o maxStripes da preta.
    test('black belt with 4 stripes is still promotable (not max grade)', () {
      final r = svc.checkEligibility(
        currentBelt: 'black',
        currentStripes: 4,
        totalClasses: 9999,
        config: const AcademyGraduationConfig(threshold: 75),
      );
      expect(r.eligible, isTrue);
      expect(r.nextBelt, 'black');
      expect(r.nextStripes, 5);
    });
  });

  group('BeltProgression.baselineCount', () {
    test('returns effectiveCountAtPromotion when present', () {
      final bp = BeltProgression(
        id: 'p1',
        studentId: 's1',
        previousBelt: 'white',
        previousStripes: 3,
        newBelt: 'white',
        newStripes: 4,
        promotionDate: DateTime(2025, 1, 1),
        totalClasses: 80,
        effectiveCountAtPromotion: 95, // weighted, > totalClasses
        createdAt: DateTime(2025, 1, 1),
      );
      expect(bp.baselineCount, 95);
    });

    test('falls back to totalClasses when effectiveCountAtPromotion null', () {
      final bp = BeltProgression(
        id: 'p1',
        studentId: 's1',
        previousBelt: 'white',
        previousStripes: 3,
        newBelt: 'white',
        newStripes: 4,
        promotionDate: DateTime(2025, 1, 1),
        totalClasses: 80,
        createdAt: DateTime(2025, 1, 1),
      );
      expect(bp.baselineCount, 80);
    });
  });
}
