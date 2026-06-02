import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/physical_assessment.dart';

/// Pure-logic tests for [PhysicalAssessment] — the BMI computation and WHO
/// classification, which are the regression-prone bits. Serialization isn't
/// covered here (needs Firestore plumbing); the math/edge-cases are.
PhysicalAssessment _a({double? weight, double? height}) => PhysicalAssessment(
      id: 'a1',
      studentId: 's1',
      studentName: 'Aluno',
      date: DateTime(2026, 1, 1),
      weightKg: weight,
      heightCm: height,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('PhysicalAssessment.bmi', () {
    test('computes weight / height_m²', () {
      // 80 / 1.80² = 24.69
      expect(_a(weight: 80, height: 180).bmi, closeTo(24.69, 0.01));
      // 81 / 1.80² = 25.0 exatamente
      expect(_a(weight: 81, height: 180).bmi, closeTo(25.0, 0.001));
    });

    test('null when weight or height missing, or height == 0', () {
      expect(_a(weight: null, height: 180).bmi, isNull);
      expect(_a(weight: 80, height: null).bmi, isNull);
      expect(_a(weight: 80, height: 0).bmi, isNull);
      expect(_a().bmi, isNull);
    });
  });

  group('PhysicalAssessment.bmiClass (limites OMS)', () {
    String? cls(double bmiTarget) {
      // height fixa de 1m → bmi == weightKg, facilita testar os limites
      return _a(weight: bmiTarget, height: 100).bmiClass;
    }

    test('faixas e fronteiras', () {
      expect(cls(18.4), 'Abaixo do peso');
      expect(cls(18.5), 'Peso normal'); // fronteira inclui no normal
      expect(cls(24.9), 'Peso normal');
      expect(cls(25.0), 'Sobrepeso'); // fronteira sobe pra sobrepeso
      expect(cls(29.9), 'Sobrepeso');
      expect(cls(30.0), 'Obesidade grau I');
      expect(cls(35.0), 'Obesidade grau II');
      expect(cls(40.0), 'Obesidade grau III');
    });

    test('null quando IMC nao calculavel', () {
      expect(_a().bmiClass, isNull);
    });
  });

  group('PhysicalAssessment — campos opcionais', () {
    test('measurements/skinfolds default vazios, photos vazias', () {
      final a = _a(weight: 80, height: 180);
      expect(a.measurements, isEmpty);
      expect(a.skinfolds, isEmpty);
      expect(a.photos, isEmpty);
      expect(a.bodyFatPct, isNull);
    });
  });
}
