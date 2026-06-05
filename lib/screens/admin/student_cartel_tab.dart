import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/cartel.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/fight_record.dart';
import '../../models/student.dart';
import '../../services/firebase_service.dart';
import '../../services/fight_record_service.dart';
import '../../widgets/polish/polish.dart';

const _strikingSports = [SportId.muaythai, SportId.boxing, SportId.kickboxing];

String _sportLabel(String? v) {
  switch (v) {
    case 'boxing':
      return 'Boxe';
    case 'kickboxing':
      return 'Kickboxing';
    case 'muaythai':
      return 'Muay Thai';
    default:
      return '';
  }
}

Color _resultColor(FightResult r) {
  switch (r) {
    case FightResult.win:
      return AppTheme.success;
    case FightResult.loss:
      return AppTheme.error;
    case FightResult.draw:
      return AppTheme.warning;
    case FightResult.nc:
      return AppTheme.textSecondary;
  }
}

/// Admin "Cartel" tab inside student detail (C3): official fight record with
/// summary + staff CRUD. Read-side for the student lives in the portal.
class StudentCartelTab extends StatefulWidget {
  final Student student;
  const StudentCartelTab({super.key, required this.student});

  @override
  State<StudentCartelTab> createState() => _StudentCartelTabState();
}

class _StudentCartelTabState extends State<StudentCartelTab> {
  late final FightRecordService _service =
      FightRecordService(FirebaseService.academyId);

  bool _loading = true;
  List<FightRecord> _fights = [];

  List<String> get _sportOptions {
    final s = widget.student
        .getSports()
        .where(_strikingSports.contains)
        .map((e) => e.value)
        .toList();
    return s.isNotEmpty ? s : _strikingSports.map((e) => e.value).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.getByStudent(widget.student.id);
      if (!mounted) return;
      setState(() {
        _fights = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({FightRecord? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FightFormSheet(
        sportOptions: _sportOptions,
        studentId: widget.student.id,
        studentName: widget.student.fullName,
        existing: existing,
        service: _service,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(FightRecord f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir luta?'),
        content: Text('${f.result.label} · ${f.event}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.delete(f.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: PolishSkeleton.list(count: 4, scrollable: false),
      );
    }
    final summary = summarizeCartel(_fights.map((f) => f.pair));
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _summaryCard(summary),
              const SizedBox(height: 16),
              if (_fights.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: PolishedEmptyState(
                    icon: LucideIcons.swords,
                    title: 'Sem lutas registradas',
                    subtitle: 'Adicione as lutas para montar o cartel oficial.',
                  ),
                )
              else
                ..._fights.map(_fightCard),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _openForm(),
            icon: const Icon(LucideIcons.plus),
            label: const Text('Adicionar luta'),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(CartelSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(s.record,
                style: AppTheme.headlineMedium.copyWith(
                    fontWeight: FontWeight.w800, color: AppTheme.primary)),
            const SizedBox(height: 4),
            Text('${s.total} ${s.total == 1 ? 'luta' : 'lutas'}',
                style: AppTheme.bodySmall
                    .copyWith(color: AppTheme.textSecondary)),
            if (s.koWins > 0 || s.subWins > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (s.koWins > 0) _chip('${s.koWins} por nocaute'),
                  if (s.subWins > 0) _chip('${s.subWins} por finalização'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String t) => Chip(
        label: Text(t, style: AppTheme.bodySmall),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _fightCard(FightRecord f) {
    final dd = f.date.day.toString().padLeft(2, '0');
    final mm = f.date.month.toString().padLeft(2, '0');
    final color = _resultColor(f.result);
    final sub = <String>[
      f.method.label,
      if (f.opponent != null && f.opponent!.isNotEmpty) 'vs ${f.opponent}',
      if (f.weightClass != null && f.weightClass!.isNotEmpty) f.weightClass!,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openForm(existing: f),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(f.result.tag,
              style: AppTheme.bodyMedium
                  .copyWith(color: color, fontWeight: FontWeight.w800)),
        ),
        title: Text('${f.event} · $dd/$mm/${f.date.year}',
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text([
          sub.join(' · '),
          if (f.sport != null) _sportLabel(f.sport),
        ].where((e) => e.isNotEmpty).join('\n')),
        isThreeLine: f.sport != null,
        trailing: IconButton(
          icon: const Icon(LucideIcons.trash2, size: 18),
          color: AppTheme.error,
          onPressed: () => _delete(f),
        ),
      ),
    );
  }
}

/// Add/edit a fight (staff).
class _FightFormSheet extends StatefulWidget {
  final List<String> sportOptions;
  final String studentId;
  final String studentName;
  final FightRecord? existing;
  final FightRecordService service;

  const _FightFormSheet({
    required this.sportOptions,
    required this.studentId,
    required this.studentName,
    required this.service,
    this.existing,
  });

  @override
  State<_FightFormSheet> createState() => _FightFormSheetState();
}

class _FightFormSheetState extends State<_FightFormSheet> {
  late String _sport;
  late FightResult _result;
  late FightMethod _method;
  late DateTime _date;
  late final TextEditingController _event;
  late final TextEditingController _opponent;
  late final TextEditingController _weight;
  late final TextEditingController _rounds;
  late final TextEditingController _video;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _sport = e?.sport ?? widget.sportOptions.first;
    _result = e?.result ?? FightResult.win;
    _method = e?.method ?? FightMethod.decision;
    _date = e?.date ?? DateTime.now();
    _event = TextEditingController(text: e?.event ?? '');
    _opponent = TextEditingController(text: e?.opponent ?? '');
    _weight = TextEditingController(text: e?.weightClass ?? '');
    _rounds = TextEditingController(text: e?.rounds?.toString() ?? '');
    _video = TextEditingController(text: e?.videoUrl ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    _event.dispose();
    _opponent.dispose();
    _weight.dispose();
    _rounds.dispose();
    _video.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_event.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o evento.')));
      return;
    }
    setState(() => _saving = true);
    final record = FightRecord(
      id: widget.existing?.id ?? '',
      studentId: widget.studentId,
      studentName: widget.studentName,
      sport: _sport,
      result: _result,
      method: _method,
      event: _event.text.trim(),
      date: _date,
      opponent: _opponent.text.trim().isEmpty ? null : _opponent.text.trim(),
      weightClass: _weight.text.trim().isEmpty ? null : _weight.text.trim(),
      rounds: int.tryParse(_rounds.text.trim()),
      videoUrl: _video.text.trim().isEmpty ? null : _video.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdBy: FirebaseService.currentUserId ?? '',
    );
    try {
      if (widget.existing != null) {
        await widget.service.update(widget.existing!.id, record);
      } else {
        await widget.service.create(record);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Adicionar luta' : 'Editar luta',
                style: AppTheme.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('Resultado', style: AppTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: FightResult.values
                  .map((r) => ChoiceChip(
                        label: Text(r.label),
                        selected: _result == r,
                        onSelected: (_) => setState(() => _result = r),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FightMethod>(
              initialValue: _method,
              decoration: const InputDecoration(
                  labelText: 'Método', border: OutlineInputBorder()),
              items: FightMethod.values
                  .map((m) =>
                      DropdownMenuItem(value: m, child: Text(m.label)))
                  .toList(),
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
            const SizedBox(height: 12),
            if (widget.sportOptions.length > 1) ...[
              Wrap(
                spacing: 8,
                children: widget.sportOptions
                    .map((v) => ChoiceChip(
                          label: Text(_sportLabel(v)),
                          selected: _sport == v,
                          onSelected: (_) => setState(() => _sport = v),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _event,
              decoration: const InputDecoration(
                  labelText: 'Evento *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Data', border: OutlineInputBorder()),
                child: Text(
                    '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _opponent,
              decoration: const InputDecoration(
                  labelText: 'Adversário', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weight,
                    decoration: const InputDecoration(
                        labelText: 'Categoria de peso',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _rounds,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Rounds', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _video,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Link do vídeo (opcional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notas', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Salvar luta'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }
}
