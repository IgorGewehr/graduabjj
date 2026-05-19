import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../providers/providers.dart';
import '../../../widgets/common/grade_display.dart';
import '../../../widgets/common/profile_photo_picker.dart';

/// Hero Header — Centered avatar, name, belt, status
class ProfileHeroHeader extends ConsumerWidget {
  final Student student;

  const ProfileHeroHeader({super.key, required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final academyId = ref.watch(selectedAcademyIdProvider);

    return Column(
      children: [
        // Avatar
        ProfilePhotoPicker(
          academyId: academyId ?? '',
          studentId: student.id,
          photoUrl: student.photoUrl,
          fullName: student.fullName,
          currentBelt: student.currentBelt,
          editable: true,
          size: 88.0,
          onPhotoUpdated: () {
            ref.invalidate(currentStudentProvider);
          },
        ),
        const SizedBox(height: 12),
        // Name
        Text(
          student.fullName,
          style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        // Grade Display (sport-aware)
        GradeDisplay(
          sportId: student.getPrimarySport(),
          grade: student.currentBelt,
          stripes: student.currentStripes,
          size: GradeDisplaySize.large,
          showLabel: true,
        ),
        const SizedBox(height: 8),
        // Status Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.getStatusBackgroundColor(student.status.value),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            student.status.label,
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.getStatusColor(student.status.value),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
