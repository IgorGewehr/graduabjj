import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../services/firebase_service.dart';
import '../../services/settings_service.dart';
import '../../services/skill_progress_service.dart';
import '../../services/syllabus_service.dart';

/// Portal "Minha Graduação" (B4 aluno) — faixa atual, checklist de técnicas
/// com o nível marcado pelo instrutor e % dominado. Somente leitura.
class StudentGraduationScreen extends ConsumerWidget {
  const StudentGraduationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);
    final visible = ref.watch(academySettingsProvider).valueOrNull
            ?.graduationProgressVisibleToStudents ??
        false;

    return studentAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _msg(LucideIcons.alertTriangle, 'Erro ao carregar', '$e'),
      data: (student) {
        if (student == null) {
          return _msg(LucideIcons.userX, 'Perfil não vinculado',
              'Sua conta ainda não está vinculada a um aluno.');
        }
        if (!visible) {
          return _msg(LucideIcons.lock, 'Indisponível',
              'Seu instrutor ainda não habilitou a visualização da graduação.');
        }
        return _GraduationBody(student: student);
      },
    );
  }

  static Widget _msg(IconData icon, String title, String sub) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              Text(title,
                  style: AppTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(sub,
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _GraduationBody extends ConsumerStatefulWidget {
  final Student student;
  const _GraduationBody({required this.student});

  @override
  ConsumerState<_GraduationBody> createState() => _GraduationBodyState();
}

class _GraduationBodyState extends ConsumerState<_GraduationBody> {
  late final List<SportId> _sports;
  late SportId _sport;
  late final String _category;
  String _muaythaiVariant = muaythaiVariantCbmt;
  String _gradeId = '';
  List<SyllabusTechnique> _techniques = [];
  Map<String, SkillProgress> _progress = {};
  bool _loading = true;

  String get _academyId => FirebaseService.academyId;

  @override
  void initState() {
    super.initState();
    _sports = widget.student
        .getSports()
        .where((s) => getSport(s).gradeSystem != GradeSystem.none)
        .toList();
    _category =
        widget.student.category == StudentCategory.kids ? 'kids' : 'adult';
    _sport = _sports.isEmpty
        ? SportId.bjj
        : (_sports.contains(widget.student.getPrimarySport())
            ? widget.student.getPrimarySport()
            : _sports.first);
    if (_sports.isNotEmpty) _gradeId = _currentGradeId();
    _init();
  }

  Future<void> _init() async {
    if (_sports.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final s = await SettingsService(_academyId).getAcademySettings();
      if (mounted) {
        _muaythaiVariant = s?.muaythaiGradeSystem ?? muaythaiVariantCbmt;
      }
    } catch (_) {/* default */}
    await _load();
  }

  String? get _mtVariant =>
      _sport == SportId.muaythai ? _muaythaiVariant : null;

  List<GradeDefinition> _ladder() => getGradesForSport(_sport,
      category: _category, muaythaiVariant: _mtVariant);

  String _currentGradeId() {
    final g = widget.student.getGrade(_sport)?.currentGrade;
    if (g != null && g.isNotEmpty) return g;
    final l = _ladder();
    return l.isNotEmpty ? l.first.id : '';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final techniques =
          await SyllabusService(_academyId).getBySport(_sport.value);
      final progressList = await SkillProgressService(_academyId)
          .getByStudent(widget.student.id, sport: _sport.value);
      if (!mounted) return;
      setState(() {
        _techniques = techniques;
        _progress = {for (final p in progressList) p.techniqueId: p};
        if (_gradeId.isEmpty) _gradeId = _currentGradeId();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showError('Erro ao carregar graduação: $e');
    }
  }

  List<SyllabusTechnique> get _gradeTechniques =>
      _techniques.where((t) => t.gradeId == _gradeId).toList();

  ({int done, int total, double pct}) get _mastery {
    final list = _gradeTechniques;
    final done =
        list.where((t) => _progress[t.id]?.level.isMastered ?? false).length;
    final total = list.length;
    return (done: done, total: total, pct: total == 0 ? 0 : done / total);
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) context.showError('Não foi possível abrir o vídeo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sports.isEmpty) {
      return StudentGraduationScreen._msg(LucideIcons.award,
          'Modalidade sem graduação', 'Sua modalidade não usa faixas/graus.');
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_sports.length > 1) _sportSelector(),
          _gradeHeader(),
          const SizedBox(height: 8),
          ..._gradeTechniques.map(_techniqueCard),
          if (_gradeTechniques.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text('Seu instrutor ainda não cadastrou técnicas para '
                  'esta faixa.',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary)),
            ),
        ],
      ),
    );
  }

  Widget _sportSelector() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: _sports.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = _sports[i];
          final sel = s == _sport;
          return ChoiceChip(
            label: Text(getSport(s).labelShort),
            selected: sel,
            onSelected: (_) {
              if (s != _sport) {
                setState(() {
                  _sport = s;
                  _gradeId = '';
                });
                _load();
              }
            },
            labelStyle: AppTheme.labelSmall.copyWith(
                color: sel ? Colors.white : AppTheme.textSecondary,
                fontWeight: FontWeight.w600),
            selectedColor: AppTheme.primary,
            backgroundColor: AppTheme.surfaceVariant,
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _gradeHeader() {
    final ladder = _ladder();
    final m = _mastery;
    return Container(
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
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: getGradeColor(_sport, _gradeId),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: ladder.any((g) => g.id == _gradeId) ? _gradeId : null,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: ladder
                      .map((g) =>
                          DropdownMenuItem(value: g.id, child: Text(g.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _gradeId = v ?? _gradeId),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: m.pct,
              minHeight: 8,
              backgroundColor: AppTheme.surfaceVariant,
              valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text('${m.done} de ${m.total} técnicas dominadas',
              style: AppTheme.labelSmall
                  .copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _techniqueCard(SyllabusTechnique t) {
    final p = _progress[t.id];
    final level = p?.level;
    final color = level == null
        ? AppTheme.textSecondary
        : (level.isMastered ? AppTheme.success : AppTheme.primary);
    return Container(
      margin: const EdgeInsets.only(top: 10),
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
                child: Text(t.name,
                    style: AppTheme.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              if ((t.videoUrl ?? '').isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(LucideIcons.video, size: 18),
                  color: AppTheme.primary,
                  onPressed: () => _openVideo(t.videoUrl!),
                ),
            ],
          ),
          if (t.category.isNotEmpty)
            Text(t.category,
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(level?.label ?? 'Não avaliada',
                style: AppTheme.labelSmall
                    .copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
          if ((p?.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.messageSquare,
                    size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(p!.notes!,
                      style: AppTheme.labelSmall
                          .copyWith(color: AppTheme.textSecondary)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
