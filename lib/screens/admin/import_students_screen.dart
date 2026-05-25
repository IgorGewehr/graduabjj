import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';

/// Bulk student import wizard: pick a CSV + target class, map columns,
/// preview/validate (with duplicate detection), then import.
class ImportStudentsScreen extends ConsumerStatefulWidget {
  const ImportStudentsScreen({super.key});

  @override
  ConsumerState<ImportStudentsScreen> createState() =>
      _ImportStudentsScreenState();
}

class _ImportStudentsScreenState extends ConsumerState<ImportStudentsScreen> {
  late final StudentImportService _service =
      StudentImportService(FirebaseService.academyId);

  int _step = 0; // 0 = file+turma, 1 = mapping, 2 = preview, 3 = result
  bool _busy = false;

  List<BJJClass> _classes = [];
  BJJClass? _turma;

  String? _fileName;
  List<String> _headers = [];
  List<List<String>> _dataRows = [];
  Map<int, StudentImportField> _mapping = {};
  List<StudentImportRow> _rows = [];
  List<Student> _existing = [];

  bool _importDuplicates = false;
  double _progress = 0;
  ImportReport? _report;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() => _busy = true);
    try {
      _classes = await ClassService(FirebaseService.academyId).list();
      _existing = await _service.loadExisting();
    } catch (_) {
      _classes = [];
      _existing = [];
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      content = latin1.decode(bytes); // old Excel exports
    }

    final parsed = StudentImportService.parseCsv(content);
    if (parsed.headers.isEmpty || parsed.rows.isEmpty) {
      if (mounted) context.showError('Planilha vazia ou sem dados.');
      return;
    }
    setState(() {
      _fileName = file.name;
      _headers = parsed.headers;
      _dataRows = parsed.rows;
      _mapping = StudentImportService.autoMap(parsed.headers);
    });
    _rebuildRows();
  }

  void _rebuildRows() {
    final rows = StudentImportService.buildRows(
      dataRows: _dataRows,
      mapping: _mapping,
    );
    StudentImportService.markDuplicates(rows, _existing);
    setState(() => _rows = rows);
  }

  bool get _nameMapped =>
      _mapping.values.contains(StudentImportField.fullName);

  int get _validCount => _rows
      .where((r) => !r.hasError && (_importDuplicates || !r.duplicate))
      .length;
  int get _dupCount => _rows.where((r) => !r.hasError && r.duplicate).length;
  int get _invalidCount => _rows.where((r) => r.hasError).length;

  /// Remaining slots in the class (null = unlimited).
  int? get _availableSlots {
    final max = _turma?.maxStudents;
    if (max == null) return null;
    return (max - _turma!.studentIds.length).clamp(0, 1 << 30);
  }

  /// How many eligible rows won't fit in the class.
  int get _overflow {
    final avail = _availableSlots;
    if (avail == null) return 0;
    return (_validCount - avail).clamp(0, _validCount);
  }

  Future<void> _runImport() async {
    if (_turma == null) return;
    setState(() {
      _busy = true;
      _step = 3;
      _progress = 0;
    });
    final user = await ref.read(currentUserProvider.future);
    try {
      final report = await _service.importStudents(
        turma: _turma!,
        rows: _rows,
        importDuplicates: _importDuplicates,
        createdBy: user?.id,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _progress = total == 0 ? 1 : done / total);
          }
        },
      );
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) context.showError('Erro na importacao.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Warns + asks for confirmation when the import would exceed the class
  /// capacity; the overflow rows are dropped (not created).
  Future<void> _confirmAndImport() async {
    if (_overflow > 0) {
      final avail = _availableSlots ?? 0;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Turma sem vagas suficientes'),
          content: Text(
            'A turma "${_turma!.name}" tem $avail vaga(s) livre(s) e voce esta '
            'importando $_validCount aluno(s). $_overflow nao vao caber e serao '
            'descartados (nao serao criados). Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    _runImport();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Importar alunos (CSV)'),
        backgroundColor: AppTheme.surface,
      ),
      body: _busy && _step != 3
          ? const Center(child: CircularProgressIndicator())
          : switch (_step) {
              0 => _buildFileStep(),
              1 => _buildMappingStep(),
              2 => _buildPreviewStep(),
              _ => _buildResultStep(),
            },
    );
  }

  // ---------- Step 0: file + class ----------
  Widget _buildFileStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('1. Turma de destino',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Os alunos serao criados e matriculados nesta turma. A modalidade e a categoria vem da turma.',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<BJJClass>(
          initialValue: _turma,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Turma',
            border: OutlineInputBorder(),
          ),
          items: _classes
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(
                      '${c.name} · ${sports[c.getSport()]?.labelShort ?? ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (c) => setState(() => _turma = c),
        ),
        const SizedBox(height: 24),
        Text('2. Arquivo CSV',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'A primeira linha deve conter os titulos das colunas (Nome, CPF, Telefone...).',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file),
          label: Text(_fileName == null ? 'Selecionar CSV' : 'Trocar arquivo'),
        ),
        if (_fileName != null) ...[
          const SizedBox(height: 6),
          Text(
            '$_fileName · ${_dataRows.length} linha(s)',
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: (_turma != null && _headers.isNotEmpty)
              ? () => setState(() => _step = 1)
              : null,
          child: const Text('Proximo: mapear colunas'),
        ),
      ],
    );
  }

  // ---------- Step 1: mapping ----------
  Widget _buildMappingStep() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Confirme para onde vai cada coluna da planilha. "Nome" e obrigatorio.',
                style:
                    AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              ..._headers.asMap().entries.map((e) {
                final sample = _dataRows.isNotEmpty &&
                        e.key < _dataRows.first.length
                    ? _dataRows.first[e.key]
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.value,
                                style: AppTheme.bodyMedium
                                    .copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                            if (sample.isNotEmpty)
                              Text('ex: $sample',
                                  style: AppTheme.labelSmall.copyWith(
                                      color: AppTheme.textSecondary),
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<StudentImportField>(
                        value: _mapping[e.key] ?? StudentImportField.ignore,
                        onChanged: (f) {
                          if (f == null) return;
                          setState(() => _mapping[e.key] = f);
                          _rebuildRows();
                        },
                        items: StudentImportField.values
                            .map((f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(f.label),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        _buildNavBar(
          onBack: () => setState(() => _step = 0),
          onNext: _nameMapped ? () => setState(() => _step = 2) : null,
          nextLabel: 'Proximo: revisar',
          hint: _nameMapped ? null : 'Mapeie a coluna "Nome" para continuar',
        ),
      ],
    );
  }

  // ---------- Step 2: preview ----------
  Widget _buildPreviewStep() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _statChip('${_validCount} a importar', AppTheme.success),
              const SizedBox(width: 8),
              _statChip('$_dupCount duplicados', AppTheme.warning),
              const SizedBox(width: 8),
              _statChip('$_invalidCount invalidos', AppTheme.error),
            ],
          ),
        ),
        if (_turma?.maxStudents != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.groups_outlined,
                    size: 16,
                    color: _overflow > 0
                        ? AppTheme.warning
                        : AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Turma: ${_turma!.studentIds.length}/${_turma!.maxStudents} · ${_availableSlots} vaga(s)'
                    '${_overflow > 0 ? ' · $_overflow nao caberao' : ''}',
                    style: AppTheme.labelSmall.copyWith(
                      color: _overflow > 0
                          ? AppTheme.warning
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_dupCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Importar duplicados mesmo assim'),
              subtitle: Text(
                _importDuplicates
                    ? 'Os $_dupCount duplicados SERAO criados.'
                    : 'Os $_dupCount duplicados serao descartados.',
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary),
              ),
              value: _importDuplicates,
              onChanged: (v) => setState(() => _importDuplicates = v),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _rows.length,
            separatorBuilder: (_, _) => const Divider(height: 12),
            itemBuilder: (context, i) => _rowTile(_rows[i]),
          ),
        ),
        _buildNavBar(
          onBack: () => setState(() => _step = 1),
          onNext: _validCount > 0 ? _confirmAndImport : null,
          nextLabel: 'Importar $_validCount aluno(s)',
        ),
      ],
    );
  }

  Widget _rowTile(StudentImportRow row) {
    final (icon, color, status) = row.hasError
        ? (Icons.error_outline, AppTheme.error, row.errors.join(', '))
        : row.duplicate
            ? (Icons.content_copy, AppTheme.warning, row.duplicateReason ?? 'Duplicado')
            : (Icons.check_circle_outline, AppTheme.success,
                row.warnings.isEmpty ? 'OK' : row.warnings.join(', '));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.name.isEmpty ? '(sem nome) · linha ${row.line}' : row.name,
                style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(status,
                  style: AppTheme.labelSmall.copyWith(color: color)),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Step 3: result ----------
  Widget _buildResultStep() {
    if (_report == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(value: _progress),
            ),
            const SizedBox(height: 12),
            Text('Importando... ${(_progress * 100).round()}%',
                style: AppTheme.bodyMedium),
          ],
        ),
      );
    }
    final r = _report!;
    if (r.offline) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: AppTheme.error, size: 56),
              const SizedBox(height: 12),
              Text('Sem conexao com a internet',
                  style: AppTheme.titleMedium
                      .copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Nenhum aluno foi importado. Conecte-se a internet e tente novamente.',
                style: AppTheme.bodyMedium
                    .copyWith(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => setState(() {
                  _report = null;
                  _step = 2;
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.check_circle, color: AppTheme.success, size: 56),
        const SizedBox(height: 12),
        Text('Importacao concluida',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        _resultLine('Criados', r.created, AppTheme.success),
        _resultLine('Duplicados descartados', r.skipped, AppTheme.warning),
        _resultLine('Nao couberam (turma cheia)', r.notFitted, AppTheme.warning),
        _resultLine('Invalidos (sem nome)', r.invalid, AppTheme.error),
        _resultLine('Falhas', r.failed, AppTheme.error),
        if (r.messages.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Detalhes',
              style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...r.messages.map((m) => Text('• $m',
              style: AppTheme.labelSmall
                  .copyWith(color: AppTheme.textSecondary))),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Concluir'),
        ),
      ],
    );
  }

  Widget _resultLine(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppTheme.bodyMedium)),
          Text('$value',
              style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _statChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: AppTheme.labelSmall
              .copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildNavBar({
    required VoidCallback onBack,
    required VoidCallback? onNext,
    required String nextLabel,
    String? hint,
  }) {
    return Material(
      elevation: 8,
      color: AppTheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(hint,
                      style: AppTheme.labelSmall
                          .copyWith(color: AppTheme.textSecondary)),
                ),
              Row(
                children: [
                  TextButton(onPressed: onBack, child: const Text('Voltar')),
                  const Spacer(),
                  FilledButton(onPressed: onNext, child: Text(nextLabel)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
