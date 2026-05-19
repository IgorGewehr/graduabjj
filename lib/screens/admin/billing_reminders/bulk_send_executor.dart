import '../../../services/billing_reminder_service.dart';
import '../../../services/firebase_service.dart';

/// Result returned by [executeBulkSend] for the caller to display.
class BulkSendExecutionResult {
  const BulkSendExecutionResult({
    required this.serverResult,
    this.error,
  });

  final BulkServerResult? serverResult;
  final String? error;

  bool get hasError => error != null;
}

/// Executes the bulk send loop for [stage].
///
/// Sends WhatsApp and/or Email to each student according to [notificationSettings],
/// personalizing [messageTemplate] and [subjectTemplate] per student.
/// Logs each contact attempt via [billingService].
///
/// Returns a [BulkSendExecutionResult] — never throws.
Future<BulkSendExecutionResult> executeBulkSend({
  required BillingStage stage,
  required String messageTemplate,
  required String subjectTemplate,
  required List<Map<String, dynamic>> items,
  required Map<String, StudentContact> studentContacts,
  required BillingNotificationSettings notificationSettings,
  required BillingNotificationService notificationService,
  required BillingReminderService billingService,
}) async {
  int waSent = 0, waFailed = 0, waTotal = 0;
  int emSent = 0, emFailed = 0, emTotal = 0;
  final failures = <BulkFailure>[];

  try {
    for (final item in items) {
      final studentId = item['studentId'] as String? ?? '';
      final contact = studentContacts[studentId];
      if (contact == null) continue;

      final studentName = item['studentName'] as String? ?? '';
      final amount = (item['amount'] as num?)?.toDouble() ?? 0;
      final dueDate = item['dueDate'] as DateTime;
      final daysOverdue = item['daysOverdue'] as int? ?? 0;
      final financialId = item['id'] as String? ?? '';

      final personalizedMessage = notificationService.applyMessageTemplate(
        messageTemplate,
        studentName,
        amount,
        dueDate,
        daysOverdue,
      );
      final personalizedSubject = notificationService.applyMessageTemplate(
        subjectTemplate,
        studentName,
        amount,
        dueDate,
        daysOverdue,
      );

      final phone = contact.effectivePhone;
      if ((notificationSettings.whatsappEnabled) &&
          phone != null &&
          phone.isNotEmpty) {
        waTotal++;
        final result = await notificationService.sendWhatsApp(
          phone: phone,
          studentName: studentName,
          studentId: studentId,
          financialId: financialId,
          amount: amount,
          dueDate: dueDate,
          daysOverdue: daysOverdue,
          stage: stage,
          message: personalizedMessage,
        );
        if (result.success) {
          waSent++;
        } else {
          waFailed++;
          failures.add(
            BulkFailure(
              type: 'whatsapp',
              recipient: phone,
              error: result.error ?? '',
            ),
          );
        }
      }

      final email = contact.effectiveEmail;
      if ((notificationSettings.emailEnabled) &&
          email != null &&
          email.isNotEmpty) {
        emTotal++;
        final result = await notificationService.sendEmail(
          email: email,
          studentName: studentName,
          studentId: studentId,
          financialId: financialId,
          amount: amount,
          dueDate: dueDate,
          daysOverdue: daysOverdue,
          stage: stage,
          subject: personalizedSubject,
          message: personalizedMessage,
        );
        if (result.success) {
          emSent++;
        } else {
          emFailed++;
          failures.add(
            BulkFailure(
              type: 'email',
              recipient: email,
              error: result.error ?? '',
            ),
          );
        }
      }

      final sentWhatsApp =
          notificationSettings.whatsappEnabled && phone != null && phone.isNotEmpty;
      final sentEmail =
          notificationSettings.emailEnabled && email != null && email.isNotEmpty;
      if (sentWhatsApp || sentEmail) {
        await billingService.logContactAttempt(
          financialId: financialId,
          studentId: studentId,
          studentName: studentName,
          type: sentWhatsApp ? ContactType.whatsapp : ContactType.email,
          notes: 'Cobranca em massa (personalizada)',
          stage: stage.value,
          daysOverdue: daysOverdue,
          contactedBy: FirebaseService.currentUserId ?? '',
          contactedByName: 'Admin',
        );
      }
    }

    return BulkSendExecutionResult(
      serverResult: BulkServerResult(
        success: true,
        scheduled: false,
        whatsapp: BulkChannelSummary(
          total: waTotal,
          sent: waSent,
          failed: waFailed,
        ),
        email: BulkChannelSummary(
          total: emTotal,
          sent: emSent,
          failed: emFailed,
        ),
        failures: failures,
      ),
    );
  } catch (e) {
    return BulkSendExecutionResult(
      serverResult: null,
      error: e.toString(),
    );
  }
}
