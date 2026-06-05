import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/combo_templates.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/combo.dart';
import '../../services/combo_service.dart';
import '../../services/firebase_service.dart';
import '../../widgets/polish/polish.dart';

const _strikingSports = [SportId.muaythai, SportId.boxing, SportId.kickboxing];

String _sportLabel(String v) {
  switch (v) {
    case 'boxing':
      return 'Boxe';
    case 'kickboxing':
      return 'Kickboxing';
    case 'muaythai':
      return 'Muay Thai';
    default:
      return v;
  }
}

/// Admin "Combinações" (C2) — striking combos library, grouped by level, per
/// sport, with seed + CRUD. Staff only.
class CombosScreen extends StatefulWidget {
  const CombosScreen({super.key});

  @override
  State<CombosScreen> createState() => _CombosScreenState();
}

class _CombosScreenState extends State<CombosScreen> {
  late final ComboService _service = ComboService(FirebaseService.academyId);

  String _sport = SportId.muaythai.value;
  bool _loading = true;
  bool _seeding = false;
  List<Combo> _all = [];

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
        _all = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Combo> get _forSport =>
      (_all.where((c) => c.sport == _sport).toList()
        ..sort((a, b) {
          final l = comboLevelOrder(a.level).compareTo(comboLevelOrder(b.level));
          return l != 0 ? l : a.order.compareTo(b.order);
        }));

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      await _service.createMany(
          comboTemplates(createdBy: FirebaseService.currentUserId ?? ''));
      await _load();
    } catch (e) {
      _snack('Erro ao popular: $e');
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openForm({Combo? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ComboForm(
        service: _service,
        defaultSport: _sport,
        existing: existing,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Combo c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir combinação?'),
        content: Text(c.name),
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
      await _service.delete(c.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _forSport;
    return Scaffold(
      appBar: AppBar(title: const Text('Combinações')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Nova'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              children: _strikingSports
                  .map((s) => ChoiceChip(
                        label: Text(_sportLabel(s.value)),
                        selected: _sport == s.value,
                        onSelected: (_) => setState(() => _sport = s.value),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: PolishSkeleton.list(count: 6, scrollable: false))
                : list.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _groupedList(list),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    // The seed inserts templates for ALL striking sports, so only offer it when
    // the whole library is empty — otherwise it would duplicate existing combos.
    final canSeed = _all.isEmpty;
    return ListView(
      children: [
        const SizedBox(height: 60),
        PolishedEmptyState(
          icon: LucideIcons.swords,
          title: 'Nenhuma combinação',
          subtitle: canSeed
              ? 'Crie combinações para ${_sportLabel(_sport)} ou comece com modelos prontos.'
              : 'Nenhuma combinação para ${_sportLabel(_sport)}. Toque em "Nova" para adicionar.',
        ),
        if (canSeed) ...[
          const SizedBox(height: 12),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: _seeding ? null : _seed,
              icon: _seeding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.sparkles),
              label: const Text('Usar modelos prontos'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _groupedList(List<Combo> list) {
    final children = <Widget>[];
    String? lastLevel;
    for (final c in list) {
      if (c.level != lastLevel) {
        lastLevel = c.level;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(comboLevelLabel(c.level),
              style:
                  AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700)),
        ));
      }
      children.add(_comboCard(c));
    }
    return ListView(
        padding: const EdgeInsets.only(bottom: 88), children: children);
  }

  Widget _comboCard(Combo c) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: ListTile(
        onTap: () => _openForm(existing: c),
        title: Text(c.name,
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text([
          c.strikes.join(' · '),
          if (c.videoUrl != null && c.videoUrl!.isNotEmpty) '🎬 com vídeo',
        ].where((e) => e.isNotEmpty).join('\n')),
        isThreeLine: c.strikes.isNotEmpty,
        trailing: IconButton(
          icon: const Icon(LucideIcons.trash2, size: 18),
          color: AppTheme.error,
          onPressed: () => _delete(c),
        ),
      ),
    );
  }
}

/// Add/edit a combo (staff).
class _ComboForm extends StatefulWidget {
  final ComboService service;
  final String defaultSport;
  final Combo? existing;

  const _ComboForm({
    required this.service,
    required this.defaultSport,
    this.existing,
  });

  @override
  State<_ComboForm> createState() => _ComboFormState();
}

class _ComboFormState extends State<_ComboForm> {
  late String _sport;
  late String _level;
  late final TextEditingController _name;
  late final TextEditingController _strikes;
  late final TextEditingController _desc;
  late final TextEditingController _video;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _sport = e?.sport ?? widget.defaultSport;
    _level = e?.level ?? 'iniciante';
    _name = TextEditingController(text: e?.name ?? '');
    _strikes = TextEditingController(text: e?.strikes.join(', ') ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _video = TextEditingController(text: e?.videoUrl ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _strikes.dispose();
    _desc.dispose();
    _video.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe o nome.')));
      return;
    }
    setState(() => _saving = true);
    final strikes = _strikes.text
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final combo = Combo(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      sport: _sport,
      level: _level,
      strikes: strikes,
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      videoUrl: _video.text.trim().isEmpty ? null : _video.text.trim(),
      order: widget.existing?.order ?? 999,
      createdBy: widget.existing?.createdBy ??
          (FirebaseService.currentUserId ?? ''),
    );
    try {
      if (widget.existing != null) {
        await widget.service.update(widget.existing!.id, combo);
      } else {
        await widget.service.create(combo);
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
            Text(widget.existing == null ? 'Nova combinação' : 'Editar combinação',
                style: AppTheme.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Nome (ex.: 1-2-3)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sport,
                    decoration: const InputDecoration(
                        labelText: 'Modalidade',
                        border: OutlineInputBorder()),
                    items: _strikingSports
                        .map((s) => DropdownMenuItem(
                            value: s.value, child: Text(_sportLabel(s.value))))
                        .toList(),
                    onChanged: (v) => setState(() => _sport = v ?? _sport),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _level,
                    decoration: const InputDecoration(
                        labelText: 'Nível', border: OutlineInputBorder()),
                    items: comboLevels
                        .map((l) => DropdownMenuItem(
                            value: l, child: Text(comboLevelLabel(l))))
                        .toList(),
                    onChanged: (v) => setState(() => _level = v ?? _level),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _strikes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Golpes (separados por vírgula)',
                hintText: 'Jab, Direto, Cruzado',
                border: OutlineInputBorder(),
              ),
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
              controller: _desc,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                  border: OutlineInputBorder()),
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
                    : const Text('Salvar combinação'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
