import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';

class AttendanceStudentCard extends StatelessWidget {
  const AttendanceStudentCard({
    super.key,
    required this.student,
    required this.isPresent,
    required this.onTap,
  });

  final Student student;
  final bool isPresent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPresent
              ? AppTheme.success.withValues(alpha: 0.05)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPresent ? AppTheme.success : AppTheme.divider,
            width: isPresent ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Toggle Circle
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Container(
                key: ValueKey(isPresent),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isPresent ? AppTheme.success : AppTheme.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPresent ? LucideIcons.checkCircle : LucideIcons.circle,
                  color: isPresent ? Colors.white : AppTheme.textDisabled,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  student.fullName[0].toUpperCase(),
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.nickname ?? student.fullName.split(' ').first,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color:
                          isPresent ? AppTheme.success : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    student.fullName,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Belt indicator
            _BeltIndicator(
              belt: student.currentBelt,
              stripes: student.currentStripes,
            ),
          ],
        ),
      ),
    );
  }
}

class _BeltIndicator extends StatelessWidget {
  const _BeltIndicator({required this.belt, required this.stripes});

  final String belt;
  final int stripes;

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFFF5F5F5),
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
    return colors[baseBelt] ?? Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final beltColor = _getBeltColor(belt);
    final clampedStripes = stripes.clamp(0, 4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: beltColor,
            borderRadius: BorderRadius.circular(2),
            border: belt == 'white'
                ? Border.all(color: AppTheme.divider)
                : null,
          ),
        ),
        if (clampedStripes > 0) ...[
          const SizedBox(width: 4),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              clampedStripes,
              (_) => Container(
                width: 6,
                height: 2,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
