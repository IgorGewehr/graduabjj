import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'firebase_service.dart';
import 'mercado_pago_service.dart';

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
enum BillingStage { d0, d1, d3, d7, d15, d30 }

extension BillingStageExtension on BillingStage {
  String get label {
    switch (this) {
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
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Data for a single collection stage
class CollectionStageData {
  final int count;
  final double amount;

  CollectionStageData({
    required this.count,
    required this.amount,
  });
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
    final snapshot = await _financialsRef.get();

    final result = <BillingStage, List<Map<String, dynamic>>>{
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
      if (daysOverdue < 1) continue;

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
      if (daysOverdue < 1) continue;

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
      averageDaysOverdue:
          totalOverdue > 0 ? (totalDaysOverdue / totalOverdue).round() : 0,
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
      messageTemplates: BillingMessageTemplates.fromMap(
        data['messageTemplates'] as Map<String, dynamic>?,
      ),
    );
  }

  // ============================================
  // Save Notification Settings (Toggles)
  // ============================================
  Future<void> saveNotificationSettings(BillingNotificationSettings settings) async {
    final data = <String, dynamic>{
      'whatsappEnabled': settings.whatsappEnabled,
      'emailEnabled': settings.emailEnabled,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
    if (settings.messageTemplates != null) {
      data['messageTemplates'] = settings.messageTemplates!.toMap();
    }
    await FirebaseFirestore.instance
        .collection('academies')
        .doc(academyId)
        .collection('settings')
        .doc('billingReminders')
        .set(data, SetOptions(merge: true));
  }
}

// ============================================
// Student Contact Model
// ============================================
class StudentContact {
  final String studentId;
  final String studentName;
  final String? phone;
  final String? email;
  final String? guardianPhone;
  final String? guardianEmail;
  final String? cpf;
  final String? guardianCpf;
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
    this.category = 'adult',
    this.photoUrl,
  });

  String? get effectivePhone =>
      category == 'kids' ? guardianPhone : phone;

  String? get effectiveEmail =>
      category == 'kids' ? guardianEmail : email;

  String? get effectiveCpf =>
      category == 'kids' ? guardianCpf : cpf;
}

// ============================================
// Billing Notification Settings
// ============================================
class BillingMessageTemplates {
  final Map<String, String> whatsapp;
  final Map<String, String> emailSubject;
  final Map<String, String> emailBody;

  BillingMessageTemplates({
    this.whatsapp = const {},
    this.emailSubject = const {},
    this.emailBody = const {},
  });

  factory BillingMessageTemplates.fromMap(Map<String, dynamic>? data) {
    if (data == null) return BillingMessageTemplates();
    return BillingMessageTemplates(
      whatsapp: Map<String, String>.from(data['whatsapp'] ?? {}),
      emailSubject: Map<String, String>.from(data['emailSubject'] ?? {}),
      emailBody: Map<String, String>.from(data['emailBody'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() => {
    'whatsapp': whatsapp,
    'emailSubject': emailSubject,
    'emailBody': emailBody,
  };
}

class BillingNotificationSettings {
  final bool whatsappEnabled;
  final bool emailEnabled;
  final BillingMessageTemplates? messageTemplates;

  BillingNotificationSettings({
    this.whatsappEnabled = false,
    this.emailEnabled = false,
    this.messageTemplates,
  });

  bool get hasWhatsAppApi => whatsappEnabled;
  bool get hasEmailApi => emailEnabled;
}

// ============================================
// Billing Notification Service
// ============================================
class BillingNotificationService {
  static const String _whatsappApiUrl =
      String.fromEnvironment('WHATSAPP_API_URL', defaultValue: '');
  static const String _emailApiUrl =
      String.fromEnvironment('EMAIL_API_URL', defaultValue: '');
  // Matches marcusjj split: WHATSAPP_API_KEY + EMAIL_API_KEY are independent.
  // NOTIFICATION_API_KEY remains as legacy fallback for older builds.
  static const String _legacyApiKey =
      String.fromEnvironment('NOTIFICATION_API_KEY', defaultValue: '');
  static const String _whatsappApiKeyRaw =
      String.fromEnvironment('WHATSAPP_API_KEY', defaultValue: '');
  static const String _emailApiKeyRaw =
      String.fromEnvironment('EMAIL_API_KEY', defaultValue: '');
  static String get _whatsappApiKey =>
      _whatsappApiKeyRaw.isNotEmpty ? _whatsappApiKeyRaw : _legacyApiKey;
  static String get _emailApiKey =>
      _emailApiKeyRaw.isNotEmpty ? _emailApiKeyRaw : _legacyApiKey;
  static const String _bulkApiUrlEnv =
      String.fromEnvironment('NOTIFICATION_BULK_API_URL', defaultValue: '');
  // Marcusjj proxies stamp every notification payload with this appId so the
  // notification server can route per-app. Match it for parity.
  static const String _appId = 'gestao-raiz';

  bool get hasWhatsAppApi => _whatsappApiUrl.isNotEmpty;
  bool get hasEmailApi => _emailApiUrl.isNotEmpty;

  String get _bulkApiUrl {
    if (_bulkApiUrlEnv.isNotEmpty) return _bulkApiUrlEnv;
    if (_whatsappApiUrl.isNotEmpty) {
      return _whatsappApiUrl.replaceAll('/api/send-whatsapp', '/api/send-bulk');
    }
    return '';
  }

  bool get hasBulkApi => _bulkApiUrl.isNotEmpty;

  final String academyId;
  final String academyName;
  BillingMessageTemplates? customTemplates;
  final _currencyFormat =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  // Default templates with placeholders: {nome}, {valor}, {vencimento}, {dias}, {academia}.
  // Mirrors marcusjj/src/services/billingNotificationService.ts DEFAULT_*_TEMPLATES.
  // The [[PIX]]..[[/PIX]] block is resolved by [injectPaymentInfo]: when a PIX
  // is generated, {pix}/{link} are substituted and the markers removed; when
  // there is no PIX (e.g. MP disconnected, or template preview), the whole
  // block is stripped so the message stays clean.
  static const defaultWhatsAppTemplates = {
    'D+0': 'Oi {nome}! Passando rapidinho para lembrar que hoje, dia {vencimento}, vence sua mensalidade de {valor} com a {academia}. Contamos com voce! Qualquer duvida, estamos a disposicao.[[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+1': 'Ola {nome}! Aqui e a {academia}. Identificamos que sua mensalidade de {valor} venceu em {vencimento}. Caso ja tenha efetuado o pagamento, por favor desconsidere esta mensagem. Caso contrario, solicitamos a regularizacao. Obrigado![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+3': 'Ola {nome}! Sua mensalidade de {valor} da {academia} esta com 3 dias de atraso (vencimento: {vencimento}). Por favor, regularize sua situacao o mais breve possivel. Em caso de duvidas, estamos a disposicao![[PIX]]\n\nPague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+7': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Precisamos que regularize sua situacao para manter seus treinos em dia. Entre em contato conosco para combinar o pagamento.[[PIX]]\n\nPara facilitar, pague agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+15': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Sua situacao precisa ser regularizada com urgencia para evitar a suspensao do acesso aos treinos. Por favor, entre em contato.[[PIX]]\n\nRegularize agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
    'D+30': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com mais de 30 dias de atraso. Caso a situacao nao seja regularizada, infelizmente precisaremos suspender seu acesso. Entre em contato urgente para negociarmos.[[PIX]]\n\nRegularize agora pelo PIX (copia e cola):\n{pix}\n\nOu acesse: {link}[[/PIX]]',
  };

  static const defaultEmailSubjectTemplates = {
    'D+0': 'Lembrete: Sua mensalidade vence hoje - {academia}',
    'D+1': 'Lembrete de Pagamento - {academia}',
    'D+3': 'Pagamento Atrasado - {academia}',
    'D+7': 'Pagamento Urgente - {academia}',
    'D+15': 'Aviso de Bloqueio - {academia}',
    'D+30': 'Situacao Critica de Pagamento - {academia}',
  };

  static const defaultEmailBodyTemplates = {
    'D+0': 'Ola {nome},\n\nPassamos apenas para lembrar que hoje, dia {vencimento}, vence sua mensalidade no valor de {valor} com a {academia}.\n\nSe voce ja efetuou o pagamento, obrigado e pode desconsiderar este aviso!\n\nCaso ainda nao tenha pago, contamos com voce para manter tudo em dia.\n\nAtenciosamente,\n{academia}',
    'D+1': 'Prezado(a) {nome},\n\nIdentificamos que sua mensalidade no valor de {valor} com vencimento em {vencimento} ainda nao foi quitada.\n\nCaso ja tenha efetuado o pagamento, por favor desconsidere esta mensagem.\n\nCaso contrario, solicitamos que regularize sua situacao o mais breve possivel.\n\nAtenciosamente,\n{academia}',
    'D+3': 'Prezado(a) {nome},\n\nSua mensalidade no valor de {valor} da {academia} esta com 3 dias de atraso (vencimento: {vencimento}).\n\nPor favor, regularize sua situacao o mais breve possivel.\n\nEm caso de duvidas ou dificuldades, estamos a disposicao para ajudar.\n\nAtenciosamente,\n{academia}',
    'D+7': 'Prezado(a) {nome},\n\nGostaramos de informar que sua mensalidade no valor de {valor} esta com {dias} dias de atraso.\n\nPrecisamos que regularize sua situacao para manter seus treinos em dia. Entre em contato conosco para combinar a melhor forma de pagamento.\n\nAtenciosamente,\n{academia}',
    'D+15': 'Prezado(a) {nome},\n\nSua mensalidade no valor de {valor} esta com {dias} dias de atraso.\n\nInformamos que sua situacao precisa ser regularizada com URGENCIA para evitar a suspensao do acesso aos treinos.\n\nPor favor, entre em contato imediatamente para negociarmos o pagamento.\n\nAtenciosamente,\n{academia}',
    'D+30': 'Prezado(a) {nome},\n\nSua mensalidade no valor de {valor} esta com mais de 30 dias de atraso.\n\nCaso a situacao nao seja regularizada nos proximos dias, infelizmente precisaremos suspender seu acesso a academia.\n\nEntre em contato urgente para que possamos encontrar uma solucao.\n\nAtenciosamente,\n{academia}',
  };

  BillingNotificationService({
    required this.academyId,
    required this.academyName,
    this.customTemplates,
  });

  String _applyTemplate(String template, String studentName, String amountStr, String dateStr, int daysOverdue) {
    return template
        .replaceAll('{nome}', studentName)
        .replaceAll('{valor}', amountStr)
        .replaceAll('{vencimento}', dateStr)
        .replaceAll('{dias}', '$daysOverdue')
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
  // Ensure a valid PIX for a financial record (graceful degradation)
  // ============================================
  /// Best-effort PIX generation for a tuition record. NEVER throws: on any
  /// failure (MP disconnected, CF error, network) returns empty strings so the
  /// caller falls back to a PIX-less message.
  Future<({String pixCode, String ticketUrl})> ensureValidPixForFinancial({
    required String academyId,
    required String financialId,
    required double amount,
    required String studentId,
    required String studentName,
    String? payerCpf,
  }) async {
    try {
      final mp = MercadoPagoService(academyId);
      if (!await mp.isEnabled()) return (pixCode: '', ticketUrl: '');
      final link = await mp.createPixPayment(
        amount: amount,
        financialId: financialId,
        studentId: studentId,
        studentName: studentName,
        cpf: payerCpf,
      );
      if (link == null) return (pixCode: '', ticketUrl: '');
      return (pixCode: link.pixCode, ticketUrl: link.ticketUrl ?? '');
    } catch (_) {
      return (pixCode: '', ticketUrl: '');
    }
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

    final template = customTemplates?.whatsapp[stageKey]
        ?? defaultWhatsAppTemplates[stageKey]
        ?? defaultWhatsAppTemplates['D+1']!;

    final result = _applyTemplate(template, studentName, amountStr, dateStr, daysOverdue);
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

    final subjectTemplate = customTemplates?.emailSubject[stageKey]
        ?? defaultEmailSubjectTemplates[stageKey]
        ?? defaultEmailSubjectTemplates['D+1']!;

    final bodyTemplate = customTemplates?.emailBody[stageKey]
        ?? defaultEmailBodyTemplates[stageKey]
        ?? defaultEmailBodyTemplates['D+1']!;

    return (
      subject: _applyTemplate(subjectTemplate, studentName, amountStr, dateStr, daysOverdue),
      message: _applyTemplate(bodyTemplate, studentName, amountStr, dateStr, daysOverdue),
    );
  }

  // ============================================
  // Normalize phone for WhatsApp
  // ============================================
  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('55') ? digits : '55$digits';
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
    required String message,
  }) async {
    if (!hasWhatsAppApi) {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: 'API de WhatsApp nao configurada',
      );
    }
    try {
      final response = await http.post(
        Uri.parse(_whatsappApiUrl),
        headers: {
          'Content-Type': 'application/json',
          if (_whatsappApiKey.isNotEmpty) 'x-api-key': _whatsappApiKey,
        },
        body: jsonEncode({
          'phone': _normalizePhone(phone),
          'studentName': studentName,
          'studentId': studentId,
          'financialId': financialId,
          'academyId': academyId,
          'academyName': academyName,
          'amount': amount,
          'amountFormatted': _currencyFormat.format(amount),
          'dueDate': DateFormat('yyyy-MM-dd').format(dueDate),
          'dueDateFormatted': _dateFormat.format(dueDate),
          'daysOverdue': daysOverdue,
          'stage': stage.value,
          'message': message,
          'type': 'billing_reminder',
          'appId': _appId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return NotificationResult(success: true, studentName: studentName, studentId: studentId);
      } else {
        return NotificationResult(
          success: false,
          studentName: studentName,
          studentId: studentId,
          error: 'Erro do servidor (${response.statusCode})',
        );
      }
    } on http.ClientException {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: 'Erro de conexao - verifique sua internet',
      );
    } catch (e) {
      final isTimeout = e.toString().contains('TimeoutException');
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: isTimeout ? 'Timeout: API demorou mais de 30 segundos' : e.toString(),
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
    try {
      final response = await http.post(
        Uri.parse(_emailApiUrl),
        headers: {
          'Content-Type': 'application/json',
          if (_emailApiKey.isNotEmpty) 'x-api-key': _emailApiKey,
        },
        body: jsonEncode({
          'email': email,
          'studentName': studentName,
          'studentId': studentId,
          'financialId': financialId,
          'academyId': academyId,
          'academyName': academyName,
          'amount': amount,
          'amountFormatted': _currencyFormat.format(amount),
          'dueDate': DateFormat('yyyy-MM-dd').format(dueDate),
          'dueDateFormatted': _dateFormat.format(dueDate),
          'daysOverdue': daysOverdue,
          'stage': stage.value,
          'subject': subject,
          'message': message,
          'type': 'billing_reminder',
          'appId': _appId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return NotificationResult(success: true, studentName: studentName, studentId: studentId);
      } else {
        return NotificationResult(
          success: false,
          studentName: studentName,
          studentId: studentId,
          error: 'Erro do servidor (${response.statusCode})',
        );
      }
    } on http.ClientException {
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: 'Erro de conexao - verifique sua internet',
      );
    } catch (e) {
      final isTimeout = e.toString().contains('TimeoutException');
      return NotificationResult(
        success: false,
        studentName: studentName,
        studentId: studentId,
        error: isTimeout ? 'Timeout: API demorou mais de 30 segundos' : e.toString(),
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

      final msg = customMessage ??
          generateWhatsAppMessage(
            stage: stage,
            studentName: studentName,
            amount: amount,
            dueDate: dueDate,
            daysOverdue: daysOverdue,
          );

      final result = await sendWhatsApp(
        phone: phone,
        studentName: studentName,
        studentId: studentId,
        financialId: financialId,
        amount: amount,
        dueDate: dueDate,
        daysOverdue: daysOverdue,
        stage: stage,
        message: msg,
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
    final template = customTemplates?.whatsapp[stageKey]
        ?? defaultWhatsAppTemplates[stageKey]
        ?? defaultWhatsAppTemplates['D+1']!;
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
    final result = _applyTemplate(template, studentName, amountStr, dateStr, daysOverdue);
    return injectPaymentInfo(result, pixCode: pixCode, ticketUrl: ticketUrl);
  }

  // ============================================
  // Generate Generic Email Subject
  // ============================================
  String generateGenericEmailSubject(BillingStage stage) {
    final stageKey = stage.value;
    final template = customTemplates?.emailSubject[stageKey]
        ?? defaultEmailSubjectTemplates[stageKey]
        ?? defaultEmailSubjectTemplates['D+1']!;
    return template.replaceAll('{academia}', academyName);
  }

  // ============================================
  // Collect Recipients for Stage (phones + emails, deduplicated)
  // ============================================
  ({List<String> phones, List<String> emails, int skipped}) collectRecipientsForStage({
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

      if ((phone == null || phone.isEmpty) && (email == null || email.isEmpty)) {
        skipped++;
      }
    }

    return (phones: phonesSet.toList(), emails: emailsSet.toList(), skipped: skipped);
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
    if (_bulkApiUrl.isEmpty) {
      throw Exception('Bulk API URL nao configurada');
    }

    try {
      final body = <String, dynamic>{
        'message': message,
        'phones': phones,
        'emails': emails,
        'appId': _appId,
      };
      if (subject != null && subject.isNotEmpty) body['subject'] = subject;
      if (scheduledTime != null && scheduledTime.isNotEmpty) {
        body['scheduledTime'] = scheduledTime;
      }

      // Bulk hits both channels; the notification server accepts either key.
      // Prefer WhatsApp key (most builds use the same value anyway).
      final bulkKey = _whatsappApiKey.isNotEmpty ? _whatsappApiKey : _emailApiKey;
      final response = await http.post(
        Uri.parse(_bulkApiUrl),
        headers: {
          'Content-Type': 'application/json',
          if (bulkKey.isNotEmpty) 'x-api-key': bulkKey,
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return BulkServerResult.fromJson(data);
      } else {
        throw Exception('Erro do servidor (${response.statusCode})');
      }
    } on http.ClientException {
      throw Exception('Erro de conexao - verifique sua internet');
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        throw Exception('Timeout: API demorou mais de 120 segundos');
      }
      rethrow;
    }
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

  BulkFailure({required this.type, required this.recipient, required this.error});

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
    final failuresList = (json['failures'] as List<dynamic>?)
        ?.map((f) => BulkFailure.fromJson(f as Map<String, dynamic>))
        .toList() ?? [];

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

  NotificationResult({
    required this.success,
    required this.studentName,
    this.studentId,
    this.error,
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
