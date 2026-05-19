import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';

/// Journey Card with Stats Carousel
class JourneyCard extends StatefulWidget {
  final Student student;
  final AsyncValue<int> attendanceCountAsync;
  final AsyncValue<Map<String, int>> medalCountAsync;
  final AsyncValue<List<Competition>> competitionsAsync;

  const JourneyCard({
    super.key,
    required this.student,
    required this.attendanceCountAsync,
    required this.medalCountAsync,
    required this.competitionsAsync,
  });

  @override
  State<JourneyCard> createState() => _JourneyCardState();
}

class _JourneyCardState extends State<JourneyCard> {
  final PageController _pageController = PageController(viewportFraction: 0.85);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatTrainingTime(DateTime startDate) {
    final now = DateTime.now();
    final difference = now.difference(startDate);
    final years = difference.inDays ~/ 365;
    final months = (difference.inDays % 365) ~/ 30;

    if (years > 0 && months > 0) {
      return '$years a ${months}m';
    } else if (years > 0) {
      return '$years ano${years > 1 ? 's' : ''}';
    } else if (months > 0) {
      return '$months mes${months > 1 ? 'es' : ''}';
    } else {
      final days = difference.inDays;
      return '$days dia${days > 1 ? 's' : ''}';
    }
  }

  Color _getBeltDisplayColor(String belt) {
    const colors = {
      'white': Color(0xFF6B7280),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
      'grey': Color(0xFF6B7280),
      'yellow': Color(0xFFF59E0B),
      'orange': Color(0xFFF97316),
      'green': Color(0xFF22C55E),
    };
    final baseBelt = belt.split('-').first;
    return colors[baseBelt] ?? const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) {
    final attendanceCount = widget.attendanceCountAsync.valueOrNull ?? 0;
    final medalStats =
        widget.medalCountAsync.valueOrNull ??
        {'gold': 0, 'silver': 0, 'bronze': 0, 'total': 0};
    final competitions = widget.competitionsAsync.valueOrNull ?? [];
    final beltColor = _getBeltDisplayColor(widget.student.currentBelt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stats Carousel
        SizedBox(
          height: 100,
          child: PageView(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _currentPage = page),
            children: [
              JourneyCarouselCard(
                icon: LucideIcons.award,
                iconColor: beltColor,
                iconBgColor: beltColor.withValues(alpha: 0.15),
                value: getGradeLabel(
                  widget.student.getPrimarySport(),
                  widget.student.currentBelt,
                ),
                label: widget.student.currentStripes > 0
                    ? '${widget.student.currentStripes} grau${widget.student.currentStripes > 1 ? 's' : ''}'
                    : 'Faixa Atual',
              ),
              JourneyCarouselCard(
                icon: LucideIcons.dumbbell,
                iconColor: AppTheme.success,
                iconBgColor: AppTheme.successLight,
                value: attendanceCount.toString(),
                label: 'Treinos',
              ),
              JourneyCarouselCard(
                icon: LucideIcons.clock,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
                value: _formatTrainingTime(
                  widget.student.jiujitsuStartDate ?? widget.student.startDate,
                ),
                label: 'Tempo de Tatame',
              ),
              JourneyCarouselCard(
                icon: LucideIcons.trophy,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFEF3C7),
                value: competitions.length.toString(),
                label: 'Campeonatos',
              ),
            ],
          ),
        ),

        // Dot indicators
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentPage == index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentPage == index
                    ? AppTheme.textPrimary
                    : AppTheme.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),

        // Medal Display
        if ((medalStats['total'] ?? 0) > 0) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MEDALHAS',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if ((medalStats['gold'] ?? 0) > 0)
                      MedalBadge(
                        emoji: '🥇',
                        count: medalStats['gold']!,
                        label: 'Ouro',
                      ),
                    if ((medalStats['silver'] ?? 0) > 0)
                      MedalBadge(
                        emoji: '🥈',
                        count: medalStats['silver']!,
                        label: 'Prata',
                      ),
                    if ((medalStats['bronze'] ?? 0) > 0)
                      MedalBadge(
                        emoji: '🥉',
                        count: medalStats['bronze']!,
                        label: 'Bronze',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Journey Carousel Card
class JourneyCarouselCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String value;
  final String label;

  const JourneyCarouselCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
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
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Medal Badge
class MedalBadge extends StatelessWidget {
  final String emoji;
  final int count;
  final String label;

  const MedalBadge({
    super.key,
    required this.emoji,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count.toString(),
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
