import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/class_service.dart';

// ---------------------------------------------------------------------------
// Class Dropdown
// ---------------------------------------------------------------------------

/// Dropdown to pick the active BJJ class for the attendance session.
class AttendanceClassDropdown extends StatelessWidget {
  final List<BJJClass> classes;
  final BJJClass? selectedClass;
  final ValueChanged<BJJClass?> onChanged;

  const AttendanceClassDropdown({
    super.key,
    required this.classes,
    required this.selectedClass,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<BJJClass>(
        value: selectedClass,
        isExpanded: true,
        icon: Icon(
          LucideIcons.chevronDown,
          color: AppTheme.textSecondary,
          size: 20,
        ),
        decoration: InputDecoration(
          labelText: 'Turma',
          labelStyle: AppTheme.bodySmall.copyWith(
            color: AppTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
        ),
        items: classes.map((cls) {
          return DropdownMenuItem<BJJClass>(
            value: cls,
            child: Text(
              cls.name,
              style: AppTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: onChanged,
        dropdownColor: AppTheme.surface,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date Button
// ---------------------------------------------------------------------------

/// Pill button showing the selected date; tapping opens the calendar sheet.
class AttendanceDateButton extends StatelessWidget {
  final DateTime selectedDate;
  final bool isToday;
  final VoidCallback onTap;

  const AttendanceDateButton({
    super.key,
    required this.selectedDate,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.textPrimary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.calendar, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              isToday
                  ? 'Hoje'
                  : '${selectedDate.day}/${selectedDate.month}',
              style: AppTheme.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search Bar
// ---------------------------------------------------------------------------

/// Text field to filter the student list by name or nickname.
class AttendanceSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;

  const AttendanceSearchBar({
    super.key,
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Buscar aluno...',
          hintStyle:
              AppTheme.bodyMedium.copyWith(color: AppTheme.textDisabled),
          prefixIcon: Icon(
            LucideIcons.search,
            color: AppTheme.textSecondary,
            size: 20,
          ),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    LucideIcons.x,
                    color: AppTheme.textSecondary,
                    size: 18,
                  ),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        onChanged: (value) => onChanged(value.toLowerCase()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter Chips
// ---------------------------------------------------------------------------

/// Horizontal row of chips to filter by all / present / absent.
class AttendanceFilterChips extends StatelessWidget {
  final String filterMode;
  final int totalCount;
  final int presentCount;
  final int absentCount;
  final ValueChanged<String> onFilterChanged;

  const AttendanceFilterChips({
    super.key,
    required this.filterMode,
    required this.totalCount,
    required this.presentCount,
    required this.absentCount,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChipButton(
            label: 'Todos ($totalCount)',
            isSelected: filterMode == 'all',
            onTap: () => onFilterChanged('all'),
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: 'Presentes ($presentCount)',
            icon: LucideIcons.checkCircle,
            iconColor: AppTheme.success,
            isSelected: filterMode == 'present',
            onTap: () => onFilterChanged(
              filterMode == 'present' ? 'all' : 'present',
            ),
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: 'Ausentes ($absentCount)',
            icon: LucideIcons.circle,
            iconColor: AppTheme.textSecondary,
            isSelected: filterMode == 'absent',
            onTap: () => onFilterChanged(
              filterMode == 'absent' ? 'all' : 'absent',
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private chip widget
// ---------------------------------------------------------------------------

class _FilterChipButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    this.icon,
    this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

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
