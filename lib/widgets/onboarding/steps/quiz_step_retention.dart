import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../polish/polish.dart';
import '../quiz_card_option.dart';

/// Passo 1 do Nível 2: Radar de Retenção (Alunos Sumidos)
class QuizStepRetention extends StatefulWidget {
  final VoidCallback onNext;

  const QuizStepRetention({
    super.key,
    required this.onNext,
  });

  @override
  State<QuizStepRetention> createState() => _QuizStepRetentionState();
}

class _QuizStepRetentionState extends State<QuizStepRetention> {
  bool _enableRetention = true;

  @override
  Widget build(BuildContext context) {
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
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.shieldAlert, size: 14, color: AppTheme.warning),
                    const SizedBox(width: 6),
                    Text(
                      'SUPERPODER #1',
                      style: AppTheme.labelSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.warning,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Radar de Alunos Inativos',
                style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Evite cancelamentos de matrícula recuperando alunos antes que desistam.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          QuizCardOption(
            title: 'Usar Radar de Alunos Sumidos',
            subtitle: 'O sistema identifica automaticamente quem ficar 7+ dias sem treinar. O WhatsApp só abre quando você tocar e confirmar o envio.',
            badgeText: 'Anti-Churn',
            badgeColor: AppTheme.error,
            icon: LucideIcons.messageSquare,
            isSelected: _enableRetention,
            onTap: () => setState(() => _enableRetention = true),
          ),
          QuizCardOption(
            title: 'Ver o radar depois',
            subtitle: 'O acompanhamento continuará disponível no menu Retenção, sem enviar mensagens automaticamente.',
            icon: LucideIcons.bellOff,
            isSelected: !_enableRetention,
            onTap: () => setState(() => _enableRetention = false),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text(
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
