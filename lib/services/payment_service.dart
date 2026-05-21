import '../api/dto/financial_dto.dart' as api;
import '../api/financial_repo.dart';
import 'notification_dispatcher.dart';
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

  Payment withStudentName(String name) => Payment(
        id: id,
        studentId: studentId,
        studentName: name,
        value: value,
        dueDate: dueDate,
        paidAt: paidAt,
        status: status,
        method: method,
        description: description,
        referenceMonth: referenceMonth,
        externalId: externalId,
        pixCode: pixCode,
        pixQrCode: pixQrCode,
        planId: planId,
        createdAt: createdAt,
      );

  /// Adapter `ApiFinancial` (Tatami) → `Payment` (legacy).
  ///
  /// - `studentName` não vem na resposta; passe via parâmetro quando souber.
  /// - `value`: decimal-string → double (0.0 fallback).
  /// - `referenceMonth`: passa direto (formato YYYY-MM).
  /// - `externalId`: prioriza asaas_payment_id → abacatepay_transaction_id.
  /// - `planId` não existe na API Financial; permanece null.
  factory Payment.fromApi(api.ApiFinancial f,
      {String? studentName, String? planId}) {
    return Payment(
      id: f.id,
      studentId: f.studentId,
      studentName: studentName ?? '',
      value: double.tryParse(f.amount) ?? 0.0,
      dueDate: f.dueDate,
      paidAt: f.paymentDate,
      status: _statusFromApi(f.status),
      method: f.method == null ? null : _methodFromApi(f.method!),
      description: f.description,
      referenceMonth: f.referenceMonth,
      externalId: f.asaasPaymentId ?? f.abacatepayTransactionId,
      planId: planId,
      createdAt: f.createdAt ?? DateTime.now(),
    );
  }

  static PaymentStatus _statusFromApi(api.ApiFinancialStatus s) {
    switch (s) {
      case api.ApiFinancialStatus.paid:
        return PaymentStatus.paid;
      case api.ApiFinancialStatus.pending:
        return PaymentStatus.pending;
      case api.ApiFinancialStatus.overdue:
        return PaymentStatus.overdue;
      case api.ApiFinancialStatus.cancelled:
        return PaymentStatus.cancelled;
    }
  }

  static PaymentMethod _methodFromApi(api.ApiPaymentMethod m) {
    switch (m) {
      case api.ApiPaymentMethod.pix:
        return PaymentMethod.pix;
      case api.ApiPaymentMethod.credit_card:
        return PaymentMethod.creditCard;
      case api.ApiPaymentMethod.cash:
        return PaymentMethod.cash;
      case api.ApiPaymentMethod.bank_transfer:
        return PaymentMethod.bankTransfer;
      case api.ApiPaymentMethod.other:
        // legacy não tem `other` — cai em pix (default mais comum)
        return PaymentMethod.pix;
    }
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

/// Helper: converte `PaymentMethod` legacy → `ApiPaymentMethod`.
api.ApiPaymentMethod _toApiMethod(PaymentMethod m) {
  switch (m) {
    case PaymentMethod.pix:
      return api.ApiPaymentMethod.pix;
    case PaymentMethod.creditCard:
      return api.ApiPaymentMethod.credit_card;
    case PaymentMethod.debitCard:
      // debit_card não existe no enum da API — mapeamos para `other`
      return api.ApiPaymentMethod.other;
    case PaymentMethod.cash:
      return api.ApiPaymentMethod.cash;
    case PaymentMethod.bankTransfer:
      return api.ApiPaymentMethod.bank_transfer;
  }
}

/// Helper: converte string de tipo (legacy) → `ApiBillingType`.
api.ApiBillingType _toApiType(String type) {
  switch (type) {
    case 'monthly_tuition':
      return api.ApiBillingType.monthly_tuition;
    case 'uniform':
      return api.ApiBillingType.uniform;
    case 'seminar':
      return api.ApiBillingType.seminar;
    case 'graduation':
      return api.ApiBillingType.graduation;
    case 'competition':
      return api.ApiBillingType.competition;
    default:
      return api.ApiBillingType.other;
  }
}

/// Payment Service - Multi-tenant payment management via Tatami HTTP API.
///
/// Todos os métodos delegam para [FinancialRemoteRepo]; não há mais acesso
/// direto ao Firestore neste serviço.
///
/// Mudanças de assinatura vs. versão Firestore:
/// - `streamByStudent` / `streamStatsByStudent`: convertidos para `Future`
///   (HTTP não suporta streams nativos). Callers já migraram para
///   `tatamiPaymentsLegacyProvider` / `studentPaymentStatsProvider` em
///   `student_provider.dart` — estes métodos existem apenas para
///   compatibilidade residual.
/// - `generateMonthlyTuitions`: delega para `POST /financials/generate-monthly`
///   no backend; retorna lista vazia (o backend é a fonte de verdade).
/// - `markOverduePayments`: no-op — o backend gerencia transições automáticas.
class PaymentService {
  final String academyId;
  final FinancialRemoteRepo _repo;
  late final NotificationDispatcher _notificationDispatcher;
  late final StudentService _studentService;

  PaymentService(this.academyId, {required FinancialRemoteRepo repo})
      : _repo = repo {
    _notificationDispatcher = NotificationDispatcher(academyId);
    _studentService = StudentService(academyId);
  }

  // ============================================
  // Get Payments by Student (One-time fetch)
  // ============================================
  Future<List<Payment>> getByStudent(String studentId, {int? limit}) async {
    final page = await _repo.list(
      academyId,
      filter: api.FinancialFilter(
        studentId: studentId,
        limit: limit ?? 200,
      ),
    );
    var payments = page.items.map(Payment.fromApi).toList();
    payments.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return payments;
  }

  // ============================================
  // Stream Payments by Student (legacy compat — HTTP polling stub)
  //
  // HTTP não suporta streams nativos. Este stub emite os dados como
  // Future e fecha o stream logo em seguida. Callers em
  // student_provider.dart já foram migrados para
  // tatamiPaymentsLegacyProvider — este método existe apenas para
  // retrocompatibilidade de eventuais callers não migrados.
  // ============================================
  Stream<List<Payment>> streamByStudent(String studentId) {
    return Stream.fromFuture(getByStudent(studentId));
  }

  // ============================================
  // Stream Payment Stats by Student (legacy compat — HTTP polling stub)
  // ============================================
  Stream<Map<String, dynamic>> streamStatsByStudent(String studentId) {
    return Stream.fromFuture(getStatsByStudent(studentId));
  }

  // ============================================
  // Get Pending Payments by Student
  // ============================================
  Future<List<Payment>> getPendingByStudent(String studentId) async {
    final page = await _repo.list(
      academyId,
      filter: api.FinancialFilter(
        studentId: studentId,
        status: api.ApiFinancialStatus.pending,
        limit: 200,
      ),
    );
    var payments = page.items.map(Payment.fromApi).toList();
    // also include overdue
    final overdueItems = await _repo.list(
      academyId,
      filter: api.FinancialFilter(
        studentId: studentId,
        status: api.ApiFinancialStatus.overdue,
        limit: 200,
      ),
    );
    payments.addAll(overdueItems.items.map(Payment.fromApi));
    payments.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return payments;
  }

  // ============================================
  // Get Overdue Payments by Student
  // ============================================
  Future<List<Payment>> getOverdueByStudent(String studentId) async {
    final page = await _repo.list(
      academyId,
      filter: api.FinancialFilter(
        studentId: studentId,
        status: api.ApiFinancialStatus.overdue,
        limit: 200,
      ),
    );
    final payments = page.items.map(Payment.fromApi).toList();
    payments.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return payments;
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
    try {
      final dto = await _repo.getById(academyId, id);
      return Payment.fromApi(dto);
    } catch (_) {
      return null;
    }
  }

  // ============================================
  // Get Payments by Reference Month
  // ============================================
  Future<List<Payment>> getByMonth(String referenceMonth,
      {String? studentId}) async {
    // O endpoint /financials usa reference_month como filtro.
    // FinancialFilter não tem referenceMonth direto — filtramos pelo mês
    // via due_from / due_to do mês.
    final parts = referenceMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final from = DateTime(year, month, 1);
    final to = DateTime(year, month + 1, 0); // último dia do mês

    final page = await _repo.list(
      academyId,
      filter: api.FinancialFilter(
        studentId: studentId,
        dueFrom: from,
        dueTo: to,
        limit: 200,
      ),
    );
    var payments = page.items
        .map(Payment.fromApi)
        .where((p) => p.referenceMonth == referenceMonth)
        .toList();
    payments.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return payments;
  }

  // ============================================
  // Get Payment Summary (all students)
  // ============================================
  Future<Map<String, dynamic>> getSummary() async {
    final report = await _repo.getMonthlyReport(academyId);
    final totalRevenue = double.tryParse(report.totalRevenue) ?? 0.0;
    final outstanding = double.tryParse(report.outstanding) ?? 0.0;

    return {
      'pending': {'count': report.pendingCount, 'value': outstanding},
      'overdue': {'count': report.overdueCount, 'value': 0.0},
      'paid': {'count': report.paidCount, 'value': totalRevenue},
    };
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Create Payment → POST /financials
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
    final dto = await _repo.create(
      academyId,
      api.CreateFinancialRequest(
        studentId: studentId,
        type: _toApiType(type),
        amount: value.toStringAsFixed(2),
        dueDate: dueDate,
        referenceMonth: referenceMonth,
        description: description ?? 'Mensalidade',
      ),
    );

    final payment = Payment.fromApi(dto, studentName: studentName);

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
        // ignore notification errors
      }
    }

    return payment;
  }

  // ============================================
  // Update Payment → PATCH /financials/{id}
  // ============================================
  Future<Payment> update(String id, Map<String, dynamic> data) async {
    final dto = await _repo.update(
      academyId,
      id,
      api.UpdateFinancialRequest(
        amount: data['amount'] != null
            ? (data['amount'] as num).toDouble().toStringAsFixed(2)
            : null,
        dueDate: data['dueDate'] is DateTime
            ? data['dueDate'] as DateTime
            : null,
        description: data['description'] as String?,
        referenceMonth: data['referenceMonth'] as String?,
      ),
    );
    return Payment.fromApi(dto);
  }

  // ============================================
  // Mark as Paid → PATCH /financials/{id}/status
  // ============================================
  Future<Payment> markAsPaid(
    String id, {
    PaymentMethod method = PaymentMethod.pix,
    DateTime? paymentDate,
  }) async {
    final dto = await _repo.updateStatus(
      academyId,
      id,
      api.UpdateFinancialStatusRequest(
        status: api.ApiFinancialStatus.paid,
        method: _toApiMethod(method),
        paymentDate: paymentDate ?? DateTime.now(),
      ),
    );
    return Payment.fromApi(dto);
  }

  // ============================================
  // Cancel Payment → PATCH /financials/{id}/status
  // ============================================
  Future<Payment> cancel(String id) async {
    final dto = await _repo.updateStatus(
      academyId,
      id,
      const api.UpdateFinancialStatusRequest(
        status: api.ApiFinancialStatus.cancelled,
      ),
    );
    return Payment.fromApi(dto);
  }

  // ============================================
  // Reactivate Cancelled Payment → PATCH /financials/{id}/status
  //
  // O backend decide o status correto (pending vs overdue) via regra
  // de negócio própria. Enviamos sempre `pending` — o backend pode
  // retornar `overdue` se a due_date já passou.
  // ============================================
  Future<Payment> reactivate(String id) async {
    final dto = await _repo.updateStatus(
      academyId,
      id,
      const api.UpdateFinancialStatusRequest(
        status: api.ApiFinancialStatus.pending,
      ),
    );
    return Payment.fromApi(dto);
  }

  // ============================================
  // Delete Payment → DELETE /financials/{id}
  // ============================================
  Future<void> delete(String id) async {
    await _repo.delete(academyId, id);
  }

  // ============================================
  // Get Pending Payments (all students)
  // ============================================
  Future<List<Payment>> getPending() async {
    final page = await _repo.list(
      academyId,
      filter: const api.FinancialFilter(
        status: api.ApiFinancialStatus.pending,
        limit: 200,
      ),
    );
    var payments = page.items.map(Payment.fromApi).toList();
    payments.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return payments;
  }

  // ============================================
  // Get Overdue Payments (all students)
  // ============================================
  Future<List<Payment>> getOverdue() async {
    final page = await _repo.list(
      academyId,
      filter: const api.FinancialFilter(
        status: api.ApiFinancialStatus.overdue,
        limit: 200,
      ),
    );
    var payments = page.items.map(Payment.fromApi).toList();
    payments.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return payments;
  }

  // ============================================
  // Get Paid This Month
  // ============================================
  Future<List<Payment>> getPaidThisMonth() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0);

    final page = await _repo.list(
      academyId,
      filter: api.FinancialFilter(
        status: api.ApiFinancialStatus.paid,
        dueFrom: from,
        dueTo: to,
        limit: 200,
      ),
    );
    var payments = page.items.map(Payment.fromApi).toList();
    payments.sort((a, b) => b.paidAt != null && a.paidAt != null
        ? b.paidAt!.compareTo(a.paidAt!)
        : 0);
    return payments;
  }

  // ============================================
  // Generate Monthly Tuitions
  //
  // Delega inteiramente ao backend via POST /financials/generate-monthly.
  // O backend é a fonte de verdade para a geração idempotente de
  // mensalidades — lógica de enumeração de planos/alunos foi removida
  // do cliente.
  //
  // Retorna lista vazia por compatibilidade de assinatura; use
  // GenerateMonthlyResponse via FinancialRemoteRepo.generateMonthly
  // diretamente quando precisar dos contadores.
  // ============================================
  Future<List<Payment>> generateMonthlyTuitions({
    List<({String id, String name, double value, int dueDay, String? planId})>?
        students,
    required String referenceMonth,
    String? createdBy,
    String? planId,
  }) async {
    await _repo.generateMonthly(academyId, referenceMonth);
    return const [];
  }

  // ============================================
  // Mark Overdue Payments (no-op)
  //
  // O backend gerencia transições automáticas de pending → overdue
  // via cron job. Este método é mantido por compatibilidade de
  // assinatura; nenhuma chamada HTTP é feita.
  // ============================================
  Future<int> markOverduePayments({bool sendNotifications = true}) async {
    // TODO(tatami): no-op — backend gerencia transições automáticas.
    return 0;
  }

  // ============================================
  // Get Monthly Summary
  // ============================================
  Future<Map<String, dynamic>> getMonthlySummary(
      String referenceMonth) async {
    final report =
        await _repo.getMonthlyReport(academyId, month: referenceMonth);
    final totalRevenue = double.tryParse(report.totalRevenue) ?? 0.0;
    final outstanding = double.tryParse(report.outstanding) ?? 0.0;
    final totalExpected = totalRevenue + outstanding;

    return {
      'referenceMonth': referenceMonth,
      'totalExpected': totalExpected,
      'paid': {'value': totalRevenue, 'count': report.paidCount},
      'pending': {'value': outstanding, 'count': report.pendingCount},
      'overdue': {'value': 0.0, 'count': report.overdueCount},
      'cancelled': report.cancelledCount,
      'collectionRate':
          totalExpected > 0 ? (totalRevenue / totalExpected * 100) : 0,
    };
  }

  // ============================================
  // Get WhatsApp Reminder Link (pure helper — não acessa rede)
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
PaymentService createPaymentService(String academyId,
    {required FinancialRemoteRepo repo}) {
  return PaymentService(academyId, repo: repo);
}

// O getter paymentService foi removido: PaymentService agora requer
// FinancialRemoteRepo injetado. Use PaymentService(academyId, repo: repo)
// ou acesse via financialRepoProvider + tatamiPaymentsLegacyProvider.
