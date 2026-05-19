import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/providers.dart';

/// Stats Carousel with 3 cards + dot indicators
class StatsCarousel extends ConsumerWidget {
  final dynamic student;
  final PageController pageController;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  const StatsCarousel({
    super.key,
    required this.student,
    required this.pageController,
    required this.currentPage,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceCountAsync = ref.watch(
      studentAttendanceCountProvider(student.id),
    );
    final medalCountAsync = ref.watch(studentMedalCountProvider(student.id));

    final startDate = student.jiujitsuStartDate ?? student.startDate;
    final now = DateTime.now();
    final monthsOnMat =
        (now.year - startDate.year) * 12 + (now.month - startDate.month);

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
                data: (count) => StatCarouselCard(
                  emoji: '🔥',
                  value: count.toString(),
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
                loading: () => StatCarouselCard(
                  emoji: '🔥',
                  value: '...',
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
                error: (_, __) => StatCarouselCard(
                  emoji: '🔥',
                  value: '-',
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
              ),

              // Months on mat card
              StatCarouselCard(
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
                  return StatCarouselCard(
                    emoji: '🏆',
                    value: total.toString(),
                    label: 'Competicoes',
                    sublabel: 'Participacoes',
                    color: Colors.purple,
                  );
                },
                loading: () => StatCarouselCard(
                  emoji: '🏆',
                  value: '...',
                  label: 'Competicoes',
                  sublabel: 'Participacoes',
                  color: Colors.purple,
                ),
                error: (_, __) => StatCarouselCard(
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
class StatCarouselCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final String sublabel;
  final Color color;

  const StatCarouselCard({
    super.key,
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
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
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
