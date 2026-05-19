import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/services.dart';
import 'calendar_bottom_sheet.dart';

/// Dropdown to select the BJJ class
class AttendanceClassDropdown extends StatelessWidget {
  const AttendanceClassDropdown({
    super.key,
    required this.classes,
    required this.selectedClass,
    required this.onChanged,
  });

  final List<BJJClass> classes;
  final BJJClass? selectedClass;
  final ValueChanged<BJJClass?> onChanged;

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
          labelStyle:
              AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

/// Button that opens the calendar bottom sheet for date selection
class AttendanceDateButton extends StatelessWidget {
  const AttendanceDateButton({
    super.key,
    required this.selectedDate,
    required this.isToday,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final bool isToday;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => CalendarBottomSheet(
            selectedDate: selectedDate,
            onDateSelected: (date) {
              Navigator.pop(context);
              onDateChanged(date);
            },
          ),
        );
      },
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

/// Search bar for filtering students by name
class AttendanceSearchBar extends StatelessWidget {
  const AttendanceSearchBar({
    super.key,
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

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
          hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textDisabled),
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
                  onPressed: onClear,
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// Empty state shown when no class is selected
class AttendanceSelectClassState extends StatelessWidget {
  const AttendanceSelectClassState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.users,
                size: 36,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Selecione uma turma',
              style: AppTheme.titleMedium.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Escolha uma turma acima para\nregistrar as presencas',
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
