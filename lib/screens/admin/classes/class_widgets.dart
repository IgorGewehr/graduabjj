// Small, purely-presentational widgets shared across the classes sub-screens.
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';
import '../../../widgets/common/sport_chip.dart';
import 'class_helpers.dart';

// ─── Stats Carousel Card ─────────────────────────────────────────────────────

class StatsCarouselCard extends StatelessWidget {
  final IconData icon;
  final Color? iconBgColor;
  final Color? iconColor;
  final String label;
  final String value;
  final String subtitle;

  const StatsCarouselCard({
    super.key,
    required this.icon,
    this.iconBgColor,
    this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBgColor ?? AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor ?? AppTheme.textPrimary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
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

// ─── Filter Chip ─────────────────────────────────────────────────────────────

class ClassFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const ClassFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      ),
    );
  }
}

// ─── Info Badge ──────────────────────────────────────────────────────────────

class InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const InfoBadge({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Detail Row ──────────────────────────────────────────────────────────────

class DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const DetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        Text(
          value,
          style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ─── Modern Text Field ───────────────────────────────────────────────────────

class ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;

  const ModernTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textDisabled,
              ),
              prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Toggle Chip ─────────────────────────────────────────────────────────────

class ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.textPrimary : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.textPrimary : AppTheme.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.labelSmall.copyWith(
            color: selected ? Colors.white : AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Schedule Entry Row ───────────────────────────────────────────────────────

class ScheduleEntryRow extends StatelessWidget {
  final ScheduleEntry schedule;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final BuildContext dialogContext;

  const ScheduleEntryRow({
    super.key,
    required this.schedule,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.dialogContext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButton<int>(
                value: schedule.dayOfWeek,
                isExpanded: true,
                underline: const SizedBox(),
                items: List.generate(7, (i) {
                  return DropdownMenuItem(
                    value: i,
                    child: Text(getDayLabel(i), style: AppTheme.bodySmall),
                  );
                }),
                onChanged: (value) {
                  schedule.dayOfWeek = value!;
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () async {
                  final time = await showTimePicker(
                    context: dialogContext,
                    initialTime: parseTimeString(schedule.startTime),
                  );
                  if (time != null) {
                    schedule.startTime = formatTimeOfDay(time);
                    onChanged();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  child: Text(
                    schedule.startTime,
                    style: AppTheme.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              ' - ',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () async {
                  final time = await showTimePicker(
                    context: dialogContext,
                    initialTime: parseTimeString(schedule.endTime),
                  );
                  if (time != null) {
                    schedule.endTime = formatTimeOfDay(time);
                    onChanged();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  child: Text(
                    schedule.endTime,
                    style: AppTheme.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            if (canRemove)
              IconButton(
                icon: Icon(LucideIcons.x, size: 18, color: AppTheme.error),
                onPressed: onRemove,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Stats Carousel Section ───────────────────────────────────────────────────
// Self-contained stateful widget that owns its own PageController, so the
// coordinator screen doesn't need to hold carousel state.

class StatsCarouselSection extends StatefulWidget {
  final List<BJJClass> classes;

  const StatsCarouselSection({super.key, required this.classes});

  @override
  State<StatsCarouselSection> createState() => _StatsCarouselSectionState();
}

class _StatsCarouselSectionState extends State<StatsCarouselSection> {
  final PageController _controller = PageController(viewportFraction: 0.85);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalClasses = widget.classes.length;
    final totalStudents = widget.classes.fold<int>(
      0,
      (sum, c) => sum + c.studentIds.length,
    );
    final withSchedule =
        widget.classes.where((c) => c.schedule.isNotEmpty).length;

    final cards = [
      StatsCarouselCard(
        icon: LucideIcons.users,
        iconBgColor: AppTheme.primary.withValues(alpha: 0.1),
        iconColor: AppTheme.primary,
        label: 'Total de Turmas',
        value: totalClasses.toString(),
        subtitle: 'turmas cadastradas',
      ),
      StatsCarouselCard(
        icon: LucideIcons.userCheck,
        iconBgColor: AppTheme.successLight,
        iconColor: AppTheme.success,
        label: 'Alunos em Turmas',
        value: totalStudents.toString(),
        subtitle: 'alunos matriculados',
      ),
      StatsCarouselCard(
        icon: LucideIcons.clock,
        iconBgColor: AppTheme.warning.withValues(alpha: 0.1),
        iconColor: AppTheme.warning,
        label: 'Com Horario',
        value: withSchedule.toString(),
        subtitle: 'turmas com horario definido',
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 100,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (p) => setState(() => _page = p),
            itemCount: cards.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: cards[i],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(cards.length, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _page == i ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _page == i ? AppTheme.textPrimary : AppTheme.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─── Class Card ──────────────────────────────────────────────────────────────

class ClassCard extends StatelessWidget {
  final BJJClass bjjClass;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ClassCard({
    super.key,
    required this.bjjClass,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    LucideIcons.users,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bjjClass.name,
                        style: AppTheme.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          if (bjjClass.category != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4, right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                bjjClass.category!.label,
                                style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: SportChip(sportId: bjjClass.getSport()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onEdit != null || onDelete != null)
                  PopupMenuButton<String>(
                    icon: Icon(
                      LucideIcons.moreVertical,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    onSelected: (value) {
                      if (value == 'edit') onEdit?.call();
                      if (value == 'delete') onDelete?.call();
                    },
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.pencil,
                                size: 18,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              const Text('Editar'),
                            ],
                          ),
                        ),
                      if (onDelete != null)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.trash2,
                                size: 18,
                                color: AppTheme.error,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Excluir',
                                style: TextStyle(color: AppTheme.error),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoBadge(
                  icon: LucideIcons.userCheck,
                  label: bjjClass.maxStudents != null
                      ? '${bjjClass.studentIds.length}/${bjjClass.maxStudents} alunos'
                      : '${bjjClass.studentIds.length} alunos',
                ),
                InfoBadge(
                  icon: LucideIcons.clock,
                  label: '${bjjClass.schedule.length} horarios',
                ),
                if (bjjClass.instructorName != null &&
                    bjjClass.instructorName!.isNotEmpty)
                  InfoBadge(
                    icon: LucideIcons.userCircle,
                    label: bjjClass.instructorName!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
