import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../services/billing_reminder_service.dart';
import '../../../widgets/cached_image.dart';
import 'billing_tab_bar.dart';

class BillingStageList extends StatelessWidget {
  const BillingStageList({
    super.key,
    required this.stage,
    required this.items,
    required this.studentContacts,
    required this.notificationSettings,
    required this.currencyFormat,
    required this.dateFormat,
    required this.onSendWhatsApp,
    required this.onSendEmail,
    required this.onContactLog,
  });

  final BillingStage stage;
  final List<Map<String, dynamic>> items;
  final Map<String, StudentContact> studentContacts;
  final BillingNotificationSettings? notificationSettings;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;
  final void Function({
    required Map<String, dynamic> financialItem,
    required StudentContact contact,
  }) onSendWhatsApp;
  final void Function({
    required Map<String, dynamic> financialItem,
    required StudentContact contact,
  }) onSendEmail;
  final void Function({
    required String financialId,
    required String studentId,
    required String studentName,
    required int daysOverdue,
  }) onContactLog;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.checkCircle,
              size: 48,
              color: AppTheme.success.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum pagamento neste estagio',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _BillingPaymentItem(
          item: item,
          stage: stage,
          studentContacts: studentContacts,
          notificationSettings: notificationSettings,
          currencyFormat: currencyFormat,
          dateFormat: dateFormat,
          onSendWhatsApp: onSendWhatsApp,
          onSendEmail: onSendEmail,
          onContactLog: onContactLog,
        );
      },
    );
  }
}

class _BillingPaymentItem extends StatelessWidget {
  const _BillingPaymentItem({
    required this.item,
    required this.stage,
    required this.studentContacts,
    required this.notificationSettings,
    required this.currencyFormat,
    required this.dateFormat,
    required this.onSendWhatsApp,
    required this.onSendEmail,
    required this.onContactLog,
  });

  final Map<String, dynamic> item;
  final BillingStage stage;
  final Map<String, StudentContact> studentContacts;
  final BillingNotificationSettings? notificationSettings;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;
  final void Function({
    required Map<String, dynamic> financialItem,
    required StudentContact contact,
  }) onSendWhatsApp;
  final void Function({
    required Map<String, dynamic> financialItem,
    required StudentContact contact,
  }) onSendEmail;
  final void Function({
    required String financialId,
    required String studentId,
    required String studentName,
    required int daysOverdue,
  }) onContactLog;

  @override
  Widget build(BuildContext context) {
    final studentName = item['studentName'] as String? ?? '';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final dueDate = item['dueDate'] as DateTime;
    final daysOverdue = item['daysOverdue'] as int? ?? 0;
    final financialId = item['id'] as String? ?? '';
    final studentId = item['studentId'] as String? ?? '';
    final contact = studentContacts[studentId];
    final phone = contact?.effectivePhone;
    final email = contact?.effectiveEmail;
    final hasWhatsApp = notificationSettings?.hasWhatsAppApi ?? false;
    final hasEmail = notificationSettings?.hasEmailApi ?? false;
    final photoUrl = contact?.photoUrl;
    final stageColor = billingStageColor(stage);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                AppCachedAvatar(
                  imageUrl: photoUrl,
                  radius: 18,
                  backgroundColor: stageColor.withValues(alpha: 0.1),
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? Text(
                          studentName.isNotEmpty
                              ? studentName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: stageColor,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(studentName, style: AppTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${currencyFormat.format(amount)} - Venc: ${dateFormat.format(dueDate)}',
                        style: AppTheme.bodySmall,
                      ),
                      Text(
                        '$daysOverdue dias em atraso',
                        style: AppTheme.bodySmall.copyWith(
                          color: stageColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Contact info chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (phone != null && phone.isNotEmpty)
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      LucideIcons.phone,
                      size: 12,
                      color: AppTheme.success,
                    ),
                    label: Text(phone, style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                  ),
                if (email != null && email.isNotEmpty)
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      LucideIcons.mail,
                      size: 12,
                      color: AppTheme.info,
                    ),
                    label: Text(email, style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                  ),
                if ((phone == null || phone.isEmpty) &&
                    (email == null || email.isEmpty))
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      LucideIcons.alertTriangle,
                      size: 12,
                      color: Colors.orange,
                    ),
                    label: Text(
                      contact?.category == 'kids'
                          ? 'Sem contato do responsavel'
                          : 'Sem contato',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Send WhatsApp
                if (hasWhatsApp && phone != null && phone.isNotEmpty)
                  IconButton(
                    onPressed: () => onSendWhatsApp(
                      financialItem: item,
                      contact: contact!,
                    ),
                    icon: const Icon(LucideIcons.messageCircle, size: 20),
                    color: AppTheme.success,
                    tooltip: 'Enviar WhatsApp',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                // Send Email
                if (hasEmail && email != null && email.isNotEmpty)
                  IconButton(
                    onPressed: () => onSendEmail(
                      financialItem: item,
                      contact: contact!,
                    ),
                    icon: const Icon(LucideIcons.mail, size: 20),
                    color: AppTheme.info,
                    tooltip: 'Enviar Email',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                // Phone
                if (phone != null && phone.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      FeedbackUtils.showInfo(
                        context,
                        'Ligar para $studentName: $phone',
                      );
                    },
                    icon: const Icon(LucideIcons.phone, size: 20),
                    color: AppTheme.textSecondary,
                    tooltip: 'Telefone',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                // Manual contact log
                IconButton(
                  onPressed: () => onContactLog(
                    financialId: financialId,
                    studentId: studentId,
                    studentName: studentName,
                    daysOverdue: daysOverdue,
                  ),
                  icon: const Icon(LucideIcons.clipboardList, size: 20),
                  color: AppTheme.textSecondary,
                  tooltip: 'Registrar Contato',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
