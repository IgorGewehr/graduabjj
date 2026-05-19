import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';

/// Position display config — shared between results tab and dialogs.
const positionConfig = {
  'gold': {'label': 'Ouro', 'icon': '🥇', 'color': 0xFFFFD700},
  'silver': {'label': 'Prata', 'icon': '🥈', 'color': 0xFFC0C0C0},
  'bronze': {'label': 'Bronze', 'icon': '🥉', 'color': 0xFFCD7F32},
  'participant': {'label': 'Participante', 'icon': '🎖️', 'color': 0xFF666666},
};

/// Results tab: team result card + my results card + all results card.
class CompetitionResultsTab extends StatelessWidget {
  final Competition competition;
  final List<CompetitionResult> results;
  final List<CompetitionEnrollment> enrollments;
  final Student? student;
  final bool isAdmin;
  final VoidCallback onRefresh;
  final VoidCallback onShowTeamResultDialog;
  final VoidCallback? onRemoveTeamResult;
  final VoidCallback? onShowAdminAddResultDialog;
  final void Function({
    required String studentId,
    required String studentName,
    CompetitionResult? existingResult,
    CompetitionEnrollment? enrollment,
  }) onShowResultDialog;
  final Future<void> Function(CompetitionResult) onDeleteResult;

  const CompetitionResultsTab({
    super.key,
    required this.competition,
    required this.results,
    required this.enrollments,
    required this.student,
    required this.isAdmin,
    required this.onRefresh,
    required this.onShowTeamResultDialog,
    this.onRemoveTeamResult,
    required this.onShowAdminAddResultDialog,
    required this.onShowResultDialog,
    required this.onDeleteResult,
  });

  @override
  Widget build(BuildContext context) {
    final studentId = student?.id;
    final myResults =
        results.where((r) => r.studentId == studentId).toList();
    final myEnrollment =
        enrollments.where((e) => e.studentId == studentId).firstOrNull;

    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        onRefresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Team Result Card (admin can edit, students only see)
          if (isAdmin || competition.teamPosition != null)
            _TeamResultCard(
              competition: competition,
              isAdmin: isAdmin,
              onShowTeamResultDialog: onShowTeamResultDialog,
              onRemoveTeamResult: onRemoveTeamResult,
            ),

          // My Results Card (supports multiple) - only for students
          if (!isAdmin && studentId != null)
            _MyResultsCard(
              studentId: studentId,
              studentName: student?.fullName ?? '',
              myResults: myResults,
              myEnrollment: myEnrollment,
              onShowResultDialog: onShowResultDialog,
              onDeleteResult: onDeleteResult,
            ),

          const SizedBox(height: 16),

          // All Results (admin has full management)
          _AllResultsCard(
            results: results,
            enrollments: enrollments,
            currentStudentId: studentId,
            isAdmin: isAdmin,
            onShowAdminAddResultDialog: onShowAdminAddResultDialog,
            onShowResultDialog: onShowResultDialog,
            onDeleteResult: onDeleteResult,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team Result Card
// ---------------------------------------------------------------------------

class _TeamResultCard extends StatelessWidget {
  final Competition competition;
  final bool isAdmin;
  final VoidCallback onShowTeamResultDialog;
  final VoidCallback? onRemoveTeamResult;

  const _TeamResultCard({
    required this.competition,
    required this.isAdmin,
    required this.onShowTeamResultDialog,
    this.onRemoveTeamResult,
  });

  @override
  Widget build(BuildContext context) {
    final position = competition.teamPosition;
    final config = {
      'gold': {
        'label': 'Campeao por Equipes',
        'bgColor': const Color(0xFFFEF3C7),
        'borderColor': const Color(0xFFF59E0B),
        'textColor': const Color(0xFF92400E),
      },
      'silver': {
        'label': 'Vice-campeao por Equipes',
        'bgColor': const Color(0xFFF3F4F6),
        'borderColor': const Color(0xFF9CA3AF),
        'textColor': const Color(0xFF374151),
      },
      'bronze': {
        'label': '3o Lugar por Equipes',
        'bgColor': const Color(0xFFFED7AA),
        'borderColor': const Color(0xFFF97316),
        'textColor': const Color(0xFF7C2D12),
      },
    };

    // Admin without team result: show register button
    if (position == null && isAdmin) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: OutlinedButton(
          onPressed: onShowTeamResultDialog,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: const BorderSide(
              color: AppTheme.warning,
              style: BorderStyle.solid,
              width: 2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'Registrar Resultado da Equipe',
                style: AppTheme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (position == null) return const SizedBox.shrink();

    final c = config[position] ?? config['gold']!;
    final bgColor = c['bgColor'] as Color;
    final borderColor = c['borderColor'] as Color;
    final textColor = c['textColor'] as Color;
    final label = c['label'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 36)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RESULTADO DA EQUIPE',
                  style: AppTheme.labelSmall.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: AppTheme.titleMedium.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (competition.teamNotes != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    competition.teamNotes!,
                    style: AppTheme.bodySmall.copyWith(
                      color: textColor.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isAdmin) ...[
            IconButton(
              onPressed: onShowTeamResultDialog,
              icon: Icon(LucideIcons.edit, size: 18, color: textColor),
            ),
            IconButton(
              onPressed: onRemoveTeamResult,
              icon: Icon(LucideIcons.trash2, size: 18, color: textColor),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My Results Card
// ---------------------------------------------------------------------------

class _MyResultsCard extends StatelessWidget {
  final String studentId;
  final String studentName;
  final List<CompetitionResult> myResults;
  final CompetitionEnrollment? myEnrollment;
  final void Function({
    required String studentId,
    required String studentName,
    CompetitionResult? existingResult,
    CompetitionEnrollment? enrollment,
  }) onShowResultDialog;
  final Future<void> Function(CompetitionResult) onDeleteResult;

  const _MyResultsCard({
    required this.studentId,
    required this.studentName,
    required this.myResults,
    required this.myEnrollment,
    required this.onShowResultDialog,
    required this.onDeleteResult,
  });

  @override
  Widget build(BuildContext context) {
    final firstPos = myResults.isNotEmpty
        ? positionConfig[myResults.first.position] ??
              positionConfig['participant']!
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: myResults.isNotEmpty
              ? Color(firstPos!['color'] as int).withValues(alpha: 0.5)
              : AppTheme.primary.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                myResults.length > 1 ? 'MEUS RESULTADOS' : 'MEU RESULTADO',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              TextButton.icon(
                onPressed: () => onShowResultDialog(
                  studentId: studentId,
                  studentName: studentName,
                  existingResult: null,
                  enrollment: myEnrollment,
                ),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Adicionar'),
                style: TextButton.styleFrom(
                  textStyle: AppTheme.labelSmall,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (myResults.isNotEmpty) ...[
            ...myResults.map((result) {
              final pos =
                  positionConfig[result.position] ??
                  positionConfig['participant']!;
              return Padding(
                padding: EdgeInsets.only(
                  top: result == myResults.first ? 0 : 8,
                ),
                child: Row(
                  children: [
                    Text(
                      pos['icon'] as String,
                      style: const TextStyle(fontSize: 36),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pos['label'] as String,
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (result.ageCategory != null ||
                              result.weightCategory != null)
                            Text(
                              [
                                    if (result.modality != null)
                                      result.modality == 'gi' ? 'Gi' : 'No-Gi',
                                    if (result.divisionType != null)
                                      result.divisionType == 'absolute'
                                          ? 'Absoluto'
                                          : 'Peso',
                                    result.ageCategory,
                                    result.weightCategory,
                                  ]
                                  .where((e) => e != null && e.isNotEmpty)
                                  .join(' - '),
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          if (result.notes != null)
                            Text(
                              result.notes!,
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => onShowResultDialog(
                        studentId: studentId,
                        studentName: studentName,
                        existingResult: result,
                        enrollment: myEnrollment,
                      ),
                      icon: const Icon(LucideIcons.edit, size: 18),
                      color: AppTheme.textSecondary,
                    ),
                    IconButton(
                      onPressed: () => onDeleteResult(result),
                      icon: const Icon(LucideIcons.trash2, size: 18),
                      color: Colors.red.shade400,
                    ),
                  ],
                ),
              );
            }),
          ] else ...[
            InkWell(
              onTap: () => onShowResultDialog(
                studentId: studentId,
                studentName: studentName,
                existingResult: null,
                enrollment: myEnrollment,
              ),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.medal,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Registrar meu resultado',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// All Results Card
// ---------------------------------------------------------------------------

class _AllResultsCard extends StatelessWidget {
  final List<CompetitionResult> results;
  final List<CompetitionEnrollment> enrollments;
  final String? currentStudentId;
  final bool isAdmin;
  final VoidCallback? onShowAdminAddResultDialog;
  final void Function({
    required String studentId,
    required String studentName,
    CompetitionResult? existingResult,
    CompetitionEnrollment? enrollment,
  }) onShowResultDialog;
  final Future<void> Function(CompetitionResult) onDeleteResult;

  const _AllResultsCard({
    required this.results,
    required this.enrollments,
    required this.currentStudentId,
    required this.isAdmin,
    required this.onShowAdminAddResultDialog,
    required this.onShowResultDialog,
    required this.onDeleteResult,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Icon(
                LucideIcons.users,
                size: 16,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAdmin ? 'Resultados' : 'Todos os Resultados',
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isAdmin)
                TextButton.icon(
                  onPressed: enrollments.isEmpty
                      ? null
                      : onShowAdminAddResultDialog,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Adicionar'),
                  style: TextButton.styleFrom(
                    textStyle: AppTheme.labelSmall,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.medal,
                      size: 40,
                      color: AppTheme.textDisabled,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nenhum resultado registrado ainda',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(results.length, (index) {
              final result = results[index];
              final pos =
                  positionConfig[result.position] ??
                  positionConfig['participant']!;
              final isMe = result.studentId == currentStudentId;

              return Container(
                margin: EdgeInsets.only(top: index > 0 ? 8 : 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isMe
                      ? AppTheme.primary.withValues(alpha: 0.05)
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: isMe
                      ? Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Text(
                      pos['icon'] as String,
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  result.studentName,
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: isMe
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Voce',
                                    style: AppTheme.labelSmall.copyWith(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${pos['label'] as String}'
                            '${result.modality != null ? ' - ${result.modality == 'gi' ? 'Gi' : 'No-Gi'}' : ''}'
                            '${result.weightCategory != null ? ' - ${result.weightCategory}' : ''}',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isAdmin) ...[
                      IconButton(
                        onPressed: () => onShowResultDialog(
                          studentId: result.studentId,
                          studentName: result.studentName,
                          existingResult: result,
                          enrollment: enrollments
                              .where((e) => e.studentId == result.studentId)
                              .firstOrNull,
                        ),
                        icon: const Icon(LucideIcons.edit, size: 16),
                        color: AppTheme.textSecondary,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        onPressed: () => onDeleteResult(result),
                        icon: const Icon(LucideIcons.trash2, size: 16),
                        color: Colors.red.shade400,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
