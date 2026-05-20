import '../../../api/tatami_client.dart';
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

/// Executes the bulk send loop for [stage] via Tatami
/// `POST /v1/academies/{academyId}/billing/messages/bulk`.
///
/// Builds a list of recipients and sends them all in one request. The
/// backend fans out to WhatsApp/Email via its own notification gateways.
Future<BulkSendExecutionResult> executeBulkSend({
  required BillingStage stage,
  required String messageTemplate,
  required String subjectTemplate,
  required List<Map<String, dynamic>> items,
  required Map<String, StudentContact> studentContacts,
  required BillingNotificationSettings notificationSettings,
  required BillingNotificationService notificationService,
  required BillingReminderService billingService,
  required TatamiClient tatamiClient,
  required String academyId,
}) async {
  int waSent = 0, waFailed = 0, waTotal = 0;
  int emSent = 0, emFailed = 0, emTotal = 0;
  final failures = <BulkFailure>[];

  try {
    // Build all recipients for the bulk request.
    final recipients = <Map<String, dynamic>>[];

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
      if (notificationSettings.whatsappEnabled &&
          phone != null &&
          phone.isNotEmpty) {
        waTotal++;
        recipients.add({
          'financial_id': financialId,
          'channel': 'whatsapp',
          'phone': phone,
          'message': personalizedMessage,
        });
      }

      final email = contact.effectiveEmail;
      if (notificationSettings.emailEnabled &&
          email != null &&
          email.isNotEmpty) {
        emTotal++;
        recipients.add({
          'financial_id': financialId,
          'channel': 'email',
          'email': email,
          'subject': personalizedSubject,
          'message': personalizedMessage,
        });
      }
    }

    if (recipients.isEmpty) {
      return BulkSendExecutionResult(
        serverResult: BulkServerResult(
          success: true,
          scheduled: false,
          whatsapp: BulkChannelSummary(total: 0, sent: 0, failed: 0),
          email: BulkChannelSummary(total: 0, sent: 0, failed: 0),
          failures: [],
        ),
      );
    }

    // Single bulk request to Tatami.
    final resp = await tatamiClient.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/billing/messages/bulk',
      data: {'recipients': recipients},
    );

    final results =
        (resp['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Tally results per channel.
    for (final r in results) {
      final channel = r['channel'] as String? ?? '';
      final ok = r['ok'] as bool? ?? false;
      if (channel == 'whatsapp') {
        if (ok) {
          waSent++;
        } else {
          waFailed++;
          failures.add(BulkFailure(
            type: 'whatsapp',
            recipient: r['phone'] as String? ?? '',
            error: r['error'] as String? ?? 'Falha',
          ));
        }
      } else if (channel == 'email') {
        if (ok) {
          emSent++;
        } else {
          emFailed++;
          failures.add(BulkFailure(
            type: 'email',
            recipient: r['email'] as String? ?? '',
            error: r['error'] as String? ?? 'Falha',
          ));
        }
      }
    }

    // Log contact attempts for successfully sent items.
    for (final item in items) {
      final studentId = item['studentId'] as String? ?? '';
      final contact = studentContacts[studentId];
      if (contact == null) continue;

      final sentWa = notificationSettings.whatsappEnabled &&
          (contact.effectivePhone?.isNotEmpty ?? false);
      final sentEm = notificationSettings.emailEnabled &&
          (contact.effectiveEmail?.isNotEmpty ?? false);

      if (sentWa || sentEm) {
        await billingService.logContactAttempt(
          financialId: item['id'] as String? ?? '',
          studentId: studentId,
          studentName: item['studentName'] as String? ?? '',
          type: sentWa ? ContactType.whatsapp : ContactType.email,
          notes: 'Cobranca em massa (via Tatami)',
          stage: stage.value,
          daysOverdue: item['daysOverdue'] as int? ?? 0,
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
