import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../widgets/form/form_widgets.dart';

class ContactTab extends StatelessWidget {
  const ContactTab({
    super.key,
    required this.emailController,
    required this.phoneController,
    required this.emergencyContactNameController,
    required this.emergencyContactPhoneController,
    required this.onChanged,
  });

  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController emergencyContactNameController;
  final TextEditingController emergencyContactPhoneController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FormSection(
          title: 'Contato Principal',
          subtitle: 'Formas de contato com o aluno',
          icon: LucideIcons.phone,
          child: Column(
            children: [
              FormRow(
                children: [
                  EmailInput(
                    controller: emailController,
                    onChanged: (_) => onChanged(),
                  ),
                  PhoneInput(
                    controller: phoneController,
                    onChanged: (_) => onChanged(),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        FormSection(
          title: 'Contato de Emergência',
          subtitle: 'Pessoa para contato em caso de emergência',
          icon: LucideIcons.alertTriangle,
          badge: 'Recomendado',
          badgeVariant: BadgeVariant.success,
          child: Column(
            children: [
              InputField(
                controller: emergencyContactNameController,
                label: 'Nome do Contato',
                prefixIcon: LucideIcons.user,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => onChanged(),
              ),
              const SizedBox(height: 16),
              PhoneInput(
                controller: emergencyContactPhoneController,
                label: 'Telefone de Emergência',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
