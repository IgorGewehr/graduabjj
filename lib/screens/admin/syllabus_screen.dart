import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/syllabus_templates.dart';
import '../../core/theme.dart';
import '../../services/firebase_service.dart';
import '../../services/syllabus_service.dart';
import '../../widgets/form/input_field.dart';

/// Admin: monta o currículo de técnicas por modalidade/faixa (B1).
class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  late final List<SportId> _gradedSports;
  late SportId _sport;
  List<SyllabusTechnique> _techniques = [];
  bool _loading = true;
  bool _seeding = false;

  SyllabusService get _service => SyllabusService(FirebaseService.academyId);

  @override
  void initState() {
    super.initState();
    _gradedSports = SportId.values
        .where((s) => getSport(s).gradeSystem != GradeSystem.none)
        .toList();
    _sport =
        _gradedSports.contains(SportId.bjj) ? SportId.bjj : _gradedSports.first;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.getBySport(_sport.value);
      if (!mounted) return;
      setState(() {
        _techniques = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showError('Erro ao carregar currículo: $e');
    }
  }

  int _nextOrder() {
    if (_techniques.isEmpty) return 0;
    return _techniques.map((t) => t.order).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> _openForm({SyllabusTechnique? existing}) async {
    final grades = getGradesForSport(_sport);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _TechniqueFormSheet(
          academyId: FirebaseService.academyId,
          sport: _sport,
          grades: grades,
          existing: existing,
          suggestedOrder: existing?.order ?? _nextOrder(),
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(SyllabusTechnique t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover técnica'),
        content: Text('Remover "${t.name}" do currículo?'),
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
      await _service.delete(t.id);
      _load();
    } catch (e) {
      if (mounted) context.showError('Não foi possível remover: $e');
    }
  }

  Future<void> _seedBjj() async {
    setState(() => _seeding = true);
    try {
      final uid = FirebaseService.currentUserId ?? '';
      // Ordem incremental por faixa.
      final perGrade = <String, int>{};
      for (final item in bjjStarterTemplate) {
        final order = perGrade.update(item.gradeId, (v) => v + 1,
            ifAbsent: () => 0);
        await _service.create(SyllabusTechnique(
          id: '',
          sport: SportId.bjj.value,
          gradeId: item.gradeId,
          category: item.category,
          name: item.name,
          order: order,
          createdBy: uid,
          createdAt: DateTime.now(),
        ));
      }
      if (!mounted) return;
      context.showSuccess('Template BJJ adicionado! Edite à vontade.');
      _load();
    } catch (e) {
      if (mounted) context.showError('Não foi possível semear o template: $e');
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
        title: const Text('Currículo de graduação'),
      ),
      body: Column(
        children: [
          _sportSelector(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _body(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Nova técnica'),
      ),
    );
  }

  Widget _sportSelector() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _gradedSports.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = _gradedSports[i];
          final selected = s == _sport;
          return ChoiceChip(
            label: Text(getSport(s).labelShort),
            selected: selected,
            onSelected: (_) {
              if (s != _sport) {
                setState(() => _sport = s);
                _load();
              }
            },
            labelStyle: AppTheme.labelSmall.copyWith(
              color: selected ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            selectedColor: AppTheme.primary,
            backgroundColor: AppTheme.surfaceVariant,
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _body() {
    if (_techniques.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.bookOpen, size: 48, color: AppTheme.textDisabled),
              const SizedBox(height: 12),
              Text('Nenhuma técnica neste currículo ainda',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMedium
                      .copyWith(color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              Text('Toque em "Nova técnica" para começar.',
                  textAlign: TextAlign.center,
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textDisabled)),
              if (_sport == SportId.bjj) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _seeding ? null : _seedBjj,
                  icon: _seeding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.sparkles, size: 16),
                  label: const Text('Usar template BJJ básico'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final grades = getGradesForSport(_sport);
    final byGrade = <String, List<SyllabusTechnique>>{};
    for (final t in _techniques) {
      byGrade.putIfAbsent(t.gradeId, () => []).add(t);
    }
    // Faixas na ordem da escada; depois quaisquer gradeIds órfãos.
    final orderedGradeIds = <String>[
      for (final g in grades)
        if (byGrade.containsKey(g.id)) g.id,
      ...byGrade.keys.where((k) => grades.every((g) => g.id != k)),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        for (final gid in orderedGradeIds) ...[
          _gradeHeader(gid),
          for (final t in byGrade[gid]!) _techniqueRow(t),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _gradeHeader(String gradeId) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: getGradeColor(_sport, gradeId),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.border),
            ),
          ),
          const SizedBox(width: 8),
          Text(getGradeLabel(_sport, gradeId),
              style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _techniqueRow(SyllabusTechnique t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: ListTile(
        onTap: () => _openForm(existing: t),
        title: Text(t.name, style: AppTheme.bodyMedium),
        subtitle: (t.category.isEmpty && (t.videoUrl ?? '').isEmpty)
            ? null
            : Row(
                children: [
                  if (t.category.isNotEmpty)
                    Text(t.category,
                        style: AppTheme.labelSmall
                            .copyWith(color: AppTheme.textSecondary)),
                  if ((t.videoUrl ?? '').isNotEmpty) ...[
                    if (t.category.isNotEmpty) const SizedBox(width: 8),
                    Icon(LucideIcons.video,
                        size: 12, color: AppTheme.textSecondary),
                  ],
                ],
              ),
        trailing: IconButton(
          icon: const Icon(LucideIcons.trash2, size: 18),
          color: AppTheme.textSecondary,
          onPressed: () => _delete(t),
        ),
      ),
    );
  }
}

/// Bottom-sheet form to create/edit a technique. Persists itself and pops
/// `true` on success.
class _TechniqueFormSheet extends StatefulWidget {
  final String academyId;
  final SportId sport;
  final List<GradeDefinition> grades;
  final SyllabusTechnique? existing;
  final int suggestedOrder;

  const _TechniqueFormSheet({
    required this.academyId,
    required this.sport,
    required this.grades,
    required this.existing,
    required this.suggestedOrder,
  });

  @override
  State<_TechniqueFormSheet> createState() => _TechniqueFormSheetState();
}

class _TechniqueFormSheetState extends State<_TechniqueFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _videoUrl;
  late final TextEditingController _order;
  late String _gradeId;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _videoUrl = TextEditingController(text: e?.videoUrl ?? '');
    _order = TextEditingController(text: '${e?.order ?? widget.suggestedOrder}');
    _gradeId = e?.gradeId ??
        (widget.grades.isNotEmpty ? widget.grades.first.id : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _description.dispose();
    _videoUrl.dispose();
    _order.dispose();
    super.dispose();
  }

  String? _trim(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final service = SyllabusService(widget.academyId);
      final order = int.tryParse(_order.text.trim()) ?? widget.suggestedOrder;
      final e = widget.existing;
      if (e == null) {
        await service.create(SyllabusTechnique(
          id: '',
          sport: widget.sport.value,
          gradeId: _gradeId,
          category: _category.text.trim(),
          name: _name.text.trim(),
          description: _trim(_description),
          videoUrl: _trim(_videoUrl),
          order: order,
          createdBy: FirebaseService.currentUserId ?? '',
          createdAt: DateTime.now(),
        ));
      } else {
        // copyWith preserva createdBy/createdAt do registro original.
        await service.update(
          e.id,
          e.copyWith(
            gradeId: _gradeId,
            category: _category.text.trim(),
            name: _name.text.trim(),
            description: _trim(_description),
            videoUrl: _trim(_videoUrl),
            order: order,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        context.showError('Não foi possível salvar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'Nova técnica' : 'Editar técnica',
                  style: AppTheme.titleMedium),
              const SizedBox(height: 16),
              InputField(
                controller: _name,
                label: 'Nome da técnica',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: widget.grades.any((g) => g.id == _gradeId)
                    ? _gradeId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Faixa',
                  border: OutlineInputBorder(),
                ),
                items: widget.grades
                    .map((g) =>
                        DropdownMenuItem(value: g.id, child: Text(g.label)))
                    .toList(),
                onChanged: (v) => setState(() => _gradeId = v ?? _gradeId),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Escolha a faixa' : null,
              ),
              const SizedBox(height: 12),
              InputField(controller: _category, label: 'Categoria (opcional)'),
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
              const SizedBox(height: 12),
              InputField(
                controller: _order,
                label: 'Ordem',
                keyboardType: TextInputType.number,
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
