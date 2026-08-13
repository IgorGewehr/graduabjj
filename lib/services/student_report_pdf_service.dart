import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/sports.dart';
import '../models/student.dart';

/// Generates the staff-facing student list report without additional reads.
///
/// The caller passes the already loaded list. The immutable rows are prepared
/// once and the resulting bytes are reused if Android's print dialog requests
/// the document more than once.
class StudentReportPdfService {
  Future<void> printOrSave({
    required List<Student> students,
    required String academyName,
    required String scopeLabel,
  }) async {
    final generatedAt = DateTime.now();
    final rows = _buildRows(students);
    final pdfBytes = buildPdf(
      rows: rows,
      academyName: academyName,
      scopeLabel: scopeLabel,
      generatedAt: generatedAt,
    );

    await Printing.layoutPdf(
      name:
          'relatorio_alunos_${DateFormat('yyyyMMdd').format(generatedAt)}.pdf',
      onLayout: (_) => pdfBytes,
    );
  }

  Future<Uint8List> buildPdf({
    required List<StudentReportRow> rows,
    required String academyName,
    required String scopeLabel,
    required DateTime generatedAt,
  }) async {
    final document = pw.Document();
    final activeCount = rows.where((row) => row.status == 'Ativo').length;
    final linkedCount = rows.where((row) => row.hasAccount).length;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  academyName,
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(generatedAt),
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 7),
            pw.Text(
              'Relatório de alunos',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              '$scopeLabel  |  ${rows.length} alunos  |  $activeCount ativos  |  $linkedCount com acesso ao app',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          if (rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 24),
              child: pw.Text('Nenhum aluno neste relatório.'),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Nome',
                'Categoria',
                'Modalidade',
                'Faixa',
                'Status',
                'Telefone',
                'Pres.',
              ],
              data: [
                for (final row in rows)
                  [
                    row.name,
                    row.category,
                    row.modalities,
                    row.grade,
                    row.status,
                    row.phone,
                    row.attendances.toString(),
                  ],
              ],
              border: pw.TableBorder(
                horizontalInside: const pw.BorderSide(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                bottom: const pw.BorderSide(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.6),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.6),
                3: pw.FlexColumnWidth(1.25),
                4: pw.FlexColumnWidth(1.1),
                5: pw.FlexColumnWidth(1.7),
                6: pw.FlexColumnWidth(0.7),
              },
              headerAlignment: pw.Alignment.centerLeft,
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800,
              ),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey900,
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 5,
              ),
            ),
        ],
      ),
    );

    return document.save();
  }

  List<StudentReportRow> _buildRows(List<Student> students) {
    final sorted = List<Student>.of(students)
      ..sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
    return List<StudentReportRow>.unmodifiable(
      sorted.map(StudentReportRow.fromStudent),
    );
  }
}

class StudentReportRow {
  final String name;
  final String category;
  final String modalities;
  final String grade;
  final String status;
  final String phone;
  final int attendances;
  final bool hasAccount;

  const StudentReportRow({
    required this.name,
    required this.category,
    required this.modalities,
    required this.grade,
    required this.status,
    required this.phone,
    required this.attendances,
    required this.hasAccount,
  });

  factory StudentReportRow.fromStudent(Student student) {
    final primarySport = student.getPrimarySport();
    final sport = sports[primarySport];
    final grade = student.getGrade(primarySport);
    final gradeLabel = sport?.gradeSystem == GradeSystem.none || grade == null
        ? '-'
        : getGradeLabel(primarySport, grade.currentGrade);

    return StudentReportRow(
      name: student.fullName,
      category: student.category == StudentCategory.kids
          ? 'Infantil'
          : 'Adulto',
      modalities: student
          .getSports()
          .map((item) => sports[item]?.labelShort ?? item.value)
          .join(' / '),
      grade: gradeLabel,
      status: _statusLabel(student.status),
      phone: student.phone?.trim().isNotEmpty == true
          ? student.phone!.trim()
          : '-',
      attendances: student.totalAttendanceCount,
      hasAccount: student.linkedUserId?.trim().isNotEmpty == true,
    );
  }

  static String _statusLabel(StudentStatus status) {
    switch (status) {
      case StudentStatus.active:
        return 'Ativo';
      case StudentStatus.injured:
        return 'Lesionado';
      case StudentStatus.inactive:
        return 'Inativo';
      case StudentStatus.suspended:
        return 'Suspenso';
      case StudentStatus.transferred:
        return 'Transferido';
    }
  }
}
