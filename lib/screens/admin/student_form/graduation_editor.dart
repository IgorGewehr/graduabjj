import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../widgets/form/form_widgets.dart';

/// Graduation editor widget — manages multiple sports and their belt/stripes.
/// All state lives in the parent; this widget receives grades + callbacks.
class GraduationEditor extends StatelessWidget {
  const GraduationEditor({
    super.key,
    required this.grades,
    required this.primarySport,
    required this.category,
    required this.hasError,
    required this.onSetPrimary,
    required this.onRemoveSport,
    required this.onAddSport,
    required this.onGradeChanged,
  });

  final Map<SportId, ({String belt, int stripes})> grades;
  final SportId? primarySport;
  final StudentCategory category;
  final bool hasError;
  final ValueChanged<SportId> onSetPrimary;
  final ValueChanged<SportId> onRemoveSport;
  final ValueChanged<SportId> onAddSport;
  final void Function(SportId sport, String belt, int stripes) onGradeChanged;

  List<SportId> get _availableToAdd =>
      sportOptions.where((s) => !grades.containsKey(s)).toList();

  @override
  Widget build(BuildContext context) {
    final usedSports = grades.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (grades.isEmpty) ...[
          _EmptyGradesPlaceholder(hasError: hasError),
          const SizedBox(height: 12),
        ],
        for (final sport in usedSports) ...[
          _SportGradeBlock(
            sport: sport,
            grade: grades[sport]!,
            isPrimary: primarySport == sport,
            isOnlySport: grades.length == 1,
            category: category,
            onSetPrimary: () => onSetPrimary(sport),
            onRemove: () => onRemoveSport(sport),
            onGradeChanged: (belt, stripes) =>
                onGradeChanged(sport, belt, stripes),
          ),
          const SizedBox(height: 12),
        ],
        if (_availableToAdd.isNotEmpty)
          _AddSportButton(
            available: _availableToAdd,
            category: category,
            onAdd: onAddSport,
          ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyGradesPlaceholder extends StatelessWidget {
  const _EmptyGradesPlaceholder({required this.hasError});

  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasError
            ? AppTheme.error.withValues(alpha: 0.08)
            : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasError ? AppTheme.error : AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(
            hasError ? LucideIcons.alertCircle : LucideIcons.medal,
            color: hasError ? AppTheme.error : AppTheme.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasError
                      ? 'Modalidade é obrigatória'
                      : 'Nenhuma modalidade selecionada',
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hasError ? AppTheme.error : AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Adicione pelo menos uma modalidade para definir as faixas do aluno.',
                  style: AppTheme.labelSmall.copyWith(
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

// ── Sport grade block ─────────────────────────────────────────────────────────

class _SportGradeBlock extends StatelessWidget {
  const _SportGradeBlock({
    required this.sport,
    required this.grade,
    required this.isPrimary,
    required this.isOnlySport,
    required this.category,
    required this.onSetPrimary,
    required this.onRemove,
    required this.onGradeChanged,
  });

  final SportId sport;
  final ({String belt, int stripes}) grade;
  final bool isPrimary;
  final bool isOnlySport;
  final StudentCategory category;
  final VoidCallback onSetPrimary;
  final VoidCallback onRemove;
  final void Function(String belt, int stripes) onGradeChanged;

  @override
  Widget build(BuildContext context) {
    final sportDef = sports[sport]!;
    final accent = sportChipColors[sport] ?? AppTheme.primary;
    final hasGradeSystem = sportDef.gradeSystem != GradeSystem.none;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPrimary ? accent : AppTheme.divider,
          width: isPrimary ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(sportDef.icon, color: accent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          sportDef.label,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (isPrimary)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PRINCIPAL',
                              style: AppTheme.labelSmall.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!hasGradeSystem)
                      Text(
                        'Sem sistema de graduação',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isPrimary)
                IconButton(
                  tooltip: 'Definir como principal',
                  icon: Icon(
                    LucideIcons.star,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: onSetPrimary,
                ),
              if (!isOnlySport)
                IconButton(
                  tooltip: 'Remover modalidade',
                  icon: Icon(LucideIcons.x, size: 18, color: AppTheme.error),
                  onPressed: onRemove,
                ),
            ],
          ),
          if (hasGradeSystem) ...[
            const SizedBox(height: 10),
            FormRow(
              children: [
                _BeltSelector(
                  sport: sport,
                  grade: grade,
                  category: category,
                  onChanged: (belt) => onGradeChanged(belt, grade.stripes),
                ),
                _StripesSelector(
                  sport: sport,
                  grade: grade,
                  onChanged: (stripes) => onGradeChanged(grade.belt, stripes),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Belt selector ─────────────────────────────────────────────────────────────

class _BeltSelector extends StatelessWidget {
  const _BeltSelector({
    required this.sport,
    required this.grade,
    required this.category,
    required this.onChanged,
  });

  final SportId sport;
  final ({String belt, int stripes}) grade;
  final StudentCategory category;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final grades = getGradesForSport(sport, category: category.value);
    if (grades.isEmpty) return const SizedBox.shrink();

    final gradeIds = grades.map((g) => g.id).toList();
    final value =
        gradeIds.contains(grade.belt) ? grade.belt : grades.first.id;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        icon: Icon(
          LucideIcons.chevronDown,
          color: AppTheme.textSecondary,
          size: 20,
        ),
        decoration: InputDecoration(
          labelText: 'Faixa',
          prefixIcon: Icon(
            LucideIcons.award,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: grades.map((g) {
          final hasStripe = g.id.contains('-');
          final isWhiteStripe = g.id.endsWith('-white');
          return DropdownMenuItem(
            value: g.id,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 8,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: g.color,
                          borderRadius: BorderRadius.circular(2),
                          border: g.id == 'white'
                              ? Border.all(color: AppTheme.divider)
                              : null,
                        ),
                      ),
                      if (hasStripe)
                        Positioned(
                          top: 3,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            color:
                                isWhiteStripe ? Colors.white : Colors.black,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(g.label, style: AppTheme.bodyMedium),
              ],
            ),
          );
        }).toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        dropdownColor: AppTheme.surface,
      ),
    );
  }
}

// ── Stripes selector ──────────────────────────────────────────────────────────

class _StripesSelector extends StatelessWidget {
  const _StripesSelector({
    required this.sport,
    required this.grade,
    required this.onChanged,
  });

  final SportId sport;
  final ({String belt, int stripes}) grade;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final sportDef = sports[sport]!;
    if (!sportDef.supportsStripes) return const SizedBox.shrink();

    final gradeDef = getGradeDefinition(sport, grade.belt);
    final maxStripes = gradeDef?.maxStripes ?? 4;
    final clampedStripes = grade.stripes > maxStripes ? 0 : grade.stripes;

    if (grade.stripes > maxStripes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(0);
      });
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<int>(
        value: clampedStripes,
        isExpanded: true,
        icon: Icon(
          LucideIcons.chevronDown,
          color: AppTheme.textSecondary,
          size: 20,
        ),
        decoration: InputDecoration(
          labelText: 'Graus',
          prefixIcon: Icon(
            LucideIcons.hash,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: List.generate(maxStripes + 1, (i) {
          return DropdownMenuItem(
            value: i,
            child: Row(
              children: [
                ...List.generate(
                  i,
                  (_) => Container(
                    width: 12,
                    height: 3,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.textSecondary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                if (i > 0) const SizedBox(width: 6),
                Text('$i grau${i != 1 ? 's' : ''}',
                    style: AppTheme.bodyMedium),
              ],
            ),
          );
        }).toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        dropdownColor: AppTheme.surface,
      ),
    );
  }
}

// ── Add sport button ──────────────────────────────────────────────────────────

class _AddSportButton extends StatelessWidget {
  const _AddSportButton({
    required this.available,
    required this.category,
    required this.onAdd,
  });

  final List<SportId> available;
  final StudentCategory category;
  final ValueChanged<SportId> onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showSheet(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.plus, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 8),
              Text(
                'Adicionar modalidade',
                style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 16),
            Text(
              'Adicionar modalidade',
              style:
                  AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...available.map((sport) {
              final def = sports[sport]!;
              final accent = sportChipColors[sport] ?? AppTheme.primary;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(def.icon, color: accent, size: 18),
                ),
                title: Text(
                  def.label,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  def.gradeSystem == GradeSystem.none
                      ? 'Sem graduação'
                      : 'Faixas iniciam em ${getGradesForSport(sport, category: category.value).firstOrNull?.label ?? '-'}',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onAdd(sport);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
