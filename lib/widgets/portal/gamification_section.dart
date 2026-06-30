import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/gamification.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../services/achievement_service.dart';

/// Home gamification surfacing (A4): monthly attendance goal progress, the
/// student's monthly ranking position, and their most recent achievements.
/// Each piece is conditional; renders nothing when there's nothing to show.
class GamificationSection extends ConsumerWidget {
  final Student student;
  const GamificationSection({super.key, required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final goal = effectiveMonthlyGoal(
        student.monthlyAttendanceGoal, settings?.monthlyAttendanceGoal ?? 0);
    final monthCount =
        ref.watch(studentMonthlyAttendanceProvider(student.id)).valueOrNull ?? 0;
    // Privacidade: respeita rankingVisibleToStudents — se a academia escondeu o
    // ranking dos alunos, NÃO vaza a posição aqui (meta mensal e conquistas
    // seguem). Default true (academias legadas). Espelha o gate do ranking_screen.
    final rankingVisible = settings?.rankingVisibleToStudents ?? true;
    final rank = rankingVisible
        ? ref.watch(studentMonthlyRankProvider(student.id)).valueOrNull
        : null;
    final achievements =
        ref.watch(studentAchievementsProvider(student.id)).valueOrNull ??
            const [];
    final recent = achievements.take(3).toList();

    final hasGoal = goal > 0;
    if (!hasGoal && rank == null && recent.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasGoal || rank != null)
            _monthCard(context, goal, monthCount, rank),
          if (recent.isNotEmpty) _recentCard(context, recent),
        ],
      ),
    );
  }

  Widget _monthCard(BuildContext context, int goal, int count, int? rank) {
    final p = monthlyGoalProgress(count, goal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.target, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Seu mês',
                    style: AppTheme.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (rank != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.trophy,
                            size: 13, color: AppTheme.warning),
                        const SizedBox(width: 4),
                        Text('$rankº no ranking',
                            style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.warning,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
            if (goal > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('$count', // count
                      style: AppTheme.titleLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: p.reached ? AppTheme.success : AppTheme.primary)),
                  Text(' / $goal aulas',
                      style: AppTheme.bodyMedium
                          .copyWith(color: AppTheme.textSecondary)),
                  const Spacer(),
                  if (p.reached)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.checkCircle,
                            size: 16, color: AppTheme.success),
                        const SizedBox(width: 4),
                        Text('Meta batida!',
                            style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.success,
                                fontWeight: FontWeight.w700)),
                      ],
                    )
                  else
                    Text('faltam ${p.remaining}',
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: p.pct,
                  minHeight: 8,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(
                      p.reached ? AppTheme.success : AppTheme.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recentCard(BuildContext context, List<Achievement> recent) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.medal, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Conquistas recentes',
                    style: AppTheme.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/portal/linha-do-tempo'),
                  child: const Text('Ver todas'),
                ),
              ],
            ),
            ...recent.map((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(_iconFor(a), size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(a.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.bodyMedium),
                      ),
                      Text(
                          '${a.date.day.toString().padLeft(2, '0')}/${a.date.month.toString().padLeft(2, '0')}',
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(Achievement a) {
    switch (a.type) {
      case AchievementType.graduation:
      case AchievementType.stripe:
        return LucideIcons.award;
      case AchievementType.competition:
        return LucideIcons.trophy;
      case AchievementType.attendanceStreak:
        return LucideIcons.flame;
      case AchievementType.rankingPosition:
        return LucideIcons.trendingUp;
      case AchievementType.trainingPr:
        return LucideIcons.dumbbell;
      case AchievementType.milestone:
        return LucideIcons.star;
    }
  }
}
