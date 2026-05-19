import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/billing_reminder_service.dart';

/// Shows the unified bulk-send dialog.
/// [onConfirm] receives the final message, subject, phones, emails and optional scheduledTime.
void showBillingBulkSendDialog({
  required BuildContext context,
  required BillingStage stage,
  required List<Map<String, dynamic>> items,
  required ({List<String> phones, List<String> emails, int skipped}) recipients,
  required String initialMessage,
  required String initialSubject,
  required void Function({
    required String message,
    required String subject,
    required List<String> phones,
    required List<String> emails,
    String? scheduledTime,
  }) onConfirm,
}) {
  final messageController = TextEditingController(text: initialMessage);
  final subjectController = TextEditingController(text: initialSubject);
  bool scheduleEnabled = false;
  DateTime? scheduledDateTime;

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(LucideIcons.send, color: AppTheme.success, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Cobrar todos (${items.length})',
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
                    // Recipients info card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.info.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                LucideIcons.messageCircle,
                                size: 14,
                                color: AppTheme.success,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${recipients.phones.length} telefone(s)',
                                style: AppTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.mail,
                                size: 14,
                                color: AppTheme.info,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${recipients.emails.length} email(s)',
                                style: AppTheme.bodySmall,
                              ),
                            ],
                          ),
                          if (recipients.skipped > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.alertTriangle,
                                  size: 14,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${recipients.skipped} sem contato',
                                  style: AppTheme.bodySmall.copyWith(
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Email subject
                    if (recipients.emails.isNotEmpty) ...[
                      Text('Assunto do Email', style: AppTheme.labelMedium),
                      const SizedBox(height: 6),
                      TextField(
                        controller: subjectController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Message
                    Text('Mensagem', style: AppTheme.labelMedium),
                    const SizedBox(height: 6),
                    TextField(
                      controller: messageController,
                      maxLines: 6,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        helperText:
                            'Variaveis: {nome}, {valor}, {vencimento}, {dias} — personalizadas por aluno',
                        helperMaxLines: 2,
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Schedule toggle
                    SwitchListTile(
                      title: Row(
                        children: [
                          Icon(
                            LucideIcons.clock,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Agendar envio'),
                        ],
                      ),
                      value: scheduleEnabled,
                      activeColor: AppTheme.primary,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => scheduleEnabled = value);
                      },
                    ),

                    // Date/time picker
                    if (scheduleEnabled) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          LucideIcons.calendar,
                          color: AppTheme.primary,
                        ),
                        title: Text(
                          scheduledDateTime != null
                              ? DateFormat(
                                  'dd/MM/yyyy HH:mm',
                                ).format(scheduledDateTime!)
                              : 'Selecionar data e hora',
                          style: AppTheme.bodyMedium.copyWith(
                            color: scheduledDateTime != null
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                        ),
                        subtitle: const Text('Horario de Brasilia'),
                        trailing: Icon(
                          LucideIcons.chevronRight,
                          size: 18,
                          color: AppTheme.textSecondary,
                        ),
                        onTap: () async {
                          final now = DateTime.now();
                          final date = await showDatePicker(
                            context: context,
                            initialDate: scheduledDateTime ?? now,
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 90)),
                          );
                          if (date == null) return;
                          if (!context.mounted) return;

                          final time = await showTimePicker(
                            context: context,
                            initialTime: scheduledDateTime != null
                                ? TimeOfDay.fromDateTime(scheduledDateTime!)
                                : TimeOfDay.fromDateTime(
                                    now.add(const Duration(hours: 1)),
                                  ),
                          );
                          if (time == null) return;

                          setDialogState(() {
                            scheduledDateTime = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                          });
                        },
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
              ElevatedButton.icon(
                onPressed: (scheduleEnabled && scheduledDateTime == null)
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                        onConfirm(
                          message: messageController.text,
                          subject: subjectController.text,
                          phones: recipients.phones,
                          emails: recipients.emails,
                          scheduledTime:
                              scheduleEnabled && scheduledDateTime != null
                              ? DateFormat(
                                  'yyyy-MM-dd HH:mm',
                                ).format(scheduledDateTime!)
                              : null,
                        );
                      },
                icon: Icon(
                  scheduleEnabled ? LucideIcons.clock : LucideIcons.send,
                  size: 16,
                ),
                label: Text(
                  scheduleEnabled ? 'Agendar Envio' : 'Enviar Agora',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      scheduleEnabled ? AppTheme.primary : AppTheme.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
