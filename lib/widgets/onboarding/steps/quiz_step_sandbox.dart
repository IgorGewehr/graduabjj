import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../polish/polish.dart';

/// Passo 5 do Nível 1: Mini Simulação Prática (Sandbox de 3s / Aha! Moment)
class QuizStepSandbox extends StatefulWidget {
  final VoidCallback onNext;

  const QuizStepSandbox({
    super.key,
    required this.onNext,
  });

  @override
  State<QuizStepSandbox> createState() => _QuizStepSandboxState();
}

class _QuizStepSandboxState extends State<QuizStepSandbox> {
  bool _student1Checked = false;
  bool _student2Checked = false;
  bool _celebrated = false;

  void _checkStudent(int studentIndex) {
    HapticFeedback.heavyImpact();
    setState(() {
      if (studentIndex == 1) _student1Checked = true;
      if (studentIndex == 2) _student2Checked = true;

      if (!_celebrated) {
        _celebrated = true;
        Celebration.confetti(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyChecked = _student1Checked || _student2Checked;

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
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.sparkles, size: 14, color: AppTheme.success),
                    const SizedBox(width: 6),
                    Text(
                      'EXPERIÊNCIA PRÁTICA',
                      style: AppTheme.labelSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.success,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Veja como é rápido na prática!',
                style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Toque no card de um dos alunos para registrar a presença de hoje:',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.textPrimary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(LucideIcons.flame, size: 18, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Turma das 19:00',
                                  style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Treino Técnico Geral',
                                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Hoje',
                        style: AppTheme.labelSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                _buildMockStudentTile(
                  name: 'Lucas Silva',
                  grade: 'Faixa Azul • 2º Grau',
                  gradeColor: AppTheme.beltBlue,
                  isChecked: _student1Checked,
                  onTap: () => _checkStudent(1),
                ),
                const SizedBox(height: 10),
                _buildMockStudentTile(
                  name: 'Amanda Costa',
                  grade: 'Faixa Branca • 3º Grau',
                  gradeColor: AppTheme.beltWhite,
                  isChecked: _student2Checked,
                  onTap: () => _checkStudent(2),
                ),
              ],
            ),
          ),
          if (hasAnyChecked) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.check, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Presença computada!',
                          style: AppTheme.bodyLarge.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'O sistema contabilizou a aula e atualizou o progresso de graduação automaticamente.',
                          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).entrance(),
          ],
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
              child: Text(
                hasAnyChecked ? 'Concluir e Continuar' : 'Entendi, Continuar',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockStudentTile({
    required String name,
    required String grade,
    required Color gradeColor,
    required bool isChecked,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isChecked ? AppTheme.success.withValues(alpha: 0.08) : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isChecked ? AppTheme.success : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.textPrimary.withValues(alpha: 0.08),
                  child: Text(
                    name.substring(0, 1),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: gradeColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.divider),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            grade,
                            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isChecked ? AppTheme.success : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isChecked ? AppTheme.success : AppTheme.divider,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isChecked ? LucideIcons.check : LucideIcons.userCheck,
                        size: 14,
                        color: isChecked ? Colors.white : AppTheme.textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isChecked ? 'Presente' : 'Marcar',
                        style: AppTheme.labelSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isChecked ? Colors.white : AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
