import 'validators.dart';

/// Pure helpers for the CSV student import: digit cleaning, BR phone
/// normalization, date/money parsing, name capitalization and field validity
/// checks (reusing [Validators] so the rules match the rest of the app).
class ImportUtils {
  ImportUtils._();

  static final _connectors = {'da', 'de', 'do', 'dos', 'das', 'e', 'di', 'du'};

  static String onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// "joão DA silva" -> "João da Silva" (connectors stay lowercase).
  static String capitalizeName(String raw) {
    final parts = raw.trim().toLowerCase().split(RegExp(r'\s+'));
    return parts
        .where((p) => p.isNotEmpty)
        .map((p) => _connectors.contains(p)
            ? p
            : p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  /// Normalizes a Brazilian phone to bare DDD+number digits (no country code,
  /// no mask). Returns null when it doesn't look like a valid BR phone.
  static String? normalizePhone(String raw) {
    var d = onlyDigits(raw);
    if (d.isEmpty) return null;
    // Strip BR country code (55) when the length implies it's there.
    if ((d.length == 12 || d.length == 13) && d.startsWith('55')) {
      d = d.substring(2);
    }
    // Strip a leading 0 carrier prefix on the DDD.
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    if (d.length < 10 || d.length > 11) return null;
    return d;
  }

  /// Parses dd/mm/yyyy, dd-mm-yyyy, yyyy-mm-dd (and 2-digit years). Null if it
  /// can't be parsed or is not a real calendar date.
  static DateTime? parseDate(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;

    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(v);
    if (iso != null) {
      return _safeDate(
          int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    }

    final br = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2}|\d{4})$')
        .firstMatch(v);
    if (br != null) {
      final day = int.parse(br[1]!);
      final month = int.parse(br[2]!);
      var year = int.parse(br[3]!);
      if (br[3]!.length == 2) year = year < 50 ? 2000 + year : 1900 + year;
      return _safeDate(year, month, day);
    }
    return null;
  }

  static DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    // Guards against overflow (e.g. 31/02 rolling into March).
    if (dt.year != y || dt.month != m || dt.day != d) return null;
    return dt;
  }

  /// Parses "R$ 150,00", "150.00", "1.250,50", "150" -> double. Null if empty
  /// or unparseable.
  static double? parseMoney(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^\d,.]'), '').trim();
    if (clean.isEmpty) return null;
    String norm;
    if (clean.contains(',') && clean.contains('.')) {
      // "1.250,50" -> dot = thousands, comma = decimal.
      norm = clean.replaceAll('.', '').replaceAll(',', '.');
    } else if (clean.contains(',')) {
      norm = clean.replaceAll(',', '.');
    } else {
      norm = clean;
    }
    return double.tryParse(norm);
  }

  /// Day-of-month (1..31) from a cell, or null.
  static int? parseDay(String raw) {
    final d = int.tryParse(onlyDigits(raw));
    if (d == null || d < 1 || d > 31) return null;
    return d;
  }

  static bool isValidCpf(String raw) =>
      raw.trim().isNotEmpty && Validators.cpf(raw) == null;

  static bool isValidEmail(String raw) =>
      raw.trim().isNotEmpty && Validators.email(raw) == null;

  static bool isValidPhone(String raw) =>
      raw.trim().isNotEmpty && Validators.phone(raw) == null;
}
