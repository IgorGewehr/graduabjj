import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'fns.dart';

import 'firebase_service.dart';
import 'mercado_pago_service.dart';
import 'notification_dispatcher.dart';
import 'plan_service.dart';
import 'student_service.dart';

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

/// Payment Service - Multi-tenant payment management
class PaymentService {
  final String academyId;
  late final Collections _collections;
  late final NotificationDispatcher _notificationDispatcher;
  late final StudentService _studentService;

  PaymentService(this.academyId) {
    _collections = Collections(academyId);
    _notificationDispatcher = NotificationDispatcher(academyId);
    _studentService = StudentService(academyId);
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
    final docRef = await _paymentsRef.add({
      'academyId': academyId,
      'studentId': studentId,
      'studentName': studentName,
      'amount': value,
      'type': type,
      'dueDate': Timestamp.fromDate(dueDate),
      'status': PaymentStatus.pending.value,
      'description': description ?? 'Mensalidade',
      'referenceMonth': referenceMonth,
      'planId': planId,
      'paymentMethodPolicy': paymentMethodPolicy.value,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      if (isPrivateLesson) ...{
        'lessonDate': Timestamp.fromDate(lessonDate ?? dueDate),
        'lessonWeight': lessonWeight ?? 1.0,
        'lessonSport': lessonSport ?? 'bjj',
        'instructorId': instructorId,
        'instructorName': instructorName,
        // O backend vira true ao conceder a presença (grantPrivateLessonAttendance).
        'attendanceGranted': false,
      },
    });

    final doc = await docRef.get();
    final payment = Payment.fromFirestore(doc);

    // Send notification to student if they have a linked account
    if (sendNotification && (type == 'monthly_tuition' || isPrivateLesson)) {
      try {
        final student = await _studentService.getById(studentId);
        // Route to the responsible adult (kids) when set, else the student's
        // own account.
        final notifyUserId =
            student?.responsibleUserId ?? student?.linkedUserId;
        if (student != null && notifyUserId != null) {
          await _notificationDispatcher.notifyNewTuition(
            userId: notifyUserId,
            studentName: studentName,
            amount: (value * 100).toInt(), // Convert to cents
            dueDate: dueDate,
            financialId: payment.id,
          );
        }
      } catch (e) {
        print('Failed to send new tuition notification: $e');
      }
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

  // ============================================
  // Update Payment
  // ============================================
  Future<Payment> update(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _paymentsRef.doc(id).update(data);
    final doc = await _paymentsRef.doc(id).get();
    return Payment.fromFirestore(doc);
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

    final current = await getById(id);
    if (current == null) throw StateError('Pagamento nao encontrado');
    if (current.status == PaymentStatus.paid) {
      throw StateError('Pagamentos ja quitados nao podem ser editados');
    }

    String? gatewayPaymentId = current.gatewayPaymentId;
    final paymentGateway = current.paymentGateway;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final dueStart = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final status = dueStart.isBefore(todayStart)
        ? PaymentStatus.overdue
        : PaymentStatus.pending;

    final updated = await update(id, {
      'amount': value,
      'dueDate': Timestamp.fromDate(dueDate),
      'status': status.value,
      'gatewayPaymentId': FieldValue.delete(),
      'pixCode': FieldValue.delete(),
      'pixQrCode': FieldValue.delete(),
      'pixTicketUrl': FieldValue.delete(),
      'pixExpiresAt': FieldValue.delete(),
      'lastReminderStage': FieldValue.delete(),
      'lastReminderAt': FieldValue.delete(),
      'lastDueSoonStage': FieldValue.delete(),
      'lastDueSoonAt': FieldValue.delete(),
    });

    if (gatewayPaymentId != null &&
        gatewayPaymentId.isNotEmpty &&
        paymentGateway == 'mercadopago') {
      try {
        await Fns.functions.httpsCallable('cancelMpPix').call({
          'academyId': academyId,
          'paymentId': gatewayPaymentId,
        });
      } catch (e) {
        print('[PaymentService] cancelMpPix on terms edit failed: $e');
      }
    }
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
    final paidAt = paymentDate ?? DateTime.now();

    // Read the live gateway payment id BEFORE we strip the pix fields, so we
    // can best-effort cancel the open MP PIX (otherwise the already-sent link
    // stays payable -> double payment).
    String? gatewayPaymentId;
    String? paymentGateway;
    try {
      final snap = await _paymentsRef.doc(id).get();
      final data = snap.data() as Map<String, dynamic>?;
      gatewayPaymentId = data?['gatewayPaymentId'] as String?;
      paymentGateway = data?['paymentGateway'] as String?;
    } catch (_) {
      // non-fatal: proceed with the mark-paid regardless
    }

    final payment = await update(id, {
      'status': PaymentStatus.paid.value,
      'method': method.value,
      // Offline mark-paid has no settling gateway integration — tag it 'manual'
      // (canonical field, read by the Payment model). The pre-read above still
      // holds the prior gateway/charge id for the PIX cancellation below.
      'paymentGateway': 'manual',
      // Auditoria MP (double-charge silencioso): apaga o gatewayPaymentId do PIX
      // original. Se o cancelMpPix abaixo falhar (best-effort) e a família pagar
      // o PIX ainda em aberto depois, o webhook NÃO pode achar o doc 'paid' com
      // o MESMO charge id e tratar como no-op idempotente — sem o id, o settle
      // (server_functions.js:5783/5793) cai no caminho de duplicidade/conciliação
      // e alerta o admin para reembolsar, em vez de creditar 2x em silêncio.
      'gatewayPaymentId': FieldValue.delete(),
      'paymentDate': Timestamp.fromDate(paidAt),
      // Kill the live PIX on the doc (mirrors mpMktSettle): an admin marking
      // the charge paid offline must invalidate the already-sent code.
      'pixCode': FieldValue.delete(),
      'pixQrCode': FieldValue.delete(),
      'pixTicketUrl': FieldValue.delete(),
      'pixExpiresAt': FieldValue.delete(),
    });

    // Best-effort: cancel the open MP PIX so it can no longer be paid. Never
    // block the mark-paid if cancellation fails.
    if (gatewayPaymentId != null &&
        gatewayPaymentId.isNotEmpty &&
        paymentGateway == 'mercadopago') {
      try {
        await Fns.functions.httpsCallable('cancelMpPix').call({
          'academyId': academyId,
          'paymentId': gatewayPaymentId,
        });
      } catch (e) {
        print('[PaymentService] cancelMpPix failed (non-fatal): $e');
      }
    }

    return payment;
  }

  // ============================================
  // Cancel Payment
  // ============================================
  Future<Payment> cancel(String id) async {
    // Auditoria MP (cobrança fantasma): cancelar NÃO pode deixar o PIX vivo
    // pagável — senão a família paga uma cobrança que o admin deu por cancelada.
    // Espelha markAsPaid: pré-lê o gatewayPaymentId ANTES de apagar os campos
    // pix, invalida o PIX no doc e cancela o PIX no MP (best-effort).
    // (Assinatura recorrente é cancelada por ação própria — UI de assinatura —,
    // não por cancelar uma cobrança avulsa do mês.)
    String? gatewayPaymentId;
    String? paymentGateway;
    try {
      final snap = await _paymentsRef.doc(id).get();
      final data = snap.data() as Map<String, dynamic>?;
      gatewayPaymentId = data?['gatewayPaymentId'] as String?;
      paymentGateway = data?['paymentGateway'] as String?;
    } catch (_) {
      // non-fatal: segue o cancel mesmo assim.
    }

    final payment = await update(id, {
      'status': PaymentStatus.cancelled.value,
      'gatewayPaymentId': FieldValue.delete(),
      'pixCode': FieldValue.delete(),
      'pixQrCode': FieldValue.delete(),
      'pixTicketUrl': FieldValue.delete(),
      'pixExpiresAt': FieldValue.delete(),
    });

    if (gatewayPaymentId != null &&
        gatewayPaymentId.isNotEmpty &&
        paymentGateway == 'mercadopago') {
      try {
        await Fns.functions.httpsCallable('cancelMpPix').call({
          'academyId': academyId,
          'paymentId': gatewayPaymentId,
        });
      } catch (e) {
        print('[PaymentService] cancelMpPix on cancel failed (non-fatal): $e');
      }
    }

    return payment;
  }

  // ============================================
  // Reactivate Cancelled Payment
  // ============================================
  Future<Payment> reactivate(String id) async {
    final payment = await getById(id);
    if (payment == null) {
      throw Exception('Payment not found');
    }

    // Determine new status based on due date
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final dueDate = DateTime(
      payment.dueDate.year,
      payment.dueDate.month,
      payment.dueDate.day,
    );

    final newStatus = dueDate.isBefore(todayStart)
        ? PaymentStatus.overdue
        : PaymentStatus.pending;

    return update(id, {'status': newStatus.value});
  }

  // ============================================
  // Delete Payment
  // ============================================
  Future<void> delete(String id) async {
    await _paymentsRef.doc(id).delete();
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
      List<Plan> plansToProcess;

      if (planId != null) {
        final plan = await planService.getById(planId);
        plansToProcess = plan != null && plan.isActive ? [plan] : [];
      } else {
        plansToProcess = await planService.getActive();
      }

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

      for (final plan in plansToProcess) {
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

      studentList = entries
          .where((e) => activeStudentMap.containsKey(e.studentId))
          .map((e) {
            final data = activeStudentMap[e.studentId]!;
            return (
              id: e.studentId,
              name: data['fullName'] as String? ?? '',
              value: e.value,
              dueDay: data['tuitionDay'] as int? ?? e.dueDay,
              planId: e.planId as String?,
              billingPeriod: e.billingPeriod,
            );
          })
          .where((s) => s.value > 0)
          .toList();
    }

    // Prefetch this month's charges ONCE for the monthly-plan dedup, instead of
    // one Firestore query per student (the N+1 that made bulk generation hang).
    // Non-monthly plans still use the per-student period check below.
    final monthCharges = (await getByMonth(
      referenceMonth,
    )).where((p) => p.status != PaymentStatus.cancelled).toList();

    for (final student in studentList) {
      final period = student.billingPeriod;
      bool shouldGenerate;

      if (period == BillingPeriod.monthly) {
        // Skip if an active charge already exists this month for this student
        // (matched against the plan, mirroring the prior per-student query).
        final activeExisting = monthCharges
            .where((p) => p.studentId == student.id)
            .toList();
        if (student.planId != null) {
          shouldGenerate = !activeExisting.any(
            (p) => p.planId == student.planId,
          );
        } else {
          shouldGenerate = !activeExisting.any((p) => p.planId == null);
        }
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
    }

    return results;
  }

  // ============================================
  // Mark Overdue Payments (batch job)
  // ============================================
  Future<int> markOverduePayments({bool sendNotifications = true}) async {
    // Only scan pending payments server-side (single-field index, auto-created)
    // instead of reading the whole payments history. Overdue is then derived in
    // memory from dueDate. Cuts this from a full-collection scan to just the
    // open charges — the dominant cost when opening the financial screen.
    final snapshot = await _paymentsRef
        .where('status', isEqualTo: PaymentStatus.pending.value)
        .get();
    int count = 0;

    for (final doc in snapshot.docs) {
      final payment = Payment.fromFirestore(doc);
      if (payment.status == PaymentStatus.pending && payment.isOverdue) {
        await doc.reference.update({
          'status': PaymentStatus.overdue.value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        count++;

        // Send overdue notification to student
        if (sendNotifications) {
          try {
            final student = await _studentService.getById(payment.studentId);
            final notifyUserId =
                student?.responsibleUserId ?? student?.linkedUserId;
            if (student != null && notifyUserId != null) {
              await _notificationDispatcher.notifyOverdueTuition(
                userId: notifyUserId,
                studentName: payment.studentName,
                amount: (payment.value * 100).toInt(),
                daysOverdue: payment.daysOverdue,
                financialId: payment.id,
              );
            }
          } catch (e) {
            print('Failed to send overdue notification: $e');
          }
        }
      }
    }

    return count;
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
  /// [pixCode]/[ticketUrl] are optional — when present (MP conectado e PIX
  /// gerado com sucesso), o lembrete manual ganha o mesmo copia-e-cola/link
  /// que o canal automático de cobrança já anexa (ver
  /// [generateReminderPix] e BillingNotificationService.injectPaymentInfo).
  /// Sem eles (default), a mensagem sai IDÊNTICA à de antes — assinatura
  /// compatível com todo caller existente.
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

  // ============================================
  // Best-effort PIX for the manual WhatsApp reminder
  // ============================================
  /// Mirrors BillingNotificationService.ensureValidPixForFinancial (o canal
  /// de cobrança automático) para o lembrete manual desta tela. NUNCA lança —
  /// qualquer falha (MP desconectado, erro de rede, CF) retorna vazio e o
  /// lembrete manual segue sem link, como antes.
  Future<({String pixCode, String ticketUrl})> generateReminderPix({
    required String financialId,
    required String studentId,
    required String studentName,
    required double amount,
    String? cpf,
  }) async {
    try {
      final mp = MercadoPagoService(academyId);
      if (!await mp.isEnabled()) return (pixCode: '', ticketUrl: '');
      final link = await mp.createPixPayment(
        amount: amount,
        financialId: financialId,
        studentId: studentId,
        studentName: studentName,
        cpf: cpf,
      );
      if (link == null) return (pixCode: '', ticketUrl: '');
      return (pixCode: link.pixCode, ticketUrl: link.ticketUrl ?? '');
    } catch (_) {
      return (pixCode: '', ticketUrl: '');
    }
  }
}

class PaymentOperationException implements Exception {
  final String message;

  const PaymentOperationException(this.message);

  @override
  String toString() => message;
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
