import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

/// Academy Subscription Plan.
/// `pro` = assinante pago via Cakto. Importante: `pro` NÃO concede acesso
/// permanente (diferente de premium/enterprise) — o acesso do assinante é
/// regido por `paidUntil`, então quando o período pago vence ele é bloqueado.
enum SubscriptionPlan { free, basic, pro, premium, enterprise }

extension SubscriptionPlanExtension on SubscriptionPlan {
  String get value {
    switch (this) {
      case SubscriptionPlan.free:
        return 'free';
      case SubscriptionPlan.basic:
        return 'basic';
      case SubscriptionPlan.pro:
        return 'pro';
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
      case 'pro':
        return SubscriptionPlan.pro;
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
  final DateTime? paidUntil;
  final bool freeOverride;

  /// Data de criação da academia. Usada como âncora do trial quando não há um
  /// [trialEndsAt] explícito (base legada): trial efetivo = createdAt + N dias.
  final DateTime? createdAt;

  AcademySubscription({
    required this.plan,
    required this.status,
    this.expiresAt,
    this.trialEndsAt,
    this.paidUntil,
    this.freeOverride = false,
    this.createdAt,
  });

  /// Fim do trial efetivo. **`createdAt` é a fonte de verdade**: o trial é
  /// sempre `createdAt + trialDays`, pra TODAS as academias — inclusive as
  /// antigas, que tinham um `trialEndsAt` de 30 dias gravado (esse valor antigo
  /// é ignorado de propósito). Quem deve manter acesso (pagantes/cortesia) é
  /// tratado por `paidUntil`/`freeOverride`, que têm prioridade em [hasAccess].
  /// Só cai no `trialEndsAt` explícito se, por algum motivo, não houver
  /// `createdAt` (caso raro).
  DateTime? get effectiveTrialEndsAt {
    if (createdAt != null) {
      return createdAt!.add(const Duration(days: AppConstants.trialDays));
    }
    return trialEndsAt;
  }

  /// True when the academy has full access (override, paid, or in trial).
  /// Ordem importa: override e pagamento têm prioridade sobre o trial — assim
  /// quem pagou (Cakto OU externamente, via paidUntil/freeOverride) nunca é
  /// bloqueado, mesmo sendo academia antiga.
  bool get hasAccess {
    if (freeOverride) return true;
    if (plan == SubscriptionPlan.premium || plan == SubscriptionPlan.enterprise) return true;
    if (paidUntil != null && paidUntil!.isAfter(DateTime.now())) return true;
    final trialEnd = effectiveTrialEndsAt;
    if (trialEnd != null && trialEnd.isAfter(DateTime.now())) return true;
    return false;
  }

  bool get isTrialing {
    if (freeOverride || plan != SubscriptionPlan.free) return false;
    if (paidUntil != null && paidUntil!.isAfter(DateTime.now())) return false;
    final trialEnd = effectiveTrialEndsAt;
    return trialEnd != null && trialEnd.isAfter(DateTime.now());
  }

  int get trialDaysLeft {
    final trialEnd = effectiveTrialEndsAt;
    if (trialEnd == null) return 0;
    return trialEnd.difference(DateTime.now()).inDays.clamp(0, 30);
  }

  /// Janela do aviso de vencimento: só aparece nos últimos N dias antes do
  /// `paidUntil`. Como `paidUntil = ciclo (30) + 5 de folga`, N=5 faz o aviso
  /// surgir só DEPOIS da data de cobrança (dias ~30→35) — ou seja, quando a
  /// renovação não veio e o acesso está pra acabar. Antes disso, nada.
  static const int expiryWarningDays = 5;

  /// Dias restantes de acesso PAGO (baseado em [paidUntil]). 0 se não houver
  /// pagamento ativo no futuro.
  int get paidDaysLeft {
    if (paidUntil == null) return 0;
    final d = paidUntil!.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  /// True quando é uma assinatura PAGA ativa que vence em breve
  /// (≤ [expiryWarningDays] dias) — usado no banner "assinatura prestes a
  /// vencer". Não vale para trial (tem banner próprio) nem cortesia.
  bool get isPaidExpiringSoon {
    if (freeOverride || isTrialing) return false;
    if (paidUntil == null || !paidUntil!.isAfter(DateTime.now())) return false;
    return paidDaysLeft <= expiryWarningDays;
  }

  /// True quando a academia está na janela do desconto de 1º mês (50% no plano
  /// Mensal): precisa estar **em trial**, dentro dos primeiros
  /// [AppConstants.promoFirstDays] dias desde a criação, e com cupom
  /// configurado. A restrição ao plano Mensal é aplicada na tela (paywall).
  bool get isFirstMonthPromoEligible {
    if (AppConstants.caktoMensalPromoCoupon.isEmpty) return false;
    if (!isTrialing) return false;
    return trialDaysLeft >=
        (AppConstants.trialDays - AppConstants.promoFirstDays);
  }

  factory AcademySubscription.fromMap(
    Map<String, dynamic> map, {
    DateTime? createdAt,
  }) {
    return AcademySubscription(
      plan: SubscriptionPlanExtension.fromString(map['plan'] ?? 'free'),
      status: SubscriptionStatusExtension.fromString(map['status'] ?? 'active'),
      expiresAt: map['expiresAt'] != null
          ? (map['expiresAt'] as Timestamp).toDate()
          : null,
      trialEndsAt: map['trialEndsAt'] != null
          ? (map['trialEndsAt'] as Timestamp).toDate()
          : null,
      paidUntil: map['paidUntil'] != null
          ? (map['paidUntil'] as Timestamp).toDate()
          : null,
      freeOverride: map['freeOverride'] as bool? ?? false,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'plan': plan.value,
      'status': status.value,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'trialEndsAt': trialEndsAt != null ? Timestamp.fromDate(trialEndsAt!) : null,
      'paidUntil': paidUntil != null ? Timestamp.fromDate(paidUntil!) : null,
      'freeOverride': freeOverride,
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

  // Mercado Pago marketplace/split — admin connects their OWN MP account via
  // OAuth; charges settle directly into it (0% platform fee). Secret tokens
  // live server-side in academies/{id}/private/mpAuth (never client-readable).
  final bool mpConnected;
  final String? mpUserId;
  final String? mpPublicKey;
  final DateTime? mpConnectedAt;

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

  /// Sports/modalities offered by this academy (e.g. ['bjj', 'muaythai']).
  /// Empty list means single-modality (defaults to BJJ for legacy academies).
  final List<String> sports;

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
    this.mpConnected = false,
    this.mpUserId,
    this.mpPublicKey,
    this.mpConnectedAt,
    this.autoGraduationEnabled = false,
    this.autoGraduationAttendances,
    this.storeEnabled = false,
    this.storePublished = false,
    this.storeWelcomeMessage,
    this.storeMinOrderAmount,
    this.studentCheckinEnabled = false,
    this.subscription,
    this.sports = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.ownerId,
  });

  /// Returns the effective list of sports offered, defaulting to ['bjj']
  /// for legacy academies that never declared the field.
  List<String> get effectiveSports =>
      sports.isNotEmpty ? sports : const ['bjj'];

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
      mpConnected: data['mpConnected'] ?? false,
      mpUserId: data['mpUserId'],
      mpPublicKey: data['mpPublicKey'],
      mpConnectedAt: (data['mpConnectedAt'] as Timestamp?)?.toDate(),
      autoGraduationEnabled: data['autoGraduationEnabled'] ?? false,
      autoGraduationAttendances: data['autoGraduationAttendances'],
      storeEnabled: data['storeEnabled'] ?? false,
      storePublished: data['storePublished'] ?? false,
      storeWelcomeMessage: data['storeWelcomeMessage'],
      storeMinOrderAmount: data['storeMinOrderAmount'],
      studentCheckinEnabled: data['studentCheckinEnabled'] ?? false,
      subscription: data['subscription'] != null
          ? AcademySubscription.fromMap(
              data['subscription'],
              createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
            )
          : null,
      sports: data['sports'] is List
          ? List<String>.from((data['sports'] as List).map((e) => e.toString()))
          : const [],
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
      'mpConnected': mpConnected,
      'mpUserId': mpUserId,
      'mpPublicKey': mpPublicKey,
      'mpConnectedAt': mpConnectedAt,
      'autoGraduationEnabled': autoGraduationEnabled,
      'autoGraduationAttendances': autoGraduationAttendances,
      'storeEnabled': storeEnabled,
      'storePublished': storePublished,
      'storeWelcomeMessage': storeWelcomeMessage,
      'storeMinOrderAmount': storeMinOrderAmount,
      'studentCheckinEnabled': studentCheckinEnabled,
      'subscription': subscription?.toMap(),
      if (sports.isNotEmpty) 'sports': sports,
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
    bool? mpConnected,
    String? mpUserId,
    String? mpPublicKey,
    DateTime? mpConnectedAt,
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
      mpConnected: mpConnected ?? this.mpConnected,
      mpUserId: mpUserId ?? this.mpUserId,
      mpPublicKey: mpPublicKey ?? this.mpPublicKey,
      mpConnectedAt: mpConnectedAt ?? this.mpConnectedAt,
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
