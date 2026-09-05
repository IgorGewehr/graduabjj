import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'fns.dart';

import 'firebase_service.dart';
import 'plan_service.dart';

/// Payment Status
enum PaymentStatus { pending, paid, overdue, cancelled }

extension PaymentStatusExtension on PaymentStatus {
  String get value {
    switch (this) {
      case PaymentStatus.pending:
        return 'pending';
      case PaymentStatus.paid:
        return 'paid';
      case PaymentStatus.overdue:
        return 'overdue';
      case PaymentStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case PaymentStatus.pending:
        return 'Pendente';
      case PaymentStatus.paid:
        return 'Pago';
      case PaymentStatus.overdue:
        return 'Atrasado';
      case PaymentStatus.cancelled:
        return 'Cancelado';
    }
  }

  static PaymentStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return PaymentStatus.pending;
      case 'paid':
        return PaymentStatus.paid;
      case 'overdue':
        return PaymentStatus.overdue;
      case 'cancelled':
        return PaymentStatus.cancelled;
      default:
        return PaymentStatus.pending;
    }
  }
}

/// Payment Method
enum PaymentMethod { pix, creditCard, debitCard, cash, bankTransfer }

extension PaymentMethodExtension on PaymentMethod {
  String get value {
    switch (this) {
      case PaymentMethod.pix:
        return 'pix';
      case PaymentMethod.creditCard:
        return 'credit_card';
      case PaymentMethod.debitCard:
        return 'debit_card';
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.bankTransfer:
        return 'bank_transfer';
    }
  }

  String get label {
    switch (this) {
      case PaymentMethod.pix:
        return 'PIX';
      case PaymentMethod.creditCard:
        return 'Cartão de Crédito';
      case PaymentMethod.debitCard:
        return 'Cartão de Débito';
      case PaymentMethod.cash:
        return 'Dinheiro';
      case PaymentMethod.bankTransfer:
        return 'Transferência';
    }
  }

  static PaymentMethod fromString(String value) {
    switch (value) {
      case 'pix':
        return PaymentMethod.pix;
      case 'credit_card':
        return PaymentMethod.creditCard;
      case 'debit_card':
        return PaymentMethod.debitCard;
      case 'cash':
        return PaymentMethod.cash;
      case 'bank_transfer':
        return PaymentMethod.bankTransfer;
      default:
        return PaymentMethod.pix;
    }
  }
}

/// Which payment methods a plan/charge accepts. Additive & backward-compatible:
/// an absent value resolves to [both] (the current, unrestricted behavior).
enum PaymentMethodPolicy { both, pixOnly, cardOnly }

extension PaymentMethodPolicyExtension on PaymentMethodPolicy {
  String get value {
    switch (this) {
      case PaymentMethodPolicy.both:
        return 'both';
      case PaymentMethodPolicy.pixOnly:
        return 'pix_only';
      case PaymentMethodPolicy.cardOnly:
        return 'card_only';
    }
  }

  String get label {
    switch (this) {
      case PaymentMethodPolicy.both:
        return 'PIX e Cartão';
      case PaymentMethodPolicy.pixOnly:
        return 'Somente PIX';
      case PaymentMethodPolicy.cardOnly:
        return 'Somente Cartão';
    }
  }

  bool get allowsPix => this != PaymentMethodPolicy.cardOnly;
  bool get allowsCard => this != PaymentMethodPolicy.pixOnly;

  static PaymentMethodPolicy fromString(String? value) {
    switch (value) {
      case 'pix_only':
        return PaymentMethodPolicy.pixOnly;
      case 'card_only':
        return PaymentMethodPolicy.cardOnly;
      case 'both':
      default:
        return PaymentMethodPolicy.both;
    }
  }
}

/// Payment Model
class Payment {
  final String id;
  final String studentId;
  final String studentName;
  final double value;
  final DateTime dueDate;
  final DateTime? paidAt;
  final PaymentStatus status;
  final PaymentMethod? method;
  final String? description;
  final String? referenceMonth;
  final String? externalId; // For AbacatePay integration
  /// Settling gateway: 'mercadopago' | 'abacatepay' | 'manual'. Canonical field
  /// written by every paid path (webhook, inline settle, manual mark-paid).
  final String? paymentGateway;

  /// Gateway-side charge id for the settlement (MP/AbacatePay payment id).
  final String? gatewayPaymentId;

  /// Server-authored marker for a payment received through the academy's
  /// personal PIX key. The immutable full audit (including uid) lives in
  /// paymentAuditLogs; this safe summary is also visible in payment history.
  final String? manualPaymentConfirmedByName;
  final DateTime? manualPaymentConfirmedAt;
  final String? pixCode;
  final String? pixQrCode;
  final String? planId;
  final String type; // 'monthly_tuition' | 'avulsa' | 'private_lesson'
  /// Snapshot of the plan/charge payment-method policy at generation time.
  /// Absent on legacy docs → [PaymentMethodPolicy.both].
  final PaymentMethodPolicy paymentMethodPolicy;

  /// Aula particular (type == 'private_lesson'): true depois que o backend
  /// concedeu a presença ao aluno (no settle do pagamento ou no grant manual).
  final bool attendanceGranted;
  final DateTime createdAt;

  Payment({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.value,
    required this.dueDate,
    this.paidAt,
    required this.status,
    this.method,
    this.description,
    this.referenceMonth,
    this.externalId,
    this.paymentGateway,
    this.gatewayPaymentId,
    this.manualPaymentConfirmedByName,
    this.manualPaymentConfirmedAt,
    this.pixCode,
    this.pixQrCode,
    this.planId,
    this.type = 'monthly_tuition',
    this.paymentMethodPolicy = PaymentMethodPolicy.both,
    this.attendanceGranted = false,
    required this.createdAt,
  });

  factory Payment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final manualAudit = data['manualPaymentAudit'] is Map
        ? Map<String, dynamic>.from(data['manualPaymentAudit'] as Map)
        : const <String, dynamic>{};
    return Payment(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      // Support both 'amount' (webapp) and 'value' (legacy) field names
      value: (data['amount'] ?? data['value'] ?? 0).toDouble(),
      dueDate: (data['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      // Support both 'paymentDate' (webapp) and 'paidAt' (legacy) field names
      paidAt: data['paymentDate'] != null
          ? (data['paymentDate'] as Timestamp).toDate()
          : data['paidAt'] != null
          ? (data['paidAt'] as Timestamp).toDate()
          : null,
      status: PaymentStatusExtension.fromString(data['status'] ?? 'pending'),
      method: data['method'] != null
          ? PaymentMethodExtension.fromString(data['method'])
          : null,
      description: data['description'],
      referenceMonth: data['referenceMonth'],
      externalId: data['externalId'],
      paymentGateway: data['paymentGateway'],
      gatewayPaymentId: data['gatewayPaymentId'],
      manualPaymentConfirmedByName: manualAudit['confirmedByName'] as String?,
      manualPaymentConfirmedAt: manualAudit['confirmedAt'] is Timestamp
          ? (manualAudit['confirmedAt'] as Timestamp).toDate()
          : null,
      pixCode: data['pixCode'],
      pixQrCode: data['pixQrCode'],
      planId: data['planId'],
      type: data['type'] ?? 'monthly_tuition',
      paymentMethodPolicy: PaymentMethodPolicyExtension.fromString(
        data['paymentMethodPolicy'],
      ),
      attendanceGranted: data['attendanceGranted'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Computed properties
  bool get isPaid => status == PaymentStatus.paid;

  bool get isManualPersonalPix =>
      isPaid &&
      method == PaymentMethod.pix &&
      paymentGateway == 'manual' &&
      manualPaymentConfirmedAt != null;

  /// Aula particular 1:1 (type 'private_lesson') — cobrança avulsa que concede
  /// uma presença ao aluno quando paga, sem plano nem turma.
  bool get isPrivateLesson => type == 'private_lesson';

  /// Cobrança indevida de assinatura (lote 1: type 'subscription_overcharge',
  /// status 'paid', needsRefund) — dinheiro a DEVOLVER, nunca receita. Toda
  /// soma/contagem de receita deve pular estes docs; listagens os exibem com
  /// destaque 'Reembolso pendente'.
  bool get isOvercharge => type == 'subscription_overcharge';
  bool get isOverdue =>
      status != PaymentStatus.paid &&
      status != PaymentStatus.cancelled &&
      dueDate.isBefore(DateTime.now());

  int get daysOverdue {
    if (!isOverdue) return 0;
    return DateTime.now().difference(dueDate).inDays;
  }
}

/// Canonical month key used by Financeiro for every charge type.
///
/// Avulsas and private lessons used to omit this field and consequently did
/// not appear in the month-scoped financial screen.
String paymentReferenceMonth(DateTime dueDate) =>
    '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}';

/// Payment Service - Multi-tenant payment management
class PaymentService {
  final String academyId;
  late final Collections _collections;

  PaymentService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _paymentsRef => _collections.payments;

  // ============================================
  // Get Payments by Student (One-time fetch)
  // ============================================
  Future<List<Payment>> getByStudent(String studentId, {int? limit}) async {
    final query = await _paymentsRef
        .where('studentId', isEqualTo: studentId)
        .get();

    var payments = query.docs.map((doc) => Payment.fromFirestore(doc)).toList();
    payments.sort((a, b) => b.dueDate.compareTo(a.dueDate));

    if (limit != null && payments.length > limit) {
      payments = payments.sublist(0, limit);
    }

    return payments;
  }

  // ============================================
  // Stream Payments by Student (Real-time updates)
  // ============================================
  Stream<List<Payment>> streamByStudent(String studentId) {
    return _paymentsRef
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
          var payments = snapshot.docs
              .map((doc) => Payment.fromFirestore(doc))
              .toList();
          payments.sort((a, b) => b.dueDate.compareTo(a.dueDate));
          return payments;
        });
  }

  // ============================================
  // Stream Payment Stats by Student (Real-time)
  // ============================================
  Stream<Map<String, dynamic>> streamStatsByStudent(String studentId) {
    return streamByStudent(studentId).map((payments) {
      int pendingCount = 0;
      int overdueCount = 0;
      int paidCount = 0;
      double pendingTotal = 0;
      double overdueTotal = 0;
      double paidTotal = 0;

      for (final p in payments) {
        switch (p.status) {
          case PaymentStatus.pending:
            if (p.isOverdue) {
              overdueCount++;
              overdueTotal += p.value;
            } else {
              pendingCount++;
              pendingTotal += p.value;
            }
            break;
          case PaymentStatus.paid:
            // Cobrança indevida a reembolsar (needsRefund) não infla o "pago".
            if (p.isOvercharge) break;
            paidCount++;
            paidTotal += p.value;
            break;
          case PaymentStatus.overdue:
            overdueCount++;
            overdueTotal += p.value;
            break;
          case PaymentStatus.cancelled:
            // Ignore cancelled
            break;
        }
      }

      return {
        'pending': {'count': pendingCount, 'total': pendingTotal},
        'overdue': {'count': overdueCount, 'total': overdueTotal},
        'paid': {'count': paidCount, 'total': paidTotal},
      };
    });
  }

  // ============================================
  // Get Pending Payments by Student
  // ============================================
  Future<List<Payment>> getPendingByStudent(String studentId) async {
    final payments = await getByStudent(studentId);
    return payments
        .where(
          (p) =>
              p.status == PaymentStatus.pending ||
              p.status == PaymentStatus.overdue,
        )
        .toList();
  }

  // ============================================
  // Get Overdue Payments by Student
  // ============================================
  Future<List<Payment>> getOverdueByStudent(String studentId) async {
    final payments = await getByStudent(studentId);
    return payments.where((p) => p.isOverdue).toList();
  }

  // ============================================
  // Get Payment Stats by Student
  // ============================================
  Future<Map<String, dynamic>> getStatsByStudent(String studentId) async {
    final payments = await getByStudent(studentId);

    int pendingCount = 0;
    int overdueCount = 0;
    int paidCount = 0;
    double pendingTotal = 0;
    double overdueTotal = 0;
    double paidTotal = 0;

    for (final p in payments) {
      switch (p.status) {
        case PaymentStatus.pending:
          if (p.isOverdue) {
            overdueCount++;
            overdueTotal += p.value;
          } else {
            pendingCount++;
            pendingTotal += p.value;
          }
          break;
        case PaymentStatus.paid:
          // Cobrança indevida a reembolsar (needsRefund) não infla o "pago".
          if (p.isOvercharge) break;
          paidCount++;
          paidTotal += p.value;
          break;
        case PaymentStatus.overdue:
          overdueCount++;
          overdueTotal += p.value;
          break;
        case PaymentStatus.cancelled:
          // Ignore cancelled
          break;
      }
    }

    return {
      'pending': {'count': pendingCount, 'total': pendingTotal},
      'overdue': {'count': overdueCount, 'total': overdueTotal},
      'paid': {'count': paidCount, 'total': paidTotal},
    };
  }

  // ============================================
  // Get Next Due Payment
  // ============================================
  Future<Payment?> getNextDue(String studentId) async {
    final pending = await getPendingByStudent(studentId);
    if (pending.isEmpty) return null;

    pending.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return pending.first;
  }

  // ============================================
  // Get Payment by ID
  // ============================================
  Future<Payment?> getById(String id) async {
    final doc = await _collections.payment(id).get();
    if (!doc.exists) return null;
    return Payment.fromFirestore(doc);
  }

  // ============================================
  // Get Payments by Reference Month
  // ============================================
  Future<List<Payment>> getByMonth(
    String referenceMonth, {
    String? studentId,
  }) async {
    Query query = _paymentsRef.where(
      'referenceMonth',
      isEqualTo: referenceMonth,
    );

    if (studentId != null) {
      query = query.where('studentId', isEqualTo: studentId);
    }

    final snapshot = await query.get();
    var payments = snapshot.docs
        .map((doc) => Payment.fromFirestore(doc))
        .toList();
    payments.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return payments;
  }

  /// Cobranças pendentes/atrasadas de meses ANTERIORES a [referenceMonth] —
  /// sem isso, a aba Financeiro (mês-a-mês via getByMonth) escondia dívida do
  /// mês passado assim que o calendário virava, mesmo com o aluno ainda
  /// inadimplente (caso real: Drakkar/Ueverton, 01/set/2026 — cobrança de
  /// agosto ainda em aberto sumiu da aba ao entrar em setembro). Varre por
  /// status (índice single-field automático, sem exigir índice composto) e
  /// filtra o mês no cliente — dataset pequeno por academia.
  Future<List<Payment>> getOpenBefore(String referenceMonth) async {
    final snapshot = await _paymentsRef
        .where('status', whereIn: ['pending', 'overdue'])
        .get();
    final payments = snapshot.docs
        .map((doc) => Payment.fromFirestore(doc))
        .where(
          (p) =>
              p.referenceMonth != null &&
              p.referenceMonth!.compareTo(referenceMonth) < 0,
        )
        .toList();
    payments.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return payments;
  }

  /// Live stream of a month's payments — so the admin screen reflects a webhook
  /// flip to `paid` in real time (the one-shot getByMonth went stale, showing a
  /// just-paid charge as still open).
  Stream<List<Payment>> streamByMonth(String referenceMonth) {
    return _paymentsRef
        .where('referenceMonth', isEqualTo: referenceMonth)
        .snapshots()
        .map((snap) {
          final payments = snap.docs
              .map((d) => Payment.fromFirestore(d))
              .toList();
          payments.sort((a, b) => b.dueDate.compareTo(a.dueDate));
          return payments;
        });
  }

  // ============================================
  // Get Payment Summary (all students)
  // ============================================
  Future<Map<String, dynamic>> getSummary() async {
    final snapshot = await _paymentsRef.get();

    int totalPending = 0;
    int totalOverdue = 0;
    int totalPaid = 0;
    double valuePending = 0;
    double valueOverdue = 0;
    double valuePaid = 0;

    for (final doc in snapshot.docs) {
      final payment = Payment.fromFirestore(doc);
      switch (payment.status) {
        case PaymentStatus.pending:
          if (payment.isOverdue) {
            totalOverdue++;
            valueOverdue += payment.value;
          } else {
            totalPending++;
            valuePending += payment.value;
          }
          break;
        case PaymentStatus.paid:
          totalPaid++;
          valuePaid += payment.value;
          break;
        case PaymentStatus.overdue:
          totalOverdue++;
          valueOverdue += payment.value;
          break;
        case PaymentStatus.cancelled:
          break;
      }
    }

    return {
      'pending': {'count': totalPending, 'value': valuePending},
      'overdue': {'count': totalOverdue, 'value': valueOverdue},
      'paid': {'count': totalPaid, 'value': valuePaid},
    };
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Create Payment
  // ============================================
  Future<Payment> create({
    required String studentId,
    required String studentName,
    required double value,
    required DateTime dueDate,
    String? description,
    String? referenceMonth,
    String? createdBy,
    String? planId,
    String type = 'monthly_tuition',
    PaymentMethodPolicy paymentMethodPolicy = PaymentMethodPolicy.both,
    bool sendNotification = true,
    // Aula particular (type == 'private_lesson'): metadados da aula que o
    // backend usa para conceder a presença ao liquidar a cobrança. Ignorados
    // para os demais tipos.
    DateTime? lessonDate,
    double? lessonWeight,
    String? lessonSport,
    String? instructorId,
    String? instructorName,
  }) async {
    final isPrivateLesson = type == 'private_lesson';
    final effectiveReferenceMonth = referenceMonth?.trim().isNotEmpty == true
        ? referenceMonth!.trim()
        : paymentReferenceMonth(dueDate);
    final result = await Fns.functions
        .httpsCallable('createFinancialCharge')
        .call({
          'academyId': academyId,
          'studentId': studentId,
          'studentName': studentName,
          'amount': value,
          'type': type,
          'dueDate': dueDate.toUtc().toIso8601String(),
          'description': description ?? 'Mensalidade',
          'referenceMonth': effectiveReferenceMonth,
          'planId': planId,
          'paymentMethodPolicy': paymentMethodPolicy.value,
          'sendNotification': sendNotification,
          if (isPrivateLesson) ...{
            'lessonDate': (lessonDate ?? dueDate).toUtc().toIso8601String(),
            'lessonWeight': lessonWeight ?? 1.0,
            'lessonSport': lessonSport ?? 'bjj',
            'instructorId': instructorId,
            'instructorName': instructorName,
          },
        });
    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : const <String, dynamic>{};
    final financialId = data['financialId']?.toString() ?? '';
    if (financialId.isEmpty) {
      throw PaymentOperationException(
        'O backend não retornou a cobrança criada.',
      );
    }
    final payment = await getById(financialId);
    if (payment == null) {
      throw PaymentOperationException(
        'A cobrança foi criada, mas não foi possível recarregar os dados.',
      );
    }
    return payment;
  }

  /// Concede manualmente a presença de uma aula particular (caminho offline:
  /// dinheiro em mãos, cortesia, ou confirmação de que a aula aconteceu).
  /// Chama a CF `markPrivateLessonGiven` (gated p/ admin/professor), que roda o
  /// MESMO grant idempotente do webhook — conceder manual e depois receber o
  /// pagamento MP nunca duplica a presença. Quando [markPaidCash] é true, marca
  /// a cobrança como paga (method 'cash') antes de conceder.
  Future<void> markPrivateLessonGiven({
    required String financialId,
    bool markPaidCash = false,
    String? staffName,
  }) async {
    await Fns.functions.httpsCallable('markPrivateLessonGiven').call({
      'academyId': academyId,
      'financialId': financialId,
      'markPaidCash': markPaidCash,
      if (staffName != null) 'staffName': staffName,
    });
  }

  /// Edita os termos de uma cobrança ainda aberta. Qualquer PIX já emitido
  /// deixa de representar o novo valor/vencimento, então ele é invalidado e
  /// será recriado no próximo envio. Os marcadores da régua também são limpos
  /// para que a automação reavalie a cobrança com a nova data.
  Future<Payment> updateTerms({
    required String id,
    required double value,
    required DateTime dueDate,
  }) async {
    if (value <= 0) throw ArgumentError.value(value, 'value');

    await Fns.functions.httpsCallable('updateFinancialTerms').call({
      'academyId': academyId,
      'financialId': id,
      'amount': value,
      'dueDate': dueDate.toUtc().toIso8601String(),
    });
    final updated = await getById(id);
    if (updated == null) throw StateError('Pagamento nao encontrado');
    return updated;
  }

  // ============================================
  // Mark as Paid
  // ============================================
  /// Confirms payment made to the academy's personal PIX key.
  ///
  /// This path is intentionally server-only: the callable checks the caller is
  /// an academy admin, cancels any competing Mercado Pago charge, revalidates
  /// the financial record transactionally and writes an immutable audit log.
  Future<Payment> confirmManualPix(String id) async {
    try {
      await Fns.functions.httpsCallable('confirmManualPixPayment').call({
        'academyId': academyId,
        'financialId': id,
      });
    } on FirebaseFunctionsException catch (e) {
      throw PaymentOperationException(
        e.message ?? 'Nao foi possivel confirmar o PIX manual.',
      );
    }

    final payment = await getById(id);
    if (payment == null) {
      throw PaymentOperationException(
        'A cobranca foi confirmada, mas nao foi possivel recarregar os dados.',
      );
    }
    return payment;
  }

  Future<Payment> markAsPaid(
    String id, {
    PaymentMethod method = PaymentMethod.pix,
    DateTime? paymentDate,
  }) async {
    await Fns.functions.httpsCallable('markFinancialPaidManual').call({
      'academyId': academyId,
      'financialId': id,
      'method': method.value,
      'paymentDate': (paymentDate ?? DateTime.now()).toUtc().toIso8601String(),
    });
    final payment = await getById(id);
    if (payment == null) throw StateError('Pagamento nao encontrado');
    return payment;
  }

  // ============================================
  // Cancel Payment
  // ============================================
  Future<Payment> cancel(String id) async {
    try {
      await Fns.functions.httpsCallable('cancelFinancialCharge').call({
        'academyId': academyId,
        'financialId': id,
      });
    } catch (error) {
      throw _friendlyPaymentError(
        error,
        fallback: 'Não foi possível cancelar a cobrança. Tente novamente.',
      );
    }
    final payment = await getById(id);
    if (payment == null) {
      throw const PaymentOperationException(
        'A cobrança foi cancelada, mas não foi possível atualizar os dados.',
      );
    }
    return payment;
  }

  // ============================================
  // Reactivate Cancelled Payment
  // ============================================
  Future<Payment> reactivate(String id) async {
    await Fns.functions.httpsCallable('reactivateFinancialCharge').call({
      'academyId': academyId,
      'financialId': id,
    });
    final payment = await getById(id);
    if (payment == null) throw StateError('Pagamento nao encontrado');
    return payment;
  }

  // ============================================
  // Delete Payment
  // ============================================
  Future<void> delete(String id) async {
    try {
      await Fns.functions.httpsCallable('deleteFinancialCharge').call({
        'academyId': academyId,
        'financialId': id,
      });
    } catch (error) {
      throw _friendlyPaymentError(
        error,
        fallback: 'Não foi possível excluir a cobrança. Tente novamente.',
      );
    }
  }

  // ============================================
  // Get Pending Payments (all students)
  // ============================================
  Future<List<Payment>> getPending() async {
    final snapshot = await _paymentsRef.get();
    var payments = snapshot.docs
        .map((doc) => Payment.fromFirestore(doc))
        .where((p) => p.status == PaymentStatus.pending && !p.isOverdue)
        .toList();
    payments.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return payments;
  }

  // ============================================
  // Get Overdue Payments (all students)
  // ============================================
  Future<List<Payment>> getOverdue() async {
    final snapshot = await _paymentsRef.get();
    var payments = snapshot.docs
        .map((doc) => Payment.fromFirestore(doc))
        .where((p) => p.isOverdue || p.status == PaymentStatus.overdue)
        .toList();
    payments.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return payments;
  }

  // ============================================
  // Get Paid This Month
  // ============================================
  Future<List<Payment>> getPaidThisMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final snapshot = await _paymentsRef.get();
    var payments = snapshot.docs
        .map((doc) => Payment.fromFirestore(doc))
        .where(
          (p) =>
              p.status == PaymentStatus.paid &&
              p.paidAt != null &&
              p.paidAt!.isAfter(startOfMonth) &&
              p.paidAt!.isBefore(endOfMonth),
        )
        .toList();
    payments.sort((a, b) => b.paidAt!.compareTo(a.paidAt!));
    return payments;
  }

  // ============================================
  // Generate Monthly Tuitions
  // ============================================
  /// Returns true if a non-monthly plan student is due for a new charge in [referenceMonth].
  /// Looks at the last active payment for this student+plan and checks if enough time
  /// has elapsed (>= billingPeriod.months months since last due date).
  Future<bool> _isDueForPeriod({
    required String studentId,
    required String planId,
    required BillingPeriod billingPeriod,
    required int refYear,
    required int refMonth,
  }) async {
    final snapshot = await _paymentsRef
        .where('studentId', isEqualTo: studentId)
        .where('planId', isEqualTo: planId)
        .where('type', isEqualTo: 'monthly_tuition')
        .get();

    final active = snapshot.docs
        .map((d) => Payment.fromFirestore(d))
        .where((p) => p.status != PaymentStatus.cancelled)
        .toList();

    if (active.isEmpty) return true;

    active.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    final lastDue = active.first.dueDate;

    final nextBilling = DateTime(
      lastDue.year,
      lastDue.month + billingPeriod.months,
      lastDue.day,
    );

    return nextBilling.year < refYear ||
        (nextBilling.year == refYear && nextBilling.month <= refMonth);
  }

  // ============================================
  /// Generates tuitions for students enrolled in active plans.
  /// Monthly plans: one charge per month. Non-monthly plans: one charge per period
  /// (quarterly/semiannual/annual). A student already charged within the period is skipped.
  /// If [planId] is provided, generates only for students in that specific plan.
  Future<List<Payment>> generateMonthlyTuitions({
    List<
      ({
        String id,
        String name,
        double value,
        int dueDay,
        String? planId,
        BillingPeriod billingPeriod,
      })
    >?
    students,
    required String referenceMonth,
    String? createdBy,
    String? planId,
  }) async {
    final results = <Payment>[];
    final year = int.parse(referenceMonth.split('-')[0]);
    final month = int.parse(referenceMonth.split('-')[1]);
    // planId -> payment-method policy, so each generated charge snapshots its
    // plan's policy. Populated from the plans we process below.
    final planPolicies = <String, PaymentMethodPolicy>{};

    List<
      ({
        String id,
        String name,
        double value,
        int dueDay,
        String? planId,
        BillingPeriod billingPeriod,
      })
    >
    studentList;
    if (students != null) {
      studentList = students;
    } else {
      final planService = PlanService(academyId);
      final allActivePlans = await planService.getActive();
      final selectedPlanIds = planId == null ? null : <String>{planId};
      final plansById = {for (final plan in allActivePlans) plan.id: plan};

      final entries =
          <
            ({
              String studentId,
              String planId,
              double value,
              int dueDay,
              BillingPeriod billingPeriod,
            })
          >[];

      // Build from every active plan even when the user selected one plan.
      // This lets us detect an accidental cross-plan overlap before charging.
      for (final plan in allActivePlans) {
        planPolicies[plan.id] = plan.paymentMethodPolicy;
        for (final studentId in plan.studentIds) {
          entries.add((
            studentId: studentId,
            planId: plan.id,
            value: plan.getStudentValue(studentId),
            dueDay: plan.getStudentDueDay(studentId),
            billingPeriod: plan.billingPeriod,
          ));
        }
      }

      if (entries.isEmpty) return results;

      final studentIds = entries.map((e) => e.studentId).toSet();

      final activeStudents = await _collections.students
          .where('status', isEqualTo: 'active')
          .get();

      final activeStudentMap = <String, Map<String, dynamic>>{};
      for (final doc in activeStudents.docs) {
        if (studentIds.contains(doc.id)) {
          activeStudentMap[doc.id] = doc.data() as Map<String, dynamic>;
        }
      }

      final eligibleEntries = entries
          .where((e) => activeStudentMap.containsKey(e.studentId))
          .map((e) {
            final data = activeStudentMap[e.studentId]!;
            final effectiveDueDay = data['tuitionDay'] as int? ?? e.dueDay;
            final plan = plansById[e.planId]!;
            return (
              id: e.studentId,
              name: data['fullName'] as String? ?? '',
              value: e.value,
              dueDay: effectiveDueDay,
              planId: e.planId as String?,
              billingPeriod: e.billingPeriod,
              eligible: plan.isStudentEligibleForMonth(
                e.studentId,
                year: year,
                month: month,
                dueDay: effectiveDueDay,
              ),
            );
          })
          .where((entry) => entry.value > 0 && entry.eligible)
          .toList();

      final monthlyPlanIdsByStudent = <String, Set<String>>{};
      for (final entry in eligibleEntries.where(
        (entry) => entry.billingPeriod == BillingPeriod.monthly,
      )) {
        monthlyPlanIdsByStudent
            .putIfAbsent(entry.id, () => <String>{})
            .add(entry.planId!);
      }
      final conflictingStudentIds = monthlyPlanIdsByStudent.entries
          .where((entry) => entry.value.length > 1)
          .map((entry) => entry.key)
          .toSet();

      studentList = eligibleEntries
          .where(
            (entry) =>
                !conflictingStudentIds.contains(entry.id) &&
                !plansById[entry.planId]!.isRecurring &&
                (selectedPlanIds == null ||
                    selectedPlanIds.contains(entry.planId)),
          )
          .map(
            (entry) => (
              id: entry.id,
              name: entry.name,
              value: entry.value,
              dueDay: entry.dueDay,
              planId: entry.planId,
              billingPeriod: entry.billingPeriod,
            ),
          )
          .toList();
    }

    // Prefetch this month's charges ONCE for the monthly-plan dedup, instead of
    // one Firestore query per student (the N+1 that made bulk generation hang).
    // Non-monthly plans still use the per-student period check below.
    // Cancelled is terminal too: generation must not recreate tomorrow a
    // charge that an admin deliberately cancelled. Reactivation is explicit.
    final monthCharges = await getByMonth(referenceMonth);

    for (final student in studentList) {
      final period = student.billingPeriod;
      bool shouldGenerate;

      // One tuition document per student/month, regardless of plan/status.
      if (monthCharges.any(
        (payment) =>
            payment.studentId == student.id &&
            payment.type == 'monthly_tuition',
      )) {
        continue;
      }

      if (period == BillingPeriod.monthly) {
        shouldGenerate = true;
      } else {
        // Non-monthly: skip if student was already charged within the billing period
        shouldGenerate = await _isDueForPeriod(
          studentId: student.id,
          planId: student.planId!,
          billingPeriod: period,
          refYear: year,
          refMonth: month,
        );
      }

      if (!shouldGenerate) continue;

      final lastDayOfMonth = DateTime(year, month + 1, 0).day;
      final clampedDay = student.dueDay > lastDayOfMonth
          ? lastDayOfMonth
          : student.dueDay;
      final dueDate = DateTime(year, month, clampedDay);

      final payment = await create(
        studentId: student.id,
        studentName: student.name,
        value: student.value,
        dueDate: dueDate,
        description: period == BillingPeriod.monthly
            ? 'Mensalidade'
            : period.label,
        referenceMonth: referenceMonth,
        createdBy: createdBy,
        planId: student.planId,
        paymentMethodPolicy: student.planId != null
            ? (planPolicies[student.planId] ?? PaymentMethodPolicy.both)
            : PaymentMethodPolicy.both,
      );

      results.add(payment);
      monthCharges.add(payment);
    }

    return results;
  }

  // ============================================
  // Mark Overdue Payments (batch job)
  // ============================================
  Future<int> markOverduePayments({bool sendNotifications = true}) async {
    final result = await Fns.functions
        .httpsCallable('refreshOverdueFinancials')
        .call({'academyId': academyId});
    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : const <String, dynamic>{};
    return (data['updated'] as num?)?.toInt() ?? 0;
  }

  // ============================================
  // Get Monthly Summary
  // ============================================
  Future<Map<String, dynamic>> getMonthlySummary(String referenceMonth) async {
    final payments = await getByMonth(referenceMonth);

    double totalExpected = 0;
    double totalPaid = 0;
    double totalPending = 0;
    double totalOverdue = 0;
    int countPaid = 0;
    int countPending = 0;
    int countOverdue = 0;
    int countCancelled = 0;

    for (final p in payments) {
      // Skip cancelled payments - they don't count for collection rate
      if (p.status == PaymentStatus.cancelled) {
        countCancelled++;
        continue;
      }

      // Cobrança indevida a reembolsar (needsRefund) — nunca soma como
      // receita nem entra no esperado/taxa de cobrança.
      if (p.isOvercharge) continue;

      // Only count active payments (pending, overdue, paid) in expected
      totalExpected += p.value;

      if (p.status == PaymentStatus.paid) {
        totalPaid += p.value;
        countPaid++;
      } else if (p.isOverdue || p.status == PaymentStatus.overdue) {
        totalOverdue += p.value;
        countOverdue++;
      } else if (p.status == PaymentStatus.pending) {
        totalPending += p.value;
        countPending++;
      }
    }

    return {
      'referenceMonth': referenceMonth,
      'totalExpected': totalExpected,
      'paid': {'value': totalPaid, 'count': countPaid},
      'pending': {'value': totalPending, 'count': countPending},
      'overdue': {'value': totalOverdue, 'count': countOverdue},
      'cancelled': countCancelled,
      'collectionRate': totalExpected > 0
          ? (totalPaid / totalExpected * 100)
          : 0,
    };
  }

  // ============================================
  // Get WhatsApp Reminder Link
  // ============================================
  /// [pixCode]/[ticketUrl] são mantidos apenas para compatibilidade com links
  /// manuais antigos. Os lembretes oficiais usam o Pay Link estável do backend.
  String getWhatsAppReminderLink({
    required String phone,
    required String studentName,
    required double amount,
    required DateTime dueDate,
    String? pixCode,
    String? ticketUrl,
  }) {
    final formattedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    final phoneWithCountry = formattedPhone.startsWith('55')
        ? formattedPhone
        : '55$formattedPhone';

    final formattedDate =
        '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}';
    final formattedAmount = 'R\$ ${amount.toStringAsFixed(2)}';

    final hasPix = pixCode != null && pixCode.isNotEmpty;
    final pixBlock = hasPix
        ? 'Pague agora pelo PIX (copia e cola):\n$pixCode\n\n'
              '${(ticketUrl != null && ticketUrl.isNotEmpty) ? 'Ou acesse: $ticketUrl\n\n' : ''}'
        : '';

    final message = Uri.encodeComponent(
      'Olá! Este é um lembrete sobre a mensalidade de $studentName.\n\n'
      'Valor: $formattedAmount\n'
      'Vencimento: $formattedDate\n\n'
      '$pixBlock'
      'Por favor, entre em contato caso tenha alguma dúvida.',
    );

    return 'https://wa.me/$phoneWithCountry?text=$message';
  }
}

class PaymentOperationException implements Exception {
  final String message;

  const PaymentOperationException(this.message);

  @override
  String toString() => message;
}

PaymentOperationException _friendlyPaymentError(
  Object error, {
  required String fallback,
}) {
  if (error is PaymentOperationException) return error;

  String? code;
  String? message;
  if (error is FirebaseFunctionsException) {
    code = error.code;
    message = error.message;
  } else if (error is FnsException) {
    code = error.code;
    message = error.message;
  }

  final normalizedCode = code?.trim().toLowerCase() ?? '';
  final cleanMessage = message?.trim() ?? '';
  if (cleanMessage.isNotEmpty) {
    return PaymentOperationException(cleanMessage);
  }
  if (normalizedCode == 'unavailable' ||
      normalizedCode == 'deadline-exceeded') {
    return const PaymentOperationException(
      'O serviço financeiro está temporariamente indisponível. Tente novamente.',
    );
  }
  if (normalizedCode == 'unauthenticated') {
    return const PaymentOperationException(
      'Sua sessão expirou. Entre novamente para continuar.',
    );
  }
  if (normalizedCode == 'permission-denied') {
    return const PaymentOperationException(
      'Sua conta não tem permissão para realizar esta ação.',
    );
  }
  return PaymentOperationException(fallback);
}

// ============================================
// Factory Function
// ============================================
PaymentService createPaymentService(String academyId) {
  return PaymentService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
PaymentService get paymentService => PaymentService(FirebaseService.academyId);
