import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../widgets/form/form_widgets.dart';

class PersonalTab extends StatelessWidget {
  const PersonalTab({
    super.key,
    required this.fullNameController,
    required this.nicknameController,
    required this.cpfController,
    required this.birthDate,
    required this.category,
    required this.guardianNameController,
    required this.guardianPhoneController,
    required this.guardianEmailController,
    required this.guardianCpfController,
    required this.guardianRelationship,
    required this.onChanged,
    required this.onBirthDateChanged,
    required this.onCategoryChanged,
    required this.onGuardianRelationshipChanged,
  });

  final TextEditingController fullNameController;
  final TextEditingController nicknameController;
  final TextEditingController cpfController;
  final DateTime? birthDate;
  final StudentCategory category;
  final TextEditingController guardianNameController;
  final TextEditingController guardianPhoneController;
  final TextEditingController guardianEmailController;
  final TextEditingController guardianCpfController;
  final String guardianRelationship;
  final VoidCallback onChanged;
  final ValueChanged<DateTime?> onBirthDateChanged;
  final ValueChanged<StudentCategory?> onCategoryChanged;
  final ValueChanged<String?> onGuardianRelationshipChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FormSection(
          title: 'Dados Pessoais',
          subtitle: 'Informações básicas do aluno',
          icon: LucideIcons.user,
          badge: 'Obrigatório',
          badgeVariant: BadgeVariant.warning,
          child: Column(
            children: [
              InputField(
                controller: fullNameController,
                label: 'Nome Completo',
                prefixIcon: LucideIcons.user,
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value?.isEmpty == true ? 'Nome é obrigatório' : null,
                onChanged: (_) => onChanged(),
              ),
              const SizedBox(height: 16),
              FormRow(
                children: [
                  InputField(
                    controller: nicknameController,
                    label: 'Apelido',
                    hintText: 'Como prefere ser chamado',
                    prefixIcon: LucideIcons.smile,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => onChanged(),
                  ),
                  CPFInput(
                    controller: cpfController,
                    onChanged: (_) => onChanged(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FormRow(
                children: [
                  DateInput(
                    value: birthDate,
                    label: 'Data de Nascimento',
                    lastDate: DateTime.now(),
                    firstDate: DateTime(1930),
                    onChanged: onBirthDateChanged,
                  ),
                  _CategoryDropdown(
                    category: category,
                    onChanged: onCategoryChanged,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Guardian section (for kids)
        if (category == StudentCategory.kids)
          FormSection(
            title: 'Responsável',
            subtitle: 'Dados do responsável pelo menor',
            icon: LucideIcons.users,
            badge: 'Obrigatório',
            badgeVariant: BadgeVariant.warning,
            child: Column(
              children: [
                FormRow(
                  children: [
                    InputField(
                      controller: guardianNameController,
                      label: 'Nome do Responsável',
                      prefixIcon: LucideIcons.user,
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (category == StudentCategory.kids &&
                            (value?.isEmpty ?? true)) {
                          return 'Responsável obrigatório para menores';
                        }
                        return null;
                      },
                    ),
                    PhoneInput(
                      controller: guardianPhoneController,
                      label: 'WhatsApp do Responsável',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FormRow(
                  children: [
                    EmailInput(
                      controller: guardianEmailController,
                      label: 'E-mail do Responsável',
                    ),
                    CPFInput(
                      controller: guardianCpfController,
                      label: 'CPF do Responsável',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _GuardianRelationshipDropdown(
                  value: guardianRelationship,
                  onChanged: onGuardianRelationshipChanged,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.category,
    required this.onChanged,
  });

  final StudentCategory category;
  final ValueChanged<StudentCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<StudentCategory>(
        value: category,
        isExpanded: true,
        icon: Icon(
          LucideIcons.chevronDown,
          color: AppTheme.textSecondary,
          size: 20,
        ),
        decoration: InputDecoration(
          labelText: 'Categoria',
          prefixIcon: Icon(
            LucideIcons.users,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: StudentCategory.values.map((cat) {
          return DropdownMenuItem(
            value: cat,
            child: Text(cat.label, style: AppTheme.bodyMedium),
          );
        }).toList(),
        onChanged: onChanged,
        dropdownColor: AppTheme.surface,
      ),
    );
  }
}

class _GuardianRelationshipDropdown extends StatelessWidget {
  const _GuardianRelationshipDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = ['Pai', 'Mãe', 'Avô/Avó', 'Tio/Tia', 'Outro'];
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<String>(
        value: value.isEmpty ? null : value,
        isExpanded: true,
        icon: Icon(
          LucideIcons.chevronDown,
          color: AppTheme.textSecondary,
          size: 20,
        ),
        decoration: InputDecoration(
          labelText: 'Parentesco',
          prefixIcon: Icon(
            LucideIcons.users,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: options.map((rel) {
          return DropdownMenuItem(
            value: rel,
            child: Text(rel, style: AppTheme.bodyMedium),
          );
        }).toList(),
        onChanged: onChanged,
        dropdownColor: AppTheme.surface,
      ),
    );
  }
}
