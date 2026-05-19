import 'package:flutter/material.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import 'timeline_models.dart';

/// Type Chip — small label shown in the top-right of each timeline card
class TimelineTypeChip extends StatelessWidget {
  final TimelineEventType type;

  const TimelineTypeChip({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    String label;
    Color bgColor;
    Color textColor;

    switch (type) {
      case TimelineEventType.graduation:
        label = 'Graduacao';
        bgColor = const Color(0xFFEDE9FE);
        textColor = const Color(0xFF7C3AED);
        break;
      case TimelineEventType.stripe:
        label = 'Grau';
        bgColor = const Color(0xFFFEF9C3);
        textColor = const Color(0xFFEAB308);
        break;
      case TimelineEventType.competition:
        label = 'Competicao';
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFF59E0B);
        break;
      case TimelineEventType.milestone:
        label = 'Marco';
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF10B981);
        break;
      case TimelineEventType.start:
        label = 'Inicio';
        bgColor = const Color(0xFFEFF6FF);
        textColor = const Color(0xFF2563EB);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Belt Indicator — colored belt strip shown on graduation events
class TimelineBeltIndicator extends StatelessWidget {
  final String belt;

  const TimelineBeltIndicator({super.key, required this.belt});

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFF9CA3AF),
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
    final beltColor = _getBeltColor(belt);
    final beltLabel = getGradeLabel(SportId.bjj, belt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: beltColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: beltColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 8,
            decoration: BoxDecoration(
              color: beltColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Faixa $beltLabel',
            style: AppTheme.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: beltColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Position Badge — medal icon shown on competition events
class TimelinePositionBadge extends StatelessWidget {
  final String position;

  const TimelinePositionBadge({super.key, required this.position});

  @override
  Widget build(BuildContext context) {
    String emoji;
    String label;
    Color color;

    switch (position) {
      case 'gold':
        emoji = '🥇';
        label = 'Ouro';
        color = const Color(0xFFD97706);
        break;
      case 'silver':
        emoji = '🥈';
        label = 'Prata';
        color = const Color(0xFF6B7280);
        break;
      case 'bronze':
        emoji = '🥉';
        label = 'Bronze';
        color = const Color(0xFFB45309);
        break;
      default:
        emoji = '🎖️';
        label = 'Participante';
        color = const Color(0xFF10B981);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
