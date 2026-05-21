// DTOs do contexto Financial, alinhados 1:1 com api/openapi/financial.yaml.
//
// Inclui Financial + Wallet + WalletTransaction + BillingContact +
// PayIntent + MonthlyReport. Plan vive em plan_dto.dart separado.

// Enums abaixo casam 1:1 com wire format (snake_case) do OpenAPI.
// ignore_for_file: constant_identifier_names

enum ApiBillingType {
  monthly_tuition,
  uniform,
  seminar,
  graduation,
  competition,
  other,
}

extension ApiBillingTypeX on ApiBillingType {
  String get wire => name;
  static ApiBillingType fromWire(String? value) {
    for (final t in ApiBillingType.values) {
      if (t.name == value) return t;
    }
    return ApiBillingType.other;
  }
}

enum ApiFinancialStatus { paid, pending, overdue, cancelled }

extension ApiFinancialStatusX on ApiFinancialStatus {
  String get wire => name;
  static ApiFinancialStatus fromWire(String? value) {
    for (final s in ApiFinancialStatus.values) {
      if (s.name == value) return s;
    }
    return ApiFinancialStatus.pending;
  }
}

enum ApiPaymentMethod { pix, cash, credit_card, bank_transfer, other }

extension ApiPaymentMethodX on ApiPaymentMethod {
  String get wire => name;
  static ApiPaymentMethod fromWire(String? value) {
    if (value == null) return ApiPaymentMethod.other;
    for (final m in ApiPaymentMethod.values) {
      if (m.name == value) return m;
    }
    return ApiPaymentMethod.other;
  }
}

enum ApiWalletTxnKind { credit, debit, refund, payout }

extension ApiWalletTxnKindX on ApiWalletTxnKind {
  String get wire => name;
  static ApiWalletTxnKind fromWire(String? value) {
    for (final k in ApiWalletTxnKind.values) {
      if (k.name == value) return k;
    }
    return ApiWalletTxnKind.credit;
  }
}

enum ApiBillingContactMethod { whatsapp, email, phone, in_person }

extension ApiBillingContactMethodX on ApiBillingContactMethod {
  String get wire => name;
  static ApiBillingContactMethod fromWire(String? value) {
    for (final m in ApiBillingContactMethod.values) {
      if (m.name == value) return m;
    }
    return ApiBillingContactMethod.whatsapp;
  }
}

enum ApiBillingContactResult {
  no_answer,
  promised_payment,
  paid,
  disputed,
  other,
}

extension ApiBillingContactResultX on ApiBillingContactResult {
  String get wire => name;
  static ApiBillingContactResult fromWire(String? value) {
    for (final r in ApiBillingContactResult.values) {
      if (r.name == value) return r;
    }
    return ApiBillingContactResult.other;
  }
}

enum ApiPaymentGateway { asaas, abacatepay }

extension ApiPaymentGatewayX on ApiPaymentGateway {
  String get wire => name;
}

class ApiFinancial {
  const ApiFinancial({
    required this.id,
    required this.academyId,
    required this.studentId,
    required this.type,
    required this.amount,
    required this.dueDate,
    required this.status,
    this.method,
    this.referenceMonth,
    this.receiptUrl,
    this.paymentDate,
    this.asaasPaymentId,
    this.abacatepayTransactionId,
    this.description,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String academyId;
  final String studentId;
  final ApiBillingType type;
  final String amount;
  final DateTime dueDate;
  final ApiFinancialStatus status;
  final ApiPaymentMethod? method;
  final String? referenceMonth;
  final String? receiptUrl;
  final DateTime? paymentDate;
  final String? asaasPaymentId;
  final String? abacatepayTransactionId;
  final String? description;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPaid => status == ApiFinancialStatus.paid;
  bool get isOverdue => status == ApiFinancialStatus.overdue;
  bool get isPending => status == ApiFinancialStatus.pending;

  factory ApiFinancial.fromJson(Map<String, dynamic> j) => ApiFinancial(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        studentId: j['student_id'] as String,
        type: ApiBillingTypeX.fromWire(j['type'] as String?),
        amount: j['amount'] as String,
        dueDate: _parseDate(j['due_date']) ?? DateTime.now(),
        status: ApiFinancialStatusX.fromWire(j['status'] as String?),
        method: j['method'] == null
            ? null
            : ApiPaymentMethodX.fromWire(j['method'] as String?),
        referenceMonth: j['reference_month'] as String?,
        receiptUrl: j['receipt_url'] as String?,
        paymentDate: _parseDate(j['payment_date']),
        asaasPaymentId: j['asaas_payment_id'] as String?,
        abacatepayTransactionId: j['abacatepay_transaction_id'] as String?,
        description: j['description'] as String?,
        createdByUid: j['created_by_uid'] as String?,
        createdAt: _parseDate(j['created_at']),
        updatedAt: _parseDate(j['updated_at']),
      );
}

class FinancialsPage {
  const FinancialsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiFinancial> items;
  final String? nextCursor;
  final bool hasMore;

  factory FinancialsPage.fromJson(Map<String, dynamic> j) => FinancialsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiFinancial.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class FinancialFilter {
  const FinancialFilter({
    this.status,
    this.studentId,
    this.type,
    this.dueFrom,
    this.dueTo,
    this.limit = 50,
    this.cursor,
  });

  final ApiFinancialStatus? status;
  final String? studentId;
  final ApiBillingType? type;
  final DateTime? dueFrom;
  final DateTime? dueTo;
  final int limit;
  final String? cursor;

  Map<String, dynamic> toQueryParameters() {
    final m = <String, dynamic>{'limit': limit};
    if (status != null) m['status'] = status!.wire;
    if (studentId != null) m['student_id'] = studentId;
    if (type != null) m['type'] = type!.wire;
    if (dueFrom != null) m['due_from'] = _formatDate(dueFrom!);
    if (dueTo != null) m['due_to'] = _formatDate(dueTo!);
    if (cursor != null) m['cursor'] = cursor;
    return m;
  }
}

class CreateFinancialRequest {
  const CreateFinancialRequest({
    required this.studentId,
    required this.type,
    required this.amount,
    required this.dueDate,
    this.referenceMonth,
    this.description,
  });

  final String studentId;
  final ApiBillingType type;
  final String amount;
  final DateTime dueDate;
  final String? referenceMonth;
  final String? description;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'student_id': studentId,
      'type': type.wire,
      'amount': amount,
      'due_date': _formatDate(dueDate),
    };
    if (referenceMonth != null) m['reference_month'] = referenceMonth;
    if (description != null) m['description'] = description;
    return m;
  }
}

class UpdateFinancialRequest {
  const UpdateFinancialRequest({
    this.type,
    this.amount,
    this.dueDate,
    this.status,
    this.method,
    this.paymentDate,
    this.referenceMonth,
    this.description,
  });

  final ApiBillingType? type;
  final String? amount;
  final DateTime? dueDate;
  final ApiFinancialStatus? status;
  final ApiPaymentMethod? method;
  final DateTime? paymentDate;
  final String? referenceMonth;
  final String? description;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (type != null) m['type'] = type!.wire;
    if (amount != null) m['amount'] = amount;
    if (dueDate != null) m['due_date'] = _formatDate(dueDate!);
    if (status != null) m['status'] = status!.wire;
    if (method != null) m['method'] = method!.wire;
    if (paymentDate != null) m['payment_date'] = _formatDate(paymentDate!);
    if (referenceMonth != null) m['reference_month'] = referenceMonth;
    if (description != null) m['description'] = description;
    return m;
  }
}

class UpdateFinancialStatusRequest {
  const UpdateFinancialStatusRequest({
    required this.status,
    this.method,
    this.paymentDate,
  });

  final ApiFinancialStatus status;
  final ApiPaymentMethod? method;
  final DateTime? paymentDate;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'status': status.wire};
    if (method != null) m['method'] = method!.wire;
    if (paymentDate != null) {
      m['payment_date'] = paymentDate!.toUtc().toIso8601String();
    }
    return m;
  }
}

class ApiWallet {
  const ApiWallet({
    required this.academyId,
    required this.balance,
    required this.lastUpdatedAt,
    this.availableBalance = '0.00',
    this.pendingBalance = '0.00',
    this.totalReceived = '0.00',
    this.totalWithdrawn = '0.00',
  });

  final String academyId;
  final String balance;
  final String availableBalance;
  final String pendingBalance;
  final String totalReceived;
  final String totalWithdrawn;
  final DateTime lastUpdatedAt;

  factory ApiWallet.fromJson(Map<String, dynamic> j) => ApiWallet(
        academyId: j['academy_id'] as String,
        balance: j['balance'] as String,
        availableBalance: j['available_balance'] as String? ?? '0.00',
        pendingBalance: j['pending_balance'] as String? ?? '0.00',
        totalReceived: j['total_received'] as String? ?? '0.00',
        totalWithdrawn: j['total_withdrawn'] as String? ?? '0.00',
        lastUpdatedAt: _parseDate(j['last_updated_at']) ?? DateTime.now(),
      );
}

class ApiWalletTransaction {
  const ApiWalletTransaction({
    required this.id,
    required this.academyId,
    required this.kind,
    required this.amount,
    required this.createdAt,
    this.financialId,
    this.externalId,
    this.description,
    this.status,
  });

  final String id;
  final String academyId;
  final String? financialId;
  final String? externalId;
  final ApiWalletTxnKind kind;
  final String amount;
  final String? description;
  final String? status; // "settled" | "pending" | "failed"
  final DateTime createdAt;

  factory ApiWalletTransaction.fromJson(Map<String, dynamic> j) =>
      ApiWalletTransaction(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        financialId: j['financial_id'] as String?,
        externalId: j['external_id'] as String?,
        kind: ApiWalletTxnKindX.fromWire(j['kind'] as String?),
        amount: j['amount'] as String,
        description: j['description'] as String?,
        status: j['status'] as String?,
        createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
      );
}

class WalletTransactionsPage {
  const WalletTransactionsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiWalletTransaction> items;
  final String? nextCursor;
  final bool hasMore;

  factory WalletTransactionsPage.fromJson(Map<String, dynamic> j) =>
      WalletTransactionsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiWalletTransaction.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class ApiBillingContact {
  const ApiBillingContact({
    required this.id,
    required this.academyId,
    required this.studentId,
    required this.studentNameSnapshot,
    required this.contactDate,
    required this.method,
    required this.result,
    required this.createdByUid,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String academyId;
  final String studentId;
  final String studentNameSnapshot;
  final DateTime contactDate;
  final ApiBillingContactMethod method;
  final ApiBillingContactResult result;
  final String? notes;
  final String createdByUid;
  final DateTime? createdAt;

  factory ApiBillingContact.fromJson(Map<String, dynamic> j) =>
      ApiBillingContact(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        studentId: j['student_id'] as String,
        studentNameSnapshot: j['student_name_snapshot'] as String,
        contactDate: _parseDate(j['contact_date']) ?? DateTime.now(),
        method: ApiBillingContactMethodX.fromWire(j['method'] as String?),
        result: ApiBillingContactResultX.fromWire(j['result'] as String?),
        notes: j['notes'] as String?,
        createdByUid: j['created_by_uid'] as String,
        createdAt: _parseDate(j['created_at']),
      );
}

class BillingContactsPage {
  const BillingContactsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiBillingContact> items;
  final String? nextCursor;
  final bool hasMore;

  factory BillingContactsPage.fromJson(Map<String, dynamic> j) =>
      BillingContactsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiBillingContact.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class LogBillingContactRequest {
  const LogBillingContactRequest({
    required this.studentId,
    required this.method,
    required this.result,
    this.contactDate,
    this.notes,
  });

  final String studentId;
  final ApiBillingContactMethod method;
  final ApiBillingContactResult result;
  final DateTime? contactDate;
  final String? notes;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'student_id': studentId,
      'method': method.wire,
      'result': result.wire,
    };
    if (contactDate != null) {
      m['contact_date'] = contactDate!.toUtc().toIso8601String();
    }
    if (notes != null) m['notes'] = notes;
    return m;
  }
}

class PayIntentRequest {
  const PayIntentRequest({this.customerName, this.customerEmail, this.gateway});

  final String? customerName;
  final String? customerEmail;
  final ApiPaymentGateway? gateway;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (customerName != null) m['customer_name'] = customerName;
    if (customerEmail != null) m['customer_email'] = customerEmail;
    if (gateway != null) m['gateway'] = gateway!.wire;
    return m;
  }
}

class PayIntentResponse {
  const PayIntentResponse({
    required this.externalId,
    required this.gateway,
    this.receiptUrl,
    this.pixCopyPaste,
    this.pixQrCode,
  });

  final String externalId;
  final ApiPaymentGateway gateway;
  final String? receiptUrl;
  final String? pixCopyPaste;
  final String? pixQrCode;

  bool get hasQrCode => pixQrCode != null && pixQrCode!.isNotEmpty;

  factory PayIntentResponse.fromJson(Map<String, dynamic> j) =>
      PayIntentResponse(
        externalId: j['external_id'] as String,
        gateway: j['gateway'] == 'abacatepay'
            ? ApiPaymentGateway.abacatepay
            : ApiPaymentGateway.asaas,
        receiptUrl: j['receipt_url'] as String?,
        pixCopyPaste: j['pix_copy_paste'] as String?,
        pixQrCode: j['pix_qr_code'] as String?,
      );
}

class GenerateMonthlyResponse {
  const GenerateMonthlyResponse({
    required this.generatedCount,
    required this.referenceMonth,
    this.skippedCount = 0,
  });

  final int generatedCount;
  final int skippedCount;
  final String referenceMonth;

  factory GenerateMonthlyResponse.fromJson(Map<String, dynamic> j) =>
      GenerateMonthlyResponse(
        generatedCount: (j['generated_count'] as num?)?.toInt() ?? 0,
        skippedCount: (j['skipped_count'] as num?)?.toInt() ?? 0,
        referenceMonth: j['reference_month'] as String,
      );
}

class ApiMonthlyReport {
  const ApiMonthlyReport({
    required this.month,
    required this.totalRevenue,
    required this.outstanding,
    required this.overdueCount,
    required this.paidCount,
    required this.pendingCount,
    required this.cancelledCount,
  });

  final String month;
  final String totalRevenue;
  final String outstanding;
  final int overdueCount;
  final int paidCount;
  final int pendingCount;
  final int cancelledCount;

  factory ApiMonthlyReport.fromJson(Map<String, dynamic> j) => ApiMonthlyReport(
        month: j['month'] as String,
        totalRevenue: j['total_revenue'] as String,
        outstanding: j['outstanding'] as String,
        overdueCount: (j['overdue_count'] as num?)?.toInt() ?? 0,
        paidCount: (j['paid_count'] as num?)?.toInt() ?? 0,
        pendingCount: (j['pending_count'] as num?)?.toInt() ?? 0,
        cancelledCount: (j['cancelled_count'] as num?)?.toInt() ?? 0,
      );
}

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
