import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../polish/polish.dart';
import 'belt_badge.dart';

// ============================================
// GradeBadge — Compact badge for listings
// Delegates to BeltChip for belt sports,
// renders a custom compact badge for armband,
// and renders nothing for "none" sports.
// ============================================

class GradeBadge extends StatelessWidget {
  final SportId sportId;
  final String grade;
  final int stripes;

  const GradeBadge({
    super.key,
    required this.sportId,
    required this.grade,
    this.stripes = 0,
  });

  @override
  Widget build(BuildContext context) {
    final sport = sports[sportId];
    if (sport == null) return const SizedBox.shrink();

    switch (sport.gradeSystem) {
      case GradeSystem.belt:
        return BeltChip(belt: grade, stripes: stripes);

      case GradeSystem.armband:
        final color = getGradeColor(sportId, grade);
        final label = getGradeLabel(sportId, grade);
        final isWhite = grade == 'white';
        final displayLabel = label.length >= 4
            ? label.substring(0, 4).toUpperCase()
            : label.toUpperCase();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: isWhite
                ? Border.all(color: AppTheme.divider, width: 1)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayLabel,
                style: TextStyle(
                  color: isWhite ? const Color(0xFF171717) : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
              if (stripes > 0) ...[
                const SizedBox(width: 3),
                Text(
                  '${stripes}T',
                  style: TextStyle(
                    color: isWhite ? const Color(0xFF171717) : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ).animate().scale(
              begin: const Offset(0.92, 0.92),
              end: const Offset(1, 1),
              duration: PolishMotion.normal,
              curve: Curves.easeOutBack,
            );

      case GradeSystem.none:
        return const SizedBox.shrink();
    }
  }
}
