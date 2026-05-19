import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../services/billing_reminder_service.dart';

/// Shows the notification settings dialog.
/// [onSaved] is called with the updated [BillingNotificationSettings] on save.
void showBillingSettingsDialog({
  required BuildContext context,
  required BillingNotificationSettings? currentSettings,
  required Future<void> Function(BillingNotificationSettings newSettings)
      onSaved,
}) {
  bool whatsappEnabled = currentSettings?.whatsappEnabled ?? false;
  bool emailEnabled = currentSettings?.emailEnabled ?? false;
  final waTemplates = Map<String, String>.from(
    currentSettings?.messageTemplates?.whatsapp ?? {},
  );
  final emailSubjectTemplates = Map<String, String>.from(
    currentSettings?.messageTemplates?.emailSubject ?? {},
  );
  final emailBodyTemplates = Map<String, String>.from(
    currentSettings?.messageTemplates?.emailBody ?? {},
  );
  bool showTemplates = false;
  int selectedStageIdx = 0;
  final stages = ['D+1', 'D+3', 'D+7', 'D+15', 'D+30'];

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final stageKey = stages[selectedStageIdx];

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.settings,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Configuracoes',
                  style: AppTheme.titleLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Canais de Cobranca', style: AppTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Habilite os canais que deseja utilizar para enviar cobrancas aos alunos.',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Cobranca via WhatsApp'),
                      secondary: Icon(
                        LucideIcons.phone,
                        color: whatsappEnabled
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                      ),
                      value: whatsappEnabled,
                      activeColor: AppTheme.success,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => whatsappEnabled = value);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Cobranca via Email'),
                      secondary: Icon(
                        LucideIcons.mail,
                        color: emailEnabled
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                      value: emailEnabled,
                      activeColor: AppTheme.primary,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => emailEnabled = value);
                      },
                    ),

                    const Divider(height: 24),

                    // Template Editor Toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Templates de Mensagem',
                          style: AppTheme.titleSmall,
                        ),
                        TextButton(
                          onPressed: () {
                            setDialogState(
                              () => showTemplates = !showTemplates,
                            );
                          },
                          child: Text(showTemplates ? 'Ocultar' : 'Editar'),
                        ),
                      ],
                    ),
                    Text(
                      'Variaveis: {nome}, {valor}, {vencimento}, {dias}, {academia}',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),

                    if (showTemplates) ...[
                      const SizedBox(height: 12),

                      // Stage selector chips
                      Wrap(
                        spacing: 6,
                        children: List.generate(stages.length, (i) {
                          return ChoiceChip(
                            label: Text(
                              stages[i],
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: selectedStageIdx == i,
                            onSelected: (_) {
                              setDialogState(() => selectedStageIdx = i);
                            },
                            selectedColor: AppTheme.primary.withValues(
                              alpha: 0.2,
                            ),
                            visualDensity: VisualDensity.compact,
                          );
                        }),
                      ),
                      const SizedBox(height: 12),

                      // WhatsApp template
                      Text(
                        'WhatsApp - $stageKey',
                        style: AppTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        initialValue:
                            waTemplates[stageKey] ??
                            BillingNotificationService
                                .defaultWhatsAppTemplates[stageKey] ??
                            '',
                        maxLines: 3,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.all(10),
                        ),
                        onChanged: (v) {
                          waTemplates[stageKey] = v;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Email subject
                      Text(
                        'Assunto Email - $stageKey',
                        style: AppTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        initialValue:
                            emailSubjectTemplates[stageKey] ??
                            BillingNotificationService
                                .defaultEmailSubjectTemplates[stageKey] ??
                            '',
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (v) {
                          emailSubjectTemplates[stageKey] = v;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Email body
                      Text(
                        'Corpo Email - $stageKey',
                        style: AppTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        initialValue:
                            emailBodyTemplates[stageKey] ??
                            BillingNotificationService
                                .defaultEmailBodyTemplates[stageKey] ??
                            '',
                        maxLines: 4,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.all(10),
                        ),
                        onChanged: (v) {
                          emailBodyTemplates[stageKey] = v;
                        },
                      ),

                      // Reset to default
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            setDialogState(() {
                              waTemplates.remove(stageKey);
                              emailSubjectTemplates.remove(stageKey);
                              emailBodyTemplates.remove(stageKey);
                            });
                          },
                          child: Text(
                            'Restaurar padrao para $stageKey',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.warning,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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
                    final templates = BillingMessageTemplates(
                      whatsapp: waTemplates,
                      emailSubject: emailSubjectTemplates,
                      emailBody: emailBodyTemplates,
                    );

                    final newSettings = BillingNotificationSettings(
                      whatsappEnabled: whatsappEnabled,
                      emailEnabled: emailEnabled,
                      messageTemplates: templates,
                    );

                    await onSaved(newSettings);

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      FeedbackUtils.showError(context, 'Erro ao salvar: $e');
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
