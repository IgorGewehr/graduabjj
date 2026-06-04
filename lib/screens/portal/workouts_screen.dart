import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/workout_plan.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/common/sport_chip.dart';

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

  WorkoutPlan get plan => widget.plan;

  @override
  void initState() {
    super.initState();
    if (!plan.isFile) {
      _loadLog();
      _loadCatalog();
    }
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
                    if (_videoUrlFor(ex) != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _openVideo(_videoUrlFor(ex)!),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.play_circle_outline, size: 16),
                          label: const Text('Ver demonstracao'),
                        ),
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
}
