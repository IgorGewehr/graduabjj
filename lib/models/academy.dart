import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/dto/academy_dto.dart' as api;

/// Academy Subscription Plan
enum SubscriptionPlan { free, basic, premium, enterprise }

extension SubscriptionPlanExtension on SubscriptionPlan {
  String get value {
    switch (this) {
      case SubscriptionPlan.free:
        return 'free';
      case SubscriptionPlan.basic:
        return 'basic';
      case SubscriptionPlan.premium:
        return 'premium';
      case SubscriptionPlan.enterprise:
        return 'enterprise';
    }
  }

  static SubscriptionPlan fromString(String value) {
    switch (value) {
      case 'basic':
        return SubscriptionPlan.basic;
      case 'premium':
        return SubscriptionPlan.premium;
      case 'enterprise':
        return SubscriptionPlan.enterprise;
      default:
        return SubscriptionPlan.free;
    }
  }
}

/// Subscription Status
enum SubscriptionStatus { active, cancelled, pastDue, trialing }

extension SubscriptionStatusExtension on SubscriptionStatus {
  String get value {
    switch (this) {
      case SubscriptionStatus.active:
        return 'active';
      case SubscriptionStatus.cancelled:
        return 'cancelled';
      case SubscriptionStatus.pastDue:
        return 'past_due';
      case SubscriptionStatus.trialing:
        return 'trialing';
    }
  }

  static SubscriptionStatus fromString(String value) {
    switch (value) {
      case 'cancelled':
        return SubscriptionStatus.cancelled;
      case 'past_due':
        return SubscriptionStatus.pastDue;
      case 'trialing':
        return SubscriptionStatus.trialing;
      default:
        return SubscriptionStatus.active;
    }
  }
}

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
        return 'Email';
      case PixKeyType.phone:
        return 'Telefone';
      case PixKeyType.random:
        return 'Chave Aleatoria';
    }
  }

  static PixKeyType fromString(String value) {
    switch (value) {
      case 'cnpj':
        return PixKeyType.cnpj;
      case 'email':
        return PixKeyType.email;
      case 'phone':
        return PixKeyType.phone;
      case 'random':
        return PixKeyType.random;
      default:
        return PixKeyType.cpf;
    }
  }
}

/// Academy Subscription Model
class AcademySubscription {
  final SubscriptionPlan plan;
  final SubscriptionStatus status;
  final DateTime? expiresAt;
  final DateTime? trialEndsAt;

  AcademySubscription({
    required this.plan,
    required this.status,
    this.expiresAt,
    this.trialEndsAt,
  });

  factory AcademySubscription.fromMap(Map<String, dynamic> map) {
    return AcademySubscription(
      plan: SubscriptionPlanExtension.fromString(map['plan'] ?? 'free'),
      status: SubscriptionStatusExtension.fromString(map['status'] ?? 'active'),
      expiresAt: map['expiresAt'] != null
          ? (map['expiresAt'] as Timestamp).toDate()
          : null,
      trialEndsAt: map['trialEndsAt'] != null
          ? (map['trialEndsAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'plan': plan.value,
      'status': status.value,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'trialEndsAt': trialEndsAt != null ? Timestamp.fromDate(trialEndsAt!) : null,
    };
  }
}

/// Academy Model (Tenant)
class Academy {
  final String id;
  final String name;
  final String slug;
  final String? logoUrl;

  // Branding
  final String? portalSlogan;
  final String? sidebarLogoUrl;
  final String? portalBackgroundUrl;
  final String? adminBackgroundUrl;
  final String? sidebarBackgroundUrl;

  // Contact Info
  final String? cnpj;
  final String? email;
  final String? phone;

  // Address
  final String? address;
  final String? city;
  final String? state;
  final String? zipCode;

  // Responsible Person (for Asaas onboarding)
  final String? responsibleBirthDate; // YYYY-MM-DD

  // Financial Settings
  final String? pixKey;
  final PixKeyType? pixKeyType;

  // AbacatePay Integration (API key is global in backend env, not per-academy)
  final bool abacatePayEnabled;

  // Asaas Integration (per-academy sub-account with own API key)
  final bool asaasEnabled;
  final String? asaasOnboardingStatus; // 'pending', 'approved', 'rejected'

  // Auto-graduation Settings
  final bool autoGraduationEnabled;
  final int? autoGraduationAttendances;

  // Store Settings
  final bool storeEnabled;
  final bool storePublished;
  final String? storeWelcomeMessage;
  final int? storeMinOrderAmount;

  // Student Check-in Settings
  final bool studentCheckinEnabled;

  // Subscription
  final AcademySubscription? subscription;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final String ownerId;

  Academy({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl,
    this.portalSlogan,
    this.sidebarLogoUrl,
    this.portalBackgroundUrl,
    this.adminBackgroundUrl,
    this.sidebarBackgroundUrl,
    this.cnpj,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.state,
    this.zipCode,
    this.responsibleBirthDate,
    this.pixKey,
    this.pixKeyType,
    this.abacatePayEnabled = false,
    this.asaasEnabled = false,
    this.asaasOnboardingStatus,
    this.autoGraduationEnabled = false,
    this.autoGraduationAttendances,
    this.storeEnabled = false,
    this.storePublished = false,
    this.storeWelcomeMessage,
    this.storeMinOrderAmount,
    this.studentCheckinEnabled = false,
    this.subscription,
    required this.createdAt,
    required this.updatedAt,
    required this.ownerId,
  });

  /// Constrói um [Academy] a partir do DTO [api.ApiAcademy] (resposta dos
  /// endpoints `GET/PUT /v1/academies/{id}` do Tatami).
  ///
  /// Sprint 1B adapter (FE-only). Esta factory é o ponto de tradução
  /// snake_case → camelCase entre o backend novo e o domain legacy.
  ///
  /// Pontos de atenção:
  /// - O contrato Tatami NÃO expõe campos de branding (`logo_url`,
  ///   `portal_slogan`, sidebar/background URLs). Esses campos ficam null
  ///   na conversão — o caller que precisa renderizar branding deve
  ///   recuperar do Firestore via merge enquanto o BE não expor branding
  ///   multi-tenant (Sprint B no plano de migração).
  /// - O endereço Tatami é um subset (street/city/state/zip) — sem
  ///   `number`, `complement`, `neighborhood`. Como o legacy `address` é
  ///   `String?` (não objeto), serializamos o subset como string única
  ///   "street, city/state, zip" quando há dados.
  /// - `subscription_status` Tatami inclui `trial` e `suspended`, que não
  ///   existem no enum legacy `SubscriptionStatus`. `trial` vira `trialing`
  ///   e `suspended` vira `cancelled` (degradação segura — o usuário perde
  ///   acesso em qualquer um dos dois estados).
  /// - Tatami não devolve `subscription_plan` como enum, e sim string livre
  ///   (`null` quando não set). Mapeamos string → SubscriptionPlan legacy.
  static Academy fromApi(api.ApiAcademy a) {
    return Academy(
      id: a.id,
      name: a.name,
      slug: a.slug,
      logoUrl: null,
      portalSlogan: null,
      sidebarLogoUrl: null,
      portalBackgroundUrl: null,
      adminBackgroundUrl: null,
      sidebarBackgroundUrl: null,
      cnpj: a.cnpj,
      email: a.email,
      phone: a.phone,
      address: _formatAddress(a.address),
      city: a.address?.city,
      state: a.address?.state,
      zipCode: a.address?.zipCode,
      pixKey: a.pixKey,
      pixKeyType: _mapPixKeyType(a.pixKeyType),
      abacatePayEnabled: a.abacatePayEnabled,
      asaasEnabled: a.asaasEnabled,
      asaasOnboardingStatus: a.asaasOnboardingStatus,
      autoGraduationEnabled: a.autoGraduationEnabled,
      autoGraduationAttendances: a.autoGraduationAttendances,
      storeEnabled: a.storeEnabled,
      storePublished: a.storePublished,
      studentCheckinEnabled: a.studentCheckinEnabled,
      subscription: AcademySubscription(
        plan: a.subscriptionPlan != null
            ? SubscriptionPlanExtension.fromString(a.subscriptionPlan!)
            : SubscriptionPlan.free,
        status: _mapSubscriptionStatus(a.subscriptionStatus),
        expiresAt: a.subscriptionExpiresAt,
      ),
      createdAt: a.createdAt,
      updatedAt: a.updatedAt,
      ownerId: a.ownerUid,
    );
  }

  factory Academy.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Academy(
      id: doc.id,
      name: data['name'] ?? '',
      slug: data['slug'] ?? '',
      logoUrl: data['logoUrl'],
      portalSlogan: data['portalSlogan'],
      sidebarLogoUrl: data['sidebarLogoUrl'],
      portalBackgroundUrl: data['portalBackgroundUrl'],
      adminBackgroundUrl: data['adminBackgroundUrl'],
      sidebarBackgroundUrl: data['sidebarBackgroundUrl'],
      cnpj: data['cnpj'],
      email: data['email'],
      phone: data['phone'],
      address: data['address'],
      city: data['city'],
      state: data['state'],
      zipCode: data['zipCode'],
      responsibleBirthDate: data['responsibleBirthDate'],
      pixKey: data['pixKey'],
      pixKeyType: data['pixKeyType'] != null
          ? PixKeyTypeExtension.fromString(data['pixKeyType'])
          : null,
      abacatePayEnabled: data['abacatePayEnabled'] ?? false,
      asaasEnabled: data['asaasEnabled'] ?? false,
      asaasOnboardingStatus: data['asaasOnboardingStatus'],
      autoGraduationEnabled: data['autoGraduationEnabled'] ?? false,
      autoGraduationAttendances: data['autoGraduationAttendances'],
      storeEnabled: data['storeEnabled'] ?? false,
      storePublished: data['storePublished'] ?? false,
      storeWelcomeMessage: data['storeWelcomeMessage'],
      storeMinOrderAmount: data['storeMinOrderAmount'],
      studentCheckinEnabled: data['studentCheckinEnabled'] ?? false,
      subscription: data['subscription'] != null
          ? AcademySubscription.fromMap(data['subscription'])
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ownerId: data['ownerId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'slug': slug,
      'logoUrl': logoUrl,
      'portalSlogan': portalSlogan,
      'sidebarLogoUrl': sidebarLogoUrl,
      'portalBackgroundUrl': portalBackgroundUrl,
      'adminBackgroundUrl': adminBackgroundUrl,
      'sidebarBackgroundUrl': sidebarBackgroundUrl,
      'cnpj': cnpj,
      'email': email,
      'phone': phone,
      'address': address,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'responsibleBirthDate': responsibleBirthDate,
      'pixKey': pixKey,
      'pixKeyType': pixKeyType?.value,
      'abacatePayEnabled': abacatePayEnabled,
      'asaasEnabled': asaasEnabled,
      'asaasOnboardingStatus': asaasOnboardingStatus,
      'autoGraduationEnabled': autoGraduationEnabled,
      'autoGraduationAttendances': autoGraduationAttendances,
      'storeEnabled': storeEnabled,
      'storePublished': storePublished,
      'storeWelcomeMessage': storeWelcomeMessage,
      'storeMinOrderAmount': storeMinOrderAmount,
      'studentCheckinEnabled': studentCheckinEnabled,
      'subscription': subscription?.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'ownerId': ownerId,
    };
  }

  String get displaySlogan {
    if (portalSlogan != null && portalSlogan!.isNotEmpty) {
      return '$name - $portalSlogan';
    }
    return name;
  }

  String get effectiveLogoUrl => sidebarLogoUrl ?? logoUrl ?? '';

  Academy copyWith({
    String? id,
    String? name,
    String? slug,
    String? logoUrl,
    String? portalSlogan,
    String? sidebarLogoUrl,
    String? portalBackgroundUrl,
    String? adminBackgroundUrl,
    String? sidebarBackgroundUrl,
    String? cnpj,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? responsibleBirthDate,
    String? pixKey,
    PixKeyType? pixKeyType,
    bool? abacatePayEnabled,
    bool? asaasEnabled,
    String? asaasOnboardingStatus,
    bool? autoGraduationEnabled,
    int? autoGraduationAttendances,
    bool? storeEnabled,
    bool? storePublished,
    String? storeWelcomeMessage,
    int? storeMinOrderAmount,
    bool? studentCheckinEnabled,
    AcademySubscription? subscription,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? ownerId,
  }) {
    return Academy(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      logoUrl: logoUrl ?? this.logoUrl,
      portalSlogan: portalSlogan ?? this.portalSlogan,
      sidebarLogoUrl: sidebarLogoUrl ?? this.sidebarLogoUrl,
      portalBackgroundUrl: portalBackgroundUrl ?? this.portalBackgroundUrl,
      adminBackgroundUrl: adminBackgroundUrl ?? this.adminBackgroundUrl,
      sidebarBackgroundUrl: sidebarBackgroundUrl ?? this.sidebarBackgroundUrl,
      cnpj: cnpj ?? this.cnpj,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      responsibleBirthDate: responsibleBirthDate ?? this.responsibleBirthDate,
      pixKey: pixKey ?? this.pixKey,
      pixKeyType: pixKeyType ?? this.pixKeyType,
      abacatePayEnabled: abacatePayEnabled ?? this.abacatePayEnabled,
      asaasEnabled: asaasEnabled ?? this.asaasEnabled,
      asaasOnboardingStatus: asaasOnboardingStatus ?? this.asaasOnboardingStatus,
      autoGraduationEnabled: autoGraduationEnabled ?? this.autoGraduationEnabled,
      autoGraduationAttendances: autoGraduationAttendances ?? this.autoGraduationAttendances,
      storeEnabled: storeEnabled ?? this.storeEnabled,
      storePublished: storePublished ?? this.storePublished,
      storeWelcomeMessage: storeWelcomeMessage ?? this.storeWelcomeMessage,
      storeMinOrderAmount: storeMinOrderAmount ?? this.storeMinOrderAmount,
      studentCheckinEnabled: studentCheckinEnabled ?? this.studentCheckinEnabled,
      subscription: subscription ?? this.subscription,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerId: ownerId ?? this.ownerId,
    );
  }
}

// ============================================
// Helpers privados — adapters Tatami → legacy
// ============================================

PixKeyType? _mapPixKeyType(api.ApiPixKeyType? t) {
  if (t == null) return null;
  switch (t) {
    case api.ApiPixKeyType.cpf:
      return PixKeyType.cpf;
    case api.ApiPixKeyType.cnpj:
      return PixKeyType.cnpj;
    case api.ApiPixKeyType.email:
      return PixKeyType.email;
    case api.ApiPixKeyType.phone:
      return PixKeyType.phone;
    case api.ApiPixKeyType.random:
      return PixKeyType.random;
  }
}

/// Mapeia o status do Tatami pro enum legacy. `trial` → `trialing` (legacy
/// também é trial), `suspended` → `cancelled` (legacy não tem o conceito;
/// degradação segura — usuário perde acesso em ambos).
SubscriptionStatus _mapSubscriptionStatus(
  api.ApiAcademySubscriptionStatus s,
) {
  switch (s) {
    case api.ApiAcademySubscriptionStatus.trial:
      return SubscriptionStatus.trialing;
    case api.ApiAcademySubscriptionStatus.active:
      return SubscriptionStatus.active;
    case api.ApiAcademySubscriptionStatus.pastDue:
      return SubscriptionStatus.pastDue;
    case api.ApiAcademySubscriptionStatus.canceled:
    case api.ApiAcademySubscriptionStatus.suspended:
      return SubscriptionStatus.cancelled;
  }
}

/// Serializa o endereço Tatami (subset estruturado) na string única que o
/// legacy espera em `Academy.address`. Retorna null quando todos os campos
/// estão vazios — o caller distingue "sem endereço" de "endereço vazio".
String? _formatAddress(api.ApiAcademyAddress? a) {
  if (a == null || a.isEmpty) return null;
  final parts = <String>[];
  if (a.street != null && a.street!.isNotEmpty) parts.add(a.street!);
  final cityState = <String>[];
  if (a.city != null && a.city!.isNotEmpty) cityState.add(a.city!);
  if (a.state != null && a.state!.isNotEmpty) cityState.add(a.state!);
  if (cityState.isNotEmpty) parts.add(cityState.join('/'));
  if (a.zipCode != null && a.zipCode!.isNotEmpty) parts.add(a.zipCode!);
  return parts.isEmpty ? null : parts.join(', ');
}
