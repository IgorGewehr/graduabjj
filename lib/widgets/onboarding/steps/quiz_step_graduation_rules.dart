import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/academy.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/portal_providers.dart';
import '../../../services/settings_service.dart';
import '../../polish/polish.dart';
import '../quiz_card_option.dart';

/// Passo 3 do Nível 2: Regras de Graduação & Faixas
class QuizStepGraduationRules extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const QuizStepGraduationRules({
    super.key,
    required this.onNext,
  });

  @override
  ConsumerState<QuizStepGraduationRules> createState() =>
      _QuizStepGraduationRulesState();
}

class _QuizStepGraduationRulesState extends ConsumerState<QuizStepGraduationRules> {
  String _graduationMode = 'manual';
  String _skillPolicy = 'informative';
  bool _studentCanSeeProgress = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(academySettingsProvider).valueOrNull;
    if (settings != null) {
      _graduationMode = settings.graduationMode;
      _skillPolicy = settings.graduationSkillPolicy;
      _studentCanSeeProgress = settings.graduationProgressVisibleToStudents;
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId != null) {
        final service = SettingsService(academyId);
        await service.updateAutoGraduation(
          true,
          attendances: 40, // default de aulas por grau
          mode: _graduationMode,
          progressVisibleToStudents: _studentCanSeeProgress,
          skillPolicy: _skillPolicy,
        );
        ref.invalidate(academySettingsProvider);
      }
      widget.onNext();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar regras de graduação: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final isFitness = settings?.profile == AcademyProfile.fitness.value;

    if (isFitness) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Perfil Fitness / Sem Faixa',
              style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Como o seu espaço é focado em Fitness/Musculação, o sistema de faixas marciais fica desabilitado por padrão.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.textPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Continuar', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.beltPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.award, size: 14, color: AppTheme.beltPurple),
                    const SizedBox(width: 6),
                    Text(
                      'SUPERPODER #3',
                      style: AppTheme.labelSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.beltPurple,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Regras de Graduação',
                style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Defina como o sistema auxilia na promoção de faixas e graus.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          QuizCardOption(
            title: 'Aprovação Manual do Mestre',
            subtitle: 'O sistema avisa quem bateu a meta de aulas, mas o professor decide quando promover.',
            badgeText: 'Tradicional',
            badgeColor: AppTheme.info,
            icon: LucideIcons.userCheck,
            isSelected: _graduationMode == 'manual' && _skillPolicy == 'informative',
            onTap: () => setState(() {
              _graduationMode = 'manual';
              _skillPolicy = 'informative';
            }),
          ),
          QuizCardOption(
            title: 'Promoção Automática por Presença',
            subtitle: 'Ao completar a quantidade de treinos da faixa, o grau é adicionado automaticamente.',
            badgeText: '100% Automático',
            badgeColor: AppTheme.success,
            icon: LucideIcons.sparkles,
            isSelected: _graduationMode == 'auto',
            onTap: () => setState(() {
              _graduationMode = 'auto';
              _skillPolicy = 'informative';
            }),
          ),
          QuizCardOption(
            title: 'Critério Misto (Presença + Técnicas)',
            subtitle: 'Exige número de aulas E domínio das técnicas do currículo para liberar o exame.',
            badgeText: 'Currículo',
            badgeColor: AppTheme.warning,
            icon: LucideIcons.bookOpen,
            isSelected: _skillPolicy == 'required',
            onTap: () => setState(() {
              _graduationMode = 'manual';
              _skillPolicy = 'required';
            }),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Continuar',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
