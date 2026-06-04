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

  // Musculação (schedule-less) check-in.
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

  // Monitors (students with additional permissions)
  final List<String> monitorIds;

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
    this.autoGraduationEnabled = false,
    this.autoGraduationAttendances,
    this.graduationRequirementsBySport = const {},
    this.useClassWeights = false,
    this.graduationMode = 'manual',
    this.graduationProgressVisibleToStudents = false,
    this.storeEnabled = false,
    this.storePublished = false,
    this.storeCreditCardEnabled = false,
    this.storeWelcomeMessage,
    this.storeMinOrderAmount,
    this.studentCheckinEnabled = false,
    this.journalVisibleToStudents = true,
    this.rankingVisibleToStudents = true,
    this.musculacaoCheckinMode = 'manual',
    this.operatingHours = OperatingHours.empty,
    this.muaythaiGradeSystem = 'cbmt',
    this.monitorIds = const [],
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
      autoGraduationEnabled: data['autoGraduationEnabled'] ?? false,
      autoGraduationAttendances: data['autoGraduationAttendances'],
      graduationRequirementsBySport:
          _parseRequirementsBySport(data['graduationRequirementsBySport']),
      useClassWeights: data['useClassWeights'] ?? false,
      graduationMode: (data['graduationMode'] as String?) ?? 'manual',
      graduationProgressVisibleToStudents:
          data['graduationProgressVisibleToStudents'] ?? false,
      storeEnabled: data['storeEnabled'] ?? false,
      storePublished: data['storePublished'] ?? false,
      storeCreditCardEnabled: data['storeCreditCardEnabled'] ?? false,
      storeWelcomeMessage: data['storeWelcomeMessage'],
      storeMinOrderAmount: data['storeMinOrderAmount']?.toDouble(),
      studentCheckinEnabled: data['studentCheckinEnabled'] ?? false,
      journalVisibleToStudents: data['journalVisibleToStudents'] ?? true,
      rankingVisibleToStudents: data['rankingVisibleToStudents'] ?? true,
      musculacaoCheckinMode:
          (data['musculacaoCheckinMode'] as String?) ?? 'manual',
      operatingHours: OperatingHours.fromMap(
        data['operatingHours'] as Map<String, dynamic>?,
      ),
      muaythaiGradeSystem:
          (data['muaythaiGradeSystem'] as String?) ?? 'cbmt',
      monitorIds: List<String>.from(data['monitorIds'] ?? []),
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
