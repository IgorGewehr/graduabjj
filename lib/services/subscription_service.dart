import 'package:cloud_firestore/cloud_firestore.dart';
import 'fns.dart';

import 'firebase_service.dart';
import 'mp_card_tokenizer.dart';

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

  // ---- Resilience / dunning fields (contract lives with this service) ------

  /// `createdAt + months` (when `months>0`); `null` = open-ended. Set in
  /// `createMpSubscription`. Legacy docs may be missing it — callers should
  /// fall back to `createdAt + months` where a term is needed.
  final DateTime? termEndsAt;

  /// Consecutive declined charges. Resets to 0 once back to `authorized`.
  final int failedAttempts;

  /// Timestamp of the last declined charge (null = none yet).
  final DateTime? lastFailureAt;

  /// Next dunning retry (backoff). Null when no retry is pending.
  final DateTime? nextRetryAt;

  /// Non-PCI card mirror (from the MP create/update-card response).
  final String? cardLast4;
  final int? cardExpMonth;
  final int? cardExpYear;

  /// Last time we warned the student about card expiry (de-dupes the warning).
  final DateTime? expiryNotifiedAt;

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
    this.termEndsAt,
    this.failedAttempts = 0,
    this.lastFailureAt,
    this.nextRetryAt,
    this.cardLast4,
    this.cardExpMonth,
    this.cardExpYear,
    this.expiryNotifiedAt,
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
      termEndsAt: (data['termEndsAt'] as Timestamp?)?.toDate(),
      failedAttempts: (data['failedAttempts'] as num?)?.toInt() ?? 0,
      lastFailureAt: (data['lastFailureAt'] as Timestamp?)?.toDate(),
      nextRetryAt: (data['nextRetryAt'] as Timestamp?)?.toDate(),
      cardLast4: data['cardLast4'] as String?,
      cardExpMonth: (data['cardExpMonth'] as num?)?.toInt(),
      cardExpYear: (data['cardExpYear'] as num?)?.toInt(),
      expiryNotifiedAt: (data['expiryNotifiedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Whether MP is actively charging (or about to).
  bool get isActive => status == 'authorized' || status == 'pending';

  /// Concluded after the N-month term (distinct from `cancelled` = ended
  /// manually). Never displayed/treated as cancelled.
  bool get isCompleted => status == 'completed';

  /// Remaining charges for a fixed-term subscription (null = open-ended).
  int? get remainingCharges =>
      months > 0 ? (months - chargesPaid).clamp(0, months) : null;

  /// Masked card label (e.g. `•••• 1234`) when the non-PCI mirror is present.
  String? get maskedCard =>
      (cardLast4 != null && cardLast4!.isNotEmpty) ? '•••• $cardLast4' : null;

  /// `MM/AA` expiry label when the non-PCI mirror is present.
  String? get cardExpiryLabel {
    if (cardExpMonth == null || cardExpYear == null) return null;
    final mm = cardExpMonth!.toString().padLeft(2, '0');
    final yy = (cardExpYear! % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }
}

class SubscriptionService {
  final String academyId;
  final FirebaseFirestore _db = FirebaseService.firestore;
  final CallableClient _functions = Fns.functions;

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

  /// Fresh (one-shot) check for a live subscription (pending/authorized/paused)
  /// of the same student+plan. Guards the "Assinar" flow against duplicate
  /// preapprovals (e.g. retry after a client timeout) — same rule enforced by
  /// the backend in `createMpSubscription` (failed-precondition), INCLUDING its
  /// exception: a 'pending' doc WITHOUT `mpPreapprovalId` older than 1h is an
  /// aborted attempt (CF crashed before the POST /preapproval) that the backend
  /// marks 'abandoned' and allows through — blocking on it here would make that
  /// auto-heal unreachable and lock the student out of retrying forever.
  Future<bool> hasLiveSubscription({
    required String studentId,
    required String planId,
  }) async {
    final snap = await _ref.where('studentId', isEqualTo: studentId).get();
    final now = DateTime.now();
    return snap.docs.any((d) {
      final data = d.data();
      if (data['planId'] != planId) return false;
      final status = data['status'] as String? ?? '';
      if (status != 'pending' &&
          status != 'authorized' &&
          status != 'paused') {
        return false;
      }
      final mpId = data['mpPreapprovalId'] as String?;
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      final isStaleAbort = status == 'pending' &&
          (mpId == null || mpId.isEmpty) &&
          createdAt != null &&
          now.difference(createdAt) > const Duration(hours: 1);
      return !isStaleAbort;
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

  /// Resumes a user-paused subscription. The backend (`resumeMpSubscription`)
  /// rejects with failed-precondition when the subscription is not 'paused';
  /// on success the MP preapproval is re-authorized and the doc returns to
  /// 'authorized'.
  Future<void> resume(String subscriptionId) async {
    await _functions.httpsCallable('resumeMpSubscription').call({
      'academyId': academyId,
      'subscriptionId': subscriptionId,
    });
  }

  /// Reads the academy's connected Mercado Pago PUBLIC key (for client-side card
  /// tokenization). Returns null when MP is not connected.
  Future<String?> _mpPublicKey() async {
    try {
      final doc =
          await _db.collection('academies').doc(academyId).get();
      return doc.data()?['mpPublicKey'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Swaps the card backing a recurring subscription. The raw card is tokenized
  /// client-side with the academy's PUBLIC key (PCI-safe — never touches our
  /// backend) and only the opaque token is sent to the `updateSubscriptionCard`
  /// callable, which re-authorizes the MP preapproval and clears the dunning
  /// state server-side (the server is the boundary; this only orchestrates).
  ///
  /// Throws on failure so the caller can surface the gateway message.
  Future<void> updateCard({
    required String subscriptionId,
    required String cardNumber,
    required String expirationMonth,
    required String expirationYear,
    required String securityCode,
    required String cardholderName,
    required String cpf,
  }) async {
    final pk = await _mpPublicKey();
    if (pk == null || pk.isEmpty) {
      throw Exception('Mercado Pago nao conectado.');
    }
    final token = await MpCardTokenizer.tokenize(
      publicKey: pk,
      cardNumber: cardNumber,
      expirationMonth: expirationMonth,
      expirationYear: expirationYear,
      securityCode: securityCode,
      cardholderName: cardholderName,
      cpf: cpf,
    );
    await _functions.httpsCallable('updateSubscriptionCard').call({
      'academyId': academyId,
      'subscriptionId': subscriptionId,
      'cardToken': token.tokenId,
    });
  }

  /// Settled cycles for a subscription, newest first. Reads the academy's
  /// `financials` collection filtered by the `subscriptionId` written by the
  /// backend (`mpSubSettleCycle`, deterministic id `sub_{subId}_{paymentId}`).
  /// Each entry exposes the cycle amount, reference month and paid date — used
  /// by the subscription-detail history list.
  Stream<List<SubscriptionCharge>> streamCycleHistory(String subscriptionId) {
    return _db
        .collection('academies')
        .doc(academyId)
        .collection('financials')
        .where('subscriptionId', isEqualTo: subscriptionId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(SubscriptionCharge.fromFirestore).toList();
      list.sort((a, b) {
        final ai = a.cycle ?? 0;
        final bi = b.cycle ?? 0;
        if (ai != bi) return bi.compareTo(ai); // newest cycle first
        final ad = a.paidAt;
        final bd = b.paidAt;
        if (ad == null || bd == null) return 0;
        return bd.compareTo(ad);
      });
      return list;
    });
  }
}

/// A single settled subscription cycle (mirror of a `financials` doc written by
/// `mpSubSettleCycle`). Read-only view model for the subscription-detail
/// history — it never reimplements any charge logic.
class SubscriptionCharge {
  final String id;
  final double amount;
  final String? referenceMonth;
  final DateTime? paidAt;
  final int? cycle;

  /// Cobrança indevida (type 'subscription_overcharge', needsRefund): dinheiro
  /// a devolver, não um ciclo da assinatura — o histórico a exibe destacada
  /// como 'Reembolso pendente'.
  final bool overcharge;

  const SubscriptionCharge({
    required this.id,
    required this.amount,
    required this.referenceMonth,
    required this.paidAt,
    required this.cycle,
    this.overcharge = false,
  });

  factory SubscriptionCharge.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubscriptionCharge(
      id: doc.id,
      amount: (data['amount'] ?? 0).toDouble(),
      referenceMonth: data['referenceMonth'] as String?,
      paidAt: (data['paymentDate'] as Timestamp?)?.toDate() ??
          (data['paidAt'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate(),
      cycle: (data['recurringCycle'] as num?)?.toInt(),
      overcharge: data['type'] == 'subscription_overcharge' ||
          data['overcharge'] == true,
    );
  }
}
