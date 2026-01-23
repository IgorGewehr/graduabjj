import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/common/stat_card.dart';
import '../../widgets/common/belt_badge.dart';

/// Home Screen - Portal do Aluno
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final student = ref.watch(currentStudentProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(currentUserProvider);
        ref.invalidate(currentStudentProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header
            _WelcomeHeader(
              userName: currentUser.valueOrNull?.displayName ?? 'Aluno',
            ).animate().fadeIn(duration: 300.ms),

            const SizedBox(height: 24),

            // Quick stats row
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                final countAsync = ref.watch(studentAttendanceCountProvider(s.id));
                return countAsync.when(
                  data: (count) => Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          title: 'Presencas',
                          value: count.toString(),
                          subtitle: 'Total de treinos',
                          icon: LucideIcons.clipboardCheck,
                          iconColor: AppTheme.success,
                        ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          title: 'Faixa',
                          value: _getBeltName(s.currentBelt),
                          subtitle: '${s.currentStripes} grau${s.currentStripes != 1 ? 's' : ''}',
                          icon: LucideIcons.award,
                          iconColor: _getBeltColor(s.currentBelt),
                        ).animate().fadeIn(delay: 200.ms).slideX(begin: 0.1),
                      ),
                    ],
                  ),
                  loading: () => _buildStatsLoading(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
              loading: () => _buildStatsLoading(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            // Belt progress card
            _BeltProgressCard()
                .animate()
                .fadeIn(delay: 300.ms)
                .slideY(begin: 0.1),

            const SizedBox(height: 24),

            // Next class card
            _NextClassCard()
                .animate()
                .fadeIn(delay: 400.ms)
                .slideY(begin: 0.1),

            const SizedBox(height: 24),

            // Recent achievements
            _RecentAchievementsSection()
                .animate()
                .fadeIn(delay: 500.ms)
                .slideY(begin: 0.1),

            const SizedBox(height: 24),

            // Upcoming competitions
            _UpcomingCompetitionsSection()
                .animate()
                .fadeIn(delay: 600.ms)
                .slideY(begin: 0.1),

            const SizedBox(height: 80), // Bottom padding for nav bar
          ],
        ),
      ),
    );
  }

  Widget _buildStatsLoading() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  String _getBeltName(String belt) {
    const names = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
    };
    return names[belt] ?? belt;
  }

  Color _getBeltColor(String belt) {
    switch (belt) {
      case 'white':
        return Colors.grey;
      case 'blue':
        return Colors.blue;
      case 'purple':
        return Colors.purple;
      case 'brown':
        return Colors.brown;
      case 'black':
        return Colors.black;
      default:
        return Colors.grey;
    }
  }
}

/// Welcome header with greeting
class _WelcomeHeader extends StatelessWidget {
  final String userName;

  const _WelcomeHeader({required this.userName});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_greeting,',
          style: AppTheme.bodyLarge.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          userName.split(' ').first,
          style: AppTheme.displaySmall.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Belt progress card with real data
class _BeltProgressCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);
    final eligibilityAsync = ref.watch(beltEligibilityProvider);
    final progressAsync = ref.watch(beltProgressProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildEmptyCard();
        }

        final eligibility = eligibilityAsync.valueOrNull;
        final progress = progressAsync.valueOrNull ?? 0.0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BeltBadge(belt: student.currentBelt, stripes: student.currentStripes),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Faixa ${_getBeltName(student.currentBelt)}',
                          style: AppTheme.titleLarge.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${student.currentStripes} grau${student.currentStripes != 1 ? 's' : ''}',
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.successLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${student.totalAttendanceCount} presencas',
                      style: AppTheme.labelMedium.copyWith(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Progress bar
              if (eligibility != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          eligibility.nextStripes == 0
                              ? 'Proxima faixa'
                              : 'Proximo grau',
                          style: AppTheme.labelMedium.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          '${eligibility.currentClasses}/${eligibility.requiredClasses}',
                          style: AppTheme.labelMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: AppTheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          eligibility.eligible ? AppTheme.success : AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      eligibility.message,
                      style: AppTheme.bodySmall.copyWith(
                        color: eligibility.eligible
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                        fontWeight: eligibility.eligible
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
      loading: () => _buildLoadingCard(),
      error: (_, __) => _buildEmptyCard(),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Center(
        child: Text(
          'Dados de progressao indisponiveis',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  String _getBeltName(String belt) {
    const names = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
    };
    return names[belt] ?? belt;
  }
}

/// Next class card with real data
class _NextClassCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayClassesAsync = ref.watch(todayClassesProvider);
    final currentClassAsync = ref.watch(currentClassProvider);

    return todayClassesAsync.when(
      data: (classes) {
        if (classes.isEmpty) {
          return _buildNoClassCard();
        }

        final currentClass = currentClassAsync.valueOrNull;
        final now = DateTime.now();

        // Find next class or current class
        final dayOfWeek = now.weekday % 7;
        BJJClass? nextClass;
        ClassSchedule? nextSchedule;
        for (final bjjClass in classes) {
          final schedule = bjjClass.getScheduleForDay(dayOfWeek);
          if (schedule != null) {
            final startParts = schedule.startTime.split(':').map(int.parse).toList();
            final classStart = DateTime(now.year, now.month, now.day, startParts[0], startParts[1]);
            if (classStart.isAfter(now) || currentClass?.id == bjjClass.id) {
              nextClass = bjjClass;
              nextSchedule = schedule;
              break;
            }
          }
        }

        if (nextClass == null && classes.isNotEmpty) {
          nextClass = classes.first;
          nextSchedule = nextClass.getScheduleForDay(dayOfWeek);
        }

        if (nextClass == null) {
          return _buildNoClassCard();
        }

        final isNow = currentClass?.id == nextClass.id;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isNow ? LucideIcons.activity : LucideIcons.calendar,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isNow ? 'Aula em andamento' : 'Proxima aula',
                      style: AppTheme.labelMedium.copyWith(
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isNow
                          ? 'Agora'
                          : nextSchedule != null
                              ? 'Hoje, ${nextSchedule.startTime}'
                              : 'Hoje',
                      style: AppTheme.titleLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${nextClass.name}${nextClass.instructorName != null ? ' - ${nextClass.instructorName}' : ''}',
                      style: AppTheme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: Colors.white.withOpacity(0.7),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        height: 100,
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      error: (_, __) => _buildNoClassCard(),
    );
  }

  Widget _buildNoClassCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.calendar,
              color: AppTheme.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Nenhuma aula agendada para hoje',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recent achievements section with real data
class _RecentAchievementsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) return const SizedBox.shrink();

        final achievementsAsync = ref.watch(studentAchievementsProvider(student.id));

        return achievementsAsync.when(
          data: (achievements) {
            final recentAchievements = achievements.take(5).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Conquistas recentes',
                      style: AppTheme.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // TODO: Navigate to timeline screen
                      },
                      child: const Text('Ver todas'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (recentAchievements.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Center(
                      child: Text(
                        'Nenhuma conquista ainda',
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recentAchievements.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final achievement = recentAchievements[index];
                        return _AchievementChip(
                          title: achievement.title,
                          icon: _getAchievementIcon(achievement.type),
                          color: _getAchievementColor(achievement.type),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
          loading: () => _buildLoadingSection(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
      loading: () => _buildLoadingSection(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLoadingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 150,
          height: 24,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }

  IconData _getAchievementIcon(AchievementType type) {
    switch (type) {
      case AchievementType.graduation:
      case AchievementType.stripe:
        return LucideIcons.award;
      case AchievementType.competition:
        return LucideIcons.trophy;
      case AchievementType.milestone:
        return LucideIcons.target;
    }
  }

  Color _getAchievementColor(AchievementType type) {
    switch (type) {
      case AchievementType.graduation:
      case AchievementType.stripe:
        return AppTheme.info;
      case AchievementType.competition:
        return AppTheme.warning;
      case AchievementType.milestone:
        return AppTheme.success;
    }
  }
}

/// Achievement chip widget
class _AchievementChip extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _AchievementChip({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            style: AppTheme.labelMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Upcoming competitions section with real data
class _UpcomingCompetitionsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final competitionsAsync = ref.watch(upcomingCompetitionsProvider);
    final studentAsync = ref.watch(currentStudentProvider);

    return competitionsAsync.when(
      data: (competitions) {
        if (competitions.isEmpty) {
          return const SizedBox.shrink();
        }

        final nextCompetition = competitions.first;
        final student = studentAsync.valueOrNull;

        // Check if enrolled
        bool isEnrolled = false;
        if (student != null) {
          final enrolledAsync = ref.watch(
            isStudentEnrolledProvider((
              competitionId: nextCompetition.id,
              studentId: student.id,
            )),
          );
          isEnrolled = enrolledAsync.valueOrNull ?? false;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Proximas competicoes',
                  style: AppTheme.titleLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // TODO: Navigate to competitions screen
                  },
                  child: const Text('Ver todas'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.warningLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.trophy,
                      color: AppTheme.warning,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nextCompetition.name,
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat("d 'de' MMMM, yyyy", 'pt_BR')
                              .format(nextCompetition.date),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isEnrolled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.successLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Inscrito',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => _buildLoadingSection(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLoadingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 180,
          height: 24,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }
}
