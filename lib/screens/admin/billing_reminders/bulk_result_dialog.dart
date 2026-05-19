import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/billing_reminder_service.dart';

void showBulkResultDialog({
  required BuildContext context,
  required BulkServerResult result,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              result.scheduled ? LucideIcons.clock : LucideIcons.checkCircle,
              color: result.scheduled ? AppTheme.info : AppTheme.success,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.scheduled ? 'Envio Agendado' : 'Resultado do Envio',
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (result.scheduled) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 18,
                        color: AppTheme.info,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Agendado para ${result.scheduledTime ?? ""}',
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Channel summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Icon(
                          LucideIcons.messageCircle,
                          size: 18,
                          color: AppTheme.success,
                        ),
                        const SizedBox(height: 4),
                        Text('WhatsApp', style: AppTheme.labelSmall),
                        Text(
                          '${result.whatsapp.sent ?? result.whatsapp.total}/${result.whatsapp.total}',
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Icon(
                          LucideIcons.mail,
                          size: 18,
                          color: AppTheme.info,
                        ),
                        const SizedBox(height: 4),
                        Text('Email', style: AppTheme.labelSmall),
                        Text(
                          '${result.email.sent ?? result.email.total}/${result.email.total}',
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Failures
              if (result.failures.isNotEmpty) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Falhas no envio:',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...result.failures.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.xCircle,
                          size: 14,
                          color: AppTheme.error,
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.divider,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            f.type == 'whatsapp' ? 'WA' : 'Email',
                            style: const TextStyle(fontSize: 9),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f.recipient,
                            style: AppTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          f.error,
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Fechar',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      );
    },
  );
}
