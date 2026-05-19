import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';
import 'financial_widgets.dart';

// ============================================
// Generate Tuitions Sheet
// ============================================

class GenerateTuitionsSheet extends StatefulWidget {
  final DateTime month;
  final String monthKey;
  final List<Plan> plans;
  final List<Student> students;
  final List<Payment> payments;
  final void Function(String? planId) onGenerate;

  const GenerateTuitionsSheet({
    super.key,
    required this.month,
    required this.monthKey,
    required this.plans,
    required this.students,
    required this.payments,
    required this.onGenerate,
  });

  @override
  State<GenerateTuitionsSheet> createState() =>
      _GenerateTuitionsSheetState();
}

class _GenerateTuitionsSheetState extends State<GenerateTuitionsSheet> {
  String _filterType = 'all'; // 'all' or 'specific'
  String? _selectedPlanId;

  List<Plan> get _activePlans =>
      widget.plans.where((p) => p.isActive).toList();

  ({int totalInPlans, int alreadyHave, int willReceive}) get _stats {
    final studentsWithTuition = widget.payments
        .where((p) => p.referenceMonth == widget.monthKey)
        .map((p) => p.studentId)
        .toSet();

    final plansToProcess =
        _filterType == 'specific' && _selectedPlanId != null
            ? _activePlans
                .where((p) => p.id == _selectedPlanId)
                .toList()
            : _activePlans;

    final studentsInPlans = <String>{};
    final studentsToGenerate = <String>{};

    for (final plan in plansToProcess) {
      for (final studentId in plan.studentIds) {
        final student =
            widget.students.cast<Student?>().firstWhere(
          (s) =>
              s?.id == studentId &&
              s?.status == StudentStatus.active,
          orElse: () => null,
        );
        if (student != null) {
          studentsInPlans.add(studentId);
          if (!studentsWithTuition.contains(studentId)) {
            studentsToGenerate.add(studentId);
          }
        }
      }
    }

    return (
      totalInPlans: studentsInPlans.length,
      alreadyHave:
          studentsInPlans.length - studentsToGenerate.length,
      willReceive: studentsToGenerate.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final monthLabel =
        DateFormat("MMMM 'de' yyyy", 'pt_BR').format(widget.month);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandleBar(),
            const SizedBox(height: 20),

            // Title
            Text(
              'Gerar Mensalidades',
              style: AppTheme.titleLarge
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Gera apenas para alunos sem mensalidade do mes',
              style: AppTheme.bodySmall
                  .copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),

            // Month info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
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
                    child: const Icon(LucideIcons.calendar,
                        color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mes de referencia',
                        style: AppTheme.labelSmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                      Text(
                        monthLabel.capitalize(),
                        style: AppTheme.titleSmall
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Filter section
            Text(
              'Filtrar por plano',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // All plans option
            _FilterOption(
              title: 'Todos os planos ativos',
              subtitle: 'Gera para todos os alunos em qualquer plano',
              isSelected: _filterType == 'all',
              onTap: () => setState(() {
                _filterType = 'all';
                _selectedPlanId = null;
              }),
            ),
            const SizedBox(height: 8),

            // Specific plan option
            _FilterOption(
              title: 'Plano especifico',
              subtitle: 'Gera apenas para alunos de um plano',
              isSelected: _filterType == 'specific',
              onTap: () => setState(() => _filterType = 'specific'),
            ),

            // Plan dropdown
            if (_filterType == 'specific') ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.divider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedPlanId,
                    hint: const Text('Selecione o plano'),
                    items: _activePlans.map((plan) {
                      return DropdownMenuItem(
                        value: plan.id,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                plan.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${plan.studentCount} aluno${plan.studentCount != 1 ? 's' : ''}',
                                style: AppTheme.labelSmall.copyWith(
                                    color: AppTheme.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => _selectedPlanId = value),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Stats box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: stats.willReceive > 0
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: stats.willReceive > 0
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : AppTheme.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        stats.willReceive > 0
                            ? LucideIcons.checkCircle
                            : LucideIcons.alertCircle,
                        color: stats.willReceive > 0
                            ? AppTheme.success
                            : AppTheme.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stats.willReceive > 0
                              ? '${stats.willReceive} aluno${stats.willReceive != 1 ? 's' : ''} receberao mensalidade'
                              : 'Nenhuma mensalidade sera gerada',
                          style: AppTheme.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: stats.willReceive > 0
                                ? AppTheme.success
                                : AppTheme.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatItem(
                          label:
                              'Total no${_filterType == 'specific' ? ' plano' : 's planos'}',
                          value: stats.totalInPlans.toString(),
                        ),
                      ),
                      Expanded(
                        child: _StatItem(
                          label: 'Ja possuem',
                          value: stats.alreadyHave.toString(),
                        ),
                      ),
                      Expanded(
                        child: _StatItem(
                          label: 'Novos',
                          value: stats.willReceive.toString(),
                          highlight: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Warning if specific plan not selected
            if (_filterType == 'specific' &&
                _selectedPlanId == null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.info,
                        color: AppTheme.info, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selecione um plano para continuar',
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.info),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppTheme.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: stats.willReceive == 0 ||
                            (_filterType == 'specific' &&
                                _selectedPlanId == null)
                        ? null
                        : () => widget.onGenerate(
                              _filterType == 'specific'
                                  ? _selectedPlanId
                                  : null,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      disabledBackgroundColor: AppTheme.divider,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('Gerar ${stats.willReceive}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// _FilterOption (local to this sheet)
// ============================================

class _FilterOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterOption({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTheme.labelSmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// _StatItem (local to this sheet)
// ============================================

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatItem({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style:
              AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
        Text(
          value,
          style: AppTheme.titleSmall.copyWith(
            fontWeight: FontWeight.w600,
            color:
                highlight ? AppTheme.success : AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
