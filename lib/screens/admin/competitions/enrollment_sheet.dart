import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';
import 'competition_form_sheet.dart';

/// Exibe o bottom sheet de gerenciamento de inscrições de um campeonato.
/// [onChanged] é chamado após qualquer alteração para recarregar dados.
Future<void> showEnrollmentsSheet({
  required BuildContext context,
  required String academyId,
  required Competition competition,
  required VoidCallback onChanged,
}) async {
  final enrollmentService = CompetitionEnrollmentService(academyId);
  final enrollments = await enrollmentService.getByCompetition(competition.id);

  if (!context.mounted) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          LucideIcons.users,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inscricoes',
                              style: AppTheme.titleLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              competition.name,
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          showAddEnrollmentSheet(
                            context: context,
                            academyId: academyId,
                            competition: competition,
                            onEnrolled: onChanged,
                          );
                        },
                        icon: Icon(
                          LucideIcons.userPlus,
                          color: AppTheme.primary,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.primary.withValues(
                            alpha: 0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: enrollments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.userX,
                            size: 48,
                            color: AppTheme.textDisabled,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhuma inscricao',
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: enrollments.length,
                      itemBuilder: (context, index) {
                        final enrollment = enrollments[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    enrollment.studentName
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
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
                                      enrollment.studentName,
                                      style: AppTheme.bodyMedium.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${enrollment.ageCategory ?? 'Sem categoria'} - ${enrollment.weightCategory ?? 'Sem peso'}',
                                      style: AppTheme.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  enrollment.transportPreference.label,
                                  style: AppTheme.labelSmall.copyWith(
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Exibe o bottom sheet para adicionar uma inscrição manual.
Future<void> showAddEnrollmentSheet({
  required BuildContext context,
  required String academyId,
  required Competition competition,
  required VoidCallback onEnrolled,
}) async {
  final studentService = StudentService(academyId);
  final students = await studentService.getActive();

  if (!context.mounted) return;

  Student? selectedStudent;
  final categoryController = TextEditingController();
  final weightController = TextEditingController();

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
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        LucideIcons.userPlus,
                        color: AppTheme.success,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Nova Inscricao',
                      style: AppTheme.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Aluno',
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
                  child: DropdownButtonFormField<Student>(
                    value: selectedStudent,
                    items: students.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(s.fullName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setSheetState(() => selectedStudent = value);
                    },
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    dropdownColor: AppTheme.surface,
                    hint: const Text('Selecione o aluno'),
                  ),
                ),
                const SizedBox(height: 16),
                CompetitionModernTextField(
                  controller: categoryController,
                  label: 'Categoria de Idade',
                  hint: 'Ex: Adulto',
                  icon: LucideIcons.users,
                ),
                const SizedBox(height: 16),
                CompetitionModernTextField(
                  controller: weightController,
                  label: 'Categoria de Peso',
                  hint: 'Ex: Leve',
                  icon: LucideIcons.scale,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (selectedStudent == null) {
                        sheetContext.showWarning('Selecione um aluno');
                        return;
                      }

                      try {
                        final service = CompetitionEnrollmentService(academyId);
                        await service.enroll(
                          competitionId: competition.id,
                          competitionName: competition.name,
                          studentId: selectedStudent!.id,
                          studentName: selectedStudent!.fullName,
                          ageCategory: categoryController.text.isEmpty
                              ? null
                              : categoryController.text,
                          weightCategory: weightController.text.isEmpty
                              ? null
                              : weightController.text,
                        );

                        if (!sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        sheetContext.showSuccess('Inscricao realizada!');
                        onEnrolled();
                      } catch (e) {
                        if (!sheetContext.mounted) return;
                        sheetContext.showError('Erro: $e');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.userPlus, size: 20),
                        const SizedBox(width: 8),
                        const Text('Inscrever'),
                      ],
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
