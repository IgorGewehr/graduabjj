import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/financial_dto.dart';
import '../../../api/financial_repo.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../services/billing_reminder_service.dart';

/// Maps the legacy [ContactType] enum to the Tatami [ApiBillingContactMethod].
ApiBillingContactMethod _mapContactType(ContactType type) {
  switch (type) {
    case ContactType.whatsapp:
      return ApiBillingContactMethod.whatsapp;
    case ContactType.phone:
      return ApiBillingContactMethod.phone;
    case ContactType.email:
      return ApiBillingContactMethod.email;
    case ContactType.inPerson:
      return ApiBillingContactMethod.in_person;
    case ContactType.other:
      return ApiBillingContactMethod.whatsapp; // fallback
  }
}

/// Shows the manual contact log dialog.
///
/// Uses Tatami `POST /v1/academies/{id}/billing-contacts` (or the
/// per-financial variant when [financialId] is a valid Tatami UUID).
void showBillingContactDialog({
  required BuildContext context,
  required String financialId,
  required String studentId,
  required String studentName,
  required BillingStage stage,
  required int daysOverdue,
  required String academyId,
  required FinancialRemoteRepo financialRepo,
  // Keep billingService in signature for backward compat but unused now.
  BillingReminderService? billingService,
}) {
  ContactType selectedType = ContactType.whatsapp;
  final notesController = TextEditingController();

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.clipboardList,
                    color: AppTheme.info,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Registrar Contato',
                    style: AppTheme.titleLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aluno: $studentName',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Tipo de Contato', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ContactType>(
                    value: selectedType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: ContactType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Observacoes', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Detalhes do contato...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final req = LogBillingContactRequest(
                      studentId: studentId,
                      method: _mapContactType(selectedType),
                      result: ApiBillingContactResult.other,
                      contactDate: DateTime.now(),
                      notes: notesController.text.isNotEmpty
                          ? notesController.text
                          : null,
                    );

                    await financialRepo.logBillingContact(academyId, req);

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                    if (context.mounted) {
                      FeedbackUtils.showSuccess(
                        context,
                        'Contato registrado com sucesso!',
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      FeedbackUtils.showError(
                        context,
                        'Erro ao registrar contato: $e',
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      );
    },
  );
}
