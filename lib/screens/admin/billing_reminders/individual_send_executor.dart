import '../../../services/billing_reminder_service.dart';
import '../../../services/firebase_service.dart';

class IndividualSendResult {
  const IndividualSendResult({required this.success, this.error});

  final bool success;
  final String? error;
}

/// Executes a single WhatsApp or email send for one financial item.
/// Logs the contact attempt on success.
/// Returns a result — never throws.
Future<IndividualSendResult> executeIndividualSend({
  required String mode,
  required Map<String, dynamic> financialItem,
  required BillingStage stage,
  required StudentContact contact,
  required String message,
  String? subject,
  required BillingNotificationService notificationService,
  required BillingReminderService billingService,
}) async {
  final studentName = financialItem['studentName'] as String? ?? '';
  final amount = (financialItem['amount'] as num?)?.toDouble() ?? 0;
  final dueDate = financialItem['dueDate'] as DateTime;
  final daysOverdue = financialItem['daysOverdue'] as int? ?? 0;
  final financialId = financialItem['id'] as String? ?? '';
  final studentId = financialItem['studentId'] as String? ?? '';

  try {
    final NotificationResult result;
    if (mode == 'whatsapp') {
      result = await notificationService.sendWhatsApp(
        phone: contact.effectivePhone!,
        studentName: studentName,
        studentId: studentId,
        financialId: financialId,
        amount: amount,
        dueDate: dueDate,
        daysOverdue: daysOverdue,
        stage: stage,
        message: message,
      );
    } else {
      result = await notificationService.sendEmail(
        email: contact.effectiveEmail!,
        studentName: studentName,
        studentId: studentId,
        financialId: financialId,
        amount: amount,
        dueDate: dueDate,
        daysOverdue: daysOverdue,
        stage: stage,
        subject: subject ?? 'Cobranca - $studentName',
        message: message,
      );
    }

    if (result.success) {
      await billingService.logContactAttempt(
        financialId: financialId,
        studentId: studentId,
        studentName: studentName,
        type: mode == 'whatsapp' ? ContactType.whatsapp : ContactType.email,
        notes:
            'Cobranca enviada via ${mode == 'whatsapp' ? 'WhatsApp' : 'Email'}',
        stage: stage.value,
        daysOverdue: daysOverdue,
        contactedBy: FirebaseService.currentUserId ?? '',
        contactedByName: 'Admin',
      );
      return const IndividualSendResult(success: true);
    } else {
      return IndividualSendResult(
        success: false,
        error: result.error ?? 'Falha no envio',
      );
    }
  } catch (e) {
    return IndividualSendResult(success: false, error: e.toString());
  }
}
