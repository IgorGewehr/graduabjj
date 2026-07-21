import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

/// PIX Key Type
enum PixKeyType { cpf, cnpj, email, phone, random }

extension PixKeyTypeExtension on PixKeyType {
  String get value {
    switch (this) {
      case PixKeyType.cpf:
        return 'cpf';
      case PixKeyType.cnpj:
        return 'cnpj';
      case PixKeyType.email:
        return 'email';
      case PixKeyType.phone:
        return 'phone';
      case PixKeyType.random:
        return 'random';
    }
  }

  String get label {
    switch (this) {
      case PixKeyType.cpf:
        return 'CPF';
      case PixKeyType.cnpj:
        return 'CNPJ';
      case PixKeyType.email:
        return 'E-mail';
      case PixKeyType.phone:
        return 'Telefone';
      case PixKeyType.random:
        return 'Chave Aleatória';
    }
  }

  static PixKeyType fromString(String value) {
    switch (value) {
      case 'cpf':
        return PixKeyType.cpf;
      case 'cnpj':
        return PixKeyType.cnpj;
      case 'email':
        return PixKeyType.email;
      case 'phone':
        return PixKeyType.phone;
      default:
        return PixKeyType.random;
    }
  }
}

/// Operating hours per weekday, used to gate schedule-less (musculação)
/// self check-in. Weekdays follow the app convention 0=Sunday..6=Saturday
/// (same as [ClassSchedule.dayOfWeek] and `DateTime.weekday % 7`). A weekday
/// absent from [byDay] means the academy is closed that day.
class OperatingHours {
  /// dayOfWeek (0=Sun..6=Sat) -> open/close times as "HH:mm".
  final Map<int, ({String open, String close})> byDay;

  const OperatingHours(this.byDay);

  static const OperatingHours empty = OperatingHours({});

  bool get isEmpty => byDay.isEmpty;
  bool get isNotEmpty => byDay.isNotEmpty;

  /// Whether [now] falls inside the configured window for its weekday.
  /// When nothing is configured at all, returns true (no time gate) so the
  /// feature works out of the box; admins opt into stricter hours.
  bool isOpenAt(DateTime now) {
    if (byDay.isEmpty) return true;
    final dow = now.weekday % 7; // Mon=1..Sun=7 -> 0=Sun..6=Sat
    final window = byDay[dow];
    if (window == null) return false; // closed that day
    final open = _at(window.open, now);
    final close = _at(window.close, now);
    return !now.isBefore(open) && now.isBefore(close);
  }

  DateTime _at(String hhmm, DateTime ref) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(ref.year, ref.month, ref.day, h, m);
  }

  factory OperatingHours.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return empty;
    final map = <int, ({String open, String close})>{};
    raw.forEach((key, value) {
      final day = int.tryParse(key);
      if (day == null || value is! Map) return;
      final open = value['open']?.toString();
      final close = value['close']?.toString();
      if (open != null && close != null) {
        map[day] = (open: open, close: close);
      }
    });
    return OperatingHours(map);
  }

  Map<String, dynamic> toMap() => {
        for (final e in byDay.entries)
          e.key.toString(): {'open': e.value.open, 'close': e.value.close},
      };
}

/// Academy Settings Model
class AcademySettings {
  // Basic Info
  final String name;
  final String? slug;
  final String? cnpj;
  final String? email;
  final String? phone;

  // Address
  final String? address;
  final String? city;
  final String? state;
  final String? zipCode;

  // Responsible Person (for Asaas onboarding)
  final String? responsibleBirthDate;

  // Branding
  final String? logoUrl;
  final String? portalSlogan;
  final String? sidebarLogoUrl;
  final String? portalBackgroundUrl;
  final String? adminBackgroundUrl;
  final String? sidebarBackgroundUrl;

  // Financial
  final String? pixKey;
  final PixKeyType? pixKeyType;

  // AbacatePay Integration (API key is global in backend env, not per-academy)
  final bool abacatePayEnabled;

  // Asaas Integration (per-academy sub-account)
  final bool asaasEnabled;
  final String? asaasOnboardingStatus; // 'pending', 'approved', 'rejected'

  // Asaas KYC Document Verification
  final String? asaasKycStatus; // 'not_checked', 'pending_upload', 'pending_review', 'approved', 'rejected', 'onboarding_url'
  final String? asaasKycOnboardingUrl;

  // Mercado Pago marketplace/split — admin's own connected MP account.
  final bool mpConnected;
  final String? mpPublicKey;

  /// Set by the backend when MP auth repeatedly fails (e.g. the refresh token
  /// was revoked or expired). When true, the admin must reconnect even if
  /// [mpConnected] is still true. Defaults to false.
  final bool mpNeedsReauth;

  /// Set pelo backend (troca de conta / disconnect com token revogado) quando
  /// assinaturas recorrentes (preapprovals) NÃO puderam ser canceladas e ficaram
  /// ÓRFÃS — ainda cobrando cartões de alunos numa conta MP que o app não
  /// gerencia mais. Exibido como alerta para o admin agir (reconectar ou
  /// cancelar no painel do MP). Sem leitor na UI = receita órfã silenciosa.
  final bool mpHasOrphanPreapprovals;
  final int mpOrphanPreapprovalCount;

  // Auto-graduation Settings
  /// Master toggle for the entire attendance-based graduation feature.
  /// When false: the Graduation tab disappears from admin nav, the student
  /// progress widget hides, and auto-promotion never fires (regardless of
  /// graduationMode). Existing data is preserved when the flag is flipped off.
  final bool autoGraduationEnabled;
  final int? autoGraduationAttendances;
  /// Per-sport, per-belt graduation requirements: sportValue → {gradeId → classes}.
  /// The configured number applies to every degree/stripe within that belt.
  /// Falls back to [autoGraduationAttendances] (global), then legacy defaults.
  final Map<String, Map<String, int>> graduationRequirementsBySport;
  /// When true, attendance counts use Class.weight instead of 1 per doc.
  final bool useClassWeights;
  /// 'manual' → mestre confirma promoção a partir da tela de Graduação.
  /// 'auto'   → ao bater o threshold, markPresent já promove sem intervenção.
  /// Default 'manual' preserves prior behavior.
  final String graduationMode;
  /// Whether students see their own attendance-to-graduation progress on
  /// the portal home. When false, the count stays admin-only.
  final bool graduationProgressVisibleToStudents;
  /// Política das técnicas do currículo na graduação (B2): 'informative'
  /// (default — só mostra) ou 'required' (bloqueia até atingir o % mínimo).
  final String graduationSkillPolicy;
  /// % mínimo de técnicas dominadas exigido quando a política é 'required'.
  final int graduationMinSkillPct;

  // Store Settings
  final bool storeEnabled;
  final bool storePublished;
  final bool storeCreditCardEnabled;
  final String? storeWelcomeMessage;
  final double? storeMinOrderAmount;

  // Student Check-in Settings
  final bool studentCheckinEnabled;

  /// Whether the student-facing "Jornal da Academia" feed is shown. When false,
  /// the home headline tile is hidden and the JornalScreen renders an
  /// unavailable state. Defaults to true for new and legacy academies.
  final bool journalVisibleToStudents;

  /// Whether the student-facing class attendance ranking is shown. When false,
  /// the portal nav entry is hidden and the RankingScreen renders an
  /// unavailable state. Defaults to true for new and legacy academies.
  final bool rankingVisibleToStudents;

  /// Whether the structured workout plans feature is available (admin "Treinos"
  /// e portal "/portal/treinos"). Opt-in: defaults to false; a backfill turns it
  /// on for academies that already have workout data.
  final bool workoutPlansEnabled;

  /// Whether the training videos feature is available (admin "Vídeos" e portal
  /// "/portal/videos"). Opt-in: defaults to false; a backfill turns it on for
  /// academies that already have video content.
  final bool trainingVideosEnabled;

  /// Whether the physical-evolution (avaliações físicas) feature is available
  /// for students (portal "/portal/evolucao"). Opt-in: defaults to false.
  final bool physicalEvolutionEnabled;

  // Musculação (schedule-less) check-in.
  /// Whether the musculação feature is available at all for this academy. When
  /// false the admin "Musculação" entry is hidden and students never see the
  /// check-in card. Defaults to true for new and legacy academies (current
  /// behaviour was always-on). The check-in MODE below only applies when this
  /// is true.
  final bool musculacaoEnabled;

  /// Controle de acesso (catraca) — MAPA server-side em
  /// academies/{id}.accessControl, o MESMO doc lido por
  /// functions/access_control/{financial_gate,ingest}.js. Default {} = feature
  /// DESLIGADA (graceful-off: nada aparece para a academia).
  final Map<String, dynamic> accessControl;

  /// Catraca habilitada (master switch).
  bool get accessControlEnabled => accessControl['enabled'] == true;

  /// Marca/modelo selecionada (default/dica de setup; o vendor REAL é por-device).
  String get accessControlVendor => (accessControl['vendor'] ?? '').toString();

  /// Bloquear inadimplentes no portão (2º nível explícito — ligar a catraca NÃO
  /// começa a bloquear ninguém sozinho).
  bool get accessControlBlockOnOverdue => accessControl['blockOnOverdue'] == true;

  /// 'manual' → staff records presence (works with current rules, no Cloud
  /// Function); 'qr' → student scans a fixed QR; 'button' → student taps a
  /// check-in button. 'qr'/'button' route through the selfCheckin function.
  final String musculacaoCheckinMode;

  /// Open/close hours that gate musculação self check-in. Empty = no time gate.
  final OperatingHours operatingHours;

  // Muay Thai graduation system.
  /// Which Muay Thai prajied ladder this academy uses: 'cbmt' (white→red→blue→
  /// black, the default/legacy system) or 'cbmtt' (white→yellow→...→gold). Only
  /// affects which grades are OFFERED for Muay Thai; stored grades from either
  /// system always resolve for display. See [muaythaiVariantCbmt] in sports.dart.
  final String muaythaiGradeSystem;

  // Class booking (A1: reserva de aula com vaga + lista de espera).
  /// Master toggle: when false students never see the "Reservar aula" entry and
  /// the reserve callable rejects non-staff. Default false (opt-in per academy).
  final bool bookingEnabled;
  /// How far ahead (days) a student may reserve. Default 7.
  final int bookingWindowDays;
  /// Minutes before class start after which a student can no longer self-cancel
  /// (staff always can). Default 60.
  final int bookingCancelCutoffMinutes;
  /// Max simultaneous active (confirmed+waitlist) future reservations per
  /// student. Default 3.
  final int maxActiveBookingsPerStudent;

  /// Striking module (C1–C3: timer de rounds, registro de sessão, cartel,
  /// combinações). Opt-in per academy, default off.
  final bool strikingEnabled;

  /// Default monthly attendance goal (A4) shown to every student unless they
  /// have a per-student override. 0 = disabled (no goal shown).
  final int monthlyAttendanceGoal;

  // Monitors (students with additional permissions)
  final List<String> monitorIds;

  /// Passos do checklist de ativação que o dono dispensou ("não vou usar") —
  /// somem do checklist e não contam contra a conclusão. Ex.: uma academia que
  /// não vai usar o Mercado Pago dispensa esse passo e o checklist completa.
  final List<String> onboardingDismissedSteps;

  /// Quando o dono saiu do wizard `/admin/comece-aqui` (SPEC_ONBOARDING_2026-07
  /// §0.1/Fatia 7) — por "Pular" explícito OU por concluir o último passo
  /// ("Ir para o Painel"). `null` = nunca visto. Único gate de "mostra 1x": o
  /// router NUNCA redireciona pra lá de novo depois que este campo é setado,
  /// mesmo que a academia continue sem turma/aluno/presença (ex.: fitness que
  /// só compartilhou o código e ainda não teve nenhum aluno aprovado).
  final DateTime? wizardSkippedAt;

  /// Perfil de negócio ('fight' | 'fitness' | 'hybrid') — raw string, parsed
  /// via `AcademyProfileExtension.fromString` (models/academy.dart) at the
  /// point of use, which defaults `null`/unrecognized to 'fight'. Kept raw
  /// here (not the enum) so this service stays decoupled from the model.
  /// Drives copy/vocabulary (core/academy_vocab.dart) and the academy's
  /// default modality — NOT a feature gate.
  final String? profile;

  final DateTime? updatedAt;

  AcademySettings({
    required this.name,
    this.slug,
    this.cnpj,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.state,
    this.zipCode,
    this.responsibleBirthDate,
    this.logoUrl,
    this.portalSlogan,
    this.sidebarLogoUrl,
    this.portalBackgroundUrl,
    this.adminBackgroundUrl,
    this.sidebarBackgroundUrl,
    this.pixKey,
    this.pixKeyType,
    this.abacatePayEnabled = false,
    this.asaasEnabled = false,
    this.asaasOnboardingStatus,
    this.asaasKycStatus,
    this.asaasKycOnboardingUrl,
    this.mpConnected = false,
    this.mpPublicKey,
    this.mpNeedsReauth = false,
    this.mpHasOrphanPreapprovals = false,
    this.mpOrphanPreapprovalCount = 0,
    this.autoGraduationEnabled = false,
    this.autoGraduationAttendances,
    this.graduationRequirementsBySport = const {},
    this.useClassWeights = false,
    this.graduationMode = 'manual',
    this.graduationProgressVisibleToStudents = false,
    this.graduationSkillPolicy = 'informative',
    this.graduationMinSkillPct = 80,
    this.storeEnabled = false,
    this.storePublished = false,
    this.storeCreditCardEnabled = false,
    this.storeWelcomeMessage,
    this.storeMinOrderAmount,
    this.studentCheckinEnabled = false,
    this.journalVisibleToStudents = true,
    this.rankingVisibleToStudents = true,
    this.workoutPlansEnabled = false,
    this.trainingVideosEnabled = false,
    this.physicalEvolutionEnabled = false,
    this.musculacaoEnabled = true,
    this.accessControl = const {},
    this.musculacaoCheckinMode = 'manual',
    this.operatingHours = OperatingHours.empty,
    this.muaythaiGradeSystem = 'cbmt',
    this.bookingEnabled = false,
    this.bookingWindowDays = 7,
    this.bookingCancelCutoffMinutes = 60,
    this.maxActiveBookingsPerStudent = 3,
    this.strikingEnabled = false,
    this.monthlyAttendanceGoal = 0,
    this.monitorIds = const [],
    this.onboardingDismissedSteps = const [],
    this.wizardSkippedAt,
    this.profile,
    this.updatedAt,
  });

  /// Parses the nested {sportValue: {gradeId: classes}} map from Firestore,
  /// dropping non-positive entries.
  static Map<String, Map<String, int>> _parseRequirementsBySport(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, Map<String, int>>{};
    raw.forEach((sport, belts) {
      if (belts is Map) {
        final byBelt = <String, int>{};
        belts.forEach((belt, n) {
          if (n is num && n > 0) byBelt[belt.toString()] = n.toInt();
        });
        if (byBelt.isNotEmpty) out[sport.toString()] = byBelt;
      }
    });
    return out;
  }

  /// O backend grava mpOrphanPreapprovalIds de forma inconsistente (ora a LISTA
  /// de ids, ora só a CONTAGEM) — normaliza para um int defensivamente.
  static int _parseOrphanCount(dynamic v) {
    if (v is List) return v.length;
    if (v is num) return v.toInt();
    return 0;
  }

  factory AcademySettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AcademySettings(
      name: data['name'] ?? 'Minha Academia',
      slug: data['slug'],
      cnpj: data['cnpj'],
      email: data['email'],
      phone: data['phone'],
      address: data['address'],
      city: data['city'],
      state: data['state'],
      zipCode: data['zipCode'],
      responsibleBirthDate: data['responsibleBirthDate'],
      logoUrl: data['logoUrl'],
      portalSlogan: data['portalSlogan'],
      sidebarLogoUrl: data['sidebarLogoUrl'],
      portalBackgroundUrl: data['portalBackgroundUrl'],
      adminBackgroundUrl: data['adminBackgroundUrl'],
      sidebarBackgroundUrl: data['sidebarBackgroundUrl'],
      pixKey: data['pixKey'],
      pixKeyType: data['pixKeyType'] != null
          ? PixKeyTypeExtension.fromString(data['pixKeyType'])
          : null,
      abacatePayEnabled: data['abacatePayEnabled'] ?? false,
      asaasEnabled: data['asaasEnabled'] ?? false,
      asaasOnboardingStatus: data['asaasOnboardingStatus'],
      asaasKycStatus: data['asaasKycStatus'],
      asaasKycOnboardingUrl: data['asaasKycOnboardingUrl'],
      mpConnected: data['mpConnected'] ?? false,
      mpPublicKey: data['mpPublicKey'],
      mpNeedsReauth: data['mpNeedsReauth'] ?? false,
      mpHasOrphanPreapprovals: data['mpHasOrphanPreapprovals'] == true,
      mpOrphanPreapprovalCount:
          _parseOrphanCount(data['mpOrphanPreapprovalIds']),
      autoGraduationEnabled: data['autoGraduationEnabled'] ?? false,
      autoGraduationAttendances: data['autoGraduationAttendances'],
      graduationRequirementsBySport:
          _parseRequirementsBySport(data['graduationRequirementsBySport']),
      useClassWeights: data['useClassWeights'] ?? false,
      graduationMode: (data['graduationMode'] as String?) ?? 'manual',
      graduationProgressVisibleToStudents:
          data['graduationProgressVisibleToStudents'] ?? false,
      graduationSkillPolicy:
          (data['graduationSkillPolicy'] as String?) ?? 'informative',
      graduationMinSkillPct:
          (data['graduationMinSkillPct'] as num?)?.toInt() ?? 80,
      storeEnabled: data['storeEnabled'] ?? false,
      storePublished: data['storePublished'] ?? false,
      storeCreditCardEnabled: data['storeCreditCardEnabled'] ?? false,
      storeWelcomeMessage: data['storeWelcomeMessage'],
      storeMinOrderAmount: data['storeMinOrderAmount']?.toDouble(),
      studentCheckinEnabled: data['studentCheckinEnabled'] ?? false,
      journalVisibleToStudents: data['journalVisibleToStudents'] ?? true,
      rankingVisibleToStudents: data['rankingVisibleToStudents'] ?? true,
      workoutPlansEnabled: data['workoutPlansEnabled'] ?? false,
      trainingVideosEnabled: data['trainingVideosEnabled'] ?? false,
      physicalEvolutionEnabled: data['physicalEvolutionEnabled'] ?? false,
      musculacaoEnabled: data['musculacaoEnabled'] ?? true,
      accessControl: (data['accessControl'] as Map?)?.cast<String, dynamic>() ??
          const {},
      musculacaoCheckinMode:
          (data['musculacaoCheckinMode'] as String?) ?? 'manual',
      operatingHours: OperatingHours.fromMap(
        data['operatingHours'] as Map<String, dynamic>?,
      ),
      muaythaiGradeSystem:
          (data['muaythaiGradeSystem'] as String?) ?? 'cbmt',
      bookingEnabled: data['bookingEnabled'] ?? false,
      bookingWindowDays: (data['bookingWindowDays'] as num?)?.toInt() ?? 7,
      bookingCancelCutoffMinutes:
          (data['bookingCancelCutoffMinutes'] as num?)?.toInt() ?? 60,
      maxActiveBookingsPerStudent:
          (data['maxActiveBookingsPerStudent'] as num?)?.toInt() ?? 3,
      strikingEnabled: data['strikingEnabled'] ?? false,
      monthlyAttendanceGoal:
          (data['monthlyAttendanceGoal'] as num?)?.toInt() ?? 0,
      monitorIds: List<String>.from(data['monitorIds'] ?? []),
      onboardingDismissedSteps:
          List<String>.from(data['onboardingDismissedSteps'] ?? []),
      wizardSkippedAt: (data['wizardSkippedAt'] as Timestamp?)?.toDate(),
      profile: data['profile'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Computed properties
  String get fullAddress {
    final parts = <String>[];
    if (address != null) parts.add(address!);
    if (city != null) parts.add(city!);
    if (state != null) parts.add(state!);
    if (zipCode != null) parts.add(zipCode!);
    return parts.join(', ');
  }

  bool get hasPixKey => pixKey != null && pixKey!.isNotEmpty;

  /// Classes required to advance within [beltId] of [sportValue], or null when
  /// not configured per-belt for that sport (caller falls back to the global
  /// [autoGraduationAttendances] / legacy defaults).
  int? graduationRequirementFor(String sportValue, String beltId) {
    final n = graduationRequirementsBySport[sportValue]?[beltId];
    return (n != null && n > 0) ? n : null;
  }

  /// Whether any payment provider is enabled (Mercado Pago, AbacatePay or Asaas)
  bool get isPaymentEnabled => mpConnected || abacatePayEnabled || asaasEnabled;

  /// Whether musculação students record their own attendance (vs. staff doing
  /// it manually). Both 'qr' and 'button' modes go through the selfCheckin
  /// Cloud Function.
  bool get musculacaoSelfCheckin =>
      musculacaoCheckinMode == 'qr' || musculacaoCheckinMode == 'button';
}

/// Settings Service - Multi-tenant settings management
class SettingsService {
  final String academyId;
  late final Collections _collections;

  SettingsService(this.academyId) {
    _collections = Collections(academyId);
  }

  DocumentReference get _academyRef => _collections.academy;

  // ============================================
  // Get Academy Settings
  // ============================================
  Future<AcademySettings?> getAcademySettings() async {
    try {
      final doc = await _academyRef.get();
      if (!doc.exists) {
        return AcademySettings(name: 'Minha Academia');
      }
      return AcademySettings.fromFirestore(doc);
    } catch (e) {
      return null;
    }
  }

  // ============================================
  // Get Academy Name
  // ============================================
  Future<String> getAcademyName() async {
    final settings = await getAcademySettings();
    return settings?.name ?? 'Minha Academia';
  }

  // ============================================
  // Get Academy Logo URL
  // ============================================
  Future<String?> getLogoUrl() async {
    final settings = await getAcademySettings();
    return settings?.logoUrl;
  }

  // ============================================
  // Get PIX Info
  // ============================================
  Future<Map<String, String?>> getPixInfo() async {
    final settings = await getAcademySettings();
    return {
      'key': settings?.pixKey,
      'type': settings?.pixKeyType?.value,
    };
  }

  // ============================================
  // Check if AbacatePay is Enabled
  // ============================================
  Future<bool> isAbacatePayEnabled() async {
    final settings = await getAcademySettings();
    return settings?.abacatePayEnabled ?? false;
  }

  // ============================================
  // Check if Auto-graduation is Enabled
  // ============================================
  Future<bool> isAutoGraduationEnabled() async {
    final settings = await getAcademySettings();
    return settings?.autoGraduationEnabled ?? false;
  }

  // ============================================
  // Get Auto-graduation Attendances Threshold
  // ============================================
  Future<int?> getAutoGraduationAttendances() async {
    final settings = await getAcademySettings();
    return settings?.autoGraduationAttendances;
  }

  // ============================================
  // Check if Store is Enabled
  // ============================================
  Future<bool> isStoreEnabled() async {
    final settings = await getAcademySettings();
    return settings?.storeEnabled ?? false;
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Save Academy Settings
  // ============================================
  Future<AcademySettings> saveAcademySettings(Map<String, dynamic> settings) async {
    settings['updatedAt'] = FieldValue.serverTimestamp();
    await _academyRef.set(settings, SetOptions(merge: true));
    final updated = await getAcademySettings();
    return updated!;
  }

  // ============================================
  // Update Logo
  // ============================================
  Future<void> updateLogo(String logoUrl) async {
    await _academyRef.update({
      'logoUrl': logoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Update Sidebar Logo
  // ============================================
  Future<void> updateSidebarLogo(String sidebarLogoUrl) async {
    await _academyRef.update({
      'sidebarLogoUrl': sidebarLogoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Toggle AbacatePay
  // API key is global (in backend environment variable), not per-academy
  // ============================================
  Future<void> toggleAbacatePay(bool enabled) async {
    await _academyRef.update({
      'abacatePayEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Check if Asaas is Enabled
  // ============================================
  Future<bool> isAsaasEnabled() async {
    final settings = await getAcademySettings();
    return settings?.asaasEnabled ?? false;
  }

  // ============================================
  // Toggle Asaas
  // ============================================
  Future<void> toggleAsaas(bool enabled) async {
    await _academyRef.update({
      'asaasEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Update Auto-graduation Settings
  // ============================================
  Future<void> updateAutoGraduation(
    bool enabled, {
    int? attendances,
    String? mode,
    bool? progressVisibleToStudents,
    Map<String, Map<String, int>>? requirementsBySport,
    String? skillPolicy,
    int? minSkillPct,
  }) async {
    final data = <String, dynamic>{
      'autoGraduationEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (attendances != null) {
      data['autoGraduationAttendances'] = attendances;
    }
    if (mode != null) {
      data['graduationMode'] = mode;
    }
    if (progressVisibleToStudents != null) {
      data['graduationProgressVisibleToStudents'] = progressVisibleToStudents;
    }
    if (requirementsBySport != null) {
      data['graduationRequirementsBySport'] = requirementsBySport;
    }
    if (skillPolicy != null) {
      data['graduationSkillPolicy'] = skillPolicy;
    }
    if (minSkillPct != null) {
      data['graduationMinSkillPct'] = minSkillPct;
    }
    await _academyRef.update(data);
  }

  // ============================================
  // Toggle Class Weights Feature
  // ============================================
  Future<void> updateUseClassWeights(bool enabled) async {
    await _academyRef.update({
      'useClassWeights': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Update PIX Info
  // ============================================
  Future<void> updatePixInfo(String pixKey, PixKeyType pixKeyType) async {
    await _academyRef.update({
      'pixKey': pixKey,
      'pixKeyType': pixKeyType.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Update PIX (set or clear)
  // ============================================
  /// Sets the PIX key/type when both are provided, or clears them otherwise.
  /// Unlike [updatePixInfo] (which can only set), this lets the settings form
  /// remove a PIX key — previously a cleared/partial PIX was silently ignored.
  Future<void> updatePix({String? pixKey, PixKeyType? pixKeyType}) async {
    final key = pixKey ?? '';
    final type = pixKeyType;
    if (key.isNotEmpty && type != null) {
      await _academyRef.update({
        'pixKey': key,
        'pixKeyType': type.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _academyRef.update({
        'pixKey': FieldValue.delete(),
        'pixKeyType': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ============================================
  // Update Store Settings
  // ============================================
  Future<void> updateStoreSettings({
    bool? enabled,
    bool? published,
    bool? creditCardEnabled,
    String? welcomeMessage,
    double? minOrderAmount,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (enabled != null) data['storeEnabled'] = enabled;
    if (published != null) data['storePublished'] = published;
    if (creditCardEnabled != null) data['storeCreditCardEnabled'] = creditCardEnabled;
    if (welcomeMessage != null) data['storeWelcomeMessage'] = welcomeMessage;
    if (minOrderAmount != null) data['storeMinOrderAmount'] = minOrderAmount;

    await _academyRef.update(data);
  }

  // ============================================
  // Toggle Student Check-in
  // ============================================
  Future<void> toggleStudentCheckin(bool enabled) async {
    await _academyRef.update({
      'studentCheckinEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Toggle Jornal Visibility for Students
  // ============================================
  Future<void> updateJournalVisibility(bool value) async {
    await _academyRef.set({
      'journalVisibleToStudents': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================
  // Toggle Ranking Visibility for Students
  // ============================================
  Future<void> updateRankingVisibility(bool value) async {
    await _academyRef.set({
      'rankingVisibleToStudents': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================
  // Toggle Workout Plans Feature
  // ============================================
  Future<void> updateWorkoutPlansEnabled(bool value) async {
    await _academyRef.set({
      'workoutPlansEnabled': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================
  // Toggle Training Videos Feature
  // ============================================
  Future<void> updateTrainingVideosEnabled(bool value) async {
    await _academyRef.set({
      'trainingVideosEnabled': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================
  // Reserva de aula (A1): master toggle + tunables
  // ============================================
  Future<void> updateBookingEnabled(bool value) async {
    await _academyRef.set({
      'bookingEnabled': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateBookingSettings({
    int? windowDays,
    int? cancelCutoffMinutes,
    int? maxActivePerStudent,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (windowDays != null) data['bookingWindowDays'] = windowDays;
    if (cancelCutoffMinutes != null) {
      data['bookingCancelCutoffMinutes'] = cancelCutoffMinutes;
    }
    if (maxActivePerStudent != null) {
      data['maxActiveBookingsPerStudent'] = maxActivePerStudent;
    }
    await _academyRef.set(data, SetOptions(merge: true));
  }

  // ============================================
  // Gamificação (A4): meta de frequência mensal (padrão da academia)
  // ============================================
  Future<void> updateMonthlyAttendanceGoal(int value) async {
    await _academyRef.set({
      'monthlyAttendanceGoal': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================
  // Trocação (C1–C3): master toggle
  // ============================================
  Future<void> updateStrikingEnabled(bool value) async {
    await _academyRef.set({
      'strikingEnabled': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================
  // Toggle Physical Evolution (avaliações físicas) Feature
  // ============================================
  Future<void> updatePhysicalEvolutionEnabled(bool value) async {
    await _academyRef.set({
      'physicalEvolutionEnabled': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================
  // Toggle Musculação Feature (master on/off)
  // ============================================
  Future<void> updateMusculacaoEnabled(bool value) async {
    await _academyRef.set({
      'musculacaoEnabled': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Atualiza a config de controle de acesso (catraca) no sub-mapa
  /// academies/{id}.accessControl — o MESMO doc lido por
  /// functions/access_control/{financial_gate,ingest}.js. Usa dot-paths via
  /// update() (o doc da academia sempre existe) para mexer só nos campos dados,
  /// preservando o resto do mapa (ex.: exemptStudentIds/message futuros) e não
  /// brigando com o save em massa de settings.
  Future<void> updateAccessControl({
    required bool enabled,
    String? vendor,
    bool? blockOnOverdue,
    int? graceDays,
    List<String>? blockTypes,
  }) async {
    await _academyRef.update({
      'accessControl.enabled': enabled,
      if (vendor != null) 'accessControl.vendor': vendor,
      if (blockOnOverdue != null) 'accessControl.blockOnOverdue': blockOnOverdue,
      if (graceDays != null) 'accessControl.graceDays': graceDays,
      if (blockTypes != null) 'accessControl.blockTypes': blockTypes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Update Musculação Check-in (mode + operating hours)
  // ============================================
  Future<void> updateMusculacaoCheckin({
    String? mode,
    OperatingHours? operatingHours,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (mode != null) data['musculacaoCheckinMode'] = mode;
    if (operatingHours != null) {
      data['operatingHours'] = operatingHours.toMap();
    }
    await _academyRef.update(data);
  }

  // ============================================
  // Update Muay Thai Graduation System ('cbmt' | 'cbmtt')
  // ============================================
  Future<void> updateMuaythaiGradeSystem(String system) async {
    await _academyRef.update({
      'muaythaiGradeSystem': system,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Update Academy Profile ('fight' | 'fitness' | 'hybrid')
  // ============================================
  Future<void> updateAcademyProfile(String profile) async {
    await _academyRef.set({
      'profile': profile,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================
  // Update Basic Info
  // ============================================
  Future<void> updateBasicInfo({
    String? name,
    String? cnpj,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? responsibleBirthDate,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) data['name'] = name;
    if (cnpj != null) data['cnpj'] = cnpj;
    if (email != null) data['email'] = email;
    if (phone != null) data['phone'] = phone;
    if (address != null) data['address'] = address;
    if (city != null) data['city'] = city;
    if (state != null) data['state'] = state;
    if (zipCode != null) data['zipCode'] = zipCode;
    if (responsibleBirthDate != null) data['responsibleBirthDate'] = responsibleBirthDate;

    await _academyRef.update(data);
  }

  // ============================================
  // Update Branding
  // ============================================
  Future<void> updateBranding({
    String? portalSlogan,
    String? portalBackgroundUrl,
    String? adminBackgroundUrl,
    String? sidebarBackgroundUrl,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (portalSlogan != null) data['portalSlogan'] = portalSlogan;
    if (portalBackgroundUrl != null) data['portalBackgroundUrl'] = portalBackgroundUrl;
    if (adminBackgroundUrl != null) data['adminBackgroundUrl'] = adminBackgroundUrl;
    if (sidebarBackgroundUrl != null) data['sidebarBackgroundUrl'] = sidebarBackgroundUrl;

    await _academyRef.update(data);
  }

  // ============================================
  // Monitor Management
  // ============================================

  /// Get list of monitor IDs
  Future<List<String>> getMonitors() async {
    try {
      final doc = await _academyRef.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return List<String>.from(data['monitorIds'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Add a student as monitor
  Future<void> addMonitor(String studentId) async {
    await _academyRef.update({
      'monitorIds': FieldValue.arrayUnion([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Dispensa um passo do checklist de ativação (o dono optou por não fazê-lo).
  Future<void> dismissOnboardingStep(String stepId) async {
    await _academyRef.update({
      'onboardingDismissedSteps': FieldValue.arrayUnion([stepId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marca o wizard `/admin/comece-aqui` como visto (SPEC_ONBOARDING_2026-07
  /// §0.1/Fatia 7) — chamado tanto por um "Pular" explícito em qualquer passo
  /// quanto pelo "Ir para o Painel" do último passo. Idempotente (pode ser
  /// chamado mais de uma vez sem efeito colateral: só a 1ª escrita importa
  /// pro gate, que só olha "não-nulo").
  Future<void> markWizardSeen() async {
    await _academyRef.update({
      'wizardSkippedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Remove a student from monitors
  Future<void> removeMonitor(String studentId) async {
    await _academyRef.update({
      'monitorIds': FieldValue.arrayRemove([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

// ============================================
// Factory Function
// ============================================
SettingsService createSettingsService(String academyId) {
  return SettingsService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
SettingsService get settingsService => SettingsService(FirebaseService.academyId);
