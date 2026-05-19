import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/delete_account_helper.dart';
import 'settings_shared_widgets.dart';

/// Content for the "Funcionalidades" settings tab (auto-graduation, store,
/// check-in, account actions).
class FeaturesTab extends ConsumerWidget {
  final bool autoGraduationEnabled;
  final ValueChanged<bool> onAutoGraduationChanged;
  final TextEditingController autoGraduationAttendancesController;
  final bool useClassWeights;
  final ValueChanged<bool> onUseClassWeightsChanged;
  final bool studentCheckinEnabled;
  final ValueChanged<bool> onStudentCheckinChanged;
  final bool storeEnabled;
  final ValueChanged<bool> onStoreEnabledChanged;
  final bool storePublished;
  final ValueChanged<bool> onStorePublishedChanged;
  final TextEditingController storeWelcomeController;
  final TextEditingController storeMinAmountController;
  final bool storeCreditCardEnabled;

  const FeaturesTab({
    super.key,
    required this.autoGraduationEnabled,
    required this.onAutoGraduationChanged,
    required this.autoGraduationAttendancesController,
    required this.useClassWeights,
    required this.onUseClassWeightsChanged,
    required this.studentCheckinEnabled,
    required this.onStudentCheckinChanged,
    required this.storeEnabled,
    required this.onStoreEnabledChanged,
    required this.storePublished,
    required this.onStorePublishedChanged,
    required this.storeWelcomeController,
    required this.storeMinAmountController,
    required this.storeCreditCardEnabled,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('features'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Auto-graduation settings
          SettingsCard(
            title: 'Graduacao Automatica',
            icon: LucideIcons.award,
            child: Column(
              children: [
                ModernSwitch(
                  title: 'Habilitar Graduacao Automatica',
                  subtitle:
                      'Sinaliza alunos elegiveis com base no numero de presencas',
                  value: autoGraduationEnabled,
                  onChanged: onAutoGraduationChanged,
                  icon: LucideIcons.award,
                  iconColor: AppTheme.warning,
                ),
                if (autoGraduationEnabled) ...[
                  const SizedBox(height: 16),
                  ModernTextField(
                    controller: autoGraduationAttendancesController,
                    label: 'Presencas para graduar',
                    hint: '70',
                    icon: LucideIcons.target,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  _InfoBox(
                    color: AppTheme.info,
                    message:
                        'Alunos serao destacados na lista quando atingirem o numero configurado. A graduacao em si precisa ser confirmada por um admin.',
                  ),
                  const SizedBox(height: 16),
                  ModernSwitch(
                    title: 'Usar pesos por turma',
                    subtitle:
                        'Aula particular pode valer 2 ou mais (configurado por turma)',
                    value: useClassWeights,
                    onChanged: onUseClassWeightsChanged,
                    icon: LucideIcons.scale,
                    iconColor: AppTheme.info,
                  ),
                  if (useClassWeights) ...[
                    const SizedBox(height: 12),
                    _InfoBox(
                      color: AppTheme.warning,
                      message:
                          'Defina o peso de cada turma na tela de Turmas. Turmas sem peso configurado contam como 1.',
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Student Check-in Settings
          SettingsCard(
            title: 'Check-in de Alunos',
            icon: LucideIcons.userCheck,
            child: Column(
              children: [
                ModernSwitch(
                  title: 'Habilitar Check-in',
                  subtitle: 'Alunos podem marcar presenca pelo app',
                  value: studentCheckinEnabled,
                  onChanged: onStudentCheckinChanged,
                  icon: LucideIcons.userCheck,
                  iconColor: AppTheme.success,
                ),
                if (studentCheckinEnabled) ...[
                  const SizedBox(height: 12),
                  _InfoBox(
                    color: AppTheme.info,
                    message:
                        'Alunos podem fazer check-in de 30 min antes ate 1h apos o fim da aula. O professor confirma as presencas na tela de chamada.',
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Store Settings
          SettingsCard(
            title: 'Loja',
            icon: LucideIcons.shoppingBag,
            child: Column(
              children: [
                ModernSwitch(
                  title: 'Habilitar Loja',
                  subtitle: 'Ativar modulo de produtos e vendas',
                  value: storeEnabled,
                  onChanged: onStoreEnabledChanged,
                  icon: LucideIcons.store,
                  iconColor: AppTheme.warning,
                ),
                if (storeEnabled) ...[
                  const SizedBox(height: 16),
                  ModernSwitch(
                    title: 'Loja Publicada',
                    subtitle: 'Tornar a loja visivel para alunos',
                    value: storePublished,
                    onChanged: onStorePublishedChanged,
                    icon: LucideIcons.eye,
                    iconColor: AppTheme.success,
                  ),
                  const SizedBox(height: 16),
                  ModernTextField(
                    controller: storeWelcomeController,
                    label: 'Mensagem de Boas-vindas',
                    hint: 'Bem-vindo a nossa loja!',
                    icon: LucideIcons.messageSquare,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  ModernTextField(
                    controller: storeMinAmountController,
                    label: 'Pedido Minimo (R\$)',
                    hint: '0.00',
                    icon: LucideIcons.dollarSign,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ModernSwitch(
                    title: 'Permitir Cartao de Credito',
                    subtitle: 'Em breve',
                    value: false,
                    onChanged: null,
                    icon: LucideIcons.creditCard,
                    iconColor: AppTheme.textSecondary,
                    disabled: true,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Account section
          SettingsCard(
            title: 'Conta',
            icon: LucideIcons.user,
            child: Column(
              children: [
                AccountActionTile(
                  icon: LucideIcons.fileText,
                  title: 'Termos de Uso',
                  onTap: () => _openUrl(AppConstants.termsOfServiceUrl),
                ),
                const SizedBox(height: 8),
                AccountActionTile(
                  icon: LucideIcons.shield,
                  title: 'Politica de Privacidade',
                  onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
                ),
                const SizedBox(height: 8),
                AccountActionTile(
                  icon: LucideIcons.logOut,
                  title: 'Sair da conta',
                  subtitle: 'Encerrar sessao atual',
                  isDestructive: true,
                  onTap: () async {
                    final authService = ref.read(authServiceProvider);
                    await authService.signOut();
                  },
                ),
                const SizedBox(height: 8),
                AccountActionTile(
                  icon: LucideIcons.trash2,
                  title: 'Excluir minha conta',
                  subtitle: 'Remover permanentemente seus dados',
                  isDestructive: true,
                  onTap: () =>
                      DeleteAccountHelper.showConfirmation(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _InfoBox extends StatelessWidget {
  final Color color;
  final String message;

  const _InfoBox({required this.color, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTheme.labelSmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
