import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/services/student_report_pdf_service.dart';

void main() {
  test('gera um PDF válido a partir de uma lista já carregada', () async {
    final bytes = await StudentReportPdfService().buildPdf(
      rows: const [
        StudentReportRow(
          name: 'Aluno de Teste',
          category: 'Adulto',
          modalities: 'BJJ',
          grade: 'Azul',
          status: 'Ativo',
          phone: '(11) 99999-9999',
          attendances: 42,
          hasAccount: true,
        ),
      ],
      academyName: 'Academia Teste',
      scopeLabel: 'Todos os alunos',
      generatedAt: DateTime(2026, 8, 13, 18, 30),
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
