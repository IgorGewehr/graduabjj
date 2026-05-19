import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../widgets/cached_image.dart';
import 'settings_shared_widgets.dart';

/// Content for the "Academia" settings tab.
///
/// All data is passed in by the parent [_AdminSettingsScreenState] so that
/// state (controllers, logo URL, callbacks) stays in a single place.
class AcademyTab extends StatelessWidget {
  final String? logoUrl;
  final VoidCallback onPickLogo;
  final TextEditingController nameController;
  final TextEditingController sloganController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController cnpjController;
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController stateController;
  final TextEditingController zipCodeController;
  final TextEditingController birthDateController;
  final VoidCallback onPickBirthDate;

  const AcademyTab({
    super.key,
    required this.logoUrl,
    required this.onPickLogo,
    required this.nameController,
    required this.sloganController,
    required this.emailController,
    required this.phoneController,
    required this.cnpjController,
    required this.addressController,
    required this.cityController,
    required this.stateController,
    required this.zipCodeController,
    required this.birthDateController,
    required this.onPickBirthDate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('academy'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Logo Section
          SettingsCard(
            title: 'Logo e Identidade',
            icon: LucideIcons.image,
            child: Column(
              children: [
                GestureDetector(
                  onTap: onPickLogo,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.divider, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (logoUrl ?? '').isEmpty
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.upload,
                                color: AppTheme.textSecondary,
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Adicionar',
                                style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Positioned.fill(
                                child: AppCachedImage(
                                  imageUrl: logoUrl,
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppTheme.textPrimary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  LucideIcons.pencil,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Toque para ${logoUrl != null ? 'alterar' : 'adicionar'} o logo',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Name and Slogan
          SettingsCard(
            title: 'Informacoes Basicas',
            icon: LucideIcons.building2,
            child: Column(
              children: [
                ModernTextField(
                  controller: nameController,
                  label: 'Nome da Academia',
                  hint: 'Ex: Academia de Jiu-Jitsu',
                  icon: LucideIcons.building,
                ),
                const SizedBox(height: 16),
                ModernTextField(
                  controller: sloganController,
                  label: 'Frase / Slogan',
                  hint: 'Ex: Transformando vidas atraves do Jiu-Jitsu',
                  icon: LucideIcons.quote,
                  maxLines: 2,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Contact Info
          SettingsCard(
            title: 'Contato',
            icon: LucideIcons.phone,
            child: Column(
              children: [
                ModernTextField(
                  controller: emailController,
                  label: 'E-mail',
                  hint: 'contato@academia.com',
                  icon: LucideIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                ModernTextField(
                  controller: phoneController,
                  label: 'Telefone',
                  hint: '(11) 99999-9999',
                  icon: LucideIcons.phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                ModernTextField(
                  controller: cnpjController,
                  label: 'CPF/CNPJ',
                  hint: 'CPF do responsavel ou CNPJ da academia',
                  icon: LucideIcons.fileText,
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Address
          SettingsCard(
            title: 'Endereco',
            icon: LucideIcons.mapPin,
            child: Column(
              children: [
                ModernTextField(
                  controller: addressController,
                  label: 'Endereco',
                  hint: 'Rua, numero, bairro',
                  icon: LucideIcons.home,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ModernTextField(
                        controller: cityController,
                        label: 'Cidade',
                        hint: 'Sao Paulo',
                        icon: LucideIcons.building2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ModernTextField(
                        controller: stateController,
                        label: 'UF',
                        hint: 'SP',
                        icon: LucideIcons.map,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ModernTextField(
                        controller: zipCodeController,
                        label: 'CEP',
                        hint: '00000-000',
                        icon: LucideIcons.mailbox,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ModernTextField(
                        controller: birthDateController,
                        label: 'Nascimento do Responsavel',
                        hint: 'Selecione a data',
                        icon: LucideIcons.calendarDays,
                        readOnly: true,
                        onTap: onPickBirthDate,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
