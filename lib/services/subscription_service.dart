import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_service.dart';

/// A recurring card subscription (Mercado Pago Preapproval) for a monthly,
/// card-only plan. Mirrors the `academies/{id}/subscriptions/{id}` doc written
/// by the backend (createMpSubscription + webhook).
class Subscription {
  final String id;
  final String studentId;
  final String studentName;
  final String? planId;

  /// pending | authorized | paused | cancelled | completed | error
  final String status;
  final double recurringValue;
  final int billingDay;

  /// Fixed term in months (0 = open-ended / no end).
  final int months;
  final int chargesPaid;
  final DateTime? nextBillingDate;

  /// Card declined/expired → show a "update card" banner.
  final bool needsReauth;
  final String? mpPreapprovalId;

  const Subscription({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.planId,
    required this.status,
    required this.recurringValue,
    required this.billingDay,
    required this.months,
    required this.chargesPaid,
    required this.nextBillingDate,
    required this.needsReauth,
    required this.mpPreapprovalId,
  });

  factory Subscription.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Subscription(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      planId: data['planId'],
      status: data['status'] ?? 'pending',
      recurringValue: (data['recurringValue'] ?? 0).toDouble(),
      billingDay: (data['billingDay'] as num?)?.toInt() ?? 0,
      months: (data['months'] as num?)?.toInt() ?? 0,
      chargesPaid: (data['chargesPaid'] as num?)?.toInt() ?? 0,
      nextBillingDate: (data['nextBillingDate'] as Timestamp?)?.toDate(),
      needsReauth: data['needsReauth'] == true,
      mpPreapprovalId: data['mpPreapprovalId'],
    );
  }

  /// Whether MP is actively charging (or about to).
  bool get isActive => status == 'authorized' || status == 'pending';

  /// Remaining charges for a fixed-term subscription (null = open-ended).
  int? get remainingCharges =>
      months > 0 ? (months - chargesPaid).clamp(0, months) : null;
}

class SubscriptionService {
  final String academyId;
  final FirebaseFirestore _db = FirebaseService.firestore;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  SubscriptionService(this.academyId);

  CollectionReference<Map<String, dynamic>> get _ref =>
      _db.collection('academies').doc(academyId).collection('subscriptions');

  /// Live subscriptions for a student, most relevant first (active before
  /// cancelled/completed). Excludes failed-to-create (`error`) docs.
  Stream<List<Subscription>> streamByStudent(String studentId) {
    return _ref.where('studentId', isEqualTo: studentId).snapshots().map((snap) {
      final list = snap.docs
          .map(Subscription.fromFirestore)
          .where((s) => s.status != 'error')
          .toList();
      int rank(Subscription s) {
        switch (s.status) {
          case 'authorized':
          case 'pending':
            return 0;
          case 'paused':
            return 1;
          default:
            return 2;
        }
      }

      list.sort((a, b) => rank(a).compareTo(rank(b)));
      return list;
    });
  }

  Future<void> cancel(String subscriptionId) async {
    await _functions.httpsCallable('cancelMpSubscription').call({
      'academyId': academyId,
      'subscriptionId': subscriptionId,
    });
  }

  Future<void> pause(String subscriptionId) async {
    await _functions.httpsCallable('pauseMpSubscription').call({
      'academyId': academyId,
      'subscriptionId': subscriptionId,
    });
  }
}
