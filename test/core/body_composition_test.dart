import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/body_composition.dart';

void main() {
  group('pollock3Sites', () {
    test('male = chest/abdominal/thigh; female = triceps/suprailiac/thigh', () {
      expect(pollock3Sites(isMale: true), ['chest', 'abdominal', 'thigh']);
      expect(
          pollock3Sites(isMale: false), ['triceps', 'suprailiac', 'thigh']);
    });
  });

  group('pollockBodyFatPct', () {
    test('male JP3 + Siri', () {
      final bf = pollockBodyFatPct(
        isMale: true,
        age: 30,
        skinfolds: {'chest': 10, 'abdominal': 20, 'thigh': 15},
      );
      expect(bf, isNotNull);
      expect(bf!, closeTo(13.6, 0.2));
    });

    test('female JP3 + Siri (uses triceps/suprailiac/thigh, ignores chest)',
        () {
      final bf = pollockBodyFatPct(
        isMale: false,
        age: 30,
        skinfolds: {
          'triceps': 20,
          'suprailiac': 20,
          'thigh': 30,
          'chest': 99, // ignored for females
        },
      );
      expect(bf, isNotNull);
      expect(bf!, closeTo(27.3, 0.2));
    });

    test('null when a required site is missing', () {
      expect(
        pollockBodyFatPct(
          isMale: true,
          age: 30,
          skinfolds: {'chest': 10, 'thigh': 15}, // no abdominal
        ),
        isNull,
      );
    });

    test('null when age is non-positive', () {
      expect(
        pollockBodyFatPct(
          isMale: true,
          age: 0,
          skinfolds: {'chest': 10, 'abdominal': 20, 'thigh': 15},
        ),
        isNull,
      );
    });

    test('null when a site is non-positive', () {
      expect(
        pollockBodyFatPct(
          isMale: false,
          age: 25,
          skinfolds: {'triceps': 0, 'suprailiac': 16, 'thigh': 22},
        ),
        isNull,
      );
    });

    test('very lean still yields a low but valid %', () {
      final bf = pollockBodyFatPct(
        isMale: false,
        age: 20,
        skinfolds: {'triceps': 3, 'suprailiac': 3, 'thigh': 3},
      );
      expect(bf, isNotNull);
      expect(bf!, closeTo(5.0, 0.3));
    });
  });

  group('bodyMassSplit', () {
    test('splits weight into fat + lean', () {
      final split = bodyMassSplit(weightKg: 80, bodyFatPct: 20);
      expect(split, isNotNull);
      expect(split!.fatMassKg, closeTo(16, 0.001));
      expect(split.leanMassKg, closeTo(64, 0.001));
    });

    test('null on invalid input', () {
      expect(bodyMassSplit(weightKg: 0, bodyFatPct: 20), isNull);
      expect(bodyMassSplit(weightKg: 80, bodyFatPct: 100), isNull);
      expect(bodyMassSplit(weightKg: 80, bodyFatPct: -1), isNull);
    });
  });
}
