import 'package:flutter/material.dart';

import '../../../api/competition_repo.dart';
import '../../../api/dto/competition_dto.dart';
import '../../../core/theme.dart';
import '../../../services/competition_enrollment_service.dart';
import '../../../services/competition_service.dart';
import 'competition_results_tab.dart' show positionConfig;

/// Stateless helpers to open the three bottom-sheet dialogs related to
/// competition results.  All async work is delegated back to the caller via
/// callbacks so that state lives in one place (_CompetitionDetailScreenState).

/// Opens the "Register / Edit team result" bottom sheet.
///
/// [onSaved] is called after a successful save so the caller can reload data.
void showTeamResultDialog(
  BuildContext context, {
  required Competition competition,
  required String academyId,
  required CompetitionRemoteRepo repo,
  required VoidCallback onSaved,
}) {
  String teamPosition = competition.teamPosition ?? 'gold';
  final notesController = TextEditingController(
    text: competition.teamNotes ?? '',
  );

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 16),
                Text(
                  competition.teamPosition != null
                      ? 'Editar Resultado da Equipe'
                      : 'Registrar Resultado da Equipe',
                  style: AppTheme.titleLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Posicao',
                  style: AppTheme.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('🥇 Campeao'),
                      selected: teamPosition == 'gold',
                      onSelected: (_) =>
                          setSheetState(() => teamPosition = 'gold'),
                      selectedColor: const Color(0xFFFEF3C7),
                    ),
                    ChoiceChip(
                      label: const Text('🥈 Vice'),
                      selected: teamPosition == 'silver',
                      onSelected: (_) =>
                          setSheetState(() => teamPosition = 'silver'),
                      selectedColor: const Color(0xFFF3F4F6),
                    ),
                    ChoiceChip(
                      label: const Text('🥉 3o Lugar'),
                      selected: teamPosition == 'bronze',
                      onSelected: (_) =>
                          setSheetState(() => teamPosition = 'bronze'),
                      selectedColor: const Color(0xFFFED7AA),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Observacoes (opcional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      // Map string position to int (Tatami wire format).
                      // 'gold' → 1, 'silver' → 2, 'bronze' → 3.
                      final positionInt = switch (teamPosition) {
                        'gold' => 1,
                        'silver' => 2,
                        'bronze' => 3,
                        _ => 1,
                      };
                      final req = UpdateCompetitionRequest(
                        teamPosition: positionInt,
                        teamNotes: notesController.text.isNotEmpty
                            ? notesController.text
                            : null,
                      );
                      try {
                        await repo.update(academyId, competition.id, req);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        onSaved();
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Erro: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Opens the "Remove team result" confirmation dialog and performs the delete.
///
/// Calls DELETE /v1/academies/{academyId}/competitions/{competitionId}/team-result
/// which sets team_position and team_notes to NULL on the backend.
Future<void> showRemoveTeamResultDialog(
  BuildContext context, {
  required Competition competition,
  required String academyId,
  required CompetitionRemoteRepo repo,
  required VoidCallback onRemoved,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remover Resultado da Equipe'),
      content: const Text('Deseja remover o resultado da equipe?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Remover'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    await repo.clearTeamResult(academyId, competition.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resultado da equipe removido'),
          backgroundColor: Colors.green,
        ),
      );
    }
    onRemoved();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

/// Opens the "Select student → add result" bottom sheet for admins.
///
/// On student selection, calls [onStudentSelected] so the caller can open
/// [showResultDialog] with the chosen enrollment.
void showAdminAddResultDialog(
  BuildContext context, {
  required List<CompetitionEnrollment> enrollments,
  required void Function(CompetitionEnrollment) onStudentSelected,
}) {
  CompetitionEnrollment? selectedEnrollment;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              const SizedBox(height: 16),
              Text(
                'Adicionar Resultado',
                style: AppTheme.titleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Selecione o Aluno',
                style: AppTheme.labelMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<CompetitionEnrollment>(
                value: selectedEnrollment,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'Selecione...',
                ),
                items: enrollments
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.studentName),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setSheetState(() => selectedEnrollment = value),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selectedEnrollment == null
                      ? null
                      : () {
                          Navigator.of(ctx).pop();
                          onStudentSelected(selectedEnrollment!);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.textPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Opens the "Register / Edit result" bottom sheet.
///
/// [onSave] is called with the assembled data; all service calls stay in the
/// main screen so the caller can update _results / _enrollments state.
void showResultDialog(
  BuildContext context, {
  required String studentId,
  required String studentName,
  CompetitionResult? existingResult,
  CompetitionEnrollment? enrollment,
  required Future<void> Function({
    required String studentId,
    required String studentName,
    required String position,
    required String ageCategory,
    required String weightCategory,
    String? modality,
    String? divisionType,
    String? notes,
    CompetitionResult? existingResult,
  }) onSave,
}) {
  String position = existingResult?.position ?? 'participant';
  String ageCategory =
      existingResult?.ageCategory ?? enrollment?.ageCategory ?? 'adult';
  String weightCategory =
      existingResult?.weightCategory ?? enrollment?.weightCategory ?? '';
  String modality = existingResult?.modality ?? 'gi';
  String divisionType = existingResult?.divisionType ?? 'weight';
  String notes = existingResult?.notes ?? '';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 16),
                Text(
                  existingResult != null
                      ? 'Editar Resultado'
                      : 'Registrar Resultado',
                  style: AppTheme.titleLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),

                // Position selector
                Text(
                  'Resultado',
                  style: AppTheme.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: positionConfig.entries.map((entry) {
                    final isSelected = position == entry.key;
                    return ChoiceChip(
                      label: Text(
                        '${entry.value['icon']} ${entry.value['label']}',
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        setSheetState(() => position = entry.key);
                      },
                      selectedColor: Color(
                        entry.value['color'] as int,
                      ).withValues(alpha: 0.2),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Modality
                Text(
                  'Modalidade',
                  style: AppTheme.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Gi'),
                        selected: modality == 'gi',
                        onSelected: (_) {
                          setSheetState(() => modality = 'gi');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('No-Gi'),
                        selected: modality == 'nogi',
                        onSelected: (_) {
                          setSheetState(() => modality = 'nogi');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Division Type
                Text(
                  'Divisao',
                  style: AppTheme.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Peso'),
                        selected: divisionType == 'weight',
                        onSelected: (_) {
                          setSheetState(() => divisionType = 'weight');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Absoluto'),
                        selected: divisionType == 'absolute',
                        onSelected: (_) {
                          setSheetState(() => divisionType = 'absolute');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Weight category
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Categoria de Peso',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  controller: TextEditingController(text: weightCategory),
                  onChanged: (v) => weightCategory = v,
                ),
                const SizedBox(height: 12),

                // Notes
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Observacoes (opcional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  controller: TextEditingController(text: notes),
                  onChanged: (v) => notes = v,
                  maxLines: 2,
                ),
                const SizedBox(height: 20),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: weightCategory.isEmpty
                        ? null
                        : () => onSave(
                            studentId: studentId,
                            studentName: studentName,
                            position: position,
                            ageCategory: ageCategory,
                            weightCategory: weightCategory,
                            modality: modality,
                            divisionType: divisionType,
                            notes: notes.isNotEmpty ? notes : null,
                            existingResult: existingResult,
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      existingResult != null
                          ? 'Atualizar Resultado'
                          : 'Salvar Resultado',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Confirmation dialogs
// ---------------------------------------------------------------------------

/// Asks the user to confirm deleting a result.
/// Returns true if confirmed.
Future<bool?> showDeleteResultDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir Resultado'),
      content: const Text('Deseja excluir seu resultado desta competição?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared private helper
// ---------------------------------------------------------------------------

Widget _sheetHandle() => Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
