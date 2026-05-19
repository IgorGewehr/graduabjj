import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/student_dto.dart' as api;
import '../../../api/repositories.dart' as tatami_repos;
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/assessment_service.dart' show Assessment, AssessmentCategory, AssessmentCategoryExtension;

/// Behavior tab content for student detail screen.
///
/// Needs [WidgetRef] to read currentUserProvider when saving assessments.
class StudentBehaviorTab extends StatelessWidget {
  final Student student;
  final List<Assessment> assessments;
  final WidgetRef ref;
  final VoidCallback onRefresh;

  const StudentBehaviorTab({
    super.key,
    required this.student,
    required this.assessments,
    required this.ref,
    required this.onRefresh,
  });

  // ──────────────────────────────────────────────────────────────
  // Helpers (score color / label) — duplicated from parent to keep
  // this file self-contained without creating a shared util.
  // ──────────────────────────────────────────────────────────────

  static Color getScoreColor(double score) {
    if (score >= 4.5) return Colors.green;
    if (score >= 4.0) return Colors.lightGreen;
    if (score >= 3.0) return Colors.orange;
    if (score >= 2.0) return Colors.deepOrange;
    return Colors.red;
  }

  static String getScoreLabel(double score) {
    if (score >= 4.5) return 'Excelente';
    if (score >= 4.0) return 'Muito Bom';
    if (score >= 3.0) return 'Bom';
    if (score >= 2.0) return 'Regular';
    return 'Precisa Melhorar';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        assessments.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.star,
                      size: 64,
                      color: AppTheme.textDisabled,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma avaliação registrada',
                      style: AppTheme.bodyLarge.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Adicione avaliações comportamentais\npara que os pais possam acompanhar',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textDisabled,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: assessments.length,
                itemBuilder: (context, index) {
                  final assessment = assessments[index];
                  return _AssessmentCard(
                    assessment: assessment,
                    onEdit: () =>
                        _showEditAssessmentDialog(context, assessment),
                    onDelete: () =>
                        _showDeleteAssessmentConfirmation(context, assessment),
                  );
                },
              ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _showAddAssessmentDialog(context),
            backgroundColor: AppTheme.primary,
            icon: const Icon(Icons.add, color: Colors.white),
            label:
                const Text('Avaliar', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  void _showAddAssessmentDialog(BuildContext context) {
    final scores = <AssessmentCategory, int>{
      AssessmentCategory.respeito: 3,
      AssessmentCategory.disciplina: 3,
      AssessmentCategory.pontualidade: 3,
      AssessmentCategory.tecnica: 3,
      AssessmentCategory.esforco: 3,
    };
    final notesController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          double average =
              scores.values.fold<int>(0, (acc, v) => acc + v) / scores.length;

          return AlertDialog(
            title: const Text('Nova Avaliação'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date
                  Text('Data', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        locale: const Locale('pt', 'BR'),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.divider),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 8),
                          Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Average display
                  Center(
                    child: Column(
                      children: [
                        Text(
                          average.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: getScoreColor(average),
                          ),
                        ),
                        Text(
                          getScoreLabel(average),
                          style: TextStyle(
                            color: getScoreColor(average),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Score sliders
                  ...AssessmentCategory.values.map((category) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                category.label,
                                style: AppTheme.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${scores[category]}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: getScoreColor(
                                    scores[category]!.toDouble(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: scores[category]!.toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            activeColor: getScoreColor(
                              scores[category]!.toDouble(),
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => scores[category] = value.round(),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  }),

                  // Notes
                  Text('Observações (opcional)', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Feedback para os pais...',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);

                  try {
                    final currentUser =
                        ref.read(currentUserProvider).valueOrNull;
                    final academyId = currentUser?.academyId;
                    if (academyId == null) throw Exception('academyId ausente');

                    final req = api.CreateAssessmentRequest(
                      date: selectedDate,
                      notes: notesController.text.trim().isNotEmpty
                          ? notesController.text.trim()
                          : null,
                      scores: api.ApiAssessmentScores(
                        respeito: scores[AssessmentCategory.respeito]!,
                        disciplina: scores[AssessmentCategory.disciplina]!,
                        pontualidade: scores[AssessmentCategory.pontualidade]!,
                        tecnica: scores[AssessmentCategory.tecnica]!,
                        esforco: scores[AssessmentCategory.esforco]!,
                      ),
                    );

                    await ref
                        .read(tatami_repos.assessmentRepoProvider)
                        .create(academyId, student.id, req);

                    if (parentContext.mounted) {
                      parentContext.showSuccess('Avaliação adicionada!');
                      onRefresh();
                    }
                  } catch (e) {
                    if (parentContext.mounted) {
                      parentContext.showError('Erro: $e');
                    }
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditAssessmentDialog(
    BuildContext context,
    Assessment assessment,
  ) {
    final scores = <AssessmentCategory, int>{};
    for (final category in AssessmentCategory.values) {
      scores[category] = assessment.getScoreForCategory(category) ?? 3;
    }
    final notesController = TextEditingController(text: assessment.notes);
    DateTime selectedDate = assessment.date;
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          double average =
              scores.values.fold<int>(0, (acc, v) => acc + v) / scores.length;

          return AlertDialog(
            title: const Text('Editar Avaliação'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date
                  Text('Data', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        locale: const Locale('pt', 'BR'),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.divider),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 8),
                          Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Average
                  Center(
                    child: Column(
                      children: [
                        Text(
                          average.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: getScoreColor(average),
                          ),
                        ),
                        Text(
                          getScoreLabel(average),
                          style: TextStyle(
                            color: getScoreColor(average),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Scores
                  ...AssessmentCategory.values.map((category) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                category.label,
                                style: AppTheme.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${scores[category]}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: getScoreColor(
                                    scores[category]!.toDouble(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: scores[category]!.toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            activeColor: getScoreColor(
                              scores[category]!.toDouble(),
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => scores[category] = value.round(),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  }),

                  // Notes
                  Text('Observações (opcional)', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Feedback para os pais...',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);

                  try {
                    final currentUser =
                        ref.read(currentUserProvider).valueOrNull;
                    final academyId = currentUser?.academyId;
                    if (academyId == null) throw Exception('academyId ausente');

                    final data = <String, dynamic>{
                      'date': '${selectedDate.year.toString().padLeft(4, '0')}-'
                          '${selectedDate.month.toString().padLeft(2, '0')}-'
                          '${selectedDate.day.toString().padLeft(2, '0')}',
                      'scores': {
                        'respeito': scores[AssessmentCategory.respeito],
                        'disciplina': scores[AssessmentCategory.disciplina],
                        'pontualidade':
                            scores[AssessmentCategory.pontualidade],
                        'tecnica': scores[AssessmentCategory.tecnica],
                        'esforco': scores[AssessmentCategory.esforco],
                      },
                      if (notesController.text.trim().isNotEmpty)
                        'notes': notesController.text.trim(),
                    };

                    await ref
                        .read(tatami_repos.assessmentRepoProvider)
                        .update(academyId, student.id, assessment.id, data);

                    if (parentContext.mounted) {
                      parentContext.showSuccess('Avaliação atualizada!');
                      onRefresh();
                    }
                  } catch (e) {
                    if (parentContext.mounted) {
                      parentContext.showError('Erro: $e');
                    }
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteAssessmentConfirmation(
    BuildContext context,
    Assessment assessment,
  ) {
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir Avaliação'),
        content: Text(
          'Deseja excluir a avaliação de ${DateFormat('dd/MM/yyyy').format(assessment.date)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);

              try {
                final currentUser =
                    ref.read(currentUserProvider).valueOrNull;
                final academyId = currentUser?.academyId;
                if (academyId == null) throw Exception('academyId ausente');

                await ref
                    .read(tatami_repos.assessmentRepoProvider)
                    .delete(academyId, student.id, assessment.id);

                if (parentContext.mounted) {
                  parentContext.showSuccess('Avaliação excluída.');
                  onRefresh();
                }
              } catch (e) {
                if (parentContext.mounted) {
                  parentContext.showError('Erro ao excluir: $e');
                }
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widget
// ---------------------------------------------------------------------------

class _AssessmentCard extends StatelessWidget {
  final Assessment assessment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AssessmentCard({
    required this.assessment,
    required this.onEdit,
    required this.onDelete,
  });

  Color _getScoreColor(double score) =>
      StudentBehaviorTab.getScoreColor(score);
  String _getScoreLabel(double score) =>
      StudentBehaviorTab.getScoreLabel(score);

  @override
  Widget build(BuildContext context) {
    final average = assessment.averageScore;
    final scoreColor = _getScoreColor(average);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd/MM/yyyy').format(assessment.date),
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scoreColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${average.toStringAsFixed(1)} - ${_getScoreLabel(average)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        onSelected: (value) {
                          if (value == 'edit') onEdit();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 20),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 20, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Excluir',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Scores grid
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: AssessmentCategory.values.map((category) {
                  final score = assessment.getScoreForCategory(category) ?? 0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.star,
                        size: 12,
                        color: _getScoreColor(score.toDouble()),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${category.label}: $score',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),

              // Notes
              if (assessment.notes != null && assessment.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '"${assessment.notes}"',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
