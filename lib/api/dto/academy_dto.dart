// DTOs do contexto Academy (settings + link codes), alinhados 1:1 com
// api/openapi/academy.yaml.
//
// Aqui ficam tipos pequenos compartilhados por settings_repo + link_code_repo.

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
