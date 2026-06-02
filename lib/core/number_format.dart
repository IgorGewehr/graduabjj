import 'package:intl/intl.dart';

/// pt-BR decimal formatting for measurements (comma decimal, dot thousands).
///
/// Trims trailing zeros up to [maxDecimals] places:
///   82.5 → "82,5", 78.0 → "78", 2500 → "2.500".
String fmtNum(double v, {int maxDecimals = 1}) {
  final f = NumberFormat.decimalPattern('pt_BR')
    ..maximumFractionDigits = maxDecimals
    ..minimumFractionDigits = 0;
  return f.format(v);
}

/// Like [fmtNum] but appends a unit (e.g. "82,5 kg"). Empty unit → no suffix.
String fmtMeasure(double v, String unit, {int maxDecimals = 1}) {
  final n = fmtNum(v, maxDecimals: maxDecimals);
  return unit.isEmpty ? n : '$n $unit';
}
