import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/feedback_utils.dart';
import '../../core/number_format.dart';
import '../../core/theme.dart';
import '../../models/workout_plan.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/common/sport_chip.dart';
import 'exercise_progress_screen.dart';

/// Student-facing list of workout plans assigned to them (academy-wide,
/// their-sport library, or personal). Tapping a plan opens a native detail
/// view rendering the days and exercises.
class WorkoutsScreen extends ConsumerStatefulWidget {
  const WorkoutsScreen({super.key});

  @override
  ConsumerState<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends ConsumerState<WorkoutsScreen> {
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
      final student = await ref.read(currentStudentProvider.future);
      if (student != null) {
        _plans = await WorkoutPlanService(FirebaseService.academyId)
            .getForStudent(studentId: student.id, sports: student.getSports());
      } else {
        _plans = [];
      }
    } catch (_) {
      _plans = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _open(WorkoutPlan plan) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _WorkoutPlanDetailScreen(plan: plan)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Treinos'),
        backgroundColor: AppTheme.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _plans.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = _plans[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _open(p),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.fitness_center,
                                    color: AppTheme.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.title,
                                      style: AppTheme.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      p.isFile
                                          ? 'Planilha em arquivo'
                                          : '${p.days.length} dia(s) · ${p.exerciseCount} exercicio(s)',
                                      style: AppTheme.labelSmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (p.sportId != null) SportChip(sportId: p.sportId!),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right,
                                  color: AppTheme.textSecondary),
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
              'Nenhum treino disponivel ainda.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Quando seu professor liberar um treino, ele aparece aqui.',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutPlanDetailScreen extends ConsumerStatefulWidget {
  final WorkoutPlan plan;
  const _WorkoutPlanDetailScreen({required this.plan});

  @override
  ConsumerState<_WorkoutPlanDetailScreen> createState() =>
      _WorkoutPlanDetailScreenState();
}

class _WorkoutPlanDetailScreenState
    extends ConsumerState<_WorkoutPlanDetailScreen> {
  final Set<String> _done = {};
  String? _studentId;
  // Catálogo (A5) por id → para mostrar "Ver demonstração" nos exercícios linkados.
  Map<String, Exercise> _exercisesById = {};
  // Execuções de hoje (A6), por "dayIndex:exerciseIndex".
  Map<String, WorkoutExecution> _execByKey = {};

  WorkoutPlan get plan => widget.plan;

  @override
  void initState() {
    super.initState();
    if (!plan.isFile) {
      _loadLog();
      _loadCatalog();
    }
  }

  Future<void> _loadExecutions(String studentId) async {
    try {
      final map = await WorkoutExecutionService(FirebaseService.academyId)
          .getByPlanForDay(studentId, plan.id, DateTime.now());
      if (mounted) setState(() => _execByKey = map);
    } catch (_) {/* não-fatal */}
  }

  Future<void> _loadCatalog() async {
    // Só carrega se algum exercício do plano está vinculado ao catálogo.
    final hasLinked = plan.days
        .any((d) => d.exercises.any((e) => (e.exerciseId ?? '').isNotEmpty));
    if (!hasLinked) return;
    try {
      final list = await ExerciseService(FirebaseService.academyId).listAll();
      if (mounted) setState(() => _exercisesById = {for (final e in list) e.id: e});
    } catch (_) {/* não-fatal: sem botão de vídeo */}
  }

  Future<void> _loadLog() async {
    try {
      final student = await ref.read(currentStudentProvider.future);
      if (student == null) return;
      _studentId = student.id;
      _loadExecutions(student.id);
      final done = await WorkoutPlanService(FirebaseService.academyId)
          .getTodayLog(student.id, plan.id);
      if (mounted) {
        setState(() {
          _done
            ..clear()
            ..addAll(done);
        });
      }
    } catch (_) {
      // Non-fatal: start with an empty checklist.
    }
  }

  void _toggle(String key, bool value) {
    setState(() {
      if (value) {
        _done.add(key);
      } else {
        _done.remove(key);
      }
    });
    final sid = _studentId;
    if (sid != null) {
      // Fire-and-forget; small doc, one per day.
      WorkoutPlanService(FirebaseService.academyId)
          .saveTodayLog(sid, plan.id, _done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = plan.exerciseCount;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Treino'),
        backgroundColor: AppTheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  style: AppTheme.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (plan.sportId != null) SportChip(sportId: plan.sportId!),
            ],
          ),
          if (plan.description != null && plan.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              plan.description!,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
          if (!plan.isFile && total > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Concluidos hoje: ${_done.length}/$total',
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (plan.isFile)
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(plan.fileUrl!);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: Text(plan.fileKind == 'pdf' ? 'Abrir PDF' : 'Abrir planilha'),
            )
          else
            for (var d = 0; d < plan.days.length; d++)
              _buildDay(d, plan.days[d]),
        ],
      ),
    );
  }

  Widget _buildDay(int dayIndex, WorkoutDay day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              day.name,
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (day.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                'Sem exercicios.',
                style:
                    AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              ),
            )
          else
            for (var i = 0; i < day.exercises.length; i++)
              _buildExercise(
                dayIndex,
                i,
                day.exercises[i],
                i == day.exercises.length - 1,
              ),
        ],
      ),
    );
  }

  Widget _buildExercise(
    int dayIndex,
    int exIndex,
    WorkoutExercise ex,
    bool isLast,
  ) {
    final key = '$dayIndex:$exIndex';
    final done = _done.contains(key);
    final meta = <String>[
      if (ex.sets != null && ex.sets!.isNotEmpty) '${ex.sets} series',
      if (ex.reps != null && ex.reps!.isNotEmpty) '${ex.reps} reps',
      if (ex.load != null && ex.load!.isNotEmpty) ex.load!,
      if (ex.rest != null && ex.rest!.isNotEmpty) 'desc ${ex.rest}',
    ];
    return InkWell(
      onTap: () => _toggle(key, !done),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(top: BorderSide(color: AppTheme.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: done,
              onChanged: (v) => _toggle(key, v ?? false),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ex.name,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration:
                            done ? TextDecoration.lineThrough : null,
                        color: done ? AppTheme.textSecondary : null,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta.join(' · '),
                        style: AppTheme.labelSmall
                            .copyWith(color: AppTheme.primary),
                      ),
                    ],
                    if (ex.notes != null && ex.notes!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        ex.notes!,
                        style: AppTheme.labelSmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                    _execSummary(dayIndex, exIndex),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_videoUrlFor(ex) != null)
                          TextButton.icon(
                            onPressed: () => _openVideo(_videoUrlFor(ex)!),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.play_circle_outline,
                                size: 16),
                            label: const Text('Ver demonstracao'),
                          ),
                        TextButton.icon(
                          onPressed: () => _register(dayIndex, exIndex, ex),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.fitness_center, size: 16),
                          label: Text(
                            _execByKey.containsKey('$dayIndex:$exIndex')
                                ? 'Editar registro'
                                : 'Registrar',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _openProgress(ex.name),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.show_chart, size: 16),
                          label: const Text('Progresso'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Resumo do que foi registrado hoje (séries · melhor carga), se houver.
  Widget _execSummary(int dayIndex, int exIndex) {
    final e = _execByKey['$dayIndex:$exIndex'];
    if (e == null || e.sets.isEmpty) return const SizedBox.shrink();
    final best = e.bestLoadKg;
    final txt = '${e.sets.length} série(s)'
        '${best > 0 ? ' · melhor ${fmtNum(best)} kg' : ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 13, color: AppTheme.success),
          const SizedBox(width: 4),
          Text(txt,
              style:
                  AppTheme.labelSmall.copyWith(color: AppTheme.success)),
        ],
      ),
    );
  }

  Future<void> _register(int dayIndex, int exIndex, WorkoutExercise ex) async {
    final sid = _studentId;
    if (sid == null) return;
    final saved = await showModalBottomSheet<WorkoutExecution>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _RegisterExecutionSheet(
        academyId: FirebaseService.academyId,
        studentId: sid,
        planId: plan.id,
        dayIndex: dayIndex,
        exerciseIndex: exIndex,
        exerciseId: ex.exerciseId,
        exerciseName: ex.name,
        existing: _execByKey['$dayIndex:$exIndex'],
      ),
    );
    if (saved != null && mounted) {
      setState(() => _execByKey['$dayIndex:$exIndex'] = saved);
    }
  }

  /// URL de vídeo do exercício do catálogo vinculado (ou null).
  String? _videoUrlFor(WorkoutExercise ex) {
    final id = ex.exerciseId;
    if (id == null || id.isEmpty) return null;
    final url = _exercisesById[id]?.videoUrl;
    return (url == null || url.isEmpty) ? null : url;
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openProgress(String exerciseName) {
    final sid = _studentId;
    if (sid == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExerciseProgressScreen(
          studentId: sid, exerciseName: exerciseName),
    ));
  }
}

/// Folha de registro de execução (A6): séries (reps + carga, RPE opcional).
class _RegisterExecutionSheet extends StatefulWidget {
  final String academyId;
  final String studentId;
  final String planId;
  final int dayIndex;
  final int exerciseIndex;
  final String? exerciseId;
  final String exerciseName;
  final WorkoutExecution? existing;

  const _RegisterExecutionSheet({
    required this.academyId,
    required this.studentId,
    required this.planId,
    required this.dayIndex,
    required this.exerciseIndex,
    required this.exerciseId,
    required this.exerciseName,
    required this.existing,
  });

  @override
  State<_RegisterExecutionSheet> createState() =>
      _RegisterExecutionSheetState();
}

class _SetRow {
  final TextEditingController reps;
  final TextEditingController load;
  final TextEditingController rpe;
  _SetRow({String reps = '', String load = '', String rpe = ''})
      : reps = TextEditingController(text: reps),
        load = TextEditingController(text: load),
        rpe = TextEditingController(text: rpe);
  void dispose() {
    reps.dispose();
    load.dispose();
    rpe.dispose();
  }
}

class _RegisterExecutionSheetState extends State<_RegisterExecutionSheet> {
  final List<_SetRow> _rows = [];
  late final TextEditingController _notes;
  bool _saving = false;

  static String _n(num v) =>
      v == v.toInt() ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
    final sets = widget.existing?.sets ?? const [];
    if (sets.isEmpty) {
      _rows.add(_SetRow());
    } else {
      for (final s in sets) {
        _rows.add(_SetRow(
          reps: s.reps == 0 ? '' : '${s.reps}',
          load: s.load == 0 ? '' : _n(s.load),
          rpe: s.rpe == null ? '' : '${s.rpe}',
        ));
      }
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  double? _parseLoad(String t) =>
      double.tryParse(t.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final sets = <SetEntry>[];
    for (final r in _rows) {
      final reps = int.tryParse(r.reps.text.trim()) ?? 0;
      final load = _parseLoad(r.load.text) ?? 0;
      if (reps <= 0) continue; // linha sem reps é ignorada
      sets.add(SetEntry(
        reps: reps,
        load: load,
        rpe: int.tryParse(r.rpe.text.trim()),
      ));
    }
    if (sets.isEmpty) {
      context.showWarning('Informe ao menos uma série (reps).');
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final exec = WorkoutExecution(
      id: '',
      studentId: widget.studentId,
      planId: widget.planId,
      dayIndex: widget.dayIndex,
      exerciseIndex: widget.exerciseIndex,
      exerciseId: widget.exerciseId,
      exerciseName: widget.exerciseName,
      date: DateTime(now.year, now.month, now.day),
      sets: sets,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: now,
    );
    try {
      await WorkoutExecutionService(widget.academyId).upsert(exec);
      if (!mounted) return;
      Navigator.of(context).pop(exec);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        context.showError('Nao foi possivel salvar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: mq.viewInsets.bottom + 16,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.exerciseName,
                  style: AppTheme.titleMedium
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Registre as séries feitas hoje',
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textSecondary)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _rows.length,
                  itemBuilder: (_, i) => _setRowWidget(i),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _rows.add(_SetRow())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar série'),
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Observações (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
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

  Widget _setRowWidget(int i) {
    final r = _rows[i];
    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('${i + 1}',
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: TextField(
              controller: r.reps,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: dec('Reps'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: r.load,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              decoration: dec('Carga kg'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: TextField(
              controller: r.rpe,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: dec('RPE'),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            color: AppTheme.textSecondary,
            onPressed: _rows.length <= 1
                ? null
                : () => setState(() => _rows.removeAt(i).dispose()),
          ),
        ],
      ),
    );
  }
}
