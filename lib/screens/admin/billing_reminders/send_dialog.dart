import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/billing_reminder_service.dart';

/// Shows the individual send dialog (WhatsApp or Email) for a single payment.
/// Calls [onConfirm] with the (possibly edited) message and subject when confirmed.
void showBillingSendDialog({
  required BuildContext context,
  required String mode,
  required String studentName,
  required StudentContact contact,
  required String message,
  required String subject,
  required Future<void> Function({
    required String message,
    String? subject,
  }) onConfirm,
}) {
  final messageController = TextEditingController(text: message);
  final subjectController = TextEditingController(text: subject);

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              mode == 'whatsapp' ? LucideIcons.messageCircle : LucideIcons.mail,
              color: mode == 'whatsapp' ? AppTheme.success : AppTheme.info,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              mode == 'whatsapp' ? 'Enviar WhatsApp' : 'Enviar Email',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Para: $studentName',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              if (mode == 'whatsapp')
                Text(
                  'Tel: ${contact.effectivePhone}',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              if (mode == 'email')
                Text(
                  'Email: ${contact.effectiveEmail}',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              const SizedBox(height: 16),
              if (mode == 'email') ...[
                Text('Assunto', style: AppTheme.labelMedium),
                const SizedBox(height: 8),
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
              Text('Mensagem', style: AppTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: messageController,
                maxLines: 8,
                decoration: InputDecoration(
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
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await onConfirm(
                message: messageController.text,
                subject: mode == 'email' ? subjectController.text : null,
              );
            },
            icon: const Icon(LucideIcons.send, size: 16),
            label: Text(
              mode == 'whatsapp' ? 'Enviar WhatsApp' : 'Enviar Email',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  mode == 'whatsapp' ? AppTheme.success : AppTheme.primary,
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
}
