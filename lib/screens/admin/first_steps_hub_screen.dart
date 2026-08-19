import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/academy.dart';
import '../../providers/portal_providers.dart';
import '../../widgets/onboarding/steps/quiz_step_attendance.dart';
import '../../widgets/onboarding/steps/quiz_step_billing.dart';
import '../../widgets/onboarding/steps/quiz_step_extra_modules.dart';
import '../../widgets/onboarding/steps/quiz_step_gamification.dart';
import '../../widgets/onboarding/steps/quiz_step_graduation_rules.dart';
import '../../widgets/onboarding/steps/quiz_step_modalities.dart';
import '../../widgets/onboarding/steps/quiz_step_retention.dart';
import '../../widgets/onboarding/steps/quiz_step_students.dart';

/// Central de Primeiros Passos — Acessível a qualquer momento em Configurações
/// Permite ao administrador revisar, configurar ou refazer qualquer módulo do onboarding.
class FirstStepsHubScreen extends ConsumerWidget {
  const FirstStepsHubScreen({super.key});

  void _openStepModal(BuildContext context, String title, Widget child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.88,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(academySettingsProvider);
    final settings = settingsAsync.valueOrNull;

    final profile = AcademyProfileExtension.fromString(settings?.profile);
    final sportsCount = settings?.effectiveSports.length ?? 1;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          'Central de Primeiros Passos',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Guia de Configuração da Academia',
                          style: AppTheme.titleMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Revise suas configurações básicas ou ative superpoderes para o seu dojô a qualquer momento.',
                    style: AppTheme.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/admin/comece-aqui'),
                    icon: const Icon(LucideIcons.play, size: 16),
                    label: const Text('Refazer Quiz Completo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Módulos de Configuração',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Acesse e edite qualquer etapa de forma independente:',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            _buildHubCard(
              context: context,
              icon: LucideIcons.shield,
              title: 'Modalidades & Foco do Espaço',
              subtitle: 'Perfil: ${profile == AcademyProfile.fight ? "Lutas" : profile == AcademyProfile.fitness ? "Fitness" : "Híbrido"} • $sportsCount modalidades ativas',
              statusBadge: 'Configurado',
              badgeColor: AppTheme.success,
              onTap: () => _openStepModal(
                context,
                'Modalidades & Perfil',
                QuizStepModalities(onNext: () => Navigator.of(context).pop()),
              ),
            ),
            _buildHubCard(
              context: context,
              icon: LucideIcons.creditCard,
              title: 'Faturamento & Chave PIX',
              subtitle: settings?.hasPixKey == true
                  ? 'PIX cadastrado: ${settings!.pixKey}'
                  : 'Configure Mercado Pago ou PIX direto',
              statusBadge: settings?.hasPixKey == true ? 'Ativo' : 'Pendente',
              badgeColor: settings?.hasPixKey == true ? AppTheme.success : AppTheme.warning,
              onTap: () => _openStepModal(
                context,
                'Faturamento & Cobrança',
                QuizStepBilling(onNext: () => Navigator.of(context).pop()),
              ),
            ),
            _buildHubCard(
              context: context,
              icon: LucideIcons.userPlus,
              title: 'Entrada de Alunos & Código de Convite',
              subtitle: 'Compartilhe o código de entrada no grupo do WhatsApp da academia',
              statusBadge: 'Pronto',
              badgeColor: AppTheme.info,
              onTap: () => _openStepModal(
                context,
                'Convite de Alunos',
                QuizStepStudents(onNext: () => Navigator.of(context).pop()),
              ),
            ),
            _buildHubCard(
              context: context,
              icon: LucideIcons.clipboardCheck,
              title: 'Método de Chamada & Presença',
              subtitle: settings?.studentCheckinEnabled == true
                  ? 'Check-in via QR Code no Tatame'
                  : settings?.accessControlEnabled == true
                      ? 'Catraca Eletrônica integrada'
                      : 'Chamada pelo app do professor',
              statusBadge: 'Definido',
              badgeColor: AppTheme.success,
              onTap: () => _openStepModal(
                context,
                'Método de Presença',
                QuizStepAttendance(onNext: () => Navigator.of(context).pop()),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Superpoderes & Recursos Extras',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            _buildHubCard(
              context: context,
              icon: LucideIcons.shieldAlert,
              title: 'Radar de Retenção (Alunos Inativos)',
              subtitle: 'Alerta quando um aluno ficar sem treinar para mandar WhatsApp',
              onTap: () => _openStepModal(
                context,
                'Radar de Retenção',
                QuizStepRetention(onNext: () => Navigator.of(context).pop()),
              ),
            ),
            _buildHubCard(
              context: context,
              icon: LucideIcons.trophy,
              title: 'Gamificação & Ranking de Presença',
              subtitle: settings?.rankingVisibleToStudents == true
                  ? 'Ranking público ativo • Meta: ${settings?.monthlyAttendanceGoal ?? 12} treinos/mês'
                  : 'Ranking privado',
              onTap: () => _openStepModal(
                context,
                'Gamificação',
                QuizStepGamification(onNext: () => Navigator.of(context).pop()),
              ),
            ),
            _buildHubCard(
              context: context,
              icon: LucideIcons.award,
              title: 'Regras de Graduação & Faixas',
              subtitle: settings?.graduationMode == 'auto'
                  ? 'Promoção 100% automática por presença'
                  : 'Aprovação manual sob comando do Mestre',
              onTap: () => _openStepModal(
                context,
                'Regras de Graduação',
                QuizStepGraduationRules(onNext: () => Navigator.of(context).pop()),
              ),
            ),
            _buildHubCard(
              context: context,
              icon: LucideIcons.boxes,
              title: 'Módulos Extras (Loja, Vídeos, Agendamento)',
              subtitle: 'Ligue ou desligue módulos adicionais da sua academia',
              onTap: () => _openStepModal(
                context,
                'Módulos Extras',
                QuizStepExtraModules(onFinish: () => Navigator.of(context).pop()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    String? statusBadge,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: AppTheme.textPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: AppTheme.bodyLarge.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (statusBadge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (badgeColor ?? AppTheme.info).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusBadge,
                                style: AppTheme.labelSmall.copyWith(
                                  color: badgeColor ?? AppTheme.info,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.chevronRight, size: 18, color: AppTheme.textDisabled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
