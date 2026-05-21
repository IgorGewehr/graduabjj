import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api/dto/financial_dto.dart' as api;
import '../api/dto/student_dto.dart' as api_student;
import '../api/financial_repo.dart';
import '../api/settings_repo.dart';
import '../api/student_repo.dart';
import 'firebase_service.dart';

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

  /// Converte o label do backend ("D+0", "D+3", etc.) para o enum.
  static BillingStage? fromWireLabel(String label) {
    switch (label) {
      case 'D+0':
        return BillingStage.d0;
      case 'D+1':
        return BillingStage.d1;
      case 'D+3':
        return BillingStage.d3;
      case 'D+7':
        return BillingStage.d7;
      case 'D+15':
        return BillingStage.d15;
      case 'D+30':
        return BillingStage.d30;
      default:
        return null;
    }
  }
}

/// Billing Contact Log Model
///
/// Mapeado a partir de [api.ApiBillingContact]. Campos sem equivalente
/// direto na API (stage, daysOverdue, contactedByName) são aproximados
/// ou deixados com defaults para compatibilidade do widget tree.
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

  factory BillingContactLog.fromApi(
    api.ApiBillingContact c, {
    String? financialId,
    String? academyId,
  }) {
    return BillingContactLog(
      id: c.id,
      financialId: financialId ?? '',
      studentId: c.studentId,
      studentName: c.studentNameSnapshot,
      type: ContactTypeExtension.fromString(c.method.name),
      notes: c.notes ?? '',
      stage: '', // campo sem equivalente direto na API
      daysOverdue: 0, // campo sem equivalente direto na API
      contactedBy: c.createdByUid,
      contactedByName: '', // campo sem equivalente direto na API
      academyId: academyId ?? c.academyId,
      createdAt: c.createdAt ?? DateTime.now(),
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

/// Billing Reminder Service - Multi-tenant billing reminder management via
/// Tatami HTTP API.
///
/// Mudanças vs. versão Firestore:
/// - `getOverdueWithStages`: usa GET /billing/stages (via FinancialRemoteRepo).
/// - `logContactAttempt`: usa POST /financials/{id}/billing-contacts.
/// - `getContactLog`: usa GET /financials/{id}/billing-contacts.
/// - `getStudentContacts`: usa GET /students (via StudentRemoteRepo).
/// - `getCollectionStats`: derivado de GET /billing/stages; campos sem
///   equivalente (recoveryRate, averageDaysOverdue) retornam 0.
/// - `getNotificationSettings` / `saveNotificationSettings`: mantidos via
///   SettingsRemoteRepo (sem mudança).
class BillingReminderService {
  final String academyId;

  /// Repositório de financials — cobre billing/stages e billing-contacts.
  final FinancialRemoteRepo? financialRepo;

  /// Repositório de alunos — cobre getStudentContacts.
  final StudentRemoteRepo? studentRepo;

  /// Repositório de settings — billing_reminders settings.
  final SettingsRemoteRepo? settingsRepo;

  BillingReminderService(
    this.academyId, {
    this.financialRepo,
    this.studentRepo,
    this.settingsRepo,
  });

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
  // Get Overdue Financials Grouped by Stage
  //
  // GET /v1/academies/{id}/billing/stages
  //
  // O backend retorna JSON com chaves "D+0", "D+1", etc. Cada item da
  // lista deve ter pelo menos: id, student_id, amount, due_date, status.
  // ============================================
  Future<Map<BillingStage, List<Map<String, dynamic>>>>
      getOverdueWithStages() async {
    final result = <BillingStage, List<Map<String, dynamic>>>{
      BillingStage.d0: [],
      BillingStage.d1: [],
      BillingStage.d3: [],
      BillingStage.d7: [],
      BillingStage.d15: [],
      BillingStage.d30: [],
    };

    if (financialRepo == null || academyId.isEmpty) return result;

    try {
      final raw = await financialRepo!.getBillingStages(academyId);

      for (final entry in raw.entries) {
        final stage = BillingStageExtension.fromWireLabel(entry.key);
        if (stage == null) continue;

        final items = (entry.value as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];

        for (final item in items) {
          final dueDate = _parseDate(item['due_date']);
          final daysOverdue =
              dueDate != null ? _calculateDaysOverdue(dueDate) : 0;
          final amount = _parseAmount(item['amount']);

          result[stage]!.add({
            'id': item['id'] ?? '',
            'studentId': item['student_id'] ?? '',
            'studentName': item['student_name'] ?? '',
            'amount': amount,
            'dueDate': dueDate ?? DateTime.now(),
            'status': item['status'] ?? '',
            'referenceMonth': item['reference_month'],
            'planId': item['plan_id'],
            'description': item['description'],
            'daysOverdue': daysOverdue,
            'stage': stage.value,
          });
        }

        // Sort by daysOverdue desc (most overdue first)
        result[stage]!.sort((a, b) {
          final daysA = a['daysOverdue'] as int;
          final daysB = b['daysOverdue'] as int;
          return daysB.compareTo(daysA);
        });
      }
    } catch (_) {
      // On error, return empty map so UI renders without crashing.
    }

    return result;
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  double _parseAmount(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  // ============================================
  // Log Contact Attempt
  //
  // POST /v1/academies/{id}/financials/{financialId}/billing-contacts
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
    if (financialRepo == null || academyId.isEmpty) {
      // Fallback: retorna log local sem persistir
      return BillingContactLog(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
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
        createdAt: DateTime.now(),
      );
    }

    final contactMethod = _toApiBillingMethod(type);
    final req = api.LogBillingContactRequest(
      studentId: studentId,
      method: contactMethod,
      result: api.ApiBillingContactResult.other,
      contactDate: DateTime.now(),
      notes: notes.isNotEmpty ? notes : null,
    );

    final contact = await financialRepo!
        .logBillingContactForFinancial(academyId, financialId, req);

    return BillingContactLog.fromApi(
      contact,
      financialId: financialId,
      academyId: academyId,
    );
  }

  api.ApiBillingContactMethod _toApiBillingMethod(ContactType type) {
    switch (type) {
      case ContactType.whatsapp:
        return api.ApiBillingContactMethod.whatsapp;
      case ContactType.email:
        return api.ApiBillingContactMethod.email;
      case ContactType.phone:
        return api.ApiBillingContactMethod.phone;
      case ContactType.inPerson:
        return api.ApiBillingContactMethod.in_person;
      case ContactType.other:
        return api.ApiBillingContactMethod.whatsapp; // fallback
    }
  }

  // ============================================
  // Get Contact Log for a Financial Record
  //
  // GET /v1/academies/{id}/financials/{financialId}/billing-contacts
  // ============================================
  Future<List<BillingContactLog>> getContactLog(String financialId) async {
    if (financialRepo == null || academyId.isEmpty) return [];

    try {
      final page = await financialRepo!
          .listBillingContactsForFinancial(academyId, financialId);
      return page.items
          .map((c) => BillingContactLog.fromApi(
                c,
                financialId: financialId,
                academyId: academyId,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ============================================
  // Get Collection Stats
  //
  // Derivado de GET /billing/stages. Campos sem equivalente na API
  // (recoveryRate, averageDaysOverdue) retornam 0.
  //
  // TODO(tatami): migrar para endpoint dedicado de stats quando exposto.
  // ============================================
  Future<CollectionStats> getCollectionStats() async {
    final stages = await getOverdueWithStages();

    int totalOverdue = 0;
    double totalOverdueAmount = 0;
    final uniqueStudents = <String>{};

    final emptyStage = CollectionStageData(count: 0, amount: 0);
    final finalByStage = <BillingStage, CollectionStageData>{
      for (final s in BillingStage.values) s: emptyStage,
    };

    for (final entry in stages.entries) {
      final stage = entry.key;
      final items = entry.value;

      // D+0 não é "overdue" stricto sensu — inclua somente D+1+
      if (stage == BillingStage.d0) continue;

      int stageCount = 0;
      double stageAmount = 0;

      for (final item in items) {
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final studentId = item['studentId'] as String? ?? '';
        totalOverdue++;
        totalOverdueAmount += amount;
        uniqueStudents.add(studentId);
        stageCount++;
        stageAmount += amount;
      }

      finalByStage[stage] =
          CollectionStageData(count: stageCount, amount: stageAmount);
    }

    return CollectionStats(
      totalOverdue: totalOverdue,
      totalOverdueAmount: totalOverdueAmount,
      totalStudentsOverdue: uniqueStudents.length,
      recoveryRate: 0, // sem endpoint dedicado
      averageDaysOverdue: 0, // sem endpoint dedicado
      byStage: finalByStage,
    );
  }

  // ============================================
  // Get Student Contacts Map (for notifications)
  //
  // GET /v1/academies/{id}/students (lista completa com limit alto)
  // ============================================
  Future<Map<String, StudentContact>> getStudentContacts() async {
    if (studentRepo == null || academyId.isEmpty) return {};

    final contacts = <String, StudentContact>{};

    try {
      // Busca até 500 alunos em uma chamada; para academias maiores
      // seria necessário paginação — suficiente para o uso atual.
      const filter = api_student.StudentFilter(
        status: api_student.ApiStudentStatus.active,
        limit: 500,
      );
      final page = await studentRepo!.list(academyId, filter: filter);

      for (final s in page.items) {
        contacts[s.id] = StudentContact(
          studentId: s.id,
          studentName: s.fullName,
          phone: s.phone,
          email: s.email,
          guardianPhone: s.guardian?.phone,
          guardianEmail: s.guardian?.email,
          category: s.category.name, // 'adult' | 'kids'
          photoUrl: s.photoUrl,
        );
      }
    } catch (_) {
      // On error, return partial/empty map so callers can degrade gracefully.
    }

    return contacts;
  }

  // ============================================
  // Get Billing Reminder Settings
  // ============================================
  /// Reads billing reminder settings from Tatami
  /// `GET /v1/academies/{id}/settings` (key: `billing_reminders`).
  Future<BillingNotificationSettings> getNotificationSettings() async {
    if (settingsRepo == null || academyId.isEmpty) {
      return BillingNotificationSettings(
        whatsappEnabled: false,
        emailEnabled: false,
      );
    }

    try {
      final allSettings = await settingsRepo!.getAll(academyId);
      final setting = allSettings['billing_reminders'];
      if (setting == null || setting.value == null) {
        return BillingNotificationSettings(
          whatsappEnabled: false,
          emailEnabled: false,
        );
      }

      final data = setting.value is Map<String, dynamic>
          ? setting.value as Map<String, dynamic>
          : <String, dynamic>{};

      return BillingNotificationSettings(
        whatsappEnabled: data['whatsappEnabled'] as bool? ?? false,
        emailEnabled: data['emailEnabled'] as bool? ?? false,
        messageTemplates: BillingMessageTemplates.fromMap(
          data['messageTemplates'] as Map<String, dynamic>?,
        ),
      );
    } catch (e) {
      return BillingNotificationSettings(
        whatsappEnabled: false,
        emailEnabled: false,
      );
    }
  }

  // ============================================
  // Save Notification Settings (Toggles)
  // ============================================
  /// Persists billing reminder settings via Tatami
  /// `PUT /v1/academies/{id}/settings/billing_reminders`.
  Future<void> saveNotificationSettings(
      BillingNotificationSettings settings) async {
    if (settingsRepo == null || academyId.isEmpty) {
      throw Exception(
        'Settings repo not available. Cannot save notification settings.',
      );
    }

    final data = <String, dynamic>{
      'whatsappEnabled': settings.whatsappEnabled,
      'emailEnabled': settings.emailEnabled,
    };
    if (settings.messageTemplates != null) {
      data['messageTemplates'] = settings.messageTemplates!.toMap();
    }

    await settingsRepo!.set(academyId, 'billing_reminders', data);
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
  final String category;
  final String? photoUrl;

  StudentContact({
    required this.studentId,
    required this.studentName,
    this.phone,
    this.email,
    this.guardianPhone,
    this.guardianEmail,
    this.category = 'adult',
    this.photoUrl,
  });

  String? get effectivePhone =>
      category == 'kids' ? guardianPhone : phone;

  String? get effectiveEmail =>
      category == 'kids' ? guardianEmail : email;
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
  static const defaultWhatsAppTemplates = {
    'D+0': 'Oi {nome}! Passando rapidinho para lembrar que hoje, dia {vencimento}, vence sua mensalidade de {valor} com a {academia}. Contamos com voce! Qualquer duvida, estamos a disposicao.',
    'D+1': 'Ola {nome}! Aqui e a {academia}. Identificamos que sua mensalidade de {valor} venceu em {vencimento}. Caso ja tenha efetuado o pagamento, por favor desconsidere esta mensagem. Caso contrario, solicitamos a regularizacao. Obrigado!',
    'D+3': 'Ola {nome}! Sua mensalidade de {valor} da {academia} esta com 3 dias de atraso (vencimento: {vencimento}). Por favor, regularize sua situacao o mais breve possivel. Em caso de duvidas, estamos a disposicao!',
    'D+7': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Precisamos que regularize sua situacao para manter seus treinos em dia. Entre em contato conosco para combinar o pagamento.',
    'D+15': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com {dias} dias de atraso. Sua situacao precisa ser regularizada com urgencia para evitar a suspensao do acesso aos treinos. Por favor, entre em contato.',
    'D+30': 'Ola {nome}, sua mensalidade de {valor} da {academia} esta com mais de 30 dias de atraso. Caso a situacao nao seja regularizada, infelizmente precisaremos suspender seu acesso. Entre em contato urgente para negociarmos.',
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

  String _applyTemplate(String template, String studentName, String amountStr,
      String dateStr, int daysOverdue) {
    return template
        .replaceAll('{nome}', studentName)
        .replaceAll('{valor}', amountStr)
        .replaceAll('{vencimento}', dateStr)
        .replaceAll('{dias}', '$daysOverdue')
        .replaceAll('{academia}', academyName);
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
  }) {
    final amountStr = _currencyFormat.format(amount);
    final dateStr = _dateFormat.format(dueDate);
    final stageKey = stage.value;

    final template = customTemplates?.whatsapp[stageKey] ??
        defaultWhatsAppTemplates[stageKey] ??
        defaultWhatsAppTemplates['D+1']!;

    return _applyTemplate(
        template, studentName, amountStr, dateStr, daysOverdue);
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

    final subjectTemplate = customTemplates?.emailSubject[stageKey] ??
        defaultEmailSubjectTemplates[stageKey] ??
        defaultEmailSubjectTemplates['D+1']!;

    final bodyTemplate = customTemplates?.emailBody[stageKey] ??
        defaultEmailBodyTemplates[stageKey] ??
        defaultEmailBodyTemplates['D+1']!;

    return (
      subject: _applyTemplate(
          subjectTemplate, studentName, amountStr, dateStr, daysOverdue),
      message: _applyTemplate(
          bodyTemplate, studentName, amountStr, dateStr, daysOverdue),
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
      final response = await http
          .post(
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
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return NotificationResult(
            success: true, studentName: studentName, studentId: studentId);
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
        error: isTimeout
            ? 'Timeout: API demorou mais de 30 segundos'
            : e.toString(),
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
      final response = await http
          .post(
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
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return NotificationResult(
            success: true, studentName: studentName, studentId: studentId);
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
        error: isTimeout
            ? 'Timeout: API demorou mais de 30 segundos'
            : e.toString(),
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
    final template = customTemplates?.whatsapp[stageKey] ??
        defaultWhatsAppTemplates[stageKey] ??
        defaultWhatsAppTemplates['D+1']!;
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
    int daysOverdue,
  ) {
    final amountStr = _currencyFormat.format(amount);
    final dateStr = _dateFormat.format(dueDate);
    return _applyTemplate(
        template, studentName, amountStr, dateStr, daysOverdue);
  }

  // ============================================
  // Generate Generic Email Subject
  // ============================================
  String generateGenericEmailSubject(BillingStage stage) {
    final stageKey = stage.value;
    final template = customTemplates?.emailSubject[stageKey] ??
        defaultEmailSubjectTemplates[stageKey] ??
        defaultEmailSubjectTemplates['D+1']!;
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

      if ((phone == null || phone.isEmpty) &&
          (email == null || email.isEmpty)) {
        skipped++;
      }
    }

    return (
      phones: phonesSet.toList(),
      emails: emailsSet.toList(),
      skipped: skipped
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

      final bulkKey =
          _whatsappApiKey.isNotEmpty ? _whatsappApiKey : _emailApiKey;
      final response = await http
          .post(
            Uri.parse(_bulkApiUrl),
            headers: {
              'Content-Type': 'application/json',
              if (bulkKey.isNotEmpty) 'x-api-key': bulkKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));

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

  BulkFailure(
      {required this.type, required this.recipient, required this.error});

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
