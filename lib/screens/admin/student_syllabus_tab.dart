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

/// Aba "Currículo" no detalhe do aluno (B4 admin): checklist das técnicas da
/// faixa, marcação de nível (aprendendo/praticando/dominado) e feedback por
/// técnica, com % dominado.
class StudentSyllabusTab extends ConsumerStatefulWidget {
  final Student student;
  const StudentSyllabusTab({super.key, required this.student});

  @override
  ConsumerState<StudentSyllabusTab> createState() => _StudentSyllabusTabState();
}

class _StudentSyllabusTabState extends ConsumerState<StudentSyllabusTab> {
  late final List<SportId> _sports;
  late SportId _sport;
  late final String _category; // 'adult' | 'kids'
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
    if (_sports.isNotEmpty) {
      final primary = widget.student.getPrimarySport();
      _sport = _sports.contains(primary) ? primary : _sports.first;
      _gradeId = _currentGradeId();
    } else {
      _sport = SportId.bjj;
    }
    _init();
  }

  Future<void> _init() async {
    if (_sports.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final settings =
          await SettingsService(_academyId).getAcademySettings();
      if (mounted) {
        _muaythaiVariant = settings?.muaythaiGradeSystem ?? muaythaiVariantCbmt;
      }
    } catch (_) {/* default CBMT */}
    await _load();
  }

  String? get _mtVariant =>
      _sport == SportId.muaythai ? _muaythaiVariant : null;

  List<GradeDefinition> _ladder() => getGradesForSport(_sport,
      category: _category, muaythaiVariant: _mtVariant);

  String _currentGradeId() {
    final g = widget.student.getGrade(_sport)?.currentGrade;
    if (g != null && g.isNotEmpty) return g;
    final ladder = _ladder();
    return ladder.isNotEmpty ? ladder.first.id : '';
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
      context.showError('Erro ao carregar currículo: $e');
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

  ({String uid, String name}) _rater() {
    final u = ref.read(currentUserProvider).valueOrNull;
    return (uid: u?.id ?? '', name: u?.displayName ?? '');
  }

  Future<void> _setLevel(SyllabusTechnique t, SkillLevel level) async {
    final existing = _progress[t.id];
    if (existing?.level == level) return; // já está nesse nível (no-op)
    final r = _rater();
    try {
      // Single-select: troca o nível preservando a nota. (Não há "desmarcar"
      // por toque — evita apagar a nota sem querer.)
      await SkillProgressService(_academyId).setLevel(
        studentId: widget.student.id,
        sport: _sport.value,
        gradeId: t.gradeId,
        techniqueId: t.id,
        level: level,
        notes: existing?.notes,
        ratedBy: r.uid,
        ratedByName: r.name,
      );
      if (!mounted) return;
      setState(() {
        _progress[t.id] = SkillProgress(
          id: SkillProgress.docId(widget.student.id, t.id),
          studentId: widget.student.id,
          sport: _sport.value,
          gradeId: t.gradeId,
          techniqueId: t.id,
          level: level,
          notes: existing?.notes,
          ratedBy: r.uid,
          ratedByName: r.name,
          updatedAt: DateTime.now(),
        );
      });
    } catch (e) {
      if (mounted) context.showError('Não foi possível salvar: $e');
    }
  }

  Future<void> _editNote(SyllabusTechnique t) async {
    final existing = _progress[t.id];
    final ctrl = TextEditingController(text: existing?.notes ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.name),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Feedback / observação',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    final notes = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    // Nada a salvar: sem nível anterior e sem nota → não cria entrada fantasma.
    if (existing == null && notes == null) return;
    final r = _rater();
    // Mantém o nível existente; se ainda não há nível, começa em "aprendendo".
    final level = existing?.level ?? SkillLevel.aprendendo;
    try {
      await SkillProgressService(_academyId).setLevel(
        studentId: widget.student.id,
        sport: _sport.value,
        gradeId: t.gradeId,
        techniqueId: t.id,
        level: level,
        notes: notes,
        ratedBy: r.uid,
        ratedByName: r.name,
      );
      if (!mounted) return;
      setState(() {
        _progress[t.id] = SkillProgress(
          id: SkillProgress.docId(widget.student.id, t.id),
          studentId: widget.student.id,
          sport: _sport.value,
          gradeId: t.gradeId,
          techniqueId: t.id,
          level: level,
          notes: notes,
          ratedBy: r.uid,
          ratedByName: r.name,
          updatedAt: DateTime.now(),
        );
      });
    } catch (e) {
      if (mounted) context.showError('Não foi possível salvar: $e');
    }
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
      return _centerMsg(LucideIcons.award, 'Modalidade sem graduação',
          'Esta modalidade não usa faixas/graus.');
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (_sports.length > 1) _sportSelector(),
        _gradeHeader(),
        Expanded(child: _list()),
      ],
    );
  }

  Widget _centerMsg(IconData icon, String title, String sub) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: AppTheme.textDisabled),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMedium
                      .copyWith(color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textDisabled)),
            ],
          ),
        ),
      );

  Widget _sportSelector() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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

  Widget _list() {
    final list = _gradeTechniques;
    if (list.isEmpty) {
      return _centerMsg(LucideIcons.bookOpen, 'Sem técnicas nesta faixa',
          'Cadastre o currículo em Graduação → Currículo.');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: list.length,
      itemBuilder: (_, i) => _techniqueCard(list[i]),
    );
  }

  Widget _techniqueCard(SyllabusTechnique t) {
    final p = _progress[t.id];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  (p?.notes ?? '').isNotEmpty
                      ? LucideIcons.messageSquare
                      : LucideIcons.messageSquarePlus,
                  size: 18,
                ),
                color: (p?.notes ?? '').isNotEmpty
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
                onPressed: () => _editNote(t),
              ),
            ],
          ),
          if (t.category.isNotEmpty)
            Text(t.category,
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final level in SkillLevel.values)
                ChoiceChip(
                  label: Text(level.label),
                  selected: p?.level == level,
                  onSelected: (_) => _setLevel(t, level),
                  labelStyle: AppTheme.labelSmall.copyWith(
                    color: p?.level == level
                        ? Colors.white
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: level.isMastered
                      ? AppTheme.success
                      : AppTheme.primary,
                  backgroundColor: AppTheme.surfaceVariant,
                  showCheckmark: false,
                ),
            ],
          ),
          if ((p?.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(p!.notes!,
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }
}
