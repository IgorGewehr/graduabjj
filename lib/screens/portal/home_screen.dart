import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../widgets/common/belt_badge.dart';

/// Home Screen - Portal do Aluno (New Layout)
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final PageController _statsPageController = PageController(viewportFraction: 0.85);
  int _currentStatsPage = 0;

  @override
  void dispose() {
    _statsPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final student = ref.watch(currentStudentProvider);

    final studentId = student.valueOrNull?.id;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(currentUserProvider);
        ref.invalidate(currentStudentProvider);
        ref.invalidate(upcomingCompetitionsProvider);
        if (studentId != null) {
          ref.invalidate(studentAttendanceCountProvider(studentId));
          ref.invalidate(studentMedalCountProvider(studentId));
          ref.invalidate(studentStreakProvider(studentId));
          ref.invalidate(studentMonthlyAttendanceProvider(studentId));
          ref.invalidate(studentNextClassProvider(studentId));
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header with belt badge
            student.when(
              data: (s) {
                if (s == null) {
                  return _WelcomeHeader(
                    userName: currentUser.valueOrNull?.displayName ?? 'Aluno',
                  );
                }
                return _WelcomeHeaderWithBelt(
                  userName: s.displayName,
                  belt: s.currentBelt,
                  stripes: s.currentStripes,
                );
              },
              loading: () => _WelcomeHeader(
                userName: currentUser.valueOrNull?.displayName ?? 'Aluno',
              ),
              error: (_, __) => _WelcomeHeader(
                userName: currentUser.valueOrNull?.displayName ?? 'Aluno',
              ),
            ),

            const SizedBox(height: 24),

            // Stats Carousel
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                return _StatsCarousel(
                  student: s,
                  pageController: _statsPageController,
                  currentPage: _currentStatsPage,
                  onPageChanged: (page) {
                    setState(() => _currentStatsPage = page);
                  },
                );
              },
              loading: () => _buildStatsLoading(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            // Dynamic Cards Section
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                return _DynamicCardsSection(
                  studentId: s.id,
                  onTap: (path) => context.go(path),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 80), // Bottom padding for nav bar
          ],
        ),
      ),
    );
  }

  Widget _buildStatsLoading() {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
    );
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

/// Welcome header with belt badge inline
class _WelcomeHeaderWithBelt extends StatelessWidget {
  final String userName;
  final String belt;
  final int stripes;

  const _WelcomeHeaderWithBelt({
    required this.userName,
    required this.belt,
    required this.stripes,
  });

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
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                userName.split(' ').first,
                style: AppTheme.displaySmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            BeltBadge(
              belt: belt,
              stripes: stripes,
              size: BeltSize.small,
            ),
          ],
        ),
      ],
    );
  }
}

/// Stats Carousel with 3 cards + dot indicators
class _StatsCarousel extends ConsumerWidget {
  final dynamic student;
  final PageController pageController;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  const _StatsCarousel({
    required this.student,
    required this.pageController,
    required this.currentPage,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceCountAsync = ref.watch(studentAttendanceCountProvider(student.id));
    final medalCountAsync = ref.watch(studentMedalCountProvider(student.id));

    // Calculate months on the mat
    final startDate = student.jiujitsuStartDate ?? student.startDate;
    final now = DateTime.now();
    final monthsOnMat = (now.year - startDate.year) * 12 + (now.month - startDate.month);

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PageView(
            controller: pageController,
            onPageChanged: onPageChanged,
            children: [
              // Training count card
              attendanceCountAsync.when(
                data: (count) => _StatCarouselCard(
                  emoji: '🔥',
                  value: count.toString(),
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
                loading: () => _StatCarouselCard(
                  emoji: '🔥',
                  value: '...',
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
                error: (_, __) => _StatCarouselCard(
                  emoji: '🔥',
                  value: '-',
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
              ),

              // Months on mat card
              _StatCarouselCard(
                emoji: '📅',
                value: monthsOnMat > 0 ? monthsOnMat.toString() : '0',
                label: 'Meses de Tatame',
                sublabel: 'Tempo de jornada',
                color: AppTheme.info,
              ),

              // Competitions card
              medalCountAsync.when(
                data: (medals) {
                  final total = medals['total'] ?? 0;
                  return _StatCarouselCard(
                    emoji: '🏆',
                    value: total.toString(),
                    label: 'Competicoes',
                    sublabel: 'Participacoes',
                    color: Colors.purple,
                  );
                },
                loading: () => _StatCarouselCard(
                  emoji: '🏆',
                  value: '...',
                  label: 'Competicoes',
                  sublabel: 'Participacoes',
                  color: Colors.purple,
                ),
                error: (_, __) => _StatCarouselCard(
                  emoji: '🏆',
                  value: '0',
                  label: 'Competicoes',
                  sublabel: 'Participacoes',
                  color: Colors.purple,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: currentPage == index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: currentPage == index
                    ? AppTheme.textPrimary
                    : AppTheme.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Individual stat carousel card
class _StatCarouselCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final String sublabel;
  final Color color;

  const _StatCarouselCard({
    required this.emoji,
    required this.value,
    required this.label,
    required this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: AppTheme.displayMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  sublabel,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dynamic Cards Section with real data
class _DynamicCardsSection extends ConsumerWidget {
  final String studentId;
  final void Function(String path) onTap;

  const _DynamicCardsSection({
    required this.studentId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextClassAsync = ref.watch(studentNextClassProvider(studentId));
    final streakAsync = ref.watch(studentStreakProvider(studentId));
    final monthlyAttendanceAsync = ref.watch(studentMonthlyAttendanceProvider(studentId));
    final upcomingCompetitionsAsync = ref.watch(upcomingCompetitionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Next Class Card (Featured)
        nextClassAsync.when(
          data: (data) {
            if (data == null || data.classInfo == null) {
              return _NextClassCard(
                className: null,
                schedule: null,
                nextDate: null,
                onTap: () => onTap('/portal/horarios'),
              );
            }
            return _NextClassCard(
              className: data.classInfo!.name,
              schedule: data.schedule,
              nextDate: data.nextDate,
              onTap: () => onTap('/portal/horarios'),
            );
          },
          loading: () => _NextClassCard(
            className: null,
            schedule: null,
            nextDate: null,
            isLoading: true,
            onTap: () => onTap('/portal/horarios'),
          ),
          error: (_, __) => _NextClassCard(
            className: null,
            schedule: null,
            nextDate: null,
            onTap: () => onTap('/portal/horarios'),
          ),
        ),

        const SizedBox(height: 12),

        // Row with Streak and Monthly Stats
        Row(
          children: [
            Expanded(
              child: streakAsync.when(
                data: (streak) => _StreakCard(
                  streak: streak,
                  onTap: () => onTap('/portal/presencas'),
                ),
                loading: () => _StreakCard(
                  streak: 0,
                  isLoading: true,
                  onTap: () => onTap('/portal/presencas'),
                ),
                error: (_, __) => _StreakCard(
                  streak: 0,
                  onTap: () => onTap('/portal/presencas'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: monthlyAttendanceAsync.when(
                data: (count) => _MonthlyCard(
                  count: count,
                  onTap: () => onTap('/portal/presencas'),
                ),
                loading: () => _MonthlyCard(
                  count: 0,
                  isLoading: true,
                  onTap: () => onTap('/portal/presencas'),
                ),
                error: (_, __) => _MonthlyCard(
                  count: 0,
                  onTap: () => onTap('/portal/presencas'),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Next Competition Card
        upcomingCompetitionsAsync.when(
          data: (competitions) {
            final next = competitions.isNotEmpty ? competitions.first : null;
            return _NextCompetitionCard(
              competition: next,
              onTap: () => onTap('/portal/competicoes'),
            );
          },
          loading: () => _NextCompetitionCard(
            competition: null,
            isLoading: true,
            onTap: () => onTap('/portal/competicoes'),
          ),
          error: (_, __) => _NextCompetitionCard(
            competition: null,
            onTap: () => onTap('/portal/competicoes'),
          ),
        ),
      ],
    );
  }
}

/// Next Class Card (Featured)
class _NextClassCard extends StatelessWidget {
  final String? className;
  final dynamic schedule;
  final DateTime? nextDate;
  final bool isLoading;
  final VoidCallback onTap;

  const _NextClassCard({
    required this.className,
    required this.schedule,
    required this.nextDate,
    this.isLoading = false,
    required this.onTap,
  });

  String _formatNextClass() {
    if (nextDate == null || schedule == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final classDay = DateTime(nextDate!.year, nextDate!.month, nextDate!.day);
    final difference = classDay.difference(today).inDays;

    String dayLabel;
    if (difference == 0) {
      dayLabel = 'Hoje';
    } else if (difference == 1) {
      dayLabel = 'Amanha';
    } else {
      dayLabel = DateFormat('EEEE', 'pt_BR').format(nextDate!);
      dayLabel = dayLabel[0].toUpperCase() + dayLabel.substring(1);
    }

    return '$dayLabel as ${schedule.startTime}';
  }

  @override
  Widget build(BuildContext context) {
    final hasClass = className != null && !isLoading;

    return Material(
      color: hasClass ? AppTheme.textPrimary : AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: hasClass ? null : Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: hasClass
                      ? Colors.white.withValues(alpha: 0.15)
                      : AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  LucideIcons.calendar,
                  size: 28,
                  color: hasClass ? Colors.white : AppTheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROXIMA AULA',
                      style: AppTheme.labelSmall.copyWith(
                        color: hasClass
                            ? Colors.white.withValues(alpha: 0.7)
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isLoading)
                      Text(
                        'Carregando...',
                        style: AppTheme.titleMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      )
                    else if (hasClass) ...[
                      Text(
                        className!,
                        style: AppTheme.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _formatNextClass(),
                        style: AppTheme.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ] else
                      Text(
                        'Ver horarios disponiveis',
                        style: AppTheme.titleMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: hasClass ? Colors.white.withValues(alpha: 0.5) : AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Streak Card
class _StreakCard extends StatelessWidget {
  final int streak;
  final bool isLoading;
  final VoidCallback onTap;

  const _StreakCard({
    required this.streak,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasStreak = streak > 0;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    hasStreak ? '🔥' : '💪',
                    style: const TextStyle(fontSize: 24),
                  ),
                  const Spacer(),
                  if (hasStreak)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Em alta!',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (isLoading)
                Text(
                  '...',
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Text(
                  hasStreak ? '$streak dias' : 'Comece hoje!',
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                'Sequencia',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Monthly Attendance Card
class _MonthlyCard extends StatelessWidget {
  final int count;
  final bool isLoading;
  final VoidCallback onTap;

  const _MonthlyCard({
    required this.count,
    this.isLoading = false,
    required this.onTap,
  });

  String get _monthName {
    final now = DateTime.now();
    final month = DateFormat('MMMM', 'pt_BR').format(now);
    return month[0].toUpperCase() + month.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '📅',
                    style: TextStyle(fontSize: 24),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _monthName,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (isLoading)
                Text(
                  '...',
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Text(
                  '$count treinos',
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                'Este mes',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Next Competition Card
class _NextCompetitionCard extends StatelessWidget {
  final dynamic competition;
  final bool isLoading;
  final VoidCallback onTap;

  const _NextCompetitionCard({
    required this.competition,
    this.isLoading = false,
    required this.onTap,
  });

  String _formatDate(DateTime date) {
    return DateFormat("d 'de' MMMM", 'pt_BR').format(date);
  }

  int _daysUntil(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    return eventDay.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final hasCompetition = competition != null && !isLoading;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('🏆', style: TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLoading) ...[
                      Text(
                        'Carregando...',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ] else if (hasCompetition) ...[
                      Text(
                        competition.name,
                        style: AppTheme.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _formatDate(competition.date),
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Proximo Campeonato',
                        style: AppTheme.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Nenhum evento proximo',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasCompetition)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_daysUntil(competition.date)} dias',
                    style: AppTheme.labelSmall.copyWith(
                      color: Colors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
