// DTOs do contexto Identity, alinhados 1:1 com api/openapi/identity.yaml.
//
// Esta camada é PURA conversão snake_case ↔ Dart. NÃO carrega referências a
// Firestore (Timestamp etc.) e NÃO assume estado da app. Os providers de
// alto nível (AppUser, GlobalUser em lib/models/user.dart) podem absorver
// esses DTOs via factories quando o wiring acontecer.

enum ApiRole { admin, instructor, monitor, student, guardian }

extension ApiRoleX on ApiRole {
  String get wire => name;
  static ApiRole fromWire(String value) {
    for (final r in ApiRole.values) {
      if (r.name == value) return r;
    }
    // Default conservativo — `student` é o menor privilégio aplicável.
    return ApiRole.student;
  }
}

enum ApiMembershipStatus { active, suspended, removed }

extension ApiMembershipStatusX on ApiMembershipStatus {
  String get wire => name;
  static ApiMembershipStatus fromWire(String value) {
    for (final s in ApiMembershipStatus.values) {
      if (s.name == value) return s;
    }
    return ApiMembershipStatus.removed;
  }
}

enum ApiAccountType { free, linked }

extension ApiAccountTypeX on ApiAccountType {
  String get wire => name;
  static ApiAccountType fromWire(String? value) {
    if (value == 'linked') return ApiAccountType.linked;
    return ApiAccountType.free;
  }
}

class ApiGlobalUser {
  const ApiGlobalUser({
    required this.uid,
    required this.email,
    required this.accountType,
    this.displayName,
    this.photoUrl,
    this.phone,
    this.birthDate,
    this.cpf,
    this.weightKg,
    this.jiujitsuStartDate,
    this.highestBelt,
    this.highestStripes,
    this.isProfilePublic = false,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String email;
  final ApiAccountType accountType;
  final String? displayName;
  final String? photoUrl;
  final String? phone;
  final DateTime? birthDate;
  final String? cpf;
  final double? weightKg;
  final DateTime? jiujitsuStartDate;
  final String? highestBelt;
  final int? highestStripes;
  final bool isProfilePublic;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ApiGlobalUser.fromJson(Map<String, dynamic> j) => ApiGlobalUser(
        uid: j['uid'] as String,
        email: j['email'] as String,
        accountType: ApiAccountTypeX.fromWire(j['account_type'] as String?),
        displayName: j['display_name'] as String?,
        photoUrl: j['photo_url'] as String?,
        phone: j['phone'] as String?,
        birthDate: _parseDate(j['birth_date']),
        cpf: j['cpf'] as String?,
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        jiujitsuStartDate: _parseDate(j['jiujitsu_start_date']),
        highestBelt: j['highest_belt'] as String?,
        highestStripes: (j['highest_stripes'] as num?)?.toInt(),
        isProfilePublic: j['is_profile_public'] as bool? ?? false,
        createdAt: _parseDate(j['created_at']),
        updatedAt: _parseDate(j['updated_at']),
      );
}

class ApiMembership {
  const ApiMembership({
    required this.uid,
    required this.academyId,
    required this.role,
    required this.status,
    this.studentId,
    this.joinedAt,
    this.extraPermissions = const [],
  });

  final String uid;
  final String academyId;
  final ApiRole role;
  final ApiMembershipStatus status;
  final String? studentId;
  final DateTime? joinedAt;
  final List<String> extraPermissions;

  factory ApiMembership.fromJson(Map<String, dynamic> j) => ApiMembership(
        uid: j['uid'] as String,
        academyId: j['academy_id'] as String,
        role: ApiRoleX.fromWire(j['role'] as String),
        status: ApiMembershipStatusX.fromWire(j['status'] as String),
        studentId: j['student_id'] as String?,
        joinedAt: _parseDate(j['joined_at']),
        extraPermissions: (j['extra_permissions'] as List?)
                ?.whereType<String>()
                .toList() ??
            const [],
      );

  bool get isActive => status == ApiMembershipStatus.active;
}

class CurrentUserResponse {
  const CurrentUserResponse({
    required this.user,
    required this.memberships,
    this.primaryAcademyId,
  });

  final ApiGlobalUser user;
  final List<ApiMembership> memberships;
  final String? primaryAcademyId;

  /// Memberships ativas, na ordem em que o backend devolveu. A primária
  /// (quando há `primary_academy_id`) é movida para o topo.
  List<ApiMembership> get activeMemberships {
    final actives =
        memberships.where((m) => m.status == ApiMembershipStatus.active).toList();
    if (primaryAcademyId == null) return actives;
    actives.sort((a, b) {
      if (a.academyId == primaryAcademyId) return -1;
      if (b.academyId == primaryAcademyId) return 1;
      return 0;
    });
    return actives;
  }

  factory CurrentUserResponse.fromJson(Map<String, dynamic> j) =>
      CurrentUserResponse(
        user: ApiGlobalUser.fromJson(j['user'] as Map<String, dynamic>),
        memberships: (j['memberships'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiMembership.fromJson)
            .toList(),
        primaryAcademyId: j['primary_academy_id'] as String?,
      );
}

class UpdateUserRequest {
  const UpdateUserRequest({
    this.displayName,
    this.phone,
    this.photoUrl,
    this.birthDate,
    this.weightKg,
    this.isProfilePublic,
  });

  final String? displayName;
  final String? phone;
  final String? photoUrl;
  final DateTime? birthDate;
  final double? weightKg;
  final bool? isProfilePublic;

  /// Serializa para JSON em snake_case. Campos null são omitidos para que o
  /// backend faça PATCH semântico (não sobrescreve com null).
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (displayName != null) m['display_name'] = displayName;
    if (phone != null) m['phone'] = phone;
    if (photoUrl != null) m['photo_url'] = photoUrl;
    if (birthDate != null) {
      // OpenAPI: format=date → "YYYY-MM-DD"
      m['birth_date'] =
          '${birthDate!.year.toString().padLeft(4, '0')}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}';
    }
    if (weightKg != null) m['weight_kg'] = weightKg;
    if (isProfilePublic != null) m['is_profile_public'] = isProfilePublic;
    return m;
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
