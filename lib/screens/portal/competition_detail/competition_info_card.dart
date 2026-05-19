import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';
import '../../../widgets/loading_button.dart';

/// Header card showing competition name, date, location, status and
/// the self-enroll / cancel-enrollment button for students.
class CompetitionInfoCard extends StatelessWidget {
  final Competition competition;
  final List<CompetitionEnrollment> enrollments;
  final Student? student;
  final bool isAdmin;
  final bool isEnrolling;
  final VoidCallback? onEnroll;
  final VoidCallback? onCancelEnrollment;

  const CompetitionInfoCard({
    super.key,
    required this.competition,
    required this.enrollments,
    required this.student,
    required this.isAdmin,
    required this.isEnrolling,
    this.onEnroll,
    this.onCancelEnrollment,
  });

  bool get _isEnrolled =>
      student != null && enrollments.any((e) => e.studentId == student!.id);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  competition.name,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildStatusChip(competition.status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                LucideIcons.calendar,
                size: 14,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR')
                    .format(competition.date),
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          if (competition.location != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  LucideIcons.mapPin,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    competition.location!,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (competition.description != null &&
              competition.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              competition.description!,
              style:
                  AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // Self-enrollment button (students only)
          if (!isAdmin &&
              student != null &&
              competition.status != CompetitionStatus.completed) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _isEnrolled
                  ? OutlinedButton(
                      onPressed:
                          isEnrolling ? null : onCancelEnrollment,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        isEnrolling ? 'Cancelando...' : 'Cancelar Inscricao',
                      ),
                    )
                  : LoadingButton(
                      isLoading: isEnrolling,
                      onPressed: onEnroll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(LucideIcons.userPlus, size: 16),
                          SizedBox(width: 8),
                          Text('Inscrever-se'),
                        ],
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(CompetitionStatus status) {
    final config = {
      CompetitionStatus.upcoming: {
        'label': 'Proxima',
        'color': AppTheme.warning,
      },
      CompetitionStatus.ongoing: {
        'label': 'Em Andamento',
        'color': AppTheme.info,
      },
      CompetitionStatus.completed: {
        'label': 'Concluida',
        'color': AppTheme.success,
      },
    };

    final c = config[status] ?? config[CompetitionStatus.upcoming]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (c['color'] as Color).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        c['label'] as String,
        style: AppTheme.labelSmall.copyWith(
          color: c['color'] as Color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
