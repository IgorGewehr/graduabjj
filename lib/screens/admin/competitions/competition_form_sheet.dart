import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/competition_dto.dart';
import '../../../api/repositories.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../services/services.dart';

/// Shared text field widget used inside competition form sheets
class CompetitionModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;

  const CompetitionModernTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
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

/// Exibe o bottom sheet para criar um novo campeonato.
/// [academyId] é o id da academia corrente.
/// [onCreated] é chamado após criação bem-sucedida para recarregar a lista.
void showCreateCompetitionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String academyId,
  required VoidCallback onCreated,
}) {
  final nameController = TextEditingController();
  final locationController = TextEditingController();
  final descriptionController = TextEditingController();
  DateTime? selectedDate;
  bool isSaving = false;

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
                      child: Icon(
                        LucideIcons.trophy,
                        color: AppTheme.warning,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Novo Campeonato',
                      style: AppTheme.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                CompetitionModernTextField(
                  controller: nameController,
                  label: 'Nome do Campeonato',
                  hint: 'Ex: CBJJ Nacional',
                  icon: LucideIcons.trophy,
                ),
                const SizedBox(height: 16),
                Text(
                  'Data',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setSheetState(() => selectedDate = date);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.calendar,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          selectedDate != null
                              ? DateFormat('dd/MM/yyyy').format(selectedDate!)
                              : 'Selecionar data',
                          style: AppTheme.bodyMedium.copyWith(
                            color: selectedDate != null
                                ? AppTheme.textPrimary
                                : AppTheme.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (selectedDate != null &&
                    selectedDate!.isBefore(DateTime.now()))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.checkCircle,
                            color: AppTheme.warning,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sera criado como concluido. Alunos poderao adicionar seus resultados e fotos.',
                              style: AppTheme.labelSmall.copyWith(
                                color: AppTheme.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                CompetitionModernTextField(
                  controller: locationController,
                  label: 'Local (opcional)',
                  hint: 'Endereco ou cidade',
                  icon: LucideIcons.mapPin,
                ),
                const SizedBox(height: 16),
                CompetitionModernTextField(
                  controller: descriptionController,
                  label: 'Descricao (opcional)',
                  hint: 'Informacoes adicionais',
                  icon: LucideIcons.fileText,
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (nameController.text.isEmpty ||
                                selectedDate == null) {
                              sheetContext.showWarning(
                                'Preencha nome e data',
                              );
                              return;
                            }

                            setSheetState(() => isSaving = true);

                            try {
                              final isPast = selectedDate!.isBefore(
                                DateTime.now(),
                              );
                              final competitionRepo =
                                  ref.read(competitionRepoProvider);
                              await competitionRepo.create(
                                academyId,
                                CreateCompetitionRequest(
                                  name: nameController.text,
                                  date: selectedDate!,
                                  location: locationController.text.isEmpty
                                      ? null
                                      : locationController.text,
                                  description:
                                      descriptionController.text.isEmpty
                                      ? null
                                      : descriptionController.text,
                                ),
                              );

                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                              sheetContext.showSuccess(
                                isPast
                                    ? 'Campeonato concluido criado!'
                                    : 'Campeonato criado!',
                              );
                              onCreated();
                            } catch (e) {
                              setSheetState(() => isSaving = false);
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
                    child: isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                selectedDate != null &&
                                        selectedDate!.isBefore(DateTime.now())
                                    ? LucideIcons.checkCircle
                                    : LucideIcons.plus,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                selectedDate != null &&
                                        selectedDate!.isBefore(DateTime.now())
                                    ? 'Criar como Concluido'
                                    : 'Criar Campeonato',
                              ),
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

/// Exibe o bottom sheet para editar um campeonato existente.
/// [onUpdated] é chamado após atualização bem-sucedida.
void showEditCompetitionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String academyId,
  required Competition competition,
  required VoidCallback onUpdated,
}) {
  bool isSaving = false;
  final nameController = TextEditingController(text: competition.name);
  final locationController = TextEditingController(
    text: competition.location ?? '',
  );
  final descriptionController = TextEditingController(
    text: competition.description ?? '',
  );
  DateTime selectedDate = competition.date;

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
                      child: Icon(
                        LucideIcons.pencil,
                        color: AppTheme.warning,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Editar Campeonato',
                      style: AppTheme.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                CompetitionModernTextField(
                  controller: nameController,
                  label: 'Nome do Campeonato',
                  hint: 'Ex: CBJJ Nacional',
                  icon: LucideIcons.trophy,
                ),
                const SizedBox(height: 16),
                Text(
                  'Data',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setSheetState(() => selectedDate = date);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.calendar,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('dd/MM/yyyy').format(selectedDate),
                          style: AppTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CompetitionModernTextField(
                  controller: locationController,
                  label: 'Local (opcional)',
                  hint: 'Endereco ou cidade',
                  icon: LucideIcons.mapPin,
                ),
                const SizedBox(height: 16),
                CompetitionModernTextField(
                  controller: descriptionController,
                  label: 'Descricao (opcional)',
                  hint: 'Informacoes adicionais',
                  icon: LucideIcons.fileText,
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (nameController.text.isEmpty) {
                              sheetContext.showWarning('Nome e obrigatorio');
                              return;
                            }

                            setSheetState(() => isSaving = true);

                            try {
                              final competitionRepo =
                                  ref.read(competitionRepoProvider);
                              await competitionRepo.update(
                                academyId,
                                competition.id,
                                UpdateCompetitionRequest(
                                  name: nameController.text,
                                  date: selectedDate,
                                  location: locationController.text.isEmpty
                                      ? null
                                      : locationController.text,
                                  description:
                                      descriptionController.text.isEmpty
                                      ? null
                                      : descriptionController.text,
                                ),
                              );

                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                              sheetContext.showSuccess(
                                'Campeonato atualizado!',
                              );
                              onUpdated();
                            } catch (e) {
                              setSheetState(() => isSaving = false);
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
                    child: isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.save, size: 20),
                              const SizedBox(width: 8),
                              const Text('Salvar'),
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
