import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/mesocycle.dart';
import '../../models/workout_plan.dart' show WorkoutAudience;
import '../../services/firebase_service.dart';
import '../../services/mesocycle_service.dart';
import '../../widgets/polish/polish.dart';

/// Admin "Periodização" (E1) — list of mesocycles + editor (weeks builder).
class MesocyclesScreen extends StatefulWidget {
  const MesocyclesScreen({super.key});

  @override
  State<MesocyclesScreen> createState() => _MesocyclesScreenState();
}

class _MesocyclesScreenState extends State<MesocyclesScreen> {
  late final MesocycleService _service =
      MesocycleService(FirebaseService.academyId);
  bool _loading = true;
  List<Mesocycle> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.listAll();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({Mesocycle? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _MesocycleEditScreen(service: _service, existing: existing),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Periodização')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Novo'),
      ),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: PolishSkeleton.list(count: 5, scrollable: false))
          : _items.isEmpty
              ? const PolishedEmptyState(
                  icon: LucideIcons.calendarRange,
                  title: 'Nenhum mesociclo',
                  subtitle:
                      'Crie um programa de várias semanas (ex.: força, hipertrofia, deload).',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    children: _items.map(_card).toList(),
                  ),
                ),
    );
  }

  Widget _card(Mesocycle m) {
    final audLabel = m.audience == WorkoutAudience.academy
        ? 'Toda a academia'
        : m.audience == WorkoutAudience.sport
            ? 'Por modalidade'
            : 'Alunos específicos';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _edit(existing: m),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
          child: const Icon(LucideIcons.calendarRange,
              size: 18, color: AppTheme.primary),
        ),
        title: Text(m.name,
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text('${m.totalWeeks} semanas · $audLabel'
            '${m.active ? '' : ' · inativo'}'),
        trailing: const Icon(LucideIcons.chevronRight),
      ),
    );
  }
}

class _MesocycleEditScreen extends StatefulWidget {
  final MesocycleService service;
  final Mesocycle? existing;
  const _MesocycleEditScreen({required this.service, this.existing});

  @override
  State<_MesocycleEditScreen> createState() => _MesocycleEditScreenState();
}

class _MesocycleEditScreenState extends State<_MesocycleEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late WorkoutAudience _audience;
  String? _sport;
  DateTime? _startDate;
  bool _active = true;
  late List<_WeekDraft> _weeks;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _audience = e?.audience ?? WorkoutAudience.academy;
    _sport = e?.sport;
    _startDate = e?.startDate;
    _active = e?.active ?? true;
    _weeks = (e?.weeks ?? const [])
        .map((w) => _WeekDraft(
              focus: TextEditingController(text: w.focus),
              prescription: TextEditingController(text: w.prescription),
              deload: w.deload,
            ))
        .toList();
    if (_weeks.isEmpty) _addWeek();
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    for (final w in _weeks) {
      w.focus.dispose();
      w.prescription.dispose();
    }
    super.dispose();
  }

  void _addWeek() {
    setState(() => _weeks.add(_WeekDraft(
        focus: TextEditingController(),
        prescription: TextEditingController(),
        deload: false)));
  }

  void _removeWeek(int i) {
    setState(() {
      _weeks[i].focus.dispose();
      _weeks[i].prescription.dispose();
      _weeks.removeAt(i);
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe o nome.')));
      return;
    }
    setState(() => _saving = true);
    final weeks = <MesoWeek>[];
    for (var i = 0; i < _weeks.length; i++) {
      weeks.add(MesoWeek(
        index: i + 1,
        focus: _weeks[i].focus.text.trim(),
        prescription: _weeks[i].prescription.text.trim(),
        deload: _weeks[i].deload,
      ));
    }
    final m = Mesocycle(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      sport: _audience == WorkoutAudience.sport ? _sport : null,
      audience: _audience,
      assignedStudentIds: widget.existing?.assignedStudentIds ?? const [],
      startDate: _startDate,
      weeks: weeks,
      active: _active,
      createdBy: widget.existing?.createdBy ??
          (FirebaseService.currentUserId ?? ''),
    );
    try {
      if (widget.existing != null) {
        await widget.service.update(widget.existing!.id, m);
      } else {
        await widget.service.create(m);
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

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir mesociclo?'),
        content: Text(widget.existing!.name),
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
      await widget.service.delete(widget.existing!.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Novo mesociclo' : 'Editar mesociclo'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(LucideIcons.trash2),
              color: AppTheme.error,
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Nome (ex.: Bloco de força)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Text('Para quem', style: AppTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Toda a academia'),
                selected: _audience == WorkoutAudience.academy,
                onSelected: (_) =>
                    setState(() => _audience = WorkoutAudience.academy),
              ),
              ChoiceChip(
                label: const Text('Por modalidade'),
                selected: _audience == WorkoutAudience.sport,
                onSelected: (_) =>
                    setState(() => _audience = WorkoutAudience.sport),
              ),
            ],
          ),
          if (_audience == WorkoutAudience.sport) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _sport,
              decoration: const InputDecoration(
                  labelText: 'Modalidade', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: null, child: Text('Qualquer')),
                DropdownMenuItem(value: 'musculacao', child: Text('Musculação')),
                DropdownMenuItem(value: 'muaythai', child: Text('Muay Thai')),
                DropdownMenuItem(value: 'boxing', child: Text('Boxe')),
                DropdownMenuItem(value: 'kickboxing', child: Text('Kickboxing')),
                DropdownMenuItem(value: 'bjj', child: Text('Jiu-Jitsu')),
              ],
              onChanged: (v) => setState(() => _sport = v),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickStart,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Início (opcional)',
                        border: OutlineInputBorder()),
                    child: Text(_startDate == null
                        ? 'Sem data — só lista as semanas'
                        : '${_startDate!.day.toString().padLeft(2, '0')}/${_startDate!.month.toString().padLeft(2, '0')}/${_startDate!.year}'),
                  ),
                ),
              ),
              if (_startDate != null)
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => setState(() => _startDate = null),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ativo'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Text('Semanas (${_weeks.length})',
                  style:
                      AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: _addWeek,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Semana'),
              ),
            ],
          ),
          for (var i = 0; i < _weeks.length; i++) _weekCard(i),
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
                  : const Text('Salvar mesociclo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekCard(int i) {
    final w = _weeks[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text('Semana ${i + 1}',
                    style: AppTheme.bodyMedium
                        .copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  color: AppTheme.error,
                  onPressed:
                      _weeks.length > 1 ? () => _removeWeek(i) : null,
                ),
              ],
            ),
            TextField(
              controller: w.focus,
              decoration: const InputDecoration(
                  labelText: 'Foco (ex.: Força)', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: w.prescription,
              decoration: const InputDecoration(
                  labelText: 'Prescrição (ex.: 5x5 @ pesado)', isDense: true),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Semana de deload (descarga)'),
              value: w.deload,
              onChanged: (v) => setState(() => w.deload = v),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }
}

class _WeekDraft {
  final TextEditingController focus;
  final TextEditingController prescription;
  bool deload;
  _WeekDraft(
      {required this.focus, required this.prescription, required this.deload});
}
