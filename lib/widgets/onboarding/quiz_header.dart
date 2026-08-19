import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../polish/polish.dart';

/// Top bar padronizada para o Quiz de Onboarding.
/// Exibe botão de voltar (se aplicável), categoria/passo,
/// barra de progresso suave e botão de "Pular".
class QuizHeader extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final String stageTitle;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final String skipLabel;

  const QuizHeader({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.stageTitle = 'Configuração Inicial',
    this.onBack,
    this.onSkip,
    this.skipLabel = 'Pular etapa',
  });

  @override
  Widget build(BuildContext context) {
    final progress = (currentStep / totalSteps).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  icon: const Icon(LucideIcons.arrowLeft, size: 20),
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  color: AppTheme.textPrimary,
                  tooltip: 'Voltar',
                )
              else
                const SizedBox(width: 4),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stageTitle.toUpperCase(),
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Passo $currentStep de $totalSteps',
                      style: AppTheme.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onSkip != null)
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    skipLabel,
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedProgressBar(
            value: progress,
            minHeight: 6,
            color: AppTheme.textPrimary,
            backgroundColor: AppTheme.surfaceVariant,
          ),
        ],
      ),
    );
  }
}
