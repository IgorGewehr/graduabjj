import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../cached_image.dart';
import '../../common/grade_display.dart';
import '../../polish/polish.dart';

/// Passo 4 do Nível 1: Mini Simulação Prática (Chamada Real do Tatame)
/// Espelha fielmente a tela real de chamada do app (AttendanceScreen)
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
  bool _student3Checked = false;
  bool _celebrated = false;

  int get _presentCount =>
      11 +
      (_student1Checked ? 1 : 0) +
      (_student2Checked ? 1 : 0) +
      (_student3Checked ? 1 : 0);

  static const int _totalStudents = 14;

  void _toggleStudent(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      if (index == 1) _student1Checked = !_student1Checked;
      if (index == 2) _student2Checked = !_student2Checked;
      if (index == 3) _student3Checked = !_student3Checked;

      if ((_student1Checked || _student2Checked || _student3Checked) && !_celebrated) {
        _celebrated = true;
        Celebration.confetti(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyChecked = _student1Checked || _student2Checked || _student3Checked;
    final progress = _presentCount / _totalStudents;

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
                'Toque em um aluno para marcar presença na chamada da turma:',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          Container(
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
                // Header da Turma
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
                                  child: const Icon(
                                    LucideIcons.flame,
                                    size: 18,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Turma das 19:00',
                                        style: AppTheme.titleMedium.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Jiu-Jitsu Adulto • Noite',
                                        style: AppTheme.bodySmall.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
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
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Presentes no Tatame',
                            style: AppTheme.labelSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            '$_presentCount de $_totalStudents alunos',
                            style: AppTheme.bodySmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: AppTheme.surfaceVariant,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Lista de Alunos (idêntica à tela real de chamada)
                _buildStudentItem(
                  index: 1,
                  name: 'Lucas Silva',
                  grade: 'blue',
                  stripes: 2,
                  attendancesCount: 35,
                  isPresent: _student1Checked,
                  onTap: () => _toggleStudent(1),
                ),
                const Divider(height: 1, indent: 64),
                _buildStudentItem(
                  index: 2,
                  name: 'Amanda Costa',
                  grade: 'white',
                  stripes: 3,
                  attendancesCount: 39,
                  isPresent: _student2Checked,
                  onTap: () => _toggleStudent(2),
                ),
                const Divider(height: 1, indent: 64),
                _buildStudentItem(
                  index: 3,
                  name: 'Rafael Mendonça',
                  grade: 'purple',
                  stripes: 1,
                  attendancesCount: 62,
                  isPresent: _student3Checked,
                  onTap: () => _toggleStudent(3),
                ),
              ],
            ),
          ),
          if (hasAnyChecked) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
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
                          'Presença registrada com sucesso!',
                          style: AppTheme.bodyLarge.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'A presença entra no histórico do aluno, conta para a graduação de faixa e fica salva no relatório da turma.',
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

  Widget _buildStudentItem({
    required int index,
    required String name,
    required String grade,
    required int stripes,
    required int attendancesCount,
    required bool isPresent,
    required VoidCallback onTap,
  }) {
    final effectiveAttendances = isPresent ? attendancesCount + 1 : attendancesCount;

    return Material(
      color: isPresent ? AppTheme.success.withValues(alpha: 0.05) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              AppCachedAvatar(
                imageUrl: null,
                radius: 19,
                backgroundColor: isPresent
                    ? AppTheme.success.withValues(alpha: 0.15)
                    : AppTheme.surfaceVariant,
                child: Text(
                  name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: isPresent ? AppTheme.success : AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isPresent ? AppTheme.success : AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        GradeDisplay(
                          sportId: SportId.bjj,
                          grade: grade,
                          stripes: stripes,
                          size: GradeDisplaySize.small,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• $effectiveAttendances aulas',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isPresent ? AppTheme.success : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isPresent ? AppTheme.success : AppTheme.divider,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPresent ? LucideIcons.check : LucideIcons.userCheck,
                      size: 14,
                      color: isPresent ? Colors.white : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPresent ? 'Presente' : 'Marcar',
                      style: AppTheme.labelSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isPresent ? Colors.white : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
