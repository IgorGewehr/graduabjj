/// What is being paid: a tuition (financial) charge or a store order.
///
/// Unifies the parameters every call site used to reassemble by hand before
/// opening [PixPaymentSheet]/[CardPaymentSheet] (amount, description, payer
/// identity, and the owning document id). Construct one with [PaymentTarget.tuition]
/// or [PaymentTarget.order] and pass it to `PaymentMethodSheet`.
///
/// The [amount] is always in REAIS and is forwarded to the sheets only as a
/// display value / server cross-check — the charge value remains derived
/// server-side (createMp* never trust the client amount).
import '../../services/payment_service.dart' show PaymentMethodPolicy;

enum PaymentTargetKind { tuition, order }

class PaymentTarget {
  /// Whether this charge is a tuition (financial) or a store order.
  final PaymentTargetKind kind;

  /// The owning document id: the `financials` doc id for tuition, or the
  /// `storeOrders` doc id for an order.
  final String id;

  /// Amount in REAIS. Display / cross-check only — never the authoritative value.
  final double amount;

  /// Human label shown on the sheets (e.g. "Mensalidade - 2026/06" or
  /// "Pedido #ABC123").
  final String description;

  /// The student paying (used by the card charge for ownership + payer name).
  final String studentId;

  /// The payer's display name (used by the card charge).
  final String studentName;

  /// Which methods this charge accepts (snapshot from the financial/plan).
  /// Orders are always [PaymentMethodPolicy.both].
  final PaymentMethodPolicy paymentMethodPolicy;

  const PaymentTarget._({
    required this.kind,
    required this.id,
    required this.amount,
    required this.description,
    required this.studentId,
    required this.studentName,
    this.paymentMethodPolicy = PaymentMethodPolicy.both,
  });

  /// A tuition (financial) charge. [financialId] is the `financials` doc id.
  factory PaymentTarget.tuition({
    required String financialId,
    required double amount,
    required String description,
    required String studentId,
    required String studentName,
    PaymentMethodPolicy paymentMethodPolicy = PaymentMethodPolicy.both,
  }) {
    return PaymentTarget._(
      kind: PaymentTargetKind.tuition,
      id: financialId,
      amount: amount,
      description: description,
      studentId: studentId,
      studentName: studentName,
      paymentMethodPolicy: paymentMethodPolicy,
    );
  }

  /// A store-order charge. [orderId] is the `storeOrders` doc id.
  factory PaymentTarget.order({
    required String orderId,
    required double amount,
    required String description,
    required String studentId,
    required String studentName,
    PaymentMethodPolicy paymentMethodPolicy = PaymentMethodPolicy.both,
  }) {
    return PaymentTarget._(
      kind: PaymentTargetKind.order,
      id: orderId,
      amount: amount,
      description: description,
      studentId: studentId,
      studentName: studentName,
      paymentMethodPolicy: paymentMethodPolicy,
    );
  }

  bool get isOrder => kind == PaymentTargetKind.order;
  bool get isTuition => kind == PaymentTargetKind.tuition;

  /// The `financials` doc id, or null when this is an order.
  String? get financialId => isTuition ? id : null;

  /// The `storeOrders` doc id, or null when this is a tuition.
  String? get orderId => isOrder ? id : null;
}
