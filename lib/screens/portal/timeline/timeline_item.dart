import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import 'timeline_badges.dart';
import 'timeline_models.dart';

/// Timeline Item — renders a single event row with icon column and content card
class TimelineItem extends StatelessWidget {
  final TimelineEvent event;
  final bool isLast;

  const TimelineItem({super.key, required this.event, required this.isLast});

  Color _getBeltColor(String belt) {
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

  EventConfig _getEventConfig(TimelineEventType type, String? belt) {
    switch (type) {
      case TimelineEventType.graduation:
        final beltColor = _getBeltColor(belt ?? 'white');
        return EventConfig(
          icon: LucideIcons.award,
          color: beltColor,
          bgColor: beltColor.withValues(alpha: 0.15),
        );
      case TimelineEventType.stripe:
        return EventConfig(
          icon: LucideIcons.star,
          color: const Color(0xFFEAB308),
          bgColor: const Color(0xFFFEF9C3),
        );
      case TimelineEventType.competition:
        return EventConfig(
          icon: LucideIcons.trophy,
          color: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFEF3C7),
        );
      case TimelineEventType.milestone:
        return EventConfig(
          icon: LucideIcons.target,
          color: const Color(0xFF10B981),
          bgColor: const Color(0xFFD1FAE5),
        );
      case TimelineEventType.start:
        return EventConfig(
          icon: LucideIcons.flag,
          color: const Color(0xFF2563EB),
          bgColor: const Color(0xFFEFF6FF),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _getEventConfig(event.type, event.belt);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator column
          SizedBox(
            width: 44,
            child: Column(
              children: [
                // Icon circle with shadow
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: config.bgColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: config.color, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: config.color.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(config.icon, size: 20, color: config.color),
                ),
                // Gradient vertical line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            config.color.withValues(alpha: 0.6),
                            AppTheme.divider,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Content card
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TimelineTypeChip(type: event.type),
                    ],
                  ),

                  // Description
                  if (event.description != null &&
                      event.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      event.description!,
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],

                  // Belt indicator for graduations
                  if (event.type == TimelineEventType.graduation &&
                      event.belt != null) ...[
                    const SizedBox(height: 12),
                    TimelineBeltIndicator(belt: event.belt!),
                  ],

                  // Position badge for competitions
                  if (event.type == TimelineEventType.competition &&
                      event.position != null) ...[
                    const SizedBox(height: 12),
                    TimelinePositionBadge(position: event.position!),
                  ],

                  // Academy badge for competitions
                  if (event.type == TimelineEventType.competition &&
                      event.academyName != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.building2,
                          size: 12,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Lutou por ${event.academyName}',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Date
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 14,
                        color: AppTheme.textDisabled,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat(
                          "d 'de' MMMM 'de' yyyy",
                          'pt_BR',
                        ).format(event.date),
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
