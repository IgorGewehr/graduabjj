import '../../../api/tatami_client.dart';
import '../../../services/billing_reminder_service.dart';
import '../../../services/firebase_service.dart';

class IndividualSendResult {
  const IndividualSendResult({required this.success, this.error});

  final bool success;
  final String? error;
}

/// Executes a single WhatsApp or email send for one financial item
/// via Tatami `POST /v1/academies/{academyId}/billing/messages/bulk`.
///
/// Even for a single message, we use the bulk endpoint (with one recipient)
/// because it's the only server-side dispatch route. The backend fans out
/// to the notification server (WhatsApp / Email) using its own API keys.
Future<IndividualSendResult> executeIndividualSend({
  required String mode,
  required Map<String, dynamic> financialItem,
  required BillingStage stage,
  required StudentContact contact,
  required String message,
  String? subject,
  required BillingNotificationService notificationService,
  required BillingReminderService billingService,
  required TatamiClient tatamiClient,
  required String academyId,
}) async {
  final studentName = financialItem['studentName'] as String? ?? '';
  final daysOverdue = financialItem['daysOverdue'] as int? ?? 0;
  final financialId = financialItem['id'] as String? ?? '';
  final studentId = financialItem['studentId'] as String? ?? '';

  try {
    final recipient = <String, dynamic>{
      'financial_id': financialId,
      'channel': mode,
      'message': message,
    };
    if (mode == 'whatsapp') {
      recipient['phone'] = contact.effectivePhone ?? '';
    } else {
      recipient['email'] = contact.effectiveEmail ?? '';
      recipient['subject'] = subject ?? 'Cobranca - $studentName';
    }

    final resp = await tatamiClient.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/billing/messages/bulk',
      data: {'recipients': [recipient]},
    );

    final results = (resp['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final ok = results.isNotEmpty && results.first['ok'] == true;

    if (ok) {
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
      final error = results.isNotEmpty
          ? (results.first['error'] as String? ?? 'Falha no envio')
          : 'Falha no envio';
      return IndividualSendResult(success: false, error: error);
    }
  } catch (e) {
    return IndividualSendResult(success: false, error: e.toString());
  }
}
