import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';

/// Next Class Card (Featured) — shown at the top of home dynamic section
class NextClassCard extends StatelessWidget {
  final String? className;
  final dynamic schedule;
  final DateTime? nextDate;
  final bool isLoading;
  final bool checkinEnabled;
  final bool canCheckin;
  final VoidCallback onTap;

  const NextClassCard({
    super.key,
    required this.className,
    required this.schedule,
    required this.nextDate,
    this.isLoading = false,
    required this.checkinEnabled,
    required this.canCheckin,
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
    final cardColor = canCheckin
        ? AppTheme.success
        : (hasClass ? AppTheme.textPrimary : AppTheme.surface);

    return Material(
      color: cardColor,
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
                  canCheckin ? LucideIcons.userCheck : LucideIcons.calendar,
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
                      canCheckin ? 'CHECK-IN DISPONIVEL' : 'PROXIMA AULA',
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
              if (canCheckin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Fazer Check-in',
                        style: AppTheme.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: Colors.white,
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  LucideIcons.chevronRight,
                  size: 20,
                  color: hasClass
                      ? Colors.white.withValues(alpha: 0.5)
                      : AppTheme.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
