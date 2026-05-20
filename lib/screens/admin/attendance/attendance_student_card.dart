import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';

/// Single student row in the attendance list.
/// Tapping toggles the student's presence for the selected session.
class AttendanceStudentCard extends StatefulWidget {
  final Student student;
  final bool isPresent;
  final VoidCallback onTap;

  const AttendanceStudentCard({
    super.key,
    required this.student,
    required this.isPresent,
    required this.onTap,
  });

  @override
  State<AttendanceStudentCard> createState() => _AttendanceStudentCardState();
}

class _AttendanceStudentCardState extends State<AttendanceStudentCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isPresent
              ? AppTheme.success.withValues(alpha: 0.05)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isPresent ? AppTheme.success : AppTheme.divider,
            width: widget.isPresent ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Toggle Circle
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isPresent ? AppTheme.success : AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.isPresent ? LucideIcons.checkCircle : LucideIcons.circle,
                color: widget.isPresent ? Colors.white : AppTheme.textDisabled,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.student.fullName[0].toUpperCase(),
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.student.nickname ?? widget.student.fullName.split(' ').first,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: widget.isPresent
                          ? AppTheme.success
                          : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    widget.student.fullName,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Belt stripes indicator
            _buildBeltIndicator(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildBeltIndicator() {
    final beltColor = _getBeltColor(widget.student.currentBelt);
    final stripes = widget.student.currentStripes.clamp(0, 4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Belt bar
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: beltColor,
            borderRadius: BorderRadius.circular(2),
            border: widget.student.currentBelt == 'white'
                ? Border.all(color: AppTheme.divider)
                : null,
          ),
        ),
        if (stripes > 0) ...[
          const SizedBox(width: 4),
          // Stripes
          Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              stripes,
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
}
