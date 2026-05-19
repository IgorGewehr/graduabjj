import '../../../services/billing_reminder_service.dart';
import '../../../services/payment_service.dart';

/// Pure function: groups [payments] into [BillingStage] buckets.
/// studentName is denormalized from [contacts] when the Payment object
/// does not carry it (Tatami DTO).
Map<BillingStage, List<Map<String, dynamic>>> buildStagesFromPayments(
  List<Payment> payments,
  Map<String, StudentContact> contacts,
) {
  final out = <BillingStage, List<Map<String, dynamic>>>{
    BillingStage.d0: [],
    BillingStage.d1: [],
    BillingStage.d3: [],
    BillingStage.d7: [],
    BillingStage.d15: [],
    BillingStage.d30: [],
  };
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);

  for (final p in payments) {
    if (p.status != PaymentStatus.overdue &&
        p.status != PaymentStatus.pending) {
      continue;
    }
    final dueStart = DateTime(p.dueDate.year, p.dueDate.month, p.dueDate.day);
    final daysOverdue = todayStart.difference(dueStart).inDays;
    if (daysOverdue < 1) continue;

    BillingStage? stage;
    if (daysOverdue >= 30) {
      stage = BillingStage.d30;
    } else if (daysOverdue >= 15) {
      stage = BillingStage.d15;
    } else if (daysOverdue >= 7) {
      stage = BillingStage.d7;
    } else if (daysOverdue >= 3) {
      stage = BillingStage.d3;
    } else if (daysOverdue >= 1) {
      stage = BillingStage.d1;
    }
    if (stage == null) continue;

    final contact = contacts[p.studentId];
    out[stage]!.add({
      'id': p.id,
      'studentId': p.studentId,
      'studentName': p.studentName.isNotEmpty
          ? p.studentName
          : (contact?.studentName ?? ''),
      'amount': p.value,
      'dueDate': p.dueDate,
      'status': p.status == PaymentStatus.overdue ? 'overdue' : 'pending',
      'referenceMonth': p.referenceMonth,
      'planId': p.planId,
      'description': p.description,
      'daysOverdue': daysOverdue,
      'stage': stage.value,
    });
  }

  for (final st in BillingStage.values) {
    out[st]!.sort((a, b) {
      final aD = a['daysOverdue'] as int;
      final bD = b['daysOverdue'] as int;
      return bD.compareTo(aD);
    });
  }
  return out;
}
