import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';
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
  final String? pixCode;
  final String? pixQrCode;
  final String? planId;
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
    this.pixCode,
    this.pixQrCode,
    this.planId,
    required this.createdAt,
  });

  factory Payment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
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
      pixCode: data['pixCode'],
      pixQrCode: data['pixQrCode'],
      planId: data['planId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Computed properties
  bool get isPaid => status == PaymentStatus.paid;
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
      var payments = snapshot.docs.map((doc) => Payment.fromFirestore(doc)).toList();
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
        .where((p) => p.status == PaymentStatus.pending || p.status == PaymentStatus.overdue)
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
  Future<List<Payment>> getByMonth(String referenceMonth, {String? studentId}) async {
    Query query = _paymentsRef.where('referenceMonth', isEqualTo: referenceMonth);

    if (studentId != null) {
      query = query.where('studentId', isEqualTo: studentId);
    }

    final snapshot = await query.get();
    var payments = snapshot.docs.map((doc) => Payment.fromFirestore(doc)).toList();
    payments.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return payments;
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
    bool sendNotification = true,
  }) async {
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
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    });

    final doc = await docRef.get();
    final payment = Payment.fromFirestore(doc);

    // Send notification to student if they have a linked account
    if (sendNotification && type == 'monthly_tuition') {
      try {
        final student = await _studentService.getById(studentId);
        if (student != null && student.linkedUserId != null) {
          await _notificationDispatcher.notifyNewTuition(
            userId: student.linkedUserId!,
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

  // ============================================
  // Update Payment
  // ============================================
  Future<Payment> update(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _paymentsRef.doc(id).update(data);
    final doc = await _paymentsRef.doc(id).get();
    return Payment.fromFirestore(doc);
  }

  // ============================================
  // Mark as Paid
  // ============================================
  Future<Payment> markAsPaid(
    String id, {
    PaymentMethod method = PaymentMethod.pix,
    DateTime? paymentDate,
  }) async {
    final paidAt = paymentDate ?? DateTime.now();
    return update(id, {
      'status': PaymentStatus.paid.value,
      'method': method.value,
      'paymentDate': Timestamp.fromDate(paidAt),
    });
  }

  // ============================================
  // Cancel Payment
  // ============================================
  Future<Payment> cancel(String id) async {
    return update(id, {
      'status': PaymentStatus.cancelled.value,
    });
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
    final dueDate = DateTime(payment.dueDate.year, payment.dueDate.month, payment.dueDate.day);

    final newStatus = dueDate.isBefore(todayStart)
        ? PaymentStatus.overdue
        : PaymentStatus.pending;

    return update(id, {
      'status': newStatus.value,
    });
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
        .where((p) =>
            p.status == PaymentStatus.paid &&
            p.paidAt != null &&
            p.paidAt!.isAfter(startOfMonth) &&
            p.paidAt!.isBefore(endOfMonth))
        .toList();
    payments.sort((a, b) => b.paidAt!.compareTo(a.paidAt!));
    return payments;
  }

  // ============================================
  // Generate Monthly Tuitions
  // ============================================
  /// Generates monthly tuitions ONLY for students enrolled in active plans.
  /// Uses the plan's monthlyValue (not the student's tuitionValue field).
  /// One tuition is generated per student per plan.
  /// If [planId] is provided, generates only for students in that specific plan.
  Future<List<Payment>> generateMonthlyTuitions({
    List<({String id, String name, double value, int dueDay, String? planId})>? students,
    required String referenceMonth,
    String? createdBy,
    String? planId, // Optional: filter to specific plan
  }) async {
    final results = <Payment>[];
    final year = int.parse(referenceMonth.split('-')[0]);
    final month = int.parse(referenceMonth.split('-')[1]);

    // If students not provided, build list from active plans
    List<({String id, String name, double value, int dueDay, String? planId})> studentList;
    if (students != null) {
      studentList = students;
    } else {
      // Get only students enrolled in active plans with the correct plan value
      final planService = PlanService(academyId);
      List<Plan> plansToProcess;

      if (planId != null) {
        // Filter to specific plan
        final plan = await planService.getById(planId);
        plansToProcess = plan != null && plan.isActive ? [plan] : [];
      } else {
        // All active plans
        plansToProcess = await planService.getActive();
      }

      // Build a list of (studentId, planId, value, dueDay) entries.
      // A student can appear multiple times — once per plan.
      final entries = <({String studentId, String planId, double value, int dueDay})>[];

      for (final plan in plansToProcess) {
        for (final studentId in plan.studentIds) {
          entries.add((
            studentId: studentId,
            planId: plan.id,
            value: plan.getStudentValue(studentId),
            dueDay: plan.getStudentDueDay(studentId),
          ));
        }
      }

      // Fetch student details only for students with plans
      if (entries.isEmpty) {
        return results; // No students with active plans
      }

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
        );
      }).where((s) => s.value > 0).toList();
    }

    for (final student in studentList) {
      // Check if payment already exists for this student+plan+month
      // IMPORTANT: Filter out cancelled payments - they don't count as "existing"
      final existing = await getByMonth(referenceMonth, studentId: student.id);

      // Exclude cancelled payments from the check
      final activeExisting = existing.where((p) => p.status != PaymentStatus.cancelled).toList();

      if (student.planId != null) {
        // Skip if an ACTIVE payment with this planId already exists
        if (activeExisting.any((p) => p.planId == student.planId)) continue;
      } else {
        // Fallback for legacy entries without planId: skip if any ACTIVE payment exists
        if (activeExisting.any((p) => p.planId == null)) continue;
      }

      // Clamp to last day of month (e.g., day 31 in February → Feb 28/29)
      final lastDayOfMonth = DateTime(year, month + 1, 0).day;
      final clampedDay = student.dueDay > lastDayOfMonth ? lastDayOfMonth : student.dueDay;
      final dueDate = DateTime(year, month, clampedDay);

      final payment = await create(
        studentId: student.id,
        studentName: student.name,
        value: student.value,
        dueDate: dueDate,
        description: 'Mensalidade',
        referenceMonth: referenceMonth,
        createdBy: createdBy,
        planId: student.planId,
      );

      results.add(payment);
    }

    return results;
  }

  // ============================================
  // Mark Overdue Payments (batch job)
  // ============================================
  Future<int> markOverduePayments({bool sendNotifications = true}) async {
    final snapshot = await _paymentsRef.get();
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
            if (student != null && student.linkedUserId != null) {
              await _notificationDispatcher.notifyOverdueTuition(
                userId: student.linkedUserId!,
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
      'collectionRate': totalExpected > 0 ? (totalPaid / totalExpected * 100) : 0,
    };
  }

  // ============================================
  // Get WhatsApp Reminder Link
  // ============================================
  String getWhatsAppReminderLink({
    required String phone,
    required String studentName,
    required double amount,
    required DateTime dueDate,
  }) {
    final formattedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    final phoneWithCountry = formattedPhone.startsWith('55')
        ? formattedPhone
        : '55$formattedPhone';

    final formattedDate =
        '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}';
    final formattedAmount = 'R\$ ${amount.toStringAsFixed(2)}';

    final message = Uri.encodeComponent(
      'Olá! Este é um lembrete sobre a mensalidade de $studentName.\n\n'
      'Valor: $formattedAmount\n'
      'Vencimento: $formattedDate\n\n'
      'Por favor, entre em contato caso tenha alguma dúvida.',
    );

    return 'https://wa.me/$phoneWithCountry?text=$message';
  }
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
