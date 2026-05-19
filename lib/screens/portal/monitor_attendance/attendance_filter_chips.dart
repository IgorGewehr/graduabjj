import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';

class AttendanceFilterChips extends StatelessWidget {
  const AttendanceFilterChips({
    super.key,
    required this.filterMode,
    required this.totalCount,
    required this.presentCount,
    required this.absentCount,
    required this.onFilterChanged,
  });

  final String filterMode;
  final int totalCount;
  final int presentCount;
  final int absentCount;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChipButton(
            label: 'Todos ($totalCount)',
            isSelected: filterMode == 'all',
            onTap: () => onFilterChanged('all'),
          ),
          const SizedBox(width: 8),
          FilterChipButton(
            label: 'Presentes ($presentCount)',
            icon: LucideIcons.checkCircle,
            iconColor: AppTheme.success,
            isSelected: filterMode == 'present',
            onTap: () => onFilterChanged(filterMode == 'present' ? 'all' : 'present'),
          ),
          const SizedBox(width: 8),
          FilterChipButton(
            label: 'Ausentes ($absentCount)',
            icon: LucideIcons.circle,
            iconColor: AppTheme.textSecondary,
            isSelected: filterMode == 'absent',
            onTap: () => onFilterChanged(filterMode == 'absent' ? 'all' : 'absent'),
          ),
        ],
      ),
    );
  }
}

class FilterChipButton extends StatelessWidget {
  const FilterChipButton({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color? iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : iconColor,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTheme.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
