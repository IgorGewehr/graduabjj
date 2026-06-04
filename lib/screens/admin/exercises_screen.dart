import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/exercise_templates.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../services/exercise_service.dart';
import '../../services/firebase_service.dart';
import '../../widgets/form/input_field.dart';

/// Admin: catálogo de exercícios da academia (A5). CRUD + seed.
class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  List<Exercise> _exercises = [];
  bool _loading = true;
  bool _seeding = false;

  ExerciseService get _service => ExerciseService(FirebaseService.academyId);

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
        _exercises = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showError('Erro ao carregar catálogo: $e');
    }
  }

  Future<void> _openForm({Exercise? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ExerciseFormSheet(
          academyId: FirebaseService.academyId,
          existing: existing,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Exercise e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover exercício'),
        content: Text('Remover "${e.name}" do catálogo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(e.id);
      _load();
    } catch (err) {
      if (mounted) context.showError('Não foi possível remover: $err');
    }
  }

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      final uid = FirebaseService.currentUserId ?? '';
      final items = musculacaoStarterCatalog
          .map((s) => Exercise(
                id: '',
                name: s.name,
                muscleGroup: s.muscleGroup,
                equipment: s.equipment,
                createdBy: uid,
                createdAt: DateTime.now(),
              ))
          .toList();
      await _service.createMany(items);
      if (!mounted) return;
      context.showSuccess('Catálogo básico adicionado! Edite à vontade.');
      _load();
    } catch (e) {
      if (mounted) context.showError('Não foi possível semear: $e');
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: const Text('Catálogo de exercícios'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _body(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Novo exercício'),
      ),
    );
  }

  Widget _body() {
    if (_exercises.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.dumbbell, size: 48, color: AppTheme.textDisabled),
              const SizedBox(height: 12),
              Text('Catálogo vazio',
                  style: AppTheme.bodyMedium
                      .copyWith(color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              Text('Toque em "Novo exercício" para começar.',
                  textAlign: TextAlign.center,
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textDisabled)),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _seeding ? null : _seed,
                icon: _seeding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.sparkles, size: 16),
                label: const Text('Usar catálogo básico de musculação'),
              ),
            ],
          ),
        ),
      );
    }

    // Agrupa por grupo muscular, na ordem de `muscleGroups`.
    final byGroup = <String, List<Exercise>>{};
    for (final e in _exercises) {
      byGroup.putIfAbsent(e.muscleGroup, () => []).add(e);
    }
    final orderedGroups = <String>[
      for (final g in muscleGroups.keys)
        if (byGroup.containsKey(g)) g,
      ...byGroup.keys.where((g) => !muscleGroups.containsKey(g)),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        for (final g in orderedGroups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(muscleGroups[g] ?? g,
                style:
                    AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final e in byGroup[g]!) _exerciseRow(e),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _exerciseRow(Exercise e) {
    final sub = [
      if (e.equipmentLabel != null) e.equipmentLabel!,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: ListTile(
        onTap: () => _openForm(existing: e),
        title: Text(e.name, style: AppTheme.bodyMedium),
        subtitle: (sub.isEmpty && (e.videoUrl ?? '').isEmpty)
            ? null
            : Row(
                children: [
                  if (sub.isNotEmpty)
                    Text(sub,
                        style: AppTheme.labelSmall
                            .copyWith(color: AppTheme.textSecondary)),
                  if ((e.videoUrl ?? '').isNotEmpty) ...[
                    if (sub.isNotEmpty) const SizedBox(width: 8),
                    Icon(LucideIcons.video,
                        size: 12, color: AppTheme.textSecondary),
                  ],
                ],
              ),
        trailing: IconButton(
          icon: const Icon(LucideIcons.trash2, size: 18),
          color: AppTheme.textSecondary,
          onPressed: () => _delete(e),
        ),
      ),
    );
  }
}

/// Bottom-sheet de criar/editar exercício. Persiste e pop(true) no sucesso.
class _ExerciseFormSheet extends StatefulWidget {
  final String academyId;
  final Exercise? existing;

  const _ExerciseFormSheet({required this.academyId, required this.existing});

  @override
  State<_ExerciseFormSheet> createState() => _ExerciseFormSheetState();
}

class _ExerciseFormSheetState extends State<_ExerciseFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _videoUrl;
  late String _muscleGroup;
  String? _equipment;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _videoUrl = TextEditingController(text: e?.videoUrl ?? '');
    // Coage valores fora das listas conhecidas para evitar crash do dropdown
    // (value precisa existir nos items).
    final mg = e?.muscleGroup;
    _muscleGroup = (mg != null && muscleGroups.containsKey(mg))
        ? mg
        : muscleGroups.keys.first;
    final eq = e?.equipment;
    _equipment = (eq != null && equipmentTypes.containsKey(eq)) ? eq : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _videoUrl.dispose();
    super.dispose();
  }

  String? _trim(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final service = ExerciseService(widget.academyId);
      final e = widget.existing;
      if (e == null) {
        await service.create(Exercise(
          id: '',
          name: _name.text.trim(),
          description: _trim(_description),
          videoUrl: _trim(_videoUrl),
          muscleGroup: _muscleGroup,
          equipment: _equipment,
          createdBy: FirebaseService.currentUserId ?? '',
          createdAt: DateTime.now(),
        ));
      } else {
        await service.update(
          e.id,
          e.copyWith(
            name: _name.text.trim(),
            description: _trim(_description),
            videoUrl: _trim(_videoUrl),
            muscleGroup: _muscleGroup,
            equipment: _equipment,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        context.showError('Não foi possível salvar: $err');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'Novo exercício' : 'Editar exercício',
                  style: AppTheme.titleMedium),
              const SizedBox(height: 16),
              InputField(
                controller: _name,
                label: 'Nome do exercício',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _muscleGroup,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Grupo muscular',
                  border: OutlineInputBorder(),
                ),
                items: muscleGroups.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _muscleGroup = v ?? _muscleGroup),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: _equipment,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Equipamento (opcional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('—')),
                  ...equipmentTypes.entries.map((e) =>
                      DropdownMenuItem<String?>(
                          value: e.key, child: Text(e.value))),
                ],
                onChanged: (v) => setState(() => _equipment = v),
              ),
              const SizedBox(height: 12),
              InputField(
                controller: _description,
                label: 'Descrição (opcional)',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              InputField(
                controller: _videoUrl,
                label: 'Vídeo URL (opcional)',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Salvar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
