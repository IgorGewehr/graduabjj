import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

import '../core/validators.dart';
import '../models/billing_payment_preference.dart';
import 'firebase_service.dart';
import 'fns.dart';

/// Contact type for billing reminders
enum ContactType { whatsapp, phone, email, inPerson, other }

extension ContactTypeExtension on ContactType {
  String get value {
    switch (this) {
      case ContactType.whatsapp:
        return 'whatsapp';
      case ContactType.phone:
        return 'phone';
      case ContactType.email:
        return 'email';
      case ContactType.inPerson:
        return 'in_person';
      case ContactType.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case ContactType.whatsapp:
        return 'WhatsApp';
      case ContactType.phone:
        return 'Telefone';
      case ContactType.email:
        return 'E-mail';
      case ContactType.inPerson:
        return 'Presencial';
      case ContactType.other:
        return 'Outro';
    }
  }

  static ContactType fromString(String value) {
    switch (value) {
      case 'whatsapp':
        return ContactType.whatsapp;
      case 'phone':
        return ContactType.phone;
      case 'email':
        return ContactType.email;
      case 'in_person':
        return ContactType.inPerson;
      default:
        return ContactType.other;
    }
  }
}

/// Billing stage enum.
///
/// Matches marcusjj's BillingStage union (`'D+0' | 'D+1' | 'D+3' | 'D+7' |
/// 'D+15' | 'D+30'`). `d0` is the "due-today" courtesy reminder; the others
/// fire after vencimento.
enum BillingStage { created, upcoming, d0, d1, d3, d7, d15, d30 }

extension BillingStageExtension on BillingStage {
  String get label {
    switch (this) {
      case BillingStage.created:
        return 'CREATED';
      case BillingStage.upcoming:
        return 'UPCOMING';
      case BillingStage.d0:
        return 'D+0';
      case BillingStage.d1:
        return 'D+1';
      case BillingStage.d3:
        return 'D+3';
      case BillingStage.d7:
        return 'D+7';
      case BillingStage.d15:
        return 'D+15';
      case BillingStage.d30:
        return 'D+30+';
    }
  }

  String get value {
    switch (this) {
      case BillingStage.created:
        return 'CREATED';
      case BillingStage.upcoming:
        return 'UPCOMING';
      case BillingStage.d0:
        return 'D+0';
      case BillingStage.d1:
        return 'D+1';
      case BillingStage.d3:
        return 'D+3';
      case BillingStage.d7:
        return 'D+7';
      case BillingStage.d15:
        return 'D+15';
      case BillingStage.d30:
        return 'D+30';
    }
  }
}

/// Billing Contact Log Model
class BillingContactLog {
  final String id;
  final String financialId;
  final String studentId;
  final String studentName;
  final ContactType type;
  final String notes;
  final String stage;
  final int daysOverdue;
  final String contactedBy;
  final String contactedByName;
  final String academyId;
  final DateTime createdAt;

  BillingContactLog({
    required this.id,
    required this.financialId,
    required this.studentId,
    required this.studentName,
    required this.type,
    required this.notes,
    required this.stage,
    required this.daysOverdue,
    required this.contactedBy,
    required this.contactedByName,
    required this.academyId,
    required this.createdAt,
  });

  factory BillingContactLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BillingContactLog(
      id: doc.id,
      financialId: data['financialId'] ?? '',
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      type: ContactTypeExtension.fromString(data['type'] ?? 'other'),
      notes: data['notes'] ?? '',
      stage: data['stage'] ?? '',
      daysOverdue: data['daysOverdue'] ?? 0,
      contactedBy: data['contactedBy'] ?? '',
      contactedByName: data['contactedByName'] ?? '',
      academyId: data['academyId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Data for a single collection stage
class CollectionStageData {
  final int count;
  final double amount;

  CollectionStageData({required this.count, required this.amount});
}

/// Aggregate collection statistics
class CollectionStats {
  final int totalOverdue;
  final double totalOverdueAmount;
  final int totalStudentsOverdue;
  final double recoveryRate;
  final int averageDaysOverdue;
  final Map<BillingStage, CollectionStageData> byStage;

  CollectionStats({
    required this.totalOverdue,
    required this.totalOverdueAmount,
    required this.totalStudentsOverdue,
    required this.recoveryRate,
    required this.averageDaysOverdue,
    required this.byStage,
  });
}

/// Billing Reminder Service - Multi-tenant billing reminder management
class BillingReminderService {
  final String academyId;
  late final Collections _collections;

  BillingReminderService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _financialsRef => _collections.payments;
  CollectionReference get _billingContactLogRef =>
      _collections.billingContactLog;

  // ============================================
  // Helper: Calculate days overdue from a due date
  // ============================================
  int _calculateDaysOverdue(DateTime dueDate) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final dueStart = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return todayStart.difference(dueStart).inDays;
  }

  // ============================================
  // Helper: Classify billing stage from days overdue
  // ============================================
  BillingStage? _classifyStage(int daysOverdue) {
    if (daysOverdue < 0) return BillingStage.upcoming;
    if (daysOverdue >= 30) return BillingStage.d30;
    if (daysOverdue >= 15) return BillingStage.d15;
    if (daysOverdue >= 7) return BillingStage.d7;
    if (daysOverdue >= 3) return BillingStage.d3;
    if (daysOverdue >= 1) return BillingStage.d1;
    if (daysOverdue == 0) return BillingStage.d0;
    return null;
  }

  // ============================================
  // Get Overdue Financials Grouped by Stage
  // ============================================
  Future<Map<BillingStage, List<Map<String, dynamic>>>>
  getOverdueWithStages() async {
    return getCollectibleWithStages(includeUpcoming: false);
  }

  /// Todas as cobranças ainda abertas, inclusive as que ainda não venceram.
  /// A tela de Cobranças usa esta leitura para permitir avisos/cobranças antes
  /// do vencimento; relatórios de inadimplência continuam usando
  /// [getOverdueWithStages] e, portanto, não misturam valores futuros.
  Future<Map<BillingStage, List<Map<String, dynamic>>>>
  getCollectibleWithStages({bool includeUpcoming = true}) async {
    final snapshot = await _financialsRef.get();

    final result = <BillingStage, List<Map<String, dynamic>>>{
      BillingStage.created: [],
      BillingStage.upcoming: [],
      BillingStage.d0: [],
      BillingStage.d1: [],
      BillingStage.d3: [],
      BillingStage.d7: [],
      BillingStage.d15: [],
      BillingStage.d30: [],
    };

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';

      // Only consider overdue or pending
      if (status != 'overdue' && status != 'pending') continue;

      final dueDateRaw = data['dueDate'];
      if (dueDateRaw == null) continue;

      final dueDate = dueDateRaw is Timestamp
          ? dueDateRaw.toDate()
          : DateTime.now();

      final daysOverdue = _calculateDaysOverdue(dueDate);
      // A tela operacional inclui a vencer; consumidores históricos podem
      // manter o comportamento antigo passando includeUpcoming=false.
      if (daysOverdue < 0 && !includeUpcoming) continue;

      final stage = _classifyStage(daysOverdue);
      if (stage == null) continue;

      result[stage]!.add({
        'id': doc.id,
        'studentId': data['studentId'] ?? '',
        'studentName': data['studentName'] ?? '',
        'amount': (data['amount'] ?? data['value'] ?? 0).toDouble(),
        'dueDate': dueDate,
        'status': status,
        'referenceMonth': data['referenceMonth'],
        'planId': data['planId'],
        'type': data['type'] ?? 'monthly_tuition',
        'description': data['description'],
        'daysOverdue': daysOverdue,
        'stage': stage.value,
      });
    }

    // Sort each stage by daysOverdue desc (most overdue first)
    for (final stage in BillingStage.values) {
      result[stage]!.sort((a, b) {
        final daysA = a['daysOverdue'] as int;
        final daysB = b['daysOverdue'] as int;
        return daysB.compareTo(daysA);
      });
    }

    return result;
  }

  // ============================================
  // Re-read live status for financial ids (anti double-charge guard)
  // ============================================
  /// Re-reads the current `status` of each financial id straight from
  /// Firestore. Returns the set of ids that are ALREADY PAID right now, so the
  /// caller can SKIP them before (re)sending a charge. Ids that fail to read or
  /// no longer exist are treated as paid/gone and reported as skipped, never
  /// re-charged. Never throws.
  Future<Set<String>> getPaidFinancialIds(Iterable<String> financialIds) async {
    final ids = financialIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return <String>{};

    final paid = <String>{};
    await Future.wait(
      ids.map((id) async {
        try {
          final doc = await _financialsRef.doc(id).get();
          if (!doc.exists) {
            paid.add(id); // gone -> do not charge
            return;
          }
          final data = doc.data() as Map<String, dynamic>?;
          final status = data?['status'] as String? ?? '';
          // Anything no longer collectible (paid / cancelled / refunded) is
          // treated as "do not re-charge".
          if (status != 'overdue' && status != 'pending') {
            paid.add(id);
          }
        } catch (_) {
          // Be conservative: on read failure, skip rather than risk a
          // double-charge.
          paid.add(id);
        }
      }),
    );
    return paid;
  }

  // ============================================
  // Log Contact Attempt
  // ============================================
  Future<BillingContactLog> logContactAttempt({
    required String financialId,
    required String studentId,
    required String studentName,
    required ContactType type,
    required String notes,
    required String stage,
    required int daysOverdue,
    required String contactedBy,
    required String contactedByName,
  }) async {
    final now = DateTime.now();

    final docData = {
      'financialId': financialId,
      'studentId': studentId,
      'studentName': studentName,
      'type': type.value,
      'notes': notes,
      'stage': stage,
      'daysOverdue': daysOverdue,
      'contactedBy': contactedBy,
      'contactedByName': contactedByName,
      'academyId': academyId,
      'createdAt': Timestamp.fromDate(now),
    };

    final docRef = await _billingContactLogRef.add(docData);

    return BillingContactLog(
      id: docRef.id,
      financialId: financialId,
      studentId: studentId,
      studentName: studentName,
      type: type,
      notes: notes,
      stage: stage,
      daysOverdue: daysOverdue,
      contactedBy: contactedBy,
      contactedByName: contactedByName,
      academyId: academyId,
      createdAt: now,
    );
  }

  // ============================================
  // Get Contact Log for a Financial Record
  // ============================================
  Future<List<BillingContactLog>> getContactLog(String financialId) async {
    final snapshot = await _billingContactLogRef
        .where('financialId', isEqualTo: financialId)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => BillingContactLog.fromFirestore(doc))
        .toList();
  }

  // ============================================
  // Get Collection Stats
  // ============================================
  Future<CollectionStats> getCollectionStats() async {
    final snapshot = await _financialsRef.get();

    int totalOverdue = 0;
    double totalOverdueAmount = 0;
    int totalDaysOverdue = 0;
    final uniqueStudents = <String>{};

    // Mutable counters for byStage
    final stageCounts = <BillingStage, int>{};
    final stageAmounts = <BillingStage, double>{};
    for (final stage in BillingStage.values) {
      stageCounts[stage] = 0;
      stageAmounts[stage] = 0;
    }

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';

      if (status != 'overdue' && status != 'pending') continue;

      final dueDateRaw = data['dueDate'];
      if (dueDateRaw == null) continue;

      final dueDate = dueDateRaw is Timestamp
          ? dueDateRaw.toDate()
          : DateTime.now();

      final daysOverdue = _calculateDaysOverdue(dueDate);
      // Mirror getOverdueWithStages: due-today (D+0) counts, not-yet-due drops.
      if (daysOverdue < 0) continue;

      final stage = _classifyStage(daysOverdue);
      if (stage == null) continue;

      final amount = (data['amount'] ?? data['value'] ?? 0).toDouble();
      final studentId = data['studentId'] as String? ?? '';

      totalOverdue++;
      totalOverdueAmount += amount;
      totalDaysOverdue += daysOverdue;
      uniqueStudents.add(studentId);

      stageCounts[stage] = (stageCounts[stage] ?? 0) + 1;
      stageAmounts[stage] = (stageAmounts[stage] ?? 0) + amount;
    }

    // Build final byStage map
    final finalByStage = <BillingStage, CollectionStageData>{};
    for (final stage in BillingStage.values) {
      finalByStage[stage] = CollectionStageData(
        count: stageCounts[stage] ?? 0,
        amount: stageAmounts[stage] ?? 0,
      );
    }

    return CollectionStats(
      totalOverdue: totalOverdue,
      totalOverdueAmount: totalOverdueAmount,
      totalStudentsOverdue: uniqueStudents.length,
      recoveryRate: 0, // Placeholder - needs historical data
      averageDaysOverdue: totalOverdue > 0
          ? (totalDaysOverdue / totalOverdue).round()
          : 0,
      byStage: finalByStage,
    );
  }

  // ============================================
  // Get Student Contacts Map (for notifications)
  // ============================================
  Future<Map<String, StudentContact>> getStudentContacts() async {
    final snapshot = await _collections.students.get();
    final contacts = <String, StudentContact>{};

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final guardian = data['guardian'] as Map<String, dynamic>?;

      contacts[doc.id] = StudentContact(
        studentId: doc.id,
        studentName: data['fullName'] as String? ?? '',
        phone: data['phone'] as String?,
        email: data['email'] as String?,
        guardianPhone: guardian?['phone'] as String?,
        guardianEmail: guardian?['email'] as String?,
        cpf: data['cpf'] as String?,
        guardianCpf: guardian?['cpf'] as String?,
        linkedUserId: data['linkedUserId'] as String?,
        responsibleUserId: data['responsibleUserId'] as String?,
        category: data['category'] as String? ?? 'adult',
        photoUrl: data['photoUrl'] as String?,
      );
    }

    return contacts;
  }

  // ============================================
  // Get Billing Reminder Settings
  // ============================================
  Future<BillingNotificationSettings> getNotificationSettings() async {
    final doc = await FirebaseFirestore.instance
        .collection('academies')
        .doc(academyId)
        .collection('settings')
        .doc('billingReminders')
        .get();

    if (!doc.exists) {
      return BillingNotificationSettings(
        whatsappEnabled: false,
        emailEnabled: false,
      );
    }

    final data = doc.data()!;
    return BillingNotificationSettings(
      whatsappEnabled: data['whatsappEnabled'] as bool? ?? false,
      emailEnabled: data['emailEnabled'] as bool? ?? false,
      includePaymentLink: data['includePaymentLink'] as bool? ?? true,
      notifyOnCreation: data['notifyOnCreation'] as bool? ?? false,
      dueSoonOffsets:
          ((data['dueSoonOffsets'] as List?) ?? const [7, 3, 2, 1, 0])
              .map((value) => (value as num).toInt())
              .where((value) => value >= 0)
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a)),
      messageTemplates: BillingMessageTemplates.fromMap(
        data['messageTemplates'] as Map<String, dynamic>?,
      ),
    );
  }

  // ============================================
  // Save Notification Settings (Toggles)
  // ============================================
  Future<void> saveNotificationSettings(
    BillingNotificationSettings settings,
  ) async {
    final data = <String, dynamic>{
      'whatsappEnabled': settings.whatsappEnabled,
      'emailEnabled': settings.emailEnabled,
      'includePaymentLink': settings.includePaymentLink,
      'notifyOnCreation': settings.notifyOnCreation,
      'dueSoonOffsets': settings.dueSoonOffsets,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
    if (settings.messageTemplates != null) {
      data['messageTemplates'] = settings.messageTemplates!.toMap();
    }
    final settingsRef = FirebaseFirestore.instance
        .collection('academies')
        .doc(academyId)
        .collection('settings')
        .doc('billingReminders');
    await settingsRef.set(data, SetOptions(merge: true));
    // Remove personalizacoes antigas: WhatsApp agora usa apenas templates
    // aprovados na Meta. E-mail continua personalizavel.
    await settingsRef.update({
      'messageTemplates.whatsapp': FieldValue.delete(),
    });
  }

  // ============================================
  // Get / Save Auto-Tuition-Generation Toggle
  // ============================================
  // AUDITORIA: doc DIFERENTE de billingReminders acima — o cron
  // `scheduledMonthlyTuitionGeneration` (server_functions.js) lê
  // `academies/{id}/settings/billing` campo `autoTuitionEnabled`, não
  // `settings/billingReminders`. Seguro por padrão (false): sem essa flag
  // ligada, o cron não gera nenhuma mensalidade pra academia.
  Future<bool> getAutoTuitionEnabled() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('academies')
          .doc(academyId)
          .collection('settings')
          .doc('billing')
          .get();
      if (!doc.exists) return false;
      return doc.data()?['autoTuitionEnabled'] as bool? ?? false;
    } catch (_) {
      // Nunca throwa: falha de leitura -> trata como desligado (seguro).
      return false;
    }
  }

  Future<void> setAutoTuitionEnabled(bool enabled) async {
    await FirebaseFirestore.instance
        .collection('academies')
        .doc(academyId)
        .collection('settings')
        .doc('billing')
        .set({
          'autoTuitionEnabled': enabled,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }, SetOptions(merge: true));
  }

  // ============================================
  // Cobrança-teste no WhatsApp do dono
  // (SPEC_ONBOARDING_2026-07.md §0.3 / Fatia 6)
  // ============================================
  /// Cria um financial SINTÉTICO (`status:'test'`, sem `referenceMonth`) e
  /// envia a mensagem de cobrança de exemplo pro WhatsApp informado — deixa o
  /// dono ver a mensagem real chegando no próprio celular antes de ativar a
  /// automação de verdade. Funciona independente do estado do toggle
  /// `whatsappEnabled` (a API de WhatsApp em si só depende de estar
  /// configurada — `BillingNotificationService.hasWhatsAppApi`).
  ///
  /// Por que é seguro (zero contaminação de dados financeiros):
  ///  - `getOverdueWithStages`/`getCollectionStats` (acima) só incluem
  ///    `status=='overdue'||'pending'` por comparação de STRING — 'test'
  ///    nunca entra.
  ///  - `PaymentService.getByMonth`/`generateMonthlyTuitions` filtram por
  ///    `referenceMonth` exato — este doc nunca grava esse campo.
  ///  - AUDITORIA (achado desta implementação, não coberto pela spec):
  ///    `PaymentService.getOverdue()`/`getPending()`/`getSummary()` NÃO olham
  ///    o campo `status` cru — eles fazem `Payment.fromFirestore` (que
  ///    desconhece 'test' e cai no default 'pending' via
  ///    `PaymentStatusExtension.fromString`) e depois computam
  ///    `Payment.isOverdue` a partir de `dueDate`. Por isso o `dueDate` do
  ///    doc de teste é gravado ~10 anos no futuro: `isOverdue` fica sempre
  ///    `false`, então mesmo esses getters (getOverdue() É usado hoje no
  ///    Dashboard) nunca classificam o registro de teste como
  ///    vencido/pendente de verdade. `getPending()`/`getSummary()` estão sem
  ///    nenhum call site no app hoje (grep confirmado) — mitigação defensiva
  ///    para o caso de ganharem um no futuro.
  ///  - `sendWhatsApp` não faz nenhum lookup server-side do
  ///    financialId/studentId (são só metadados soltos no payload pro proxy
  ///    de notificação) — um id sintético é seguro de usar.
  Future<TestBillingResult> sendTestBillingWhatsApp({
    required String academyName,
    required String phone,
    required double amount,
  }) async {
    const testStudentId = 'test-owner-preview';
    const testStudentName = 'Aluno (exemplo)';
    try {
      final docRef = await _financialsRef.add({
        'academyId': academyId,
        'studentId': testStudentId,
        'studentName': testStudentName,
        'amount': amount,
        'type': 'test',
        'status': 'test',
        // Bem no futuro — nunca soma como vencido/pendente em nenhuma tela
        // (ver nota de auditoria acima).
        'dueDate': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 3650)),
        ),
        'description': 'Cobrança de teste (preview do dono)',
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });

      final notificationService = BillingNotificationService(
        academyId: academyId,
        academyName: academyName,
      );

      final result = await notificationService.sendWhatsApp(
        phone: phone,
        studentName: testStudentName,
        studentId: testStudentId,
        financialId: docRef.id,
        amount: amount,
        dueDate: DateTime.now(),
        daysOverdue: 1,
        stage: BillingStage.d1,
        paymentInstruction: const BillingPaymentInstruction.none(),
      );

      return TestBillingResult(
        success: result.success,
        // O backend escolhe a instrucao de pagamento; o cliente nao recebe
        // nem pre-gera dados PIX durante o teste.
        hasPix: false,
        error: result.error,
      );
    } catch (e) {
      return TestBillingResult(success: false, hasPix: false, error: '$e');
    }
  }
}

/// Resultado do envio de cobrança-teste (Fatia 6).
class TestBillingResult {
  final bool success;
  final bool hasPix;
  final String? error;

  const TestBillingResult({
    required this.success,
    required this.hasPix,
    this.error,
  });
}

// ============================================
// Student Contact Model
// ============================================
bool isValidBillingPayerEmail(String? value) {
  final clean = value?.trim() ?? '';
  if (clean.isEmpty) return false;
  final emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );
  if (!emailRegex.hasMatch(clean)) return false;
  const blockedDomains = {
    'email.com',
    'teste.com',
    'test.com',
    'exemplo.com',
    'example.com',
  };
  return !blockedDomains.contains(clean.split('@').last.toLowerCase());
}

class StudentContact {
  final String studentId;
  final String studentName;
  final String? phone;
  final String? email;
  final String? guardianPhone;
  final String? guardianEmail;
  final String? cpf;
  final String? guardianCpf;
  final String? linkedUserId;
  final String? responsibleUserId;
  final String category;
  final String? photoUrl;

  StudentContact({
    required this.studentId,
    required this.studentName,
    this.phone,
    this.email,
    this.guardianPhone,
    this.guardianEmail,
    this.cpf,
    this.guardianCpf,
    this.linkedUserId,
    this.responsibleUserId,
    this.category = 'adult',
    this.photoUrl,
  });

  String? get effectivePhone => category == 'kids' ? guardianPhone : phone;

  String? get effectiveEmail => category == 'kids' ? guardianEmail : email;

  /// CPF do PAGADOR pro PIX do Mercado Pago (que exige um CPF válido).
  /// Kids: prefere o CPF do RESPONSÁVEL (pagador correto de um menor); se o
  /// responsável não tiver CPF cadastrado, cai no CPF PRÓPRIO do aluno — o MP
  /// só precisa de um CPF válido pra identificar o pagador. Sem NENHUM CPF, o
  /// PIX não é gerado e a cobrança sai sem o link.
  String? get effectiveCpf {
    String? nz(String? s) => (s != null && s.trim().isNotEmpty) ? s : null;
    if (category == 'kids') return nz(guardianCpf) ?? nz(cpf);
    return nz(cpf);
  }

  bool get hasValidPayerCpf => Validators.cpf(effectiveCpf ?? '') == null;

  bool get hasValidDirectPayerEmail => isValidBillingPayerEmail(effectiveEmail);

  bool get hasLinkedPayerEmailSource =>
      (linkedUserId?.trim().isNotEmpty ?? false) ||
      (responsibleUserId?.trim().isNotEmpty ?? false);

  bool get hasPayerEmailSource {
    return hasValidDirectPayerEmail || hasLinkedPayerEmailSource;
  }

  bool get canGenerateMercadoPagoPix => hasValidPayerCpf && hasPayerEmailSource;
}

// ============================================
// Billing Notification Settings
// ============================================
class BillingMessageTemplates {
  final Map<String, String> emailSubject;
  final Map<String, String> emailBody;

  BillingMessageTemplates({
    this.emailSubject = const {},
    this.emailBody = const {},
  });

  factory BillingMessageTemplates.fromMap(Map<String, dynamic>? data) {
    if (data == null) return BillingMessageTemplates();
    return BillingMessageTemplates(
      emailSubject: Map<String, String>.from(data['emailSubject'] ?? {}),
      emailBody: Map<String, String>.from(data['emailBody'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() => {
    'emailSubject': emailSubject,
    'emailBody': emailBody,
  };
}

class BillingNotificationSettings {
  final bool whatsappEnabled;
  final bool emailEnabled;
  final bool includePaymentLink;
  final bool notifyOnCreation;
  final List<int> dueSoonOffsets;
  final BillingMessageTemplates? messageTemplates;

  BillingNotificationSettings({
    this.whatsappEnabled = false,
    this.emailEnabled = false,
    this.includePaymentLink = true,
    this.notifyOnCreation = false,
    this.dueSoonOffsets = const [7, 3, 2, 1, 0],
    this.messageTemplates,
  });

  bool get hasWhatsAppApi => whatsappEnabled;
  bool get hasEmailApi => emailEnabled;

  BillingNotificationSettings copyWith({
    bool? whatsappEnabled,
    bool? emailEnabled,
    bool? includePaymentLink,
    bool? notifyOnCreation,
    List<int>? dueSoonOffsets,
    BillingMessageTemplates? messageTemplates,
  }) {
    return BillingNotificationSettings(
      whatsappEnabled: whatsappEnabled ?? this.whatsappEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      includePaymentLink: includePaymentLink ?? this.includePaymentLink,
      notifyOnCreation: notifyOnCreation ?? this.notifyOnCreation,
      dueSoonOffsets: dueSoonOffsets ?? this.dueSoonOffsets,
      messageTemplates: messageTemplates ?? this.messageTemplates,
    );
  }
}

// ============================================
// Billing Notification Service
// ============================================
class BillingNotificationService {
  // O cliente conhece apenas a callable autenticada. URLs e credenciais do
  // notification server vivem exclusivamente no backend.
  final CallableClient _functions = Fns.functions;
  bool get hasWhatsAppApi => true;
  bool get hasEmailApi => true;
  bool get hasTemplateApi => true;
  bool get useTemplates => true;
  bool get hasBulkApi => false;

  final String academyId;
  final String academyName;
  BillingMessageTemplates? customTemplates;
  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  // Default templates with placeholders: {nome}, {valor}, {vencimento}, {dias}, {academia}.
  // Mirrors marcusjj/src/services/billingNotificationService.ts DEFAULT_*_TEMPLATES.
  // The [[PIX]]..[[/PIX]] block is resolved by [injectPaymentInfo]: when a PIX
  // is generated, {pix}/{link} are substituted and the markers removed; when
  // there is no PIX (e.g. MP disconnected, or template preview), the whole
  // block is stripped so the message stays clean.
  static const defaultWhatsAppTemplates = {
    'CREATED':
        'Oi {nome}! Uma nova parcela de {valor} da {academia} ja esta disponivel, com vencimento em {vencimento}.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'UPCOMING':
        'Oi {nome}! Sua parcela de {valor} da {academia} vence em {diasAteVencimento} dia(s), em {vencimento}.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+0':
        'Oi {nome}! Passando rapidinho para lembrar que hoje, dia {vencimento}, vence sua mensalidade de {valor} com a {academia}. Contamos com voce! Qualquer duvida, estamos a disposicao.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+1':
        'Ola {nome}! Aqui e a {academia}. Identificamos que sua mensalidade de {valor} venceu em {vencimento}. Caso ja tenha efetuado o pagamento, por favor desconsidere esta mensagem. Caso contrario, solicitamos a regularizacao. Obrigado![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+3':
        'Ola {nome}! Sua mensalidade de {valor} da {academia} esta com 3 dias de atraso (vencimento: {vencimento}). Por favor, regularize sua situacao o mais breve possivel. Em caso de duvidas, estamos a disposicao![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+7':
        'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Precisamos que regularize sua situacao para manter seus treinos em dia. Entre em contato conosco para combinar o pagamento.[[PIX]]\n\nPara facilitar, pague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+15':
        'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Sua situacao precisa ser regularizada com urgencia para evitar a suspensao do acesso aos treinos. Por favor, entre em contato.[[PIX]]\n\nRegularize agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+30':
        'Ola {nome}, sua mensalidade de {valor} da {academia} esta com mais de 30 dias de atraso. Caso a situacao nao seja regularizada, infelizmente precisaremos suspender seu acesso. Entre em contato urgente para negociarmos.[[PIX]]\n\nRegularize agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  };

  static const defaultEmailSubjectTemplates = {
    'CREATED': 'Nova parcela disponivel - {academia}',
    'UPCOMING': 'Sua parcela vence em breve - {academia}',
    'D+0': 'Lembrete: Sua mensalidade vence hoje - {academia}',
    'D+1': 'Lembrete de Pagamento - {academia}',
    'D+3': 'Pagamento Atrasado - {academia}',
    'D+7': 'Pagamento Urgente - {academia}',
    'D+15': 'Aviso de Bloqueio - {academia}',
    'D+30': 'Situacao Critica de Pagamento - {academia}',
  };

  static const defaultEmailBodyTemplates = {
    'CREATED':
        'Ola {nome},\n\nUma nova parcela no valor de {valor} ja esta disponivel. O vencimento sera em {vencimento}.\n\nAtenciosamente,\n{academia}',
    'UPCOMING':
        'Ola {nome},\n\nSua parcela de {valor} vence em {diasAteVencimento} dia(s), em {vencimento}.\n\nSe voce ja efetuou o pagamento, pode desconsiderar este aviso.\n\nAtenciosamente,\n{academia}',
    'D+0':
        'Ola {nome},\n\nPassamos apenas para lembrar que hoje, dia {vencimento}, vence sua mensalidade no valor de {valor} com a {academia}.\n\nSe voce ja efetuou o pagamento, obrigado e pode desconsiderar este aviso!\n\nCaso ainda nao tenha pago, contamos com voce para manter tudo em dia.\n\nAtenciosamente,\n{academia}',
    'D+1':
        'Prezado(a) {nome},\n\nIdentificamos que sua mensalidade no valor de {valor} com vencimento em {vencimento} ainda nao foi quitada.\n\nCaso ja tenha efetuado o pagamento, por favor desconsidere esta mensagem.\n\nCaso contrario, solicitamos que regularize sua situacao o mais breve possivel.\n\nAtenciosamente,\n{academia}',
    'D+3':
        'Prezado(a) {nome},\n\nSua mensalidade no valor de {valor} da {academia} esta com 3 dias de atraso (vencimento: {vencimento}).\n\nPor favor, regularize sua situacao o mais breve possivel.\n\nEm caso de duvidas ou dificuldades, estamos a disposicao para ajudar.\n\nAtenciosamente,\n{academia}',
    'D+7':
        'Prezado(a) {nome},\n\nGostaramos de informar que sua mensalidade no valor de {valor} esta com {dias} dias de atraso.\n\nPrecisamos que regularize sua situacao para manter seus treinos em dia. Entre em contato conosco para combinar a melhor forma de pagamento.\n\nAtenciosamente,\n{academia}',
    'D+15':
        'Prezado(a) {nome},\n\nSua mensalidade no valor de {valor} esta com {dias} dias de atraso.\n\nInformamos que sua situacao precisa ser regularizada com URGENCIA para evitar a suspensao do acesso aos treinos.\n\nPor favor, entre em contato imediatamente para negociarmos o pagamento.\n\nAtenciosamente,\n{academia}',
    'D+30':
        'Prezado(a) {nome},\n\nSua mensalidade no valor de {valor} esta com mais de 30 dias de atraso.\n\nCaso a situacao nao seja regularizada nos proximos dias, infelizmente precisaremos suspender seu acesso a academia.\n\nEntre em contato urgente para que possamos encontrar uma solucao.\n\nAtenciosamente,\n{academia}',
  };

  BillingNotificationService({
    required this.academyId,
    required this.academyName,
    this.customTemplates,
  });

  /// Converts callable failures into a short message suitable for the UI.
  static String readableSendError(Object error) {
    if (error is FirebaseFunctionsException &&
        error.message != null &&
        error.message!.trim().isNotEmpty &&
        !error.message!.toLowerCase().contains('unauthenticated')) {
      return error.message!.trim();
    }
    if (error is FnsException &&
        error.message.trim().isNotEmpty &&
        !error.message.toLowerCase().contains('unauthenticated')) {
      return error.message.trim();
    }
    final raw = error.toString();
    final normalized = raw.toLowerCase();
    if (normalized.contains('unauthenticated') ||
        normalized.contains('forbidden')) {
      return 'Nao foi possivel autenticar o envio. Entre novamente e, se o problema persistir, contate o suporte.';
    }
    if (normalized.contains('permission-denied')) {
      return 'Sua conta nao tem permissao para enviar cobrancas desta academia.';
    }
    if (normalized.contains('nao configurado') ||
        normalized.contains('not_confirmed') ||
        normalized.contains('502') ||
        normalized.contains('bad gateway')) {
      return 'Servico de envio WhatsApp temporariamente indisponivel. Tente novamente em instantes.';
    }
    if (normalized.contains('unavailable') ||
        normalized.contains('deadline-exceeded') ||
        normalized.contains('timeout')) {
      return 'O servico de cobrancas esta temporariamente indisponivel. Tente novamente.';
    }
    return 'Nao foi possivel enviar a cobranca. Tente novamente.';
  }

  String _applyTemplate(
    String template,
    String studentName,
    String amountStr,
    String dateStr,
    int daysOverdue,
  ) {
    return template
        .replaceAll('{nome}', studentName)
        .replaceAll('{valor}', amountStr)
        .replaceAll('{vencimento}', dateStr)
        .replaceAll('{dias}', '$daysOverdue')
        .replaceAll(
          '{diasAteVencimento}',
          daysOverdue < 0 ? '${-daysOverdue}' : '0',
        )
        .replaceAll('{academia}', academyName);
  }

  // ============================================
  // Resolve / strip the optional PIX payment block
  // ============================================
  /// Resolves the optional [[PIX]]..[[/PIX]] payment block in a message.
  /// If pixCode is present: substitutes {pix} (copia-e-cola) and {link}
  /// (checkout) and removes the [[PIX]]/[[/PIX]] markers. If absent: removes
  /// the whole block. Always strips any leftover markers/placeholders as a
  /// safety net.
  String injectPaymentInfo(String text, {String? pixCode, String? ticketUrl}) {
    final has = pixCode != null && pixCode.isNotEmpty;
    var out = text;
    if (has) {
      if (ticketUrl == null || ticketUrl.isEmpty) {
        out = out.replaceAll(RegExp(r'\n\nOu acesse: \{link\}'), '');
      }
      out = out
          .replaceAll('{pix}', pixCode)
          .replaceAll('{link}', ticketUrl ?? '')
          .replaceAll('[[PIX]]', '')
          .replaceAll('[[/PIX]]', '');
    } else {
      // Remove the whole block (DOTALL) including markers.
      out = out.replaceAll(RegExp(r'\[\[PIX\]\][\s\S]*?\[\[/PIX\]\]'), '');
    }
    // Safety net: never leak raw markers/placeholders.
    out = out
        .replaceAll('[[PIX]]', '')
        .replaceAll('[[/PIX]]', '')
        .replaceAll('{pix}', '')
        .replaceAll('{link}', '');
    // Tidy excess blank lines left by a removed block.
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return out;
  }

  // ============================================
  // Generate WhatsApp message per stage
  // ============================================
  String generateWhatsAppMessage({
    required BillingStage stage,
    required String studentName,
    required double amount,
    required DateTime dueDate,
    required int daysOverdue,
    String? pixCode,
    String? ticketUrl,
  }) {
    final amountStr = _currencyFormat.format(amount);
    final dateStr = _dateFormat.format(dueDate);
    final stageKey = stage.value;

    final template =
        defaultWhatsAppTemplates[stageKey] ?? defaultWhatsAppTemplates['D+1']!;

    final result = _applyTemplate(
      template,
      studentName,
      amountStr,
      dateStr,
      daysOverdue,
    );
    return injectPaymentInfo(result, pixCode: pixCode, ticketUrl: ticketUrl);
  }

  // ============================================
  // Generate Email content per stage
  // ============================================
  ({String subject, String message}) generateEmailContent({
    required BillingStage stage,
    required String studentName,
    required double amount,
    required DateTime dueDate,
    required int daysOverdue,
  }) {
    final amountStr = _currencyFormat.format(amount);
    final dateStr = _dateFormat.format(dueDate);
    final stageKey = stage.value;

    final subjectTemplate =
        customTemplates?.emailSubject[stageKey] ??
        defaultEmailSubjectTemplates[stageKey] ??
        defaultEmailSubjectTemplates['D+1']!;

    final bodyTemplate =
        customTemplates?.emailBody[stageKey] ??
        defaultEmailBodyTemplates[stageKey] ??
        defaultEmailBodyTemplates['D+1']!;

    return (
      subject: _applyTemplate(
        subjectTemplate,
        studentName,
        amountStr,
        dateStr,
        daysOverdue,
      ),
      message: _applyTemplate(
        bodyTemplate,
        studentName,
        amountStr,
        dateStr,
        daysOverdue,
      ),
    );
  }

  // ============================================
  // Normalize and validate contact info
  // ============================================
  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('55') ? digits : '55$digits';
  }

  static bool _isValidPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final local = digits.startsWith('55') && digits.length >= 12
        ? digits.substring(2)
        : digits;
    if (local.length < 10 || local.length > 11) return false;
    final ddd = int.tryParse(local.substring(0, 2)) ?? 0;
    if (ddd < 11 || ddd > 99) return false;
    if (RegExp(r'^(\d)\1+$').hasMatch(local)) return false;
    if (local.contains('22223333') || local.contains('12345678')) return false;
    return true;
  }

  // ============================================
  // Send WhatsApp via API
  // ============================================
  Future<NotificationResult> sendWhatsApp({
    required String phone,
    required String studentName,
    required String studentId,
    required String financialId,
    required double amount,
    required DateTime dueDate,
    required int daysOverdue,
    required BillingStage stage,
    required BillingPaymentInstruction paymentInstruction,
  }) async {
    if (!hasWhatsAppApi) {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: 'API de WhatsApp nao configurada',
      );
    }

    if (!_isValidPhone(phone)) {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: 'Numero de telefone com formato invalido ou ficticio',
      );
    }

    return sendWhatsAppTemplate(
      phone: phone,
      studentName: studentName,
      studentId: studentId,
      financialId: financialId,
      amount: amount,
      dueDate: dueDate,
      daysOverdue: daysOverdue,
      stage: stage,
      paymentInstruction: paymentInstruction,
    );
  }

  // ============================================
  // Template name per stage (Meta Cloud API)
  // ============================================
  /// Mapeia estágio e forma de pagamento para o template aprovado na Meta.
  /// Os nomes
  /// DEVEM bater exatamente com os templates criados no WhatsApp Manager —
  /// ver TEMPLATES_META.md.
  static const Map<String, String> _stageTemplateBase = {
    'D+0': 'cobranca_d0',
    'D+1': 'cobranca_d1',
    'D+3': 'cobranca_d3',
    'D+7': 'cobranca_d7',
    'D+15': 'cobranca_d15',
    'D+30': 'cobranca_d30',
  };

  // Exact pt_BR bodies currently approved in the Meta account. Keep this
  // catalog synchronized with WhatsApp Manager; the preview must never show
  // the legacy editable copy as if it were the official template.
  static const Map<String, String> _approvedMetaTemplateBodies = {
    'cobranca_d0':
        'Oi {{1}}! Passando pra lembrar que hoje, dia {{4}}, vence sua mensalidade de {{3}} com a {{2}}. Contamos com você!\n\nPague pelo PIX (copia e cola):\n{{5}}\n\nObrigado!',
    'cobranca_d0_pix_manual':
        'Olá, {{1}}! Lembrete: sua cobrança de {{3}} da {{2}} vence hoje, {{4}}.\n\nChave PIX para pagamento:\n{{5}}\n\nApós o pagamento, envie o comprovante para a academia.',
    'cobranca_d0_sempix':
        'Oi {{1}}! Passando pra lembrar que hoje, dia {{4}}, vence sua mensalidade de {{3}} com a {{2}}. Contamos com você! Qualquer dúvida, estamos à disposição.',
    'cobranca_d1':
        'Olá {{1}}! Aqui e a {{2}}. Identificamos que sua mensalidade de {{3}} venceu em {{4}}. Se já pagou, desconsidere. Caso contrário, pague pelo PIX (copia e cola):\n\n{{5}}\n\nObrigado!',
    'cobranca_d1_pix_manual':
        'Olá, {{1}}! Identificamos que a cobrança de {{3}} da {{2}}, com vencimento em {{4}}, ainda está em aberto.\n\nChave PIX para pagamento:\n{{5}}\n\nSe já realizou o pagamento, desconsidere esta mensagem. Caso contrário, envie o comprovante após pagar.',
    'cobranca_d1_sempix':
        'Olá {{1}}! Aqui é a {{2}}. Identificamos que sua mensalidade de {{3}} venceu em {{4}}. Se já efetuou o pagamento, desconsidere esta mensagem. Caso contrário, solicitamos a regularização. Obrigado!',
    'cobranca_d3':
        'Olá {{1}}! Sua mensalidade de {{3}} da {{2}} (vencimento {{4}}) está em atraso. Por favor, regularize o quanto antes. Pague pelo PIX (copia e cola):\n\n{{5}}\n\nObrigado!',
    'cobranca_d3_pix_manual':
        'Olá, {{1}}! A cobrança de {{3}} da {{2}}, com vencimento em {{4}}, está em atraso.\n\nChave PIX para pagamento:\n{{5}}\n\nPor favor, regularize assim que possível e envie o comprovante para a academia.',
    'cobranca_d3_sempix':
        'Olá {{1}}! Sua mensalidade de {{3}} da {{2}} (vencimento {{4}}) está em atraso. Por favor, regularize sua situação o mais breve possível. Em caso de dúvidas, estamos à disposição!',
    'cobranca_d7':
        'Olá {{1}}, sua mensalidade de {{3}} da {{2}} (vencimento {{4}}) segue em atraso. Precisamos regularizar para manter seus treinos em dia. Pague pelo PIX (copia e cola):\n\n{{5}}\n\nObrigado!',
    'cobranca_d7_pix_manual':
        'Olá, {{1}}! A cobrança de {{3}} da {{2}}, com vencimento em {{4}}, segue em aberto.\n\nChave PIX para pagamento:\n{{5}}\n\nPor favor, regularize para manter sua situação em dia e envie o comprovante após o pagamento.',
    'cobranca_d7_sempix':
        'Olá {{1}}, sua mensalidade de {{3}} da {{2}} (vencimento {{4}}) segue em atraso. Precisamos que regularize para manter seus treinos em dia. Entre em contato para combinar o pagamento.',
    'cobranca_d15':
        'Olá {{1}}, sua mensalidade de {{3}} da {{2}} (vencimento {{4}}) está com atraso significativo. Regularize com urgência para evitar a suspensão do acesso aos treinos. Pague pelo PIX (copia e cola):\n\n{{5}}\n\nObrigado!',
    'cobranca_d15_pix_manual':
        'Olá, {{1}}! A cobrança de {{3}} da {{2}}, com vencimento em {{4}}, está com atraso significativo.\n\nChave PIX para pagamento:\n{{5}}\n\nPedimos que regularize com urgência e envie o comprovante para a academia.',
    'cobranca_d15_sempix':
        'Olá {{1}}, sua mensalidade de {{3}} da {{2}} (vencimento {{4}}) está com atraso significativo. Sua situação precisa ser regularizada com urgência para evitar a suspensão do acesso. Por favor, entre em contato.',
    'cobranca_d30':
        'Olá {{1}}, sua mensalidade de {{3}} da {{2}} (vencimento {{4}}) está com mais de 30 dias de atraso. Sem a regularização, precisaremos suspender seu acesso. Pague pelo PIX (copia e cola):\n\n{{5}}\n\nObrigado!',
    'cobranca_d30_pix_manual':
        'Olá, {{1}}! A cobrança de {{3}} da {{2}}, com vencimento em {{4}}, está em aberto há mais de 30 dias.\n\nChave PIX para pagamento:\n{{5}}\n\nEntre em contato com a academia para regularizar sua situação e envie o comprovante após o pagamento.',
    'cobranca_d30_sempix':
        'Olá {{1}}, sua mensalidade de {{3}} da {{2}} (vencimento {{4}}) está com mais de 30 dias de atraso. Caso não seja regularizada, infelizmente precisaremos suspender seu acesso. Entre em contato urgente para negociarmos.',
    'cobranca_avulsa_aberta':
        'Olá, {{1}}! Uma cobrança no valor de {{3}}, referente a {{5}}, foi disponibilizada pela {{2}}. O vencimento é em {{4}}.\n\nPague pelo PIX (copia e cola):\n\n{{6}}\n\nSe preferir, use o botão abaixo para abrir o pagamento. Caso já tenha pago, desconsidere esta mensagem.',
    'cobranca_avulsa_aberta_pix_manual':
        'Olá, {{1}}! Uma cobrança no valor de {{3}}, referente a {{5}}, foi disponibilizada pela {{2}}. O vencimento é em {{4}}.\n\nChave PIX para pagamento:\n\n{{6}}\n\nApós o pagamento, envie o comprovante para a academia. Caso já tenha pago, desconsidere esta mensagem.',
    'cobranca_avulsa_aberta_sempix':
        'Olá, {{1}}! Uma cobrança no valor de {{3}}, referente a {{5}}, foi disponibilizada pela {{2}}. O vencimento é em {{4}}.\n\nPara combinar a forma de pagamento, entre em contato com a academia. Caso já tenha pago, desconsidere esta mensagem.',
    'cobranca_avulsa_pendente':
        'Olá, {{1}}! A cobrança no valor de {{3}}, referente a {{5}}, da {{2}}, com vencimento em {{4}}, continua em aberto.\n\nRegularize pelo PIX (copia e cola):\n\n{{6}}\n\nSe preferir, use o botão abaixo para abrir o pagamento. Caso já tenha pago, desconsidere esta mensagem.',
    'cobranca_avulsa_pendente_pix_manual':
        'Olá, {{1}}! A cobrança no valor de {{3}}, referente a {{5}}, da {{2}}, com vencimento em {{4}}, continua em aberto.\n\nChave PIX para pagamento:\n\n{{6}}\n\nApós o pagamento, envie o comprovante para a academia. Caso já tenha pago, desconsidere esta mensagem.',
    'cobranca_avulsa_pendente_sempix':
        'Olá, {{1}}! A cobrança no valor de {{3}}, referente a {{5}}, da {{2}}, com vencimento em {{4}}, continua em aberto.\n\nEntre em contato com a academia para combinar o pagamento. Caso já tenha pago, desconsidere esta mensagem.',
  };

  static const Set<String> _oneTimeChargeTypes = {
    'avulsa',
    'private_lesson',
    'uniform',
    'seminar',
    'graduation',
    'competition',
    'other',
  };

  bool _isOneTimeChargeType(String chargeType) =>
      _oneTimeChargeTypes.contains(chargeType.trim());

  String _oneTimeTemplateBase(BillingStage stage) {
    switch (stage) {
      case BillingStage.created:
      case BillingStage.upcoming:
      case BillingStage.d0:
        return 'cobranca_avulsa_aberta';
      case BillingStage.d1:
      case BillingStage.d3:
      case BillingStage.d7:
      case BillingStage.d15:
      case BillingStage.d30:
        return 'cobranca_avulsa_pendente';
    }
  }

  String? templateNameForStage(
    BillingStage stage, {
    required BillingPaymentPreference paymentMode,
    String chargeType = 'monthly_tuition',
  }) {
    final base = _isOneTimeChargeType(chargeType)
        ? _oneTimeTemplateBase(stage)
        : _stageTemplateBase[stage.value];
    if (base == null) return null;
    switch (paymentMode) {
      case BillingPaymentPreference.mercadoPago:
        return base;
      case BillingPaymentPreference.manualPix:
        return '${base}_pix_manual';
      case BillingPaymentPreference.none:
        return '${base}_sempix';
    }
  }

  String? generateOfficialWhatsAppPreview({
    required BillingStage stage,
    required BillingPaymentPreference paymentMode,
    required String studentName,
    required double amount,
    required DateTime dueDate,
    String paymentValue = '',
    String chargeType = 'monthly_tuition',
    String description = '',
  }) {
    final templateName = templateNameForStage(
      stage,
      paymentMode: paymentMode,
      chargeType: chargeType,
    );
    final body = templateName == null
        ? null
        : _approvedMetaTemplateBodies[templateName];
    if (body == null) return null;

    final preview = body
        .replaceAll('{{1}}', studentName)
        .replaceAll('{{2}}', academyName)
        .replaceAll('{{3}}', _currencyFormat.format(amount))
        .replaceAll('{{4}}', _dateFormat.format(dueDate));
    if (_isOneTimeChargeType(chargeType)) {
      final chargeDescription = description.trim().isEmpty
          ? 'Cobrança avulsa'
          : description.trim();
      return preview
          .replaceAll('{{5}}', chargeDescription)
          .replaceAll('{{6}}', paymentValue);
    }
    return preview.replaceAll('{{5}}', paymentValue);
  }

  // ============================================
  // Send WhatsApp via TEMPLATE (Meta Cloud API)
  // ============================================
  /// Envia uma cobrança pelo canal OFICIAL (template aprovado). É o caminho que
  /// não derruba o chip. Variáveis, em ordem fixa (ver TEMPLATES_META.md):
  /// Mensalidade: {{1}}=nome {{2}}=academia {{3}}=valor {{4}}=vencimento
  /// [{{5}}=pix]. Avulsa/particular: os quatro primeiros são iguais,
  /// {{5}}=descrição e [{{6}}=pix].
  /// O `ticketUrl` vira o parâmetro do botão dinâmico (variante com PIX).
  Future<NotificationResult> sendWhatsAppTemplate({
    required String phone,
    required String studentName,
    required String studentId,
    required String financialId,
    required double amount,
    required DateTime dueDate,
    required int daysOverdue,
    required BillingStage stage,
    required BillingPaymentInstruction paymentInstruction,
  }) async {
    if (!hasWhatsAppApi) {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: 'API de template (Cloud) nao configurada',
      );
    }

    if (!_isValidPhone(phone)) {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: 'Numero de telefone com formato invalido ou ficticio',
      );
    }

    try {
      final body = <String, dynamic>{
        'academyId': academyId,
        'financialId': financialId,
        'channel': 'whatsapp',
        'stage': stage.value,
      };
      if (studentId == 'test-owner-preview') {
        body['recipientOverride'] = phone;
      }
      final response = await _functions
          .httpsCallable('sendBillingReminder')
          .call(body);
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      return NotificationResult(
        success: data['success'] == true,
        studentName: studentName,
        studentId: studentId,
        paymentMode: data['paymentMode'] as String?,
        templateName: data['templateName'] as String?,
        paymentFallbackReason: data['paymentFallbackReason'] as String?,
        error: data['success'] == true
            ? null
            : 'Falha no envio do template de WhatsApp',
      );
    } catch (e) {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: readableSendError(e),
      );
    }
  }

  // ============================================
  // Send Email via API
  // ============================================
  Future<NotificationResult> sendEmail({
    required String email,
    required String studentName,
    required String studentId,
    required String financialId,
    required double amount,
    required DateTime dueDate,
    required int daysOverdue,
    required BillingStage stage,
    required String subject,
    required String message,
  }) async {
    if (!hasEmailApi) {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: 'API de Email nao configurada',
      );
    }

    if (!isValidBillingPayerEmail(email)) {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: 'Endereco de e-mail com formato invalido ou de teste',
      );
    }

    try {
      final response = await _functions
          .httpsCallable('sendBillingReminder')
          .call({
            'academyId': academyId,
            'financialId': financialId,
            'channel': 'email',
            'stage': stage.value,
          });
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      return NotificationResult(
        success: data['success'] == true,
        studentName: studentName,
        studentId: studentId,
        error: data['success'] == true ? null : 'Falha no envio do e-mail',
      );
    } catch (e) {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: readableSendError(e),
      );
    }
  }

  // ============================================
  // Send Bulk WhatsApp for Stage
  // ============================================
  Future<BulkNotificationResult> sendBulkWhatsAppForStage({
    required List<Map<String, dynamic>> financials,
    required Map<String, StudentContact> contacts,
    required BillingStage stage,
    String? customMessage,
  }) async {
    final results = <NotificationResult>[];
    int sent = 0, failed = 0, skipped = 0;

    // O cliente lê o marcador apenas para evitar uma chamada redundante. A
    // gravação autoritativa de dedup acontece dentro de sendBillingReminder.
    final financialsRef = FirebaseFirestore.instance
        .collection('academies')
        .doc(academyId)
        .collection('financials');

    for (final item in financials) {
      final studentId = item['studentId'] as String? ?? '';
      final contact = contacts[studentId];
      final phone = contact?.effectivePhone;

      if (contact == null || phone == null || phone.isEmpty) {
        skipped++;
        continue;
      }

      final studentName = item['studentName'] as String? ?? '';
      final amount = (item['amount'] as num?)?.toDouble() ?? 0;
      final dueDate = item['dueDate'] as DateTime;
      final daysOverdue = item['daysOverdue'] as int? ?? 0;
      final financialId = item['id'] as String? ?? '';

      // AUDITORIA (idempotency): mesmo critério do cron (server_functions.js
      // sendBillingReminderWhatsApp) — se o estágio atual já foi enviado
      // (lastReminderStage == stage), pula sem reenviar. Em caso de falha de
      // leitura, é conservador e NÃO pula (prefere enviar a perder a cobrança,
      // já que sendWhatsApp em si é o ponto de envio). Itens sem id não têm
      // como deduplicar, então seguem o fluxo normal.
      String? lastReminderStage;
      if (financialId.isNotEmpty) {
        try {
          final snap = await financialsRef.doc(financialId).get();
          final data = snap.data();
          lastReminderStage = data?['lastReminderStage'] as String?;
        } catch (_) {
          lastReminderStage = null;
        }
      }
      if (lastReminderStage == stage.value) {
        skipped++;
        continue;
      }

      final result = await sendWhatsApp(
        phone: phone,
        studentName: studentName,
        studentId: studentId,
        financialId: financialId,
        amount: amount,
        dueDate: dueDate,
        daysOverdue: daysOverdue,
        stage: stage,
        paymentInstruction: const BillingPaymentInstruction.none(),
      );

      results.add(result);
      if (result.success) {
        sent++;
      } else {
        failed++;
      }
    }

    return BulkNotificationResult(
      total: financials.length,
      sent: sent,
      failed: failed,
      skipped: skipped,
      results: results,
    );
  }

  // ============================================
  // Send Bulk Email for Stage
  // ============================================
  Future<BulkNotificationResult> sendBulkEmailForStage({
    required List<Map<String, dynamic>> financials,
    required Map<String, StudentContact> contacts,
    required BillingStage stage,
    String? customSubject,
    String? customMessage,
  }) async {
    final results = <NotificationResult>[];
    int sent = 0, failed = 0, skipped = 0;

    for (final item in financials) {
      final studentId = item['studentId'] as String? ?? '';
      final contact = contacts[studentId];
      final email = contact?.effectiveEmail;

      if (contact == null || email == null || email.isEmpty) {
        skipped++;
        continue;
      }

      final studentName = item['studentName'] as String? ?? '';
      final amount = (item['amount'] as num?)?.toDouble() ?? 0;
      final dueDate = item['dueDate'] as DateTime;
      final daysOverdue = item['daysOverdue'] as int? ?? 0;
      final financialId = item['id'] as String? ?? '';

      final content = generateEmailContent(
        stage: stage,
        studentName: studentName,
        amount: amount,
        dueDate: dueDate,
        daysOverdue: daysOverdue,
      );

      final result = await sendEmail(
        email: email,
        studentName: studentName,
        studentId: studentId,
        financialId: financialId,
        amount: amount,
        dueDate: dueDate,
        daysOverdue: daysOverdue,
        stage: stage,
        subject: customSubject ?? content.subject,
        message: customMessage ?? content.message,
      );

      results.add(result);
      if (result.success) {
        sent++;
      } else {
        failed++;
      }
    }

    return BulkNotificationResult(
      total: financials.length,
      sent: sent,
      failed: failed,
      skipped: skipped,
      results: results,
    );
  }

  // ============================================
  // Generate Generic Stage Message (template preview with placeholders)
  // ============================================
  String generateGenericStageMessage(BillingStage stage) {
    final stageKey = stage.value;
    final template =
        defaultWhatsAppTemplates[stageKey] ?? defaultWhatsAppTemplates['D+1']!;
    return template.replaceAll('{academia}', academyName);
  }

  // ============================================
  // Apply message template with per-student data
  // ============================================
  String applyMessageTemplate(
    String template,
    String studentName,
    double amount,
    DateTime dueDate,
    int daysOverdue, {
    String? pixCode,
    String? ticketUrl,
  }) {
    final amountStr = _currencyFormat.format(amount);
    final dateStr = _dateFormat.format(dueDate);
    final result = _applyTemplate(
      template,
      studentName,
      amountStr,
      dateStr,
      daysOverdue,
    );
    return injectPaymentInfo(result, pixCode: pixCode, ticketUrl: ticketUrl);
  }

  // ============================================
  // Generate Generic Email Subject
  // ============================================
  String generateGenericEmailSubject(BillingStage stage) {
    final stageKey = stage.value;
    final template =
        customTemplates?.emailSubject[stageKey] ??
        defaultEmailSubjectTemplates[stageKey] ??
        defaultEmailSubjectTemplates['D+1']!;
    return template.replaceAll('{academia}', academyName);
  }

  // ============================================
  // Collect Recipients for Stage (phones + emails, deduplicated)
  // ============================================
  ({List<String> phones, List<String> emails, int skipped})
  collectRecipientsForStage({
    required List<Map<String, dynamic>> financials,
    required Map<String, StudentContact> contacts,
  }) {
    final phonesSet = <String>{};
    final emailsSet = <String>{};
    int skipped = 0;

    for (final item in financials) {
      final studentId = item['studentId'] as String? ?? '';
      final contact = contacts[studentId];
      if (contact == null) {
        skipped++;
        continue;
      }

      final phone = contact.effectivePhone;
      final email = contact.effectiveEmail;

      if (phone != null && phone.isNotEmpty) {
        phonesSet.add(_normalizePhone(phone));
      }
      if (email != null && email.isNotEmpty) {
        emailsSet.add(email);
      }

      if ((phone == null || phone.isEmpty) &&
          (email == null || email.isEmpty)) {
        skipped++;
      }
    }

    return (
      phones: phonesSet.toList(),
      emails: emailsSet.toList(),
      skipped: skipped,
    );
  }

  // ============================================
  // Send Bulk (unified WhatsApp + Email via /api/send-bulk)
  // ============================================
  Future<BulkServerResult> sendBulk({
    required String message,
    String? subject,
    required List<String> phones,
    required List<String> emails,
    String? scheduledTime,
  }) async {
    throw UnsupportedError(
      'Envio generico por destinatarios foi desativado. Use cobrancas '
      'identificadas pelo financialId para o backend resolver dados e permissoes.',
    );
  }
}

// ============================================
// Bulk Server Result Models
// ============================================
class BulkChannelSummary {
  final int total;
  final int? sent;
  final int? failed;

  BulkChannelSummary({required this.total, this.sent, this.failed});

  factory BulkChannelSummary.fromJson(Map<String, dynamic> json) {
    return BulkChannelSummary(
      total: json['total'] as int? ?? 0,
      sent: json['sent'] as int?,
      failed: json['failed'] as int?,
    );
  }
}

class BulkFailure {
  final String type;
  final String recipient;
  final String error;

  BulkFailure({
    required this.type,
    required this.recipient,
    required this.error,
  });

  factory BulkFailure.fromJson(Map<String, dynamic> json) {
    return BulkFailure(
      type: json['type'] as String? ?? '',
      recipient: json['recipient'] as String? ?? '',
      error: json['error'] as String? ?? 'Erro desconhecido',
    );
  }
}

class BulkServerResult {
  final bool success;
  final bool scheduled;
  final String? jobId;
  final String? scheduledTime;
  final BulkChannelSummary whatsapp;
  final BulkChannelSummary email;
  final List<BulkFailure> failures;

  BulkServerResult({
    required this.success,
    this.scheduled = false,
    this.jobId,
    this.scheduledTime,
    required this.whatsapp,
    required this.email,
    this.failures = const [],
  });

  factory BulkServerResult.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? {};
    final failuresList =
        (json['failures'] as List<dynamic>?)
            ?.map((f) => BulkFailure.fromJson(f as Map<String, dynamic>))
            .toList() ??
        [];

    return BulkServerResult(
      success: json['success'] as bool? ?? false,
      scheduled: json['scheduled'] as bool? ?? false,
      jobId: json['jobId'] as String?,
      scheduledTime: json['scheduledTime'] as String?,
      whatsapp: BulkChannelSummary.fromJson(
        summary['whatsapp'] as Map<String, dynamic>? ?? {'total': 0},
      ),
      email: BulkChannelSummary.fromJson(
        summary['email'] as Map<String, dynamic>? ?? {'total': 0},
      ),
      failures: failuresList,
    );
  }
}

// ============================================
// Notification Result
// ============================================
class NotificationResult {
  final bool success;
  final String studentName;
  final String? studentId;
  final String? error;
  final String? paymentMode;
  final String? templateName;
  final String? paymentFallbackReason;

  NotificationResult({
    required this.success,
    required this.studentName,
    this.studentId,
    this.error,
    this.paymentMode,
    this.templateName,
    this.paymentFallbackReason,
  });
}

// ============================================
// Bulk Notification Result
// ============================================
class BulkNotificationResult {
  final int total;
  final int sent;
  final int failed;
  final int skipped;
  final List<NotificationResult> results;

  BulkNotificationResult({
    required this.total,
    required this.sent,
    required this.failed,
    required this.skipped,
    required this.results,
  });
}

// ============================================
// Factory Function
// ============================================
BillingReminderService createBillingReminderService(String academyId) {
  return BillingReminderService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
BillingReminderService get billingReminderService =>
    BillingReminderService(FirebaseService.academyId);
