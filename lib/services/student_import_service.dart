import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';

import '../core/import_utils.dart';
import '../core/sports.dart';
import '../models/student.dart';
import 'class_service.dart';
import 'firebase_service.dart';
import 'student_service.dart';

/// Student fields a CSV column can be mapped to.
enum StudentImportField {
  ignore,
  fullName,
  nickname,
  cpf,
  rg,
  phone,
  email,
  birthDate,
  belt,
  tuitionValue,
  tuitionDay,
  weight,
  guardianName,
  guardianPhone,
}

extension StudentImportFieldX on StudentImportField {
  String get label {
    switch (this) {
      case StudentImportField.ignore:
        return 'Ignorar';
      case StudentImportField.fullName:
        return 'Nome completo';
      case StudentImportField.nickname:
        return 'Apelido';
      case StudentImportField.cpf:
        return 'CPF';
      case StudentImportField.rg:
        return 'RG';
      case StudentImportField.phone:
        return 'Telefone';
      case StudentImportField.email:
        return 'E-mail';
      case StudentImportField.birthDate:
        return 'Nascimento';
      case StudentImportField.belt:
        return 'Faixa';
      case StudentImportField.tuitionValue:
        return 'Mensalidade';
      case StudentImportField.tuitionDay:
        return 'Dia vencimento';
      case StudentImportField.weight:
        return 'Peso';
      case StudentImportField.guardianName:
        return 'Responsável';
      case StudentImportField.guardianPhone:
        return 'Tel. responsável';
    }
  }

  bool get isRequired => this == StudentImportField.fullName;
}

const Map<StudentImportField, List<String>> _fieldAliases = {
  StudentImportField.fullName: [
    'nome', 'name', 'aluno', 'nome completo', 'nome do aluno'
  ],
  StudentImportField.nickname: ['apelido', 'nickname', 'alcunha'],
  StudentImportField.cpf: ['cpf', 'documento', 'doc'],
  StudentImportField.rg: ['rg', 'identidade'],
  StudentImportField.phone: [
    'telefone', 'celular', 'fone', 'tel', 'phone', 'whatsapp', 'contato'
  ],
  StudentImportField.email: ['email', 'e-mail', 'mail'],
  StudentImportField.birthDate: [
    'nascimento', 'data de nascimento', 'aniversario', 'dn', 'birth', 'idade'
  ],
  StudentImportField.belt: ['faixa', 'graduacao', 'belt', 'grau'],
  StudentImportField.tuitionValue: ['mensalidade', 'valor', 'tuition'],
  StudentImportField.tuitionDay: [
    'dia vencimento', 'vencimento', 'dia de vencimento', 'dia'
  ],
  StudentImportField.weight: ['peso', 'weight'],
  StudentImportField.guardianName: [
    'responsavel', 'guardian', 'nome do responsavel', 'pai', 'mae'
  ],
  StudentImportField.guardianPhone: [
    'telefone responsavel', 'tel responsavel', 'contato responsavel'
  ],
};

/// One parsed CSV data row, with its mapped values and validation outcome.
class StudentImportRow {
  final int line; // 1-based data line (excludes the header)
  final Map<StudentImportField, String> values; // valid, non-empty values only
  final List<String> errors; // blocking (row skipped)
  final List<String> warnings; // non-blocking (field dropped)
  bool duplicate;
  String? duplicateReason;

  /// Whether this row is checked for import. Defaults: valid non-duplicate rows
  /// start selected; duplicates and invalid rows start unselected. The user can
  /// toggle any importable row in the preview.
  bool selected;

  StudentImportRow({
    required this.line,
    required this.values,
    required this.errors,
    required this.warnings,
    this.duplicate = false,
    this.duplicateReason,
    this.selected = true,
  });

  bool get hasError => errors.isNotEmpty;
  String get name => values[StudentImportField.fullName] ?? '';
}

/// Outcome of an import run.
class ImportReport {
  final int created;
  final int skipped; // duplicates not imported
  final int invalid; // rows with blocking errors
  final int failed; // creation threw
  final int notFitted; // dropped because the class hit its capacity
  final List<String> messages;

  /// True when the import was aborted because the device is offline. Nothing
  /// was written in this case.
  final bool offline;

  ImportReport({
    required this.created,
    required this.skipped,
    required this.invalid,
    required this.failed,
    this.notFitted = 0,
    this.messages = const [],
    this.offline = false,
  });
}

/// CSV bulk import of students into a class. Pure parsing/validation helpers
/// are static; Firestore work (loading existing students, creating + enrolling)
/// is instance-based.
class StudentImportService {
  final String academyId;
  late final StudentService _studentService;
  late final Collections _collections;

  StudentImportService(this.academyId) {
    _studentService = StudentService(academyId);
    _collections = Collections(academyId);
  }

  // ============================================
  // Parsing (pure)
  // ============================================

  /// Parses CSV text into headers + data rows. Strips BOM, normalizes line
  /// endings, and auto-detects the `,` vs `;` delimiter. All cells are strings.
  static ({List<String> headers, List<List<String>> rows}) parseCsv(
    String content,
  ) {
    var text = content;
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1); // strip UTF-8 BOM
    }
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.trim().isEmpty) return (headers: <String>[], rows: <List<String>>[]);

    final firstLine = text
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final delimiter =
        ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
            ? ';'
            : ',';

    final parsed = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(text);

    if (parsed.isEmpty) return (headers: <String>[], rows: <List<String>>[]);

    final headers =
        parsed.first.map((c) => (c ?? '').toString().trim()).toList();
    final rows = parsed
        .skip(1)
        .map((r) => r.map((c) => (c ?? '').toString()).toList())
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();
    return (headers: headers, rows: rows);
  }

  /// lowercase + trim + strip common pt-BR accents, for fuzzy matching.
  static String _norm(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c');

  /// Guesses a field for each header column. Prevents mapping two columns to
  /// the same field.
  static Map<int, StudentImportField> autoMap(List<String> headers) {
    final used = <StudentImportField>{};
    final result = <int, StudentImportField>{};
    for (var i = 0; i < headers.length; i++) {
      final h = _norm(headers[i]);
      StudentImportField match = StudentImportField.ignore;
      for (final entry in _fieldAliases.entries) {
        if (used.contains(entry.key)) continue;
        final hit = entry.value.any((a) {
          final na = _norm(a);
          return h == na || h.contains(na) || na.contains(h);
        });
        if (hit) {
          match = entry.key;
          break;
        }
      }
      result[i] = match;
      if (match != StudentImportField.ignore) used.add(match);
    }
    return result;
  }

  // ============================================
  // Row building + validation (pure)
  // ============================================

  /// Maps + validates each data row. Required: name. Optional fields that are
  /// present but invalid are dropped with a warning (never fail a whole row).
  static List<StudentImportRow> buildRows({
    required List<List<String>> dataRows,
    required Map<int, StudentImportField> mapping,
  }) {
    final rows = <StudentImportRow>[];
    for (var r = 0; r < dataRows.length; r++) {
      final cells = dataRows[r];
      final values = <StudentImportField, String>{};
      mapping.forEach((col, field) {
        if (field == StudentImportField.ignore) return;
        final v = col < cells.length ? cells[col].trim() : '';
        if (v.isNotEmpty) values[field] = v;
      });

      final errors = <String>[];
      final warnings = <String>[];

      final name = values[StudentImportField.fullName] ?? '';
      if (name.isEmpty) errors.add('Sem nome');

      void check(StudentImportField f, bool Function(String) ok, String warn) {
        final v = values[f];
        if (v != null && !ok(v)) {
          values.remove(f);
          warnings.add(warn);
        }
      }

      check(StudentImportField.cpf, ImportUtils.isValidCpf, 'CPF inválido (ignorado)');
      check(StudentImportField.email, ImportUtils.isValidEmail, 'E-mail inválido (ignorado)');
      check(StudentImportField.phone, ImportUtils.isValidPhone, 'Telefone inválido (ignorado)');
      check(StudentImportField.birthDate,
          (v) => ImportUtils.parseDate(v) != null, 'Data inválida (ignorada)');

      rows.add(StudentImportRow(
        line: r + 1,
        values: values,
        errors: errors,
        warnings: warnings,
        selected: errors.isEmpty,
      ));
    }
    return rows;
  }

  /// Flags rows that collide (by CPF > e-mail > phone) with an existing student
  /// or with an earlier row in the same file.
  static void markDuplicates(
    List<StudentImportRow> rows,
    List<Student> existing,
  ) {
    final cpfs = <String>{};
    final emails = <String>{};
    final phones = <String>{};
    for (final s in existing) {
      final c = ImportUtils.onlyDigits(s.cpf ?? '');
      if (c.length == 11) cpfs.add(c);
      final e = (s.email ?? '').toLowerCase().trim();
      if (e.isNotEmpty) emails.add(e);
      final p = ImportUtils.normalizePhone(s.phone ?? '');
      if (p != null) phones.add(p);
    }

    final seenCpf = <String>{};
    final seenEmail = <String>{};
    final seenPhone = <String>{};
    for (final row in rows) {
      row.duplicate = false;
      row.duplicateReason = null;
      if (row.hasError) continue;

      final c = ImportUtils.onlyDigits(row.values[StudentImportField.cpf] ?? '');
      final e = (row.values[StudentImportField.email] ?? '').toLowerCase().trim();
      final p = ImportUtils.normalizePhone(row.values[StudentImportField.phone] ?? '');

      String? reason;
      if (c.length == 11 && (cpfs.contains(c) || seenCpf.contains(c))) {
        reason = 'CPF já cadastrado';
      } else if (e.isNotEmpty && (emails.contains(e) || seenEmail.contains(e))) {
        reason = 'E-mail já cadastrado';
      } else if (p != null && (phones.contains(p) || seenPhone.contains(p))) {
        reason = 'Telefone já cadastrado';
      }
      row.duplicate = reason != null;
      row.duplicateReason = reason;
      // Default selection: include valid rows, leave duplicates unchecked.
      row.selected = reason == null;

      if (c.length == 11) seenCpf.add(c);
      if (e.isNotEmpty) seenEmail.add(e);
      if (p != null) seenPhone.add(p);
    }
  }

  // ============================================
  // Firestore (instance)
  // ============================================

  /// All students of the academy, for duplicate detection.
  Future<List<Student>> loadExisting() => _studentService.listAll();

  /// Creates the eligible rows as students (with the class's sport pre-set) and
  /// enrolls them in [turma] in a single array union. Skips rows with blocking
  /// errors and, unless [importDuplicates], rows flagged as duplicates.
  Future<ImportReport> importStudents({
    required BJJClass turma,
    required List<StudentImportRow> rows,
    String? createdBy,
    void Function(int done, int total)? onProgress,
  }) async {
    // Connectivity pre-check: force a server read. Offline this throws or times
    // out, so we abort before writing anything — a partial offline import
    // (some rows cached, ids unknown, enrollment incomplete) would be messy.
    DocumentSnapshot? academyDoc;
    try {
      academyDoc = await _collections.academy
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return ImportReport(
        created: 0,
        skipped: 0,
        invalid: 0,
        failed: 0,
        offline: true,
      );
    }

    final sport = turma.getSport();
    final category = turma.category ?? StudentCategory.adult;
    // Muay Thai's starting grade depends on the academy's chosen ladder; pulled
    // from the doc we just read for the connectivity check (no extra read).
    String? muaythaiVariant;
    if (sport == SportId.muaythai) {
      final academyData = academyDoc.data() as Map<String, dynamic>?;
      muaythaiVariant = academyData?['muaythaiGradeSystem'] as String?;
    }
    final grades = getGradesForSport(
      sport,
      category: category.value,
      muaythaiVariant: muaythaiVariant,
    );
    final defaultBelt = grades.isNotEmpty ? grades.first.id : 'white';

    // Only rows the user kept checked (and that have no blocking error).
    final eligible = rows.where((r) => !r.hasError && r.selected).toList();

    // Respect the class capacity: only fill the remaining slots. Overflow rows
    // are dropped (not created) and reported as "didn't fit".
    var toImport = eligible;
    var notFitted = 0;
    final max = turma.maxStudents;
    if (max != null) {
      final available = (max - turma.studentIds.length).clamp(0, eligible.length);
      if (eligible.length > available) {
        notFitted = eligible.length - available;
        toImport = eligible.sublist(0, available);
      }
    }

    final createdIds = <String>[];
    final messages = <String>[];
    var created = 0;
    var failed = 0;
    var done = 0;

    for (final row in toImport) {
      try {
        final data = _buildData(row, sport, category, grades, defaultBelt);
        final student =
            await _studentService.createFromMap(data, createdBy: createdBy);
        createdIds.add(student.id);
        created++;
      } catch (_) {
        failed++;
        messages.add('Linha ${row.line} (${row.name}): falha ao criar');
      }
      done++;
      onProgress?.call(done, toImport.length);
    }

    if (createdIds.isNotEmpty) {
      await _collections.classDoc(turma.id).update({
        'studentIds': FieldValue.arrayUnion(createdIds),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final invalid = rows.where((r) => r.hasError).length;
    final skipped = rows.where((r) => !r.hasError && !r.selected).length;

    return ImportReport(
      created: created,
      skipped: skipped,
      invalid: invalid,
      failed: failed,
      notFitted: notFitted,
      messages: messages,
    );
  }

  Map<String, dynamic> _buildData(
    StudentImportRow row,
    SportId sport,
    StudentCategory category,
    List<GradeDefinition> grades,
    String defaultBelt,
  ) {
    final v = row.values;
    final belt = _resolveBelt(v[StudentImportField.belt], grades, defaultBelt);

    final data = <String, dynamic>{
      'fullName': ImportUtils.capitalizeName(v[StudentImportField.fullName]!),
      'category': category.value,
      'status': StudentStatus.active.value,
      'currentBelt': belt,
      'currentStripes': 0,
      'sports': [sport.value],
      'sportData': {
        sport.value: {'currentGrade': belt, 'currentStripes': 0},
      },
      'primarySport': sport.value,
      'startDate': Timestamp.fromDate(DateTime.now()),
      'tuitionValue':
          ImportUtils.parseMoney(v[StudentImportField.tuitionValue] ?? '') ??
              0.0,
      'tuitionDay':
          ImportUtils.parseDay(v[StudentImportField.tuitionDay] ?? '') ?? 10,
      'isProfilePublic': false,
      'initialAttendanceCount': 0,
    };

    final nickname = v[StudentImportField.nickname];
    if (nickname != null) data['nickname'] = nickname;

    final cpf = v[StudentImportField.cpf];
    if (cpf != null) data['cpf'] = ImportUtils.onlyDigits(cpf);

    final rg = v[StudentImportField.rg];
    if (rg != null) data['rg'] = rg;

    final phone = v[StudentImportField.phone];
    if (phone != null) {
      data['phone'] = ImportUtils.normalizePhone(phone) ??
          ImportUtils.onlyDigits(phone);
    }

    final email = v[StudentImportField.email];
    if (email != null) data['email'] = email.toLowerCase();

    final birth = v[StudentImportField.birthDate];
    if (birth != null) {
      final dt = ImportUtils.parseDate(birth);
      if (dt != null) data['birthDate'] = Timestamp.fromDate(dt);
    }

    final weight = v[StudentImportField.weight];
    if (weight != null) {
      final w = ImportUtils.parseMoney(weight);
      if (w != null) data['weight'] = w;
    }

    if (category == StudentCategory.kids) {
      final gName = v[StudentImportField.guardianName];
      final gPhone = v[StudentImportField.guardianPhone];
      if (gName != null || gPhone != null) {
        data['guardian'] = {
          if (gName != null) 'name': ImportUtils.capitalizeName(gName),
          if (gPhone != null)
            'phone': ImportUtils.normalizePhone(gPhone) ??
                ImportUtils.onlyDigits(gPhone),
        };
      }
    }

    return data;
  }

  String _resolveBelt(
    String? cell,
    List<GradeDefinition> grades,
    String fallback,
  ) {
    if (cell == null || grades.isEmpty) return fallback;
    final n = _norm(cell);
    for (final g in grades) {
      if (_norm(g.id) == n || _norm(g.label) == n) return g.id;
    }
    return fallback;
  }
}
