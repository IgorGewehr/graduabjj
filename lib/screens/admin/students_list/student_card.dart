import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';
import '../../../widgets/cached_image.dart';
import '../../../widgets/common/grade_display.dart';
import '../../../widgets/common/sport_chip.dart';

class StudentCard extends StatelessWidget {
  final Student student;
  final VoidCallback? onTap;
  final EligibilitySnapshotEntry? eligibility;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final int animationIndex;

  const StudentCard({
    super.key,
    required this.student,
    this.onTap,
    this.eligibility,
    this.selectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.animationIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final showEligibility =
        eligibility != null && eligibility!.requiredClasses > 0;
    final primarySport = student.getPrimarySport();
    final grade = student.getGrade(primarySport);
    final gradeId = grade?.currentGrade ?? 'white';
    final beltColor = getGradeColor(primarySport, gradeId);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.04)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: beltColor, width: 4),
            right: BorderSide(color: AppTheme.divider),
            top: BorderSide(color: AppTheme.divider),
            bottom: BorderSide(color: AppTheme.divider),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (selectionMode) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textDisabled,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
              _buildAvatar(beltColor, gradeId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            student.fullName,
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showEligibility && eligibility!.eligible)
                          _buildEligibleBadge(),
                        if (student.status != StudentStatus.active)
                          _buildStatusBadge()
                        else
                          _buildActiveDot(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildPrimaryGrade(),
                        const SizedBox(width: 8),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.textDisabled,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '↑ ${student.totalAttendanceCount} presenças',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          student.category.label,
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (showEligibility) _buildProgressRow(),
                    _buildSportChipsRow(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!selectionMode)
                Icon(
                  LucideIcons.chevronRight,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: (animationIndex * 40).ms)
        .fadeIn(duration: 200.ms)
        .slideX(begin: -0.05, duration: 200.ms, curve: Curves.easeOut);
  }

  Widget _buildActiveDot() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppTheme.success,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildEligibleBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.warningLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.zap, size: 10, color: AppTheme.warning),
          const SizedBox(width: 4),
          Text(
            'Elegivel',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.warning,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow() {
    final e = eligibility!;
    final progress = (e.currentClasses / e.requiredClasses).clamp(0.0, 1.0);
    final unit = e.weighted ? 'pts' : 'aulas';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: AppTheme.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(
                  e.eligible ? AppTheme.warning : AppTheme.info,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${e.currentClasses}/${e.requiredClasses} $unit',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(Color beltColor, String gradeId) {
    final primarySport = student.getPrimarySport();
    final sportColor = sportChipColors[primarySport] ?? AppTheme.textSecondary;
    final avatarColor = beltColor;
    final isLightAvatar = _isLightGrade(gradeId);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: avatarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sportColor, width: 2),
      ),
      child: student.photoUrl != null
          ? AppCachedImage(
              imageUrl: student.photoUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(10),
            )
          : Center(
              child: Text(
                student.displayName[0].toUpperCase(),
                style: TextStyle(
                  color: isLightAvatar ? Colors.black87 : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
            ),
    );
  }

  Widget _buildPrimaryGrade() {
    final primarySport = student.getPrimarySport();
    final grade = student.getGrade(primarySport);
    if (grade == null) return const SizedBox.shrink();
    return GradeDisplay(
      sportId: primarySport,
      grade: grade.currentGrade,
      stripes: grade.currentStripes,
      size: GradeDisplaySize.small,
    );
  }

  Widget _buildSportChipsRow() {
    final studentSports = student.getSports();
    if (studentSports.isEmpty) return const SizedBox.shrink();
    final primary = student.getPrimarySport();
    final ordered = [primary, ...studentSports.where((s) => s != primary)];
    const maxVisible = 4;
    final visible = ordered.take(maxVisible).toList();
    final overflow = ordered.length - visible.length;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final s in visible) SportChip(sportId: s),
          if (overflow > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+$overflow',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  height: 1,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color color;
    switch (student.status) {
      case StudentStatus.injured:
        color = AppTheme.warning;
        break;
      case StudentStatus.inactive:
        color = AppTheme.textSecondary;
        break;
      case StudentStatus.suspended:
        color = AppTheme.error;
        break;
      default:
        color = AppTheme.textSecondary;
    }

    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        student.status.label,
        style: AppTheme.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  bool _isLightGrade(String gradeId) {
    const lightGrades = {'white', 'yellow', 'orange'};
    return lightGrades.contains(gradeId.split('-').first);
  }
}
