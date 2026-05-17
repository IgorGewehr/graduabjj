// DTOs do contexto Academy (academy entity + settings + link codes),
// alinhados 1:1 com api/openapi/academy.yaml.
//
// Aqui ficam tipos pequenos compartilhados por academy_repo (futuro) +
// settings_repo + link_code_repo.

enum ApiAcademySubscriptionStatus { trial, active, pastDue, canceled, suspended }

extension ApiAcademySubscriptionStatusX on ApiAcademySubscriptionStatus {
  String get wire {
    switch (this) {
      case ApiAcademySubscriptionStatus.trial:
        return 'trial';
      case ApiAcademySubscriptionStatus.active:
        return 'active';
      case ApiAcademySubscriptionStatus.pastDue:
        return 'past_due';
      case ApiAcademySubscriptionStatus.canceled:
        return 'canceled';
      case ApiAcademySubscriptionStatus.suspended:
        return 'suspended';
    }
  }

  static ApiAcademySubscriptionStatus fromWire(String? value) {
    switch (value) {
      case 'trial':
        return ApiAcademySubscriptionStatus.trial;
      case 'past_due':
        return ApiAcademySubscriptionStatus.pastDue;
      case 'canceled':
        return ApiAcademySubscriptionStatus.canceled;
      case 'suspended':
        return ApiAcademySubscriptionStatus.suspended;
      case 'active':
      default:
        return ApiAcademySubscriptionStatus.active;
    }
  }
}

enum ApiPixKeyType { cpf, cnpj, email, phone, random }

extension ApiPixKeyTypeX on ApiPixKeyType {
  String get wire => name;
  static ApiPixKeyType? fromWire(String? value) {
    if (value == null) return null;
    for (final t in ApiPixKeyType.values) {
      if (t.name == value) return t;
    }
    return null;
  }
}

/// Endereço da academia (subset do `address` legacy — Tatami só armazena
/// street/city/state/zip_code, sem número/complemento/bairro).
class ApiAcademyAddress {
  const ApiAcademyAddress({
    this.street,
    this.city,
    this.state,
    this.zipCode,
  });

  final String? street;
  final String? city;
  final String? state;
  final String? zipCode;

  bool get isEmpty =>
      (street == null || street!.isEmpty) &&
      (city == null || city!.isEmpty) &&
      (state == null || state!.isEmpty) &&
      (zipCode == null || zipCode!.isEmpty);

  factory ApiAcademyAddress.fromJson(Map<String, dynamic> j) =>
      ApiAcademyAddress(
        street: j['street'] as String?,
        city: j['city'] as String?,
        state: j['state'] as String?,
        zipCode: j['zip_code'] as String?,
      );
}

/// Academy entity (tenant root) — corresponde 1:1 ao schema `Academy` do
/// `api/openapi/academy.yaml`.
///
/// Nota: campos visuais como `logo_url`, `portal_slogan`, sidebar/background
/// URLs NÃO existem no contrato Tatami atual — eles ficam no domínio legacy
/// (Firestore) até o BE expor branding multi-tenant. O adapter
/// `Academy.fromApi` deixa esses campos null e o caller que precisa renderizar
/// branding faz `copyWith` com os valores legacy quando disponíveis.
class ApiAcademy {
  const ApiAcademy({
    required this.id,
    required this.name,
    required this.slug,
    required this.ownerUid,
    required this.subscriptionStatus,
    required this.createdAt,
    required this.updatedAt,
    this.cnpj,
    this.email,
    this.phone,
    this.pixKey,
    this.pixKeyType,
    this.address,
    this.subscriptionPlan,
    this.subscriptionExpiresAt,
    this.abacatePayEnabled = false,
    this.asaasEnabled = false,
    this.asaasOnboardingStatus,
    this.autoGraduationEnabled = false,
    this.autoGraduationAttendances,
    this.useClassWeights = false,
    this.storeEnabled = false,
    this.storePublished = false,
    this.studentCheckinEnabled = false,
  });

  final String id;
  final String name;
  final String slug;
  final String ownerUid;
  final ApiAcademySubscriptionStatus subscriptionStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  final String? cnpj;
  final String? email;
  final String? phone;
  final String? pixKey;
  final ApiPixKeyType? pixKeyType;
  final ApiAcademyAddress? address;
  final String? subscriptionPlan;
  final DateTime? subscriptionExpiresAt;
  final bool abacatePayEnabled;
  final bool asaasEnabled;
  final String? asaasOnboardingStatus;
  final bool autoGraduationEnabled;
  final int? autoGraduationAttendances;
  final bool useClassWeights;
  final bool storeEnabled;
  final bool storePublished;
  final bool studentCheckinEnabled;

  factory ApiAcademy.fromJson(Map<String, dynamic> j) => ApiAcademy(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        slug: j['slug'] as String? ?? '',
        ownerUid: j['owner_uid'] as String? ?? '',
        subscriptionStatus: ApiAcademySubscriptionStatusX.fromWire(
          j['subscription_status'] as String?,
        ),
        createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
        updatedAt: _parseDate(j['updated_at']) ?? DateTime.now(),
        cnpj: j['cnpj'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        pixKey: j['pix_key'] as String?,
        pixKeyType: ApiPixKeyTypeX.fromWire(j['pix_key_type'] as String?),
        address: j['address'] is Map<String, dynamic>
            ? ApiAcademyAddress.fromJson(j['address'] as Map<String, dynamic>)
            : null,
        subscriptionPlan: j['subscription_plan'] as String?,
        subscriptionExpiresAt: _parseDate(j['subscription_expires_at']),
        abacatePayEnabled: j['abacatepay_enabled'] as bool? ?? false,
        asaasEnabled: j['asaas_enabled'] as bool? ?? false,
        asaasOnboardingStatus: j['asaas_onboarding_status'] as String?,
        autoGraduationEnabled: j['auto_graduation_enabled'] as bool? ?? false,
        autoGraduationAttendances:
            (j['auto_graduation_attendances'] as num?)?.toInt(),
        useClassWeights: j['use_class_weights'] as bool? ?? false,
        storeEnabled: j['store_enabled'] as bool? ?? false,
        storePublished: j['store_published'] as bool? ?? false,
        studentCheckinEnabled: j['student_checkin_enabled'] as bool? ?? false,
      );
}

enum ApiLinkCodeRole { admin, instructor, monitor, student, guardian }

extension ApiLinkCodeRoleX on ApiLinkCodeRole {
  String get wire => name;
  static ApiLinkCodeRole fromWire(String? value) {
    for (final r in ApiLinkCodeRole.values) {
      if (r.name == value) return r;
    }
    return ApiLinkCodeRole.student;
  }
}

/// Entrada de configuração key/value. `value` é dynamic — o backend permite
/// qualquer JSON, o consumidor é quem sabe interpretar (string, número,
/// boolean, objeto). Settings comuns: `auto_graduation_enabled`,
/// `auto_graduation_attendances`, `use_class_weights`, `primary_sport`,
/// `pix_key`, `pix_key_type`, etc.
class ApiAcademySetting {
  const ApiAcademySetting({
    required this.academyId,
    required this.key,
    required this.value,
    this.updatedAt,
  });

  final String academyId;
  final String key;
  final dynamic value;
  final DateTime? updatedAt;

  /// Atalho tipado quando o caller sabe que value é bool.
  bool? get asBool => value is bool ? value as bool : null;

  /// Atalho tipado quando o caller sabe que value é int.
  int? get asInt {
    if (value is int) return value as int;
    if (value is num) return (value as num).toInt();
    return null;
  }

  /// Atalho tipado quando o caller sabe que value é string.
  String? get asString => value is String ? value as String : null;

  factory ApiAcademySetting.fromJson(Map<String, dynamic> j) =>
      ApiAcademySetting(
        academyId: j['academy_id'] as String,
        key: j['key'] as String,
        value: j['value'],
        updatedAt: _parseDate(j['updated_at']),
      );
}

class ApiLinkCode {
  const ApiLinkCode({
    required this.id,
    required this.academyId,
    required this.code,
    required this.role,
    required this.expiresAt,
    this.studentId,
    this.usedAt,
    this.usedByUid,
    this.createdAt,
    this.createdByUid,
  });

  final String id;
  final String academyId;
  final String code;
  final ApiLinkCodeRole role;
  final String? studentId;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final String? usedByUid;
  final DateTime? createdAt;
  final String? createdByUid;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsed => usedAt != null;
  bool get isActive => !isUsed && !isExpired;

  factory ApiLinkCode.fromJson(Map<String, dynamic> j) => ApiLinkCode(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        code: j['code'] as String,
        role: ApiLinkCodeRoleX.fromWire(j['role'] as String?),
        studentId: j['student_id'] as String?,
        expiresAt: _parseDate(j['expires_at']) ?? DateTime.now(),
        usedAt: _parseDate(j['used_at']),
        usedByUid: j['used_by_uid'] as String?,
        createdAt: _parseDate(j['created_at']),
        createdByUid: j['created_by_uid'] as String?,
      );
}

class ApiInstructorLinkCode {
  const ApiInstructorLinkCode({
    required this.id,
    required this.academyId,
    required this.code,
    required this.expiresAt,
    this.usedAt,
    this.usedByUid,
    this.createdAt,
    this.createdByUid,
  });

  final String id;
  final String academyId;
  final String code;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final String? usedByUid;
  final DateTime? createdAt;
  final String? createdByUid;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsed => usedAt != null;

  factory ApiInstructorLinkCode.fromJson(Map<String, dynamic> j) =>
      ApiInstructorLinkCode(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        code: j['code'] as String,
        expiresAt: _parseDate(j['expires_at']) ?? DateTime.now(),
        usedAt: _parseDate(j['used_at']),
        usedByUid: j['used_by_uid'] as String?,
        createdAt: _parseDate(j['created_at']),
        createdByUid: j['created_by_uid'] as String?,
      );
}

class CreateLinkCodeRequest {
  const CreateLinkCodeRequest({this.role, this.studentId, this.ttlSeconds});

  final ApiLinkCodeRole? role;
  final String? studentId;
  final int? ttlSeconds;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (role != null) m['role'] = role!.wire;
    if (studentId != null) m['student_id'] = studentId;
    if (ttlSeconds != null) m['ttl_seconds'] = ttlSeconds;
    return m;
  }
}

class RedeemLinkCodeRequest {
  const RedeemLinkCodeRequest({
    this.fullName,
    this.nickname,
    this.birthDate,
    this.phone,
    this.weightKg,
  });

  final String? fullName;
  final String? nickname;
  final DateTime? birthDate;
  final String? phone;
  final double? weightKg;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (fullName != null) m['full_name'] = fullName;
    if (nickname != null) m['nickname'] = nickname;
    if (birthDate != null) {
      m['birth_date'] =
          '${birthDate!.year.toString().padLeft(4, '0')}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}';
    }
    if (phone != null) m['phone'] = phone;
    if (weightKg != null) m['weight_kg'] = weightKg;
    return m;
  }
}

class RedeemLinkCodeResponse {
  const RedeemLinkCodeResponse({
    required this.academyId,
    required this.role,
    this.studentId,
  });

  final String academyId;
  final ApiLinkCodeRole role;
  final String? studentId;

  factory RedeemLinkCodeResponse.fromJson(Map<String, dynamic> j) =>
      RedeemLinkCodeResponse(
        academyId: j['academy_id'] as String,
        role: ApiLinkCodeRoleX.fromWire(j['role'] as String?),
        studentId: j['student_id'] as String?,
      );
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
