import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';
import '../../../widgets/polish/polish.dart';
import 'plan_override_dialog.dart';
import 'plan_overrides.dart';

/// Lista só dos alunos com valor OU vencimento personalizado de um plano
/// (aberta pelos selos do card em Financeiro → Planos), com edição na própria
/// linha. O número do selo que abriu a lista bate com o tamanho dela — ver
/// [planOverrideIds].
///
/// [canEdit] = admin: as regras do Firestore só deixam admin escrever em
/// `plans`; para os demais a lista é só de leitura (sem lápis).
Future<void> showPlanOverridesSheet(
  BuildContext context, {
  required Plan plan,
  required List<Student> students,
  required Set<String> conflictStudentIds,
  required PlanOverrideKind initialKind,
  required bool canEdit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PlanOverridesSheet(
      plan: plan,
      students: students,
      conflictStudentIds: conflictStudentIds,
      initialKind: initialKind,
      canEdit: canEdit,
    ),
  );
}

class _PlanOverridesSheet extends StatefulWidget {
  final Plan plan;
  final List<Student> students;
  final Set<String> conflictStudentIds;
  final PlanOverrideKind initialKind;
  final bool canEdit;

  const _PlanOverridesSheet({
    required this.plan,
    required this.students,
    required this.conflictStudentIds,
    required this.initialKind,
    required this.canEdit,
  });

  @override
  State<_PlanOverridesSheet> createState() => _PlanOverridesSheetState();
}

class _PlanOverridesSheetState extends State<_PlanOverridesSheet> {
  late Plan _plan;
  late PlanOverrideKind _kind;

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
    _kind = widget.initialKind;
  }

  Set<String> get _activeIds => widget.students.map((s) => s.id).toSet();

  PlanOverrideIds get _ids => planOverrideIds(
    _plan,
    activeStudentIds: _activeIds,
    conflictStudentIds: widget.conflictStudentIds,
  );

  String _money(double v) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(v);

  Future<void> _edit(Student student) async {
    final changed = await showPlanOverrideDialog(
      context,
      plan: _plan,
      studentId: student.id,
      studentName: student.fullName,
    );
    if (!changed || !mounted) return;
    // Relê o plano: a linha pode ter saído da lista (restaurou ao padrão) e
    // as contagens das abas mudam.
    try {
      final fresh = await PlanService(
        FirebaseService.academyId,
      ).getById(_plan.id);
      if (fresh != null && mounted) setState(() => _plan = fresh);
    } catch (_) {
      // O dado já foi gravado; sem a releitura a lista só fica defasada até
      // reabrir — melhor que travar a tela.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ids;
    final byId = {for (final s in widget.students) s.id: s};
    final rows =
        ids
            .of(_kind)
            .map((id) => byId[id])
            .whereType<Student>()
            .toList()
          ..sort(
            (a, b) =>
                a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
          );
    final isValue = _kind == PlanOverrideKind.value;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Personalizados',
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _plan.name,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<PlanOverrideKind>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: [
                        ButtonSegment(
                          value: PlanOverrideKind.value,
                          label: Text('Valor · ${ids.value.length}'),
                        ),
                        ButtonSegment(
                          value: PlanOverrideKind.dueDay,
                          label: Text('Vencimento · ${ids.dueDay.length}'),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) =>
                          setState(() => _kind = s.first),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.tag,
                              size: 40,
                              color: AppTheme.textDisabled,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isValue
                                  ? 'Nenhum aluno com valor personalizado'
                                  : 'Nenhum aluno com vencimento personalizado',
                              textAlign: TextAlign.center,
                              style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final s = rows[i];
                        final main = isValue
                            ? _money(_plan.getStudentValue(s.id))
                            : 'Dia ${_plan.getStudentDueDay(s.id)}';
                        final standard = isValue
                            ? 'padrão ${_money(_plan.effectivePeriodValue)}'
                            : 'padrão dia ${_plan.defaultDueDay}';
                        return Pressable(
                          onTap: widget.canEdit ? () => _edit(s) : null,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.fullName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.bodyMedium.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: main,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.success,
                                              ),
                                            ),
                                            TextSpan(
                                              text: '  ·  $standard',
                                              style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        style: AppTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.canEdit)
                                  const Icon(
                                    LucideIcons.pencil,
                                    size: 18,
                                    color: AppTheme.textSecondary,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (!widget.canEdit)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  12 + MediaQuery.of(context).padding.bottom,
                ),
                child: Text(
                  'Somente administradores podem editar.',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
