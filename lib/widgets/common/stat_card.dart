import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../polish/polish.dart';

/// Stat Card - Displays a statistic with icon
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? AppTheme.primary;
    final valueStyle = AppTheme.headlineMedium.copyWith(
      fontWeight: FontWeight.w700,
    );

    // If the value is a plain integer, count it up; otherwise render as-is.
    // Only treat strings that are purely an integer as numeric so that
    // locale-formatted values like "1.200" (thousands separator) or "R$ 1,2"
    // are shown verbatim instead of being mis-parsed by the count-up.
    final isPlainInteger = RegExp(r'^\d+$').hasMatch(value);
    final numericValue = isPlainInteger ? num.tryParse(value) : null;

    final card = Material(
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: effectiveIconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: effectiveIconColor,
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppTheme.textDisabled,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              if (numericValue != null)
                AnimatedCountUp(
                  value: numericValue,
                  decimals: 0,
                  style: valueStyle,
                )
              else
                Text(value, style: valueStyle),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // The InkWell above owns the tap + ripple feedback; keep a gentle entrance.
    return card.entrance();
  }
}
