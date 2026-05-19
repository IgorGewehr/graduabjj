import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';
import '../../../widgets/form/form_widgets.dart';
import 'graduation_editor.dart';

class AcademyTab extends StatelessWidget {
  const AcademyTab({
    super.key,
    required this.startDate,
    required this.status,
    required this.grades,
    required this.primarySport,
    required this.category,
    required this.hasGradesError,
    required this.availablePlans,
    required this.selectedPlans,
    required this.tuitionValueController,
    required this.tuitionDayController,
    required this.healthNotesController,
    required this.allergiesController,
    required this.onStartDateChanged,
    required this.onStatusChanged,
    required this.onSetPrimary,
    required this.onRemoveSport,
    required this.onAddSport,
    required this.onGradeChanged,
    required this.onPlanToggle,
  });

  final DateTime startDate;
  final StudentStatus status;
  final Map<SportId, ({String belt, int stripes})> grades;
  final SportId? primarySport;
  final StudentCategory category;
  final bool hasGradesError;
  final List<Plan> availablePlans;
  final List<Plan> selectedPlans;
  final TextEditingController tuitionValueController;
  final TextEditingController tuitionDayController;
  final TextEditingController healthNotesController;
  final TextEditingController allergiesController;
  final ValueChanged<DateTime?> onStartDateChanged;
  final ValueChanged<StudentStatus?> onStatusChanged;
  final ValueChanged<SportId> onSetPrimary;
  final ValueChanged<SportId> onRemoveSport;
  final ValueChanged<SportId> onAddSport;
  final void Function(SportId sport, String belt, int stripes) onGradeChanged;
  final void Function(Plan plan, bool selected) onPlanToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FormSection(
          title: 'Informações da Academia',
          subtitle: 'Dados de matrícula e graduação',
          icon: LucideIcons.award,
          child: Column(
            children: [
              FormRow(
                children: [
                  DateInput(
                    value: startDate,
                    label: 'Data de Início',
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime(2015),
                    onChanged: onStartDateChanged,
                  ),
                  _StatusDropdown(status: status, onChanged: onStatusChanged),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        FormSection(
          title: 'Graduação',
          subtitle: 'Modalidades, faixas e graus atuais',
          icon: LucideIcons.medal,
          child: GraduationEditor(
            grades: grades,
            primarySport: primarySport,
            category: category,
            hasError: hasGradesError,
            onSetPrimary: onSetPrimary,
            onRemoveSport: onRemoveSport,
            onAddSport: onAddSport,
            onGradeChanged: onGradeChanged,
          ),
        ),

        const SizedBox(height: 16),

        FormSection(
          title: 'Financeiro (Opcional)',
          subtitle: 'Planos e mensalidade',
          icon: LucideIcons.wallet,
          collapsible: true,
          defaultCollapsed: true,
          child: Column(
            children: [
              _PlanSelector(
                availablePlans: availablePlans,
                selectedPlans: selectedPlans,
                onPlanToggle: onPlanToggle,
              ),
              const SizedBox(height: 16),
              FormRow(
                children: [
                  CurrencyInput(
                    controller: tuitionValueController,
                    label: 'Valor da Mensalidade (Opcional)',
                  ),
                  InputField(
                    controller: tuitionDayController,
                    label: 'Dia de Vencimento',
                    hintText: '1-31 (Opcional)',
                    prefixIcon: LucideIcons.calendar,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value?.isNotEmpty == true) {
                        final day = int.tryParse(value!);
                        if (day == null || day < 1 || day > 31) {
                          return 'Dia inválido (1-31)';
                        }
                      }
                      return null;
                    },
                    helperText: 'Em meses curtos, ajusta para o último dia',
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        FormSection(
          title: 'Saúde',
          subtitle: 'Informações médicas relevantes',
          icon: LucideIcons.heart,
          collapsible: true,
          defaultCollapsed:
              healthNotesController.text.isEmpty &&
              allergiesController.text.isEmpty,
          child: Column(
            children: [
              InputField(
                controller: allergiesController,
                label: 'Alergias',
                hintText: 'Liste alergias conhecidas...',
                prefixIcon: LucideIcons.alertCircle,
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              InputField(
                controller: healthNotesController,
                label: 'Observações de Saúde',
                hintText: 'Lesões, condições médicas, restrições...',
                prefixIcon: LucideIcons.clipboardList,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Status dropdown ───────────────────────────────────────────────────────────

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({required this.status, required this.onChanged});

  final StudentStatus status;
  final ValueChanged<StudentStatus?> onChanged;

  Color _getStatusColor(StudentStatus s) {
    switch (s) {
      case StudentStatus.active:
        return AppTheme.success;
      case StudentStatus.injured:
        return Colors.orange;
      case StudentStatus.inactive:
        return AppTheme.textDisabled;
      case StudentStatus.suspended:
        return AppTheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<StudentStatus>(
        value: status,
        isExpanded: true,
        icon: Icon(
          LucideIcons.chevronDown,
          color: AppTheme.textSecondary,
          size: 20,
        ),
        decoration: InputDecoration(
          labelText: 'Status',
          prefixIcon: Icon(
            LucideIcons.activity,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: StudentStatus.values.map((s) {
          return DropdownMenuItem(
            value: s,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getStatusColor(s),
                  ),
                ),
                const SizedBox(width: 8),
                Text(s.label, style: AppTheme.bodyMedium),
              ],
            ),
          );
        }).toList(),
        onChanged: onChanged,
        dropdownColor: AppTheme.surface,
      ),
    );
  }
}

// ── Plan selector ─────────────────────────────────────────────────────────────

class _PlanSelector extends StatelessWidget {
  const _PlanSelector({
    required this.availablePlans,
    required this.selectedPlans,
    required this.onPlanToggle,
  });

  final List<Plan> availablePlans;
  final List<Plan> selectedPlans;
  final void Function(Plan plan, bool selected) onPlanToggle;

  @override
  Widget build(BuildContext context) {
    final selectedIds = selectedPlans.map((p) => p.id).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.package, size: 20, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Planos',
              style:
                  AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availablePlans.map((plan) {
            final isSelected = selectedIds.contains(plan.id);
            return FilterChip(
              label: Text(
                '${plan.name} - R\$ ${plan.monthlyValue.toStringAsFixed(2).replaceAll('.', ',')}',
              ),
              selected: isSelected,
              onSelected: (selected) => onPlanToggle(plan, selected),
              selectedColor: AppTheme.primary.withValues(alpha: 0.15),
              checkmarkColor: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              side: BorderSide(
                color: isSelected ? AppTheme.primary : AppTheme.divider,
              ),
              labelStyle: AppTheme.bodyMedium.copyWith(
                color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
              ),
            );
          }).toList(),
        ),
        if (selectedPlans.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Nenhum plano selecionado (Projeto Social)',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
      ],
    );
  }
}
