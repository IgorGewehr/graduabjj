import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/portal_providers.dart';
import '../../../services/settings_service.dart';
import '../../polish/polish.dart';
import '../quiz_card_option.dart';

/// Passo 2 do Nível 2: Gamificação (Ranking & Meta de Frequência)
class QuizStepGamification extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const QuizStepGamification({
    super.key,
    required this.onNext,
  });

  @override
  ConsumerState<QuizStepGamification> createState() => _QuizStepGamificationState();
}

class _QuizStepGamificationState extends ConsumerState<QuizStepGamification> {
  bool _rankingVisible = true;
  int _monthlyGoal = 12; // 3x por semana
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(academySettingsProvider).valueOrNull;
    if (settings != null) {
      _rankingVisible = settings.rankingVisibleToStudents;
      if (settings.monthlyAttendanceGoal > 0) {
        _monthlyGoal = settings.monthlyAttendanceGoal;
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId != null) {
        final service = SettingsService(academyId);
        await service.updateRankingVisibility(_rankingVisible);
        await service.updateMonthlyAttendanceGoal(_monthlyGoal);
        ref.invalidate(academySettingsProvider);
      }
      widget.onNext();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar gamificação: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
                  color: AppTheme.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.trophy, size: 14, color: AppTheme.info),
                    const SizedBox(width: 6),
                    Text(
                      'SUPERPODER #2',
                      style: AppTheme.labelSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.info,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Gamificação & Motivação',
                style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Aumente a assiduidade dos seus alunos com competição saudável.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          QuizCardOption(
            title: 'Ativar Ranking de Presença',
            subtitle: 'Alunos mais dedicados sobem no pódio do aplicativo da academia.',
            badgeText: 'Engajamento',
            badgeColor: AppTheme.info,
            icon: LucideIcons.medal,
            isSelected: _rankingVisible,
            onTap: () => setState(() => _rankingVisible = true),
          ),
          QuizCardOption(
            title: 'Manter Frequência Privada',
            subtitle: 'Cada aluno visualiza apenas o seu próprio histórico de treinos.',
            icon: LucideIcons.lock,
            isSelected: !_rankingVisible,
            onTap: () => setState(() => _rankingVisible = false),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.target, size: 18, color: AppTheme.textPrimary),
                    const SizedBox(width: 8),
                    Text(
                      'Meta Mensal Recomendada',
                      style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Meta de aulas por mês para motivar os alunos a manterem o ritmo:',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    (goal: 8, label: '8 treinos/mês', sub: '2x por semana'),
                    (goal: 12, label: '12 treinos/mês', sub: '3x por semana (Ideal)'),
                    (goal: 16, label: '16 treinos/mês', sub: '4x por semana'),
                    (goal: 20, label: '20 treinos/mês', sub: 'Todos os dias'),
                  ].map((item) {
                    final isSelected = _monthlyGoal == item.goal;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _monthlyGoal = item.goal),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.textPrimary : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: AppTheme.bodySmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.sub,
                                style: AppTheme.labelSmall.copyWith(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.8)
                                      : AppTheme.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
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
