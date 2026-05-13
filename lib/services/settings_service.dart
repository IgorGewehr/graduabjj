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

  // Auto-graduation Settings
  final bool autoGraduationEnabled;
  final int? autoGraduationAttendances;
  /// When true, attendance counts use Class.weight instead of 1 per doc.
  final bool useClassWeights;

  // Store Settings
  final bool storeEnabled;
  final bool storePublished;
  final bool storeCreditCardEnabled;
  final String? storeWelcomeMessage;
  final double? storeMinOrderAmount;

  // Student Check-in Settings
  final bool studentCheckinEnabled;

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
    this.autoGraduationEnabled = false,
    this.autoGraduationAttendances,
    this.useClassWeights = false,
    this.storeEnabled = false,
    this.storePublished = false,
    this.storeCreditCardEnabled = false,
    this.storeWelcomeMessage,
    this.storeMinOrderAmount,
    this.studentCheckinEnabled = false,
    this.monitorIds = const [],
    this.updatedAt,
  });

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
      autoGraduationEnabled: data['autoGraduationEnabled'] ?? false,
      autoGraduationAttendances: data['autoGraduationAttendances'],
      useClassWeights: data['useClassWeights'] ?? false,
      storeEnabled: data['storeEnabled'] ?? false,
      storePublished: data['storePublished'] ?? false,
      storeCreditCardEnabled: data['storeCreditCardEnabled'] ?? false,
      storeWelcomeMessage: data['storeWelcomeMessage'],
      storeMinOrderAmount: data['storeMinOrderAmount']?.toDouble(),
      studentCheckinEnabled: data['studentCheckinEnabled'] ?? false,
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

  /// Whether any payment provider is enabled (AbacatePay or Asaas)
  bool get isPaymentEnabled => abacatePayEnabled || asaasEnabled;
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
  Future<void> updateAutoGraduation(bool enabled, {int? attendances}) async {
    final data = <String, dynamic>{
      'autoGraduationEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (attendances != null) {
      data['autoGraduationAttendances'] = attendances;
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
