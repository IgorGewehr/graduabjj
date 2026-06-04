import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../models/workout_plan.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';
import '../../widgets/common/sport_chip.dart';

/// Admin list of workout plans + entry point to the builder. Works for any
/// modality; musculação is the primary use case.
class WorkoutPlansScreen extends ConsumerStatefulWidget {
  const WorkoutPlansScreen({super.key});

  @override
  ConsumerState<WorkoutPlansScreen> createState() => _WorkoutPlansScreenState();
}

class _WorkoutPlansScreenState extends ConsumerState<WorkoutPlansScreen> {
  bool _loading = true;
  List<WorkoutPlan> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _plans = await WorkoutPlanService(FirebaseService.academyId).listAll();
    } catch (_) {
      _plans = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openBuilder([WorkoutPlan? plan]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkoutPlanBuilderScreen(plan: plan),
      ),
    );
    if (changed == true) _load();
  }

  String _audienceLabel(WorkoutPlan p) {
    switch (p.audience) {
      case WorkoutAudience.academy:
        return 'Toda a academia';
      case WorkoutAudience.sport:
        return p.sport == null
            ? 'Por modalidade'
            : sports[p.sportId]?.label ?? 'Modalidade';
      case WorkoutAudience.students:
        return '${p.assignedStudentIds.length} aluno(s)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Treinos'),
        backgroundColor: AppTheme.surface,
        actions: [
          IconButton(
            tooltip: 'Catálogo de exercícios',
            icon: const Icon(Icons.fitness_center),
            onPressed: () => context.push('/admin/exercicios'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBuilder(),
        icon: const Icon(Icons.add),
        label: const Text('Novo treino'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _plans.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = _plans[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openBuilder(p),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.title,
                                      style: AppTheme.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (p.sportId != null) SportChip(sportId: p.sportId!),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_audienceLabel(p)} · ${p.days.length} dia(s) · ${p.exerciseCount} exercicio(s)',
                                style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Nenhum treino criado ainda.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Crie planos de treino e entregue aos alunos.',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Builder
// ============================================================

class _DayDraft {
  final TextEditingController nameCtrl;
  List<WorkoutExercise> exercises;
  _DayDraft({required String name, List<WorkoutExercise>? exercises})
      : nameCtrl = TextEditingController(text: name),
        exercises = exercises ?? [];
}

/// Create/edit a structured workout plan.
class WorkoutPlanBuilderScreen extends ConsumerStatefulWidget {
  final WorkoutPlan? plan;
  const WorkoutPlanBuilderScreen({super.key, this.plan});

  @override
  ConsumerState<WorkoutPlanBuilderScreen> createState() =>
      _WorkoutPlanBuilderScreenState();
}

class _WorkoutPlanBuilderScreenState
    extends ConsumerState<WorkoutPlanBuilderScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  SportId? _sport;
  WorkoutAudience _audience = WorkoutAudience.academy;
  final Set<String> _assignedIds = {};
  final List<_DayDraft> _days = [];
  List<Student> _allStudents = [];
  bool _saving = false;

  // File-based plan state.
  bool _isFilePlan = false;
  File? _pickedFile;
  String? _pickedName;
  bool _pickedIsPdf = false;

  bool get _isEditing => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    if (p != null) {
      _titleCtrl.text = p.title;
      _descCtrl.text = p.description ?? '';
      _sport = p.sportId;
      _audience = p.audience;
      _assignedIds.addAll(p.assignedStudentIds);
      _isFilePlan = p.isFile;
      for (final d in p.days) {
        _days.add(_DayDraft(name: d.name, exercises: List.of(d.exercises)));
      }
    }
    if (_days.isEmpty) {
      _days.add(_DayDraft(name: 'Treino A'));
    }
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      _allStudents = await StudentService(FirebaseService.academyId).getActive();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    for (final d in _days) {
      d.nameCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      context.showError('Informe um titulo para o treino.');
      return;
    }
    if (_audience == WorkoutAudience.students && _assignedIds.isEmpty) {
      context.showError('Selecione ao menos um aluno.');
      return;
    }
    if (_isFilePlan &&
        _pickedFile == null &&
        !(_isEditing && widget.plan!.isFile)) {
      context.showError('Selecione um arquivo (PDF ou imagem).');
      return;
    }
    setState(() => _saving = true);
    try {
      final service = WorkoutPlanService(FirebaseService.academyId);
      final user = await ref.read(currentUserProvider.future);

      String? fileUrl;
      String? fileStoragePath;
      String? fileKind;
      var days = <WorkoutDay>[];

      if (_isFilePlan) {
        if (_pickedFile != null) {
          final uploaded =
              await service.uploadPlanFile(_pickedFile!, isPdf: _pickedIsPdf);
          fileUrl = uploaded.url;
          fileStoragePath = uploaded.path;
          fileKind = _pickedIsPdf ? 'pdf' : 'image';
        } else {
          // Editing a file plan without replacing the file.
          fileUrl = widget.plan!.fileUrl;
          fileStoragePath = widget.plan!.fileStoragePath;
          fileKind = widget.plan!.fileKind;
        }
      } else {
        days = _days
            .map((d) => WorkoutDay(
                  name: d.nameCtrl.text.trim().isEmpty
                      ? 'Treino'
                      : d.nameCtrl.text.trim(),
                  exercises: d.exercises,
                ))
            .toList();
      }

      final plan = WorkoutPlan(
        id: widget.plan?.id ?? '',
        title: _titleCtrl.text.trim(),
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        sport: _sport?.value,
        audience: _audience,
        assignedStudentIds: _assignedIds.toList(),
        days: days,
        fileUrl: fileUrl,
        fileStoragePath: fileStoragePath,
        fileKind: fileKind,
        createdBy: widget.plan?.createdBy ?? user?.id ?? '',
        createdByName: widget.plan?.createdByName ?? user?.displayName ?? '',
      );
      if (_isEditing) {
        await service.update(widget.plan!.id, plan);
      } else {
        await service.create(plan);
        if (_audience == WorkoutAudience.students) {
          await _notifyAssignedStudents(
            title: plan.title,
            actionUrl: '/portal/treinos',
          );
        }
      }
      if (!mounted) return;
      context.showSuccess('Treino salvo!');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) context.showError('Erro ao salvar o treino.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir treino?'),
        content: const Text('Esta acao nao pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Excluir', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await WorkoutPlanService(FirebaseService.academyId)
          .delete(widget.plan!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) context.showError('Erro ao excluir.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar treino' : 'Novo treino'),
        backgroundColor: AppTheme.surface,
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir',
              icon: Icon(Icons.delete_outline, color: AppTheme.error),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Titulo',
              hintText: 'Ex: Treino de hipertrofia - 4x',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descricao (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _buildSportPicker(),
          const SizedBox(height: 16),
          _buildAudiencePicker(),
          const SizedBox(height: 24),
          _buildTypeToggle(),
          const SizedBox(height: 16),
          if (_isFilePlan)
            _buildFileSection()
          else ...[
            Text(
              'Dias de treino',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._days.asMap().entries.map((e) => _buildDayCard(e.key, e.value)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() =>
                  _days.add(_DayDraft(name: 'Treino ${_nextDayLetter()}'))),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar dia'),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar treino'),
            ),
          ),
        ],
      ),
    );
  }

  String _nextDayLetter() {
    const letters = 'ABCDEFGHIJ';
    final i = _days.length;
    return i < letters.length ? letters[i] : '${i + 1}';
  }

  /// Best-effort notification to each assigned student who has a linked app
  /// account. Used when a plan is created for specific students.
  Future<void> _notifyAssignedStudents({
    required String title,
    required String actionUrl,
  }) async {
    try {
      final dispatcher = NotificationDispatcher(FirebaseService.academyId);
      final byId = {for (final s in _allStudents) s.id: s};
      for (final id in _assignedIds) {
        final uid = byId[id]?.linkedUserId;
        if (uid != null && uid.isNotEmpty) {
          await dispatcher.notifyNewContent(
            userId: uid,
            title: title,
            isVideo: false,
            actionUrl: actionUrl,
          );
        }
      }
    } catch (_) {
      // Notifications are best-effort; never block the save.
    }
  }

  Widget _buildTypeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de treino',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Montado no app'),
              selected: !_isFilePlan,
              onSelected: (_) => setState(() => _isFilePlan = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Arquivo (PDF/imagem)'),
              selected: _isFilePlan,
              onSelected: (_) => setState(() => _isFilePlan = true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFileSection() {
    final hasExisting =
        _isEditing && widget.plan!.isFile && _pickedFile == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _pickPlanFile,
          icon: const Icon(Icons.upload_file),
          label: Text(_pickedFile == null
              ? 'Selecionar arquivo'
              : 'Trocar arquivo'),
        ),
        const SizedBox(height: 6),
        Text(
          _pickedName != null
              ? 'Selecionado: $_pickedName'
              : hasExisting
                  ? 'Arquivo atual mantido (${widget.plan!.fileKind == 'pdf' ? 'PDF' : 'imagem'}).'
                  : 'Nenhum arquivo selecionado. Aceita PDF ou imagem.',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Future<void> _pickPlanFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final picked = result?.files.single;
    if (picked?.path != null) {
      final ext = (picked!.extension ?? '').toLowerCase();
      setState(() {
        _pickedFile = File(picked.path!);
        _pickedName = picked.name;
        _pickedIsPdf = ext == 'pdf';
      });
    }
  }

  Widget _buildSportPicker() {
    return DropdownButtonFormField<SportId?>(
      initialValue: _sport,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Modalidade',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<SportId?>(
          value: null,
          child: Text('Qualquer modalidade'),
        ),
        ...sportOptions.map(
          (s) => DropdownMenuItem<SportId?>(
            value: s,
            child: Text(sports[s]?.label ?? s.value),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _sport = v),
    );
  }

  Widget _buildAudiencePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quem recebe',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _audienceChip(WorkoutAudience.academy, 'Toda a academia'),
            _audienceChip(WorkoutAudience.sport, 'Por modalidade'),
            _audienceChip(WorkoutAudience.students, 'Alunos especificos'),
          ],
        ),
        if (_audience == WorkoutAudience.students) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickStudents,
            icon: const Icon(Icons.people_outline),
            label: Text('Selecionar alunos (${_assignedIds.length})'),
          ),
        ],
      ],
    );
  }

  Widget _audienceChip(WorkoutAudience a, String label) {
    final selected = _audience == a;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _audience = a),
    );
  }

  Future<void> _pickStudents() async {
    final selected = Set<String>.from(_assignedIds);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              builder: (ctx, scroll) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Selecionar alunos',
                      style: AppTheme.titleMedium
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        controller: scroll,
                        itemCount: _allStudents.length,
                        itemBuilder: (ctx, i) {
                          final s = _allStudents[i];
                          return CheckboxListTile(
                            value: selected.contains(s.id),
                            title: Text(s.fullName),
                            onChanged: (v) => setSheet(() {
                              if (v == true) {
                                selected.add(s.id);
                              } else {
                                selected.remove(s.id);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('Confirmar (${selected.length})'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
    setState(() {
      _assignedIds
        ..clear()
        ..addAll(selected);
    });
  }

  Widget _buildDayCard(int index, _DayDraft day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: day.nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do dia',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (_days.length > 1)
                IconButton(
                  tooltip: 'Remover dia',
                  icon: Icon(Icons.close, color: AppTheme.error),
                  onPressed: () => setState(() {
                    day.nameCtrl.dispose();
                    _days.removeAt(index);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...day.exercises.asMap().entries.map(
                (e) => _buildExerciseTile(day, e.key, e.value),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final ex = await _showExerciseSheet(null);
                if (ex != null) setState(() => day.exercises.add(ex));
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar exercicio'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseTile(_DayDraft day, int index, WorkoutExercise ex) {
    final parts = <String>[
      if (ex.sets != null && ex.sets!.isNotEmpty) '${ex.sets} series',
      if (ex.reps != null && ex.reps!.isNotEmpty) '${ex.reps} reps',
      if (ex.load != null && ex.load!.isNotEmpty) ex.load!,
      if (ex.rest != null && ex.rest!.isNotEmpty) 'desc ${ex.rest}',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(ex.name, style: AppTheme.bodyMedium),
      subtitle: parts.isEmpty
          ? (ex.notes != null ? Text(ex.notes!) : null)
          : Text(parts.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () async {
              final edited = await _showExerciseSheet(ex);
              if (edited != null) {
                setState(() => day.exercises[index] = edited);
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
            onPressed: () => setState(() => day.exercises.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Future<WorkoutExercise?> _showExerciseSheet(WorkoutExercise? existing) async {
    final nameC = TextEditingController(text: existing?.name ?? '');
    final setsC = TextEditingController(text: existing?.sets ?? '');
    final repsC = TextEditingController(text: existing?.reps ?? '');
    final loadC = TextEditingController(text: existing?.load ?? '');
    final restC = TextEditingController(text: existing?.rest ?? '');
    final notesC = TextEditingController(text: existing?.notes ?? '');

    final result = await showModalBottomSheet<WorkoutExercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existing == null ? 'Novo exercicio' : 'Editar exercicio',
                style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameC,
                decoration: const InputDecoration(
                  labelText: 'Exercicio',
                  hintText: 'Ex: Supino reto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: setsC,
                      decoration: const InputDecoration(
                        labelText: 'Series',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: repsC,
                      decoration: const InputDecoration(
                        labelText: 'Reps',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: loadC,
                      decoration: const InputDecoration(
                        labelText: 'Carga',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: restC,
                      decoration: const InputDecoration(
                        labelText: 'Descanso',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesC,
                decoration: const InputDecoration(
                  labelText: 'Observacoes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (nameC.text.trim().isEmpty) {
                    Navigator.pop(ctx);
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    WorkoutExercise(
                      name: nameC.text.trim(),
                      sets: setsC.text.trim(),
                      reps: repsC.text.trim(),
                      load: loadC.text.trim(),
                      rest: restC.text.trim(),
                      notes: notesC.text.trim(),
                    ),
                  );
                },
                child: const Text('Salvar exercicio'),
              ),
            ],
          ),
        );
      },
    );

    nameC.dispose();
    setsC.dispose();
    repsC.dispose();
    loadC.dispose();
    restC.dispose();
    notesC.dispose();
    return result;
  }
}
