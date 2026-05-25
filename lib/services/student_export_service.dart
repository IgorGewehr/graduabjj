import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../core/sports.dart';
import '../models/student.dart';
import 'student_service.dart';

/// Builds a CSV export of students. Pairs with the CSV import: same columns,
/// so an exported file can be re-imported.
class StudentExportService {
  final String academyId;

  StudentExportService(this.academyId);

  Future<List<Student>> loadAll() => StudentService(academyId).listAll();

  /// UTF-8 CSV string with a BOM and ';' delimiter (so Brazilian Excel opens it
  /// with columns + accents correct).
  String buildCsv(List<Student> students) {
    final df = DateFormat('dd/MM/yyyy');
    final rows = <List<String>>[
      const [
        'Nome',
        'Apelido',
        'CPF',
        'RG',
        'Telefone',
        'E-mail',
        'Nascimento',
        'Modalidades',
        'Faixa',
        'Categoria',
        'Status',
        'Mensalidade',
        'Dia venc.',
        'Presencas',
        'Inicio',
      ],
    ];

    for (final s in students) {
      final primary = s.getPrimarySport();
      final def = sports[primary];
      final grade = s.getGrade(primary);
      final belt = (def != null &&
              def.gradeSystem != GradeSystem.none &&
              grade != null)
          ? getGradeLabel(primary, grade.currentGrade)
          : '';
      rows.add([
        s.fullName,
        s.nickname ?? '',
        s.cpf ?? '',
        s.rg ?? '',
        s.phone ?? '',
        s.email ?? '',
        s.birthDate != null ? df.format(s.birthDate!) : '',
        s.getSports().map((sp) => sports[sp]?.labelShort ?? sp.value).join(' / '),
        belt,
        s.category == StudentCategory.kids ? 'Infantil' : 'Adulto',
        _statusLabel(s.status),
        s.tuitionValue.toStringAsFixed(2).replaceAll('.', ','),
        s.tuitionDay.toString(),
        (s.attendanceCount ?? 0).toString(),
        df.format(s.startDate),
      ]);
    }

    final csv = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
    return '﻿$csv'; // BOM helps Excel detect UTF-8 (accents).
  }

  String _statusLabel(StudentStatus status) {
    switch (status) {
      case StudentStatus.active:
        return 'Ativo';
      case StudentStatus.injured:
        return 'Lesionado';
      case StudentStatus.inactive:
        return 'Inativo';
      case StudentStatus.suspended:
        return 'Suspenso';
    }
  }
}
