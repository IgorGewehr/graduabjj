import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/sports.dart';
import '../../../models/student.dart';
import '../../../providers/providers.dart';
import '../../../widgets/common/profile_photo_picker.dart';
import '../../../widgets/common/sport_chip.dart';

/// SliverAppBar for the student detail screen.
///
/// Receives permission flags and callbacks from the parent coordinator so it
/// remains a pure presentation widget with no business logic.
class StudentDetailSliverAppBar extends StatelessWidget {
  final Student student;
  final WidgetRef ref;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onPromote;
  final VoidCallback onToggleStatus;
  final VoidCallback onGenerateCode;
  final VoidCallback onDelete;
  final VoidCallback onPhotoUpdated;

  const StudentDetailSliverAppBar({
    super.key,
    required this.student,
    required this.ref,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onPromote,
    required this.onToggleStatus,
    required this.onGenerateCode,
    required this.onDelete,
    required this.onPhotoUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      actions: [
        if (canEdit)
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: onEdit,
          ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'promote') onPromote();
            if (value == 'toggle_status') onToggleStatus();
            if (value == 'generate_code') onGenerateCode();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'promote',
              child: Row(
                children: [
                  Icon(Icons.military_tech),
                  SizedBox(width: 8),
                  Text('Graduar'),
                ],
              ),
            ),
            if (canEdit)
              PopupMenuItem(
                value: 'toggle_status',
                child: Row(
                  children: [
                    Icon(
                      student.status == StudentStatus.active
                          ? Icons.person_off
                          : Icons.person,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      student.status == StudentStatus.active
                          ? 'Desativar'
                          : 'Ativar',
                    ),
                  ],
                ),
              ),
            if (canEdit && student.linkedUserId == null)
              const PopupMenuItem(
                value: 'generate_code',
                child: Row(
                  children: [
                    Icon(LucideIcons.link),
                    SizedBox(width: 8),
                    Text('Gerar Codigo de Acesso'),
                  ],
                ),
              ),
            if (canDelete)
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Excluir', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                getGradeColor(
                  student.getPrimarySport(),
                  student.currentBelt,
                ),
                getGradeColor(
                  student.getPrimarySport(),
                  student.currentBelt,
                ).withValues(alpha: 0.7),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ProfilePhotoPicker(
                        academyId: ref.watch(selectedAcademyIdProvider) ?? '',
                        studentId: student.id,
                        photoUrl: student.photoUrl,
                        fullName: student.fullName,
                        currentBelt: student.currentBelt,
                        editable: true,
                        size: 96.0,
                        onPhotoUpdated: onPhotoUpdated,
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student.fullName,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: (student.currentBelt == 'white' ||
                                        student.currentBelt == 'yellow')
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _BeltBadge(student: student),
                                const SizedBox(width: 8),
                                _StatusBadge(student: student),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private badge sub-widgets
// ---------------------------------------------------------------------------

class _BeltBadge extends StatelessWidget {
  final Student student;
  const _BeltBadge({required this.student});

  @override
  Widget build(BuildContext context) {
    final sports = student.getSports();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: sports.map((sportId) {
        final grade = student.getGrade(sportId);
        final gradeId = grade?.currentGrade ?? 'white';
        final stripes = grade?.currentStripes ?? 0;
        final gradeLabel = getGradeLabel(sportId, gradeId);
        final gradeColor = getGradeColor(sportId, gradeId);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sports.length > 1) ...[
                SportChip(sportId: sportId, size: SportChipSize.xs),
                const SizedBox(width: 4),
              ],
              Icon(LucideIcons.award, size: 16, color: gradeColor),
              const SizedBox(width: 6),
              Text(
                gradeLabel,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (stripes > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: gradeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$stripes grau${stripes > 1 ? "s" : ""}',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Student student;
  const _StatusBadge({required this.student});

  @override
  Widget build(BuildContext context) {
    final statusConfig = {
      StudentStatus.active: {
        'color': Colors.green,
        'icon': LucideIcons.checkCircle2,
      },
      StudentStatus.inactive: {
        'color': Colors.grey,
        'icon': LucideIcons.pauseCircle,
      },
      StudentStatus.suspended: {
        'color': Colors.orange,
        'icon': LucideIcons.alertCircle,
      },
      StudentStatus.injured: {
        'color': Colors.blue,
        'icon': LucideIcons.heartPulse,
      },
    };

    final config =
        statusConfig[student.status] ??
        {'color': Colors.grey, 'icon': LucideIcons.circle};
    final statusColor = config['color'] as Color;
    final statusIcon = config['icon'] as IconData;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 6),
          Text(
            student.status.label,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
