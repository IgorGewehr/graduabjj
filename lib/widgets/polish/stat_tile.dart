import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'animated_count_up.dart';

/// A compact stat card: a colored leading badge (emoji or icon) next to a big
/// (optionally count-up animated) value, a label and a sublabel.
///
/// Pixel-identical to the home dashboard stat carousel card it was extracted
/// from. Pass [countValue] to animate the value up from zero; otherwise the
/// literal [value] string is shown (used for loading/error states).
///
/// Provide either [emoji] or [icon] for the leading badge. An optional
/// [gradient] paints the badge with a gradient instead of the flat tinted
/// [color] background.
///
/// ```dart
/// StatTile(
///   emoji: '🔥',
///   value: count.toString(),
///   countValue: count,
///   label: 'Treinos',
///   sublabel: 'Total de presencas',
///   color: AppTheme.warning,
/// )
/// ```
class StatTile extends StatelessWidget {
  /// Emoji rendered in the leading badge. Mutually exclusive with [icon].
  final String? emoji;

  /// Icon rendered in the leading badge. Mutually exclusive with [emoji].
  final IconData? icon;

  /// Literal value string, shown when [countValue] is null.
  final String value;

  /// When non-null the value renders as an animated count-up; otherwise the
  /// literal [value] is shown (use null for loading/error states).
  final num? countValue;

  final String label;
  final String sublabel;

  /// Accent color used for the badge tint and (when provided) the icon color.
  final Color color;

  /// Optional gradient for the leading badge background. When set it replaces
  /// the flat tinted [color] fill.
  final Gradient? gradient;

  const StatTile({
    super.key,
    this.emoji,
    this.icon,
    required this.value,
    required this.label,
    required this.sublabel,
    required this.color,
    this.countValue,
    this.gradient,
  }) : assert(
         emoji != null || icon != null,
         'StatTile requires either an emoji or an icon.',
       );

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
              color: gradient == null ? color.withValues(alpha: 0.1) : null,
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: emoji != null
                  ? Text(emoji!, style: const TextStyle(fontSize: 28))
                  : Icon(
                      icon,
                      size: 28,
                      color: gradient == null ? color : Colors.white,
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                countValue != null
                    ? AnimatedCountUp(
                        value: countValue!,
                        style: AppTheme.displayMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Text(
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
