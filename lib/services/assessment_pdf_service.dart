import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/body_composition.dart';
import '../core/number_format.dart';
import '../models/physical_assessment.dart';

/// Builds and shares a one-page PDF of a physical assessment.
///
/// Photos are intentionally EXCLUDED — body photos are private (LGPD) and a
/// shareable PDF would defeat the storage-rules privacy model.
class AssessmentPdfService {
  static const Map<String, String> _girthLabels = {
    'neck': 'Pescoço', 'shoulder': 'Ombro', 'chest': 'Tórax', 'waist': 'Cintura',
    'abdomen': 'Abdômen', 'hip': 'Quadril', 'armR': 'Braço D', 'armL': 'Braço E',
    'forearmR': 'Antebraço D', 'forearmL': 'Antebraço E', 'thighR': 'Coxa D',
    'thighL': 'Coxa E', 'calfR': 'Panturrilha D', 'calfL': 'Panturrilha E',
  };
  static const Map<String, String> _skinfoldLabels = {
    'triceps': 'Tríceps', 'chest': 'Peitoral', 'subscapular': 'Subescapular',
    'suprailiac': 'Supra-ilíaca', 'abdominal': 'Abdominal', 'thigh': 'Coxa',
  };
  static const Map<String, String> _goalLabels = {
    'hipertrofia': 'Hipertrofia', 'emagrecimento': 'Emagrecimento',
    'condicionamento': 'Condicionamento', 'manutencao': 'Manutenção',
  };

  /// Opens the native print/share sheet (print, save PDF, send) for [a].
  Future<void> printOrShare({
    required PhysicalAssessment a,
    required String studentName,
    String? sexLabel,
    int? age,
    String? academyName,
  }) async {
    final safeName = studentName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final dateTag = DateFormat('yyyy-MM-dd').format(a.date);
    await Printing.layoutPdf(
      name: 'avaliacao_${safeName}_$dateTag.pdf',
      onLayout: (format) async => _build(
        format: format,
        a: a,
        studentName: studentName,
        sexLabel: sexLabel,
        age: age,
        academyName: academyName,
      ),
    );
  }

  Future<Uint8List> _build({
    required PdfPageFormat format,
    required PhysicalAssessment a,
    required String studentName,
    String? sexLabel,
    int? age,
    String? academyName,
  }) async {
    final doc = pw.Document();

    // Basics.
    final basics = <List<String>>[
      if (a.weightKg != null) ['Peso', fmtMeasure(a.weightKg!, 'kg')],
      if (a.heightCm != null) ['Altura', fmtMeasure(a.heightCm!, 'cm')],
      if (a.bmi != null)
        ['IMC', '${fmtNum(a.bmi!)}${a.bmiClass != null ? ' (${a.bmiClass})' : ''}'],
      if (a.bodyFatPct != null) ['% Gordura', fmtMeasure(a.bodyFatPct!, '%')],
    ];

    // Composition (stored manual or derived for lean/fat).
    final split = (a.weightKg != null && a.bodyFatPct != null)
        ? bodyMassSplit(weightKg: a.weightKg!, bodyFatPct: a.bodyFatPct!)
        : null;
    final lean = a.leanMassKg ?? split?.leanMassKg;
    final fat = a.fatMassKg ?? split?.fatMassKg;
    final composition = <List<String>>[
      if (lean != null) ['Massa magra', fmtMeasure(lean, 'kg')],
      if (fat != null) ['Massa gorda', fmtMeasure(fat, 'kg')],
      if (a.visceralFatLevel != null)
        ['Gordura visceral', fmtNum(a.visceralFatLevel!)],
      if (a.bmrKcal != null) ['TMB', fmtMeasure(a.bmrKcal!, 'kcal')],
    ];

    final girths = [
      for (final k in PhysicalAssessment.girthKeys)
        if (a.measurements[k] != null)
          [_girthLabels[k] ?? k, fmtMeasure(a.measurements[k]!, 'cm')],
    ];
    final skinfolds = [
      for (final entry in _skinfoldLabels.entries)
        if (a.skinfolds[entry.key] != null)
          [entry.value, fmtMeasure(a.skinfolds[entry.key]!, 'mm')],
    ];

    final context = <List<String>>[
      if (a.goal != null) ['Objetivo', _goalLabels[a.goal] ?? a.goal!],
      if (a.notes != null && a.notes!.trim().isNotEmpty)
        ['Observações', a.notes!.trim()],
    ];

    final subtitleParts = <String>[
      DateFormat('dd/MM/yyyy').format(a.date),
      if (sexLabel != null) sexLabel,
      if (age != null) '$age anos',
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          _header(academyName, studentName, subtitleParts.join('  •  ')),
          _section('Medidas básicas', basics),
          _section('Composição corporal', composition),
          _section('Perimetria (cm)', girths),
          _section('Dobras cutâneas (mm)', skinfolds),
          _section('Objetivo e observações', context),
          pw.SizedBox(height: 18),
          pw.Text(
            'Gerado pelo MyDojo em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _header(String? academyName, String studentName, String subtitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(academyName ?? '',
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)),
            pw.Text('Avaliação Física',
                style: pw.TextStyle(
                    fontSize: 11, color: PdfColors.blueGrey700)),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(studentName,
            style:
                pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text(subtitle,
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Divider(color: PdfColors.grey400, thickness: 1),
      ],
    );
  }

  pw.Widget _section(String title, List<List<String>> rows) {
    if (rows.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 14),
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey800)),
        pw.SizedBox(height: 4),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(3),
          },
          children: rows
              .map((r) => pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 3),
                      child: pw.Text(r[0],
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey700)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 3),
                      child: pw.Text(r[1],
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ),
                  ]))
              .toList(),
        ),
      ],
    );
  }
}
