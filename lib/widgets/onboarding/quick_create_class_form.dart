import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/analytics_service.dart';
import '../../services/services.dart';

const _quickCreateWeekdayLabels = [
  'Domingo',
  'Segunda',
  'Terça',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sábado',
];

String _formatQuickCreateTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Conteúdo (SEM chrome de sheet/tela) de criação rápida de turma — extraído
/// de `_showQuickCreateClassSheet` (lib/screens/admin/attendance_screen.dart)
/// pra ser reusado tanto ali (bottom sheet, "Criar minha primeira turma")
/// quanto no wizard `/admin/comece-aqui` (tela cheia, W1 fight/hybrid — "Crie
/// sua turma de hoje", SPEC_ONBOARDING_2026-07.md §1.1). Só o nome é
/// obrigatório: horário/dias ficam colapsados em "Mais opções" — exigir isso
/// no 1º contato trava o professor antes da 1ª presença.
class QuickCreateClassForm extends ConsumerStatefulWidget {
  /// Alunos ativos SEM turma ainda — se não-vazio, mostra o checkbox
  /// "Matricular todos os N alunos nesta turma" (pré-marcado).
  final List<Student> students;

  /// Chamado com a turma já criada (e, se marcado, já com os alunos
  /// matriculados). O chamador decide o que fazer depois (fechar sheet,
  /// avançar um passo de wizard, etc.) — este widget não navega sozinho.
  final Future<void> Function(BJJClass created) onCreated;

  final String nameHint;
  final String submitLabel;
  final bool autofocus;

  /// Fonte para o evento `first_class_created{source}` (SPEC §5): 'wizard' |
  /// 'chamada_empty_state' | 'turmas'.
  final String analyticsSource;

  const QuickCreateClassForm({
    super.key,
    required this.students,
    required this.onCreated,
    required this.analyticsSource,
    this.nameHint = 'Ex: Turma Iniciante',
    this.submitLabel = 'Criar turma',
    this.autofocus = true,
  });

  @override
  ConsumerState<QuickCreateClassForm> createState() =>
      _QuickCreateClassFormState();
}

class _QuickCreateClassFormState extends ConsumerState<QuickCreateClassForm> {
  final _nameController = TextEditingController();
  bool _isSaving = false;
  bool _showMoreOptions = false;
  bool _enrollAllStudents = false;
  int? _scheduleDayOfWeek;
  TimeOfDay _scheduleStart = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _scheduleEnd = const TimeOfDay(hour: 20, minute: 30);

  @override
  void initState() {
    super.initState();
    // Se a academia já tem alunos sem turma, o caminho mais provável é "são
    // todos dessa turma" — vem pré-marcado, mas o professor pode desmarcar.
    _enrollAllStudents = widget.students.isNotEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _scheduleStart : _scheduleEnd,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _scheduleStart = picked;
        } else {
          _scheduleEnd = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      context.showWarning('Nome da turma é obrigatório');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;
      final service = ClassService(currentUser!.academyId!);

      final schedule = _scheduleDayOfWeek == null
          ? const <ClassSchedule>[]
          : [
              ClassSchedule(
                dayOfWeek: _scheduleDayOfWeek!,
                startTime: _formatQuickCreateTime(_scheduleStart),
                endTime: _formatQuickCreateTime(_scheduleEnd),
              ),
            ];

      var created = await service.create(name: name, schedule: schedule);

      if (_enrollAllStudents && widget.students.isNotEmpty) {
        await service.addStudents(
          created.id,
          widget.students.map((s) => s.id).toList(),
        );
        created = await service.getById(created.id) ?? created;
      }

      unawaited(
        AnalyticsService.logFirstClassCreated(source: widget.analyticsSource),
      );
      // `classesProvider` (Provider global, sem autoDispose) fica com cache
      // stale se nada invalidar — o `ActivationChecklist`/dashboard só
      // enxergam a turma nova (e o wizard só evita re-mostrar "Crie sua 1ª
      // turma") depois disso.
      ref.invalidate(classesProvider);

      if (!mounted) return;
      await widget.onCreated(created);
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nome da turma',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: TextField(
            controller: _nameController,
            autofocus: widget.autofocus,
            decoration: InputDecoration(
              hintText: widget.nameHint,
              hintStyle: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textDisabled,
              ),
              prefixIcon: const Icon(
                LucideIcons.tag,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => setState(() => _showMoreOptions = !_showMoreOptions),
          icon: Icon(
            _showMoreOptions ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            size: 16,
          ),
          label: Text(_showMoreOptions ? 'Menos opções' : 'Mais opções (horário)'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        if (_showMoreOptions) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButton<int?>(
                    value: _scheduleDayOfWeek,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Sem horário fixo'),
                      ),
                      ...List.generate(
                        7,
                        (i) => DropdownMenuItem<int?>(
                          value: i,
                          child: Text(_quickCreateWeekdayLabels[i]),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _scheduleDayOfWeek = value),
                  ),
                ),
                if (_scheduleDayOfWeek != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _pickTime(true),
                    child: Text(
                      _formatQuickCreateTime(_scheduleStart),
                      style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    ' - ',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                  ),
                  GestureDetector(
                    onTap: () => _pickTime(false),
                    child: Text(
                      _formatQuickCreateTime(_scheduleEnd),
                      style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (widget.students.isNotEmpty) ...[
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _enrollAllStudents,
            onChanged: (v) => setState(() => _enrollAllStudents = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Matricular todos os ${widget.students.length} alunos nesta turma',
              style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.textPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(widget.submitLabel),
          ),
        ),
      ],
    );
  }
}
