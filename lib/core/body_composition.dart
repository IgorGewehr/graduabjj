/// Pure body-composition math (no Flutter/model deps → unit-testable).
///
/// Body fat % via the **Jackson & Pollock 3-site** skinfold protocol + the
/// **Siri** equation. Sex is passed as [isMale] so this stays model-free; the
/// caller maps its own `Sex` enum. Skinfold values are in millimetres and keyed
/// to match the physical-assessment form's skinfold map.

/// The 3 skinfold sites required by JP3 for each sex (form keys).
/// Men: chest + abdomen + thigh. Women: triceps + suprailiac + thigh.
List<String> pollock3Sites({required bool isMale}) => isMale
    ? const ['chest', 'abdominal', 'thigh']
    : const ['triceps', 'suprailiac', 'thigh'];

/// Body fat % via Jackson-Pollock 3-site body density + Siri conversion.
///
/// Returns null when [age] is non-positive or any required site is
/// missing/non-positive, or when the result is outside a sane 2–75% range.
double? pollockBodyFatPct({
  required bool isMale,
  required int age,
  required Map<String, double> skinfolds,
}) {
  if (age <= 0) return null;

  double sum = 0;
  for (final site in pollock3Sites(isMale: isMale)) {
    final v = skinfolds[site];
    if (v == null || v <= 0) return null; // need all 3 sites
    sum += v;
  }

  // Body density (g/cc) — Jackson & Pollock 3-site, sex-specific.
  final double density = isMale
      ? 1.10938 -
          (0.0008267 * sum) +
          (0.0000016 * sum * sum) -
          (0.0002574 * age)
      : 1.0994921 -
          (0.0009929 * sum) +
          (0.0000023 * sum * sum) -
          (0.0001392 * age);
  if (density <= 0) return null;

  // Siri equation.
  final bf = (495 / density) - 450;
  if (bf.isNaN || bf.isInfinite || bf < 2 || bf > 75) return null;
  return bf;
}

/// Splits body weight into fat and lean mass (kg) from a body-fat percentage.
/// Returns null on invalid inputs.
({double fatMassKg, double leanMassKg})? bodyMassSplit({
  required double weightKg,
  required double bodyFatPct,
}) {
  if (weightKg <= 0 || bodyFatPct < 0 || bodyFatPct >= 100) return null;
  final fat = weightKg * bodyFatPct / 100.0;
  return (fatMassKg: fat, leanMassKg: weightKg - fat);
}
