import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/student_dto.dart' as api_student;
import '../../../api/repositories.dart' as tatami_repos;
import '../../../core/feedback_utils.dart';
import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../services/services.dart';

/// Exibe o bottom sheet de promoção individual de um aluno.
/// [ref] é necessário para acessar o repositório Tatami.
/// [onPromoted] é chamado após promoção bem-sucedida para recarregar dados.
void showPromotionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> studentData,
  required VoidCallback onPromoted,
}) {
  final eligibility = studentData['eligibility'] as EligibilityResult;
  final currentBelt = studentData['currentBelt'] as String;
  final currentStripes = studentData['currentStripes'] as int;
  final studentId = studentData['id'] as String;
  final studentName = studentData['fullName'] as String;

  bool isStripePromotion =
      eligibility.nextStripes != null && eligibility.nextStripes! > 0;
  String? selectedBelt = eligibility.nextBelt;
  int selectedStripes = eligibility.nextStripes ?? 0;
  final notesController = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        return Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
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
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(LucideIcons.award, color: AppTheme.warning, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Confirmar Graduacao',
                      style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Student info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: _getBeltColor(currentBelt),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            studentName.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              color: currentBelt == 'white'
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentName,
                              style: AppTheme.titleSmall
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Atual: ${_getBeltLabel(currentBelt)} ${currentStripes > 0 ? "• $currentStripes grau(s)" : ""}',
                              style: AppTheme.bodySmall
                                  .copyWith(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Promotion type
                Text(
                  'Tipo de graduacao',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: currentStripes < 4
                            ? () {
                                setSheetState(() {
                                  isStripePromotion = true;
                                  selectedBelt = currentBelt;
                                  selectedStripes = currentStripes + 1;
                                });
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isStripePromotion
                                ? AppTheme.primary.withValues(alpha: 0.1)
                                : AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isStripePromotion
                                  ? AppTheme.primary
                                  : AppTheme.divider,
                              width: isStripePromotion ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                LucideIcons.star,
                                color: isStripePromotion
                                    ? AppTheme.primary
                                    : AppTheme.textSecondary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Grau',
                                style: AppTheme.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isStripePromotion
                                      ? AppTheme.primary
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            isStripePromotion = false;
                            selectedBelt = _getNextBelt(currentBelt);
                            selectedStripes = 0;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: !isStripePromotion
                                ? AppTheme.warning.withValues(alpha: 0.1)
                                : AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: !isStripePromotion
                                  ? AppTheme.warning
                                  : AppTheme.divider,
                              width: !isStripePromotion ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                LucideIcons.award,
                                color: !isStripePromotion
                                    ? AppTheme.warning
                                    : AppTheme.textSecondary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Faixa',
                                style: AppTheme.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: !isStripePromotion
                                      ? AppTheme.warning
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // New belt/stripe display
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.arrowRight,
                          color: AppTheme.success, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isStripePromotion
                              ? '$selectedStripes° grau na faixa ${_getBeltLabel(selectedBelt!)}'
                              : 'Faixa ${_getBeltLabel(selectedBelt!)}',
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Notes
                Text(
                  'Observacoes (opcional)',
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
                    controller: notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Adicione uma observacao...',
                      hintStyle: AppTheme.bodyMedium
                          .copyWith(color: AppTheme.textDisabled),
                      prefixIcon: Icon(LucideIcons.fileText,
                          color: AppTheme.textSecondary, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: AppTheme.divider),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await promoteStudent(
                            context: context,
                            ref: ref,
                            studentId: studentId,
                            studentName: studentName,
                            newBelt: selectedBelt!,
                            newStripes: selectedStripes,
                            notes: notesController.text.isEmpty
                                ? null
                                : notesController.text,
                            onPromoted: onPromoted,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.award, size: 18),
                            const SizedBox(width: 8),
                            const Text('Graduar'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Executa a promoção via repositório Tatami.
Future<void> promoteStudent({
  required BuildContext context,
  required WidgetRef ref,
  required String studentId,
  required String studentName,
  required String newBelt,
  required int newStripes,
  String? notes,
  required VoidCallback onPromoted,
}) async {
  try {
    final academyId = FirebaseService.academyId;
    final repo = ref.read(tatami_repos.studentRepoProvider);
    await repo.createBeltProgression(
      academyId,
      studentId,
      api_student.CreateBeltProgressionRequest(
        newBelt: api_student.ApiBeltX.fromWire(newBelt),
        newStripes: newStripes,
        promotionDate: DateTime.now(),
        notes: notes,
      ),
    );
    if (context.mounted) {
      context.showSuccess('$studentName foi graduado com sucesso!');
      onPromoted();
    }
  } catch (e) {
    if (context.mounted) {
      context.showError('Erro: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Belt helpers (reusados dentro deste arquivo)
// ---------------------------------------------------------------------------

String _getNextBelt(String currentBelt, {SportId sportId = SportId.bjj}) {
  final grades = getGradesForSport(sportId);
  final gradeIds = grades.map((g) => g.id).toList();
  final index = gradeIds.indexOf(currentBelt);
  if (index >= 0 && index < gradeIds.length - 1) {
    return gradeIds[index + 1];
  }
  return currentBelt;
}

String _getBeltLabel(String belt, {SportId sportId = SportId.bjj}) {
  return getGradeLabel(sportId, belt);
}

Color _getBeltColor(String belt, {SportId sportId = SportId.bjj}) {
  return getGradeColor(sportId, belt);
}
