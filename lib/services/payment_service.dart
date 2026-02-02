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
  /// If [planId] is provided, generates only for students in that specific plan.
  Future<List<Payment>> generateMonthlyTuitions({
    List<({String id, String name, double value, int dueDay})>? students,
    required String referenceMonth,
    String? createdBy,
    String? planId, // Optional: filter to specific plan
  }) async {
    final results = <Payment>[];
    final year = int.parse(referenceMonth.split('-')[0]);
    final month = int.parse(referenceMonth.split('-')[1]);

    // If students not provided, build list from active plans
    List<({String id, String name, double value, int dueDay})> studentList;
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

      // Build a map of student -> plan value (only active students in active plans)
      final studentsWithPlans = <String, ({double value, int dueDay})>{};

      for (final plan in plansToProcess) {
        for (final studentId in plan.studentIds) {
          // Use plan's monthlyValue and defaultDueDay
          studentsWithPlans[studentId] = (
            value: plan.monthlyValue,
            dueDay: plan.defaultDueDay,
          );
        }
      }

      // Fetch student details only for students with plans
      if (studentsWithPlans.isEmpty) {
        return results; // No students with active plans
      }

      final activeStudents = await _collections.students
          .where('status', isEqualTo: 'active')
          .get();

      studentList = activeStudents.docs
          .where((doc) => studentsWithPlans.containsKey(doc.id))
          .map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final planData = studentsWithPlans[doc.id]!;
        return (
          id: doc.id,
          name: data['fullName'] as String? ?? '',
          value: planData.value, // Use plan value, not student's tuitionValue
          dueDay: data['tuitionDay'] as int? ?? planData.dueDay,
        );
      }).where((s) => s.value > 0).toList();
    }

    for (final student in studentList) {
      // Check if payment already exists for this month
      final existing = await getByMonth(referenceMonth, studentId: student.id);
      if (existing.isNotEmpty) continue;

      final dueDate = DateTime(year, month, student.dueDay);

      final payment = await create(
        studentId: student.id,
        studentName: student.name,
        value: student.value,
        dueDate: dueDate,
        description: 'Mensalidade',
        referenceMonth: referenceMonth,
        createdBy: createdBy,
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
