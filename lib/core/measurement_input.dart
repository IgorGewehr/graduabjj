/// Pure parsing + validation for optional numeric measurement inputs
/// (pt-BR decimals, e.g. "82,5"). No Flutter deps → unit-testable.

/// Parses "82,5" or "82.5" → 82.5. Empty/whitespace/invalid → null.
double? parseDecimalInput(String? text) {
  final t = (text ?? '').trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Validator for an OPTIONAL measurement field. Returns a short pt-BR error
/// message, or null when valid. Empty is valid (fields are optional).
/// [min]/[max] are inclusive sanity bounds. An invalid number is REJECTED
/// (instead of being silently dropped on save).
String? validateOptionalMeasure(
  String? text, {
  required String label,
  double? min,
  double? max,
}) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty) return null; // optional
  final v = parseDecimalInput(raw);
  if (v == null) return 'Número inválido';
  if (v <= 0) return 'Deve ser maior que zero';
  if (min != null && v < min) return 'Mín. ${_bound(min)}';
  if (max != null && v > max) return 'Máx. ${_bound(max)}';
  return null;
}

String _bound(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
