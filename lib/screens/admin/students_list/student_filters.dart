import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';

/// Active filter chip shown in the scrollable row above the student list.
class StudentFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const StudentFilterChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(LucideIcons.x, size: 14, color: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for applying filters and sort order on the students list.
class FilterBottomSheet extends StatefulWidget {
  final StudentStatus? statusFilter;
  final StudentCategory? categoryFilter;
  final SportId? sportFilter;
  final String? beltFilter;
  final bool? accountFilter;
  final String sortBy;
  final Function(
    StudentStatus?,
    StudentCategory?,
    SportId?,
    String?,
    bool?,
    String,
  )
  onApply;
  final VoidCallback onClear;

  const FilterBottomSheet({
    super.key,
    required this.statusFilter,
    required this.categoryFilter,
    required this.sportFilter,
    required this.beltFilter,
    required this.accountFilter,
    required this.sortBy,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late StudentStatus? _status;
  late StudentCategory? _category;
  late SportId? _sport;
  late String? _belt;
  late bool? _account;
  late String _sort;

  @override
  void initState() {
    super.initState();
    _status = widget.statusFilter;
    _category = widget.categoryFilter;
    _sport = widget.sportFilter;
    _belt = widget.beltFilter;
    _account = widget.accountFilter;
    _sort = widget.sortBy;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Filtros',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),

            // Status filter
            _buildSectionTitle('Status'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StudentStatus.values.map((status) {
                final isSelected = _status == status;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _status = isSelected ? null : status),
                  child: _buildChip(status.label, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Category filter
            _buildSectionTitle('Categoria'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StudentCategory.values.map((category) {
                final isSelected = _category == category;
                return GestureDetector(
                  onTap: () => setState(
                      () => _category = isSelected ? null : category),
                  child: _buildChip(category.label, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Sport filter
            _buildSectionTitle('Modalidade'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sportOptions.map((sportId) {
                final isSelected = _sport == sportId;
                return GestureDetector(
                  onTap: () => setState(() {
                    if (isSelected) {
                      _sport = null;
                    } else {
                      _sport = sportId;
                    }
                    _belt = null;
                  }),
                  child: _buildSportFilterChip(sportId, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Belt filter
            _buildSectionTitle(
              'Faixa${_sport != null ? ' · ${sports[_sport]!.labelShort}' : ''}',
            ),
            Builder(
              builder: (_) {
                final activeSport = _sport ?? SportId.bjj;
                final categoryValue = _category?.value ?? 'adult';
                final grades = getGradesForSport(
                  activeSport,
                  category: categoryValue,
                );
                if (grades.isEmpty) {
                  return Text(
                    'Esta modalidade não usa graduação.',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: grades.map((g) {
                    final isSelected = _belt == g.id;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _belt = isSelected ? null : g.id),
                      child: _buildChip(g.label, isSelected),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 20),

            // Account filter
            _buildSectionTitle('Conta'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [(true, 'Com conta'), (false, 'Sem conta')].map((item) {
                final isSelected = _account == item.$1;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _account = isSelected ? null : item.$1),
                  child: _buildChip(item.$2, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Sort by
            _buildSectionTitle('Ordenar por'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ('name', 'Nome'),
                ('attendance', 'Presencas'),
                ('belt', 'Faixa'),
                ('eligible_first', 'Elegiveis primeiro'),
              ].map((item) {
                final isSelected = _sort == item.$1;
                return GestureDetector(
                  onTap: () => setState(() => _sort = item.$1),
                  child: _buildChip(item.$2, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onClear,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: AppTheme.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Limpar',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.onApply(
                      _status,
                      _category,
                      _sport,
                      _belt,
                      _account,
                      _sort,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Aplicar',
                      style: AppTheme.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: AppTheme.bodyMedium.copyWith(
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
        ),
      ),
      child: Text(
        label,
        style: AppTheme.bodySmall.copyWith(
          color: isSelected ? Colors.white : AppTheme.textPrimary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSportFilterChip(SportId sportId, bool isSelected) {
    final sport = sports[sportId]!;
    final accent = sportChipColors[sportId] ?? AppTheme.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? accent.withValues(alpha: 0.12) : AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? accent : AppTheme.divider,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sport.icon,
            size: 14,
            color: isSelected ? accent : AppTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            sport.label,
            style: AppTheme.bodySmall.copyWith(
              color: isSelected ? accent : AppTheme.textPrimary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
