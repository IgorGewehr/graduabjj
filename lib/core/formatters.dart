import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Visual masks for documents and phones.
///
/// These are **display/input only** — the underlying value should be stored as
/// digits. Forms format on load (so editing shows the mask) and strip with
/// [onlyDigits] on save; read-only screens wrap values with [formatCpfCnpj] /
/// [formatPhone]. Free-form text fields can use [PhoneInputFormatter] /
/// [CpfCnpjInputFormatter] to mask while typing.

String onlyDigits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

/// `TimeOfDay` → zero-padded `HH:mm` (24h), the wire format class schedules
/// are stored as. Was copy-pasted identically in classes_screen.dart and
/// quick_create_class_form.dart — consolidated here so the two never drift.
String formatTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 11-digit CPF → `000.000.000-00`; 14-digit CNPJ → `00.000.000/0000-00`.
/// Any other length is returned unchanged (partial / unknown values).
String formatCpfCnpj(String? raw) {
  final d = onlyDigits(raw);
  if (d.length == 11) {
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }
  if (d.length == 14) {
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}'
        '/${d.substring(8, 12)}-${d.substring(12)}';
  }
  return raw ?? '';
}

/// Brazilian phone → `(00) 00000-0000` (mobile) or `(00) 0000-0000` (landline).
/// Strips a leading `55` country code. Other lengths are returned unchanged.
String formatPhone(String? raw) {
  var d = onlyDigits(raw);
  if ((d.length == 12 || d.length == 13) && d.startsWith('55')) {
    d = d.substring(2);
  }
  if (d.length == 11) {
    return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  }
  if (d.length == 10) {
    return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  }
  return raw ?? '';
}

/// Masks a phone while typing: `(00) 00000-0000` (mobile) / `(00) 0000-0000`.
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var d = onlyDigits(newValue.text);
    if (d.length > 11) d = d.substring(0, 11);
    final hyphenAt = d.length > 10 ? 7 : 6;
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 0) b.write('(');
      if (i == 2) b.write(') ');
      if (i == hyphenAt) b.write('-');
      b.write(d[i]);
    }
    final t = b.toString();
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

/// Masks a document while typing: CPF `000.000.000-00` (≤11 digits) or
/// CNPJ `00.000.000/0000-00` (>11 digits).
class CpfCnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var d = onlyDigits(newValue.text);
    if (d.length > 14) d = d.substring(0, 14);
    final b = StringBuffer();
    if (d.length <= 11) {
      for (var i = 0; i < d.length; i++) {
        if (i == 3 || i == 6) b.write('.');
        if (i == 9) b.write('-');
        b.write(d[i]);
      }
    } else {
      for (var i = 0; i < d.length; i++) {
        if (i == 2 || i == 5) b.write('.');
        if (i == 8) b.write('/');
        if (i == 12) b.write('-');
        b.write(d[i]);
      }
    }
    final t = b.toString();
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
