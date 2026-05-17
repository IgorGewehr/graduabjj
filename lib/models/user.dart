import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/dto/identity_dto.dart';

/// Catalog of permission strings used across the Tatami backend.
///
/// Mirror of `internal/identity/domain/permission.go` no backend. Mantenha em
/// sync — qualquer permission nova precisa ser adicionada aqui E no mapa
/// [_defaultPermissionsByRole]. As strings exatas são o contrato wire com o
/// BE (são gravadas em `extra_permissions` no Firestore/Tatami).
class TatamiPermissions {
  TatamiPermissions._();

  static const attendanceRead = 'attendance.read';
  static const attendanceWrite = 'attendance.write';
  static const financialRead = 'financial.read';
  static const financialWrite = 'financial.write';
  static const studentsRead = 'students.read';
  static const studentsWrite = 'students.write';
  static const storeRead = 'store.read';
  static const storeWrite = 'store.write';
  static const notificationsSend = 'notifications.send';

  /// Conjunto de todas as permissões que podem aparecer no FE. Útil para
  /// renderizar checkboxes de extras no team management.
  static const all = <String>[
    attendanceRead,
    attendanceWrite,
    financialRead,
    financialWrite,
    studentsRead,
    studentsWrite,
    storeRead,
    storeWrite,
    notificationsSend,
  ];
}

/// User Roles
enum UserRole { admin, instructor, student, guardian }

/// Default permissions per role — mirror do BE em
/// `internal/identity/domain/permission.go::defaultPermissions`.
///
/// IMPORTANTE: o enum [UserRole] hoje colapsa `monitor` em `instructor` (ver
/// [_mapApiRoleToLegacy]). Como ainda não temos `monitor` no enum, não há
/// entrada para ele aqui — quem se importa com a diferença precisa olhar o
/// payload Tatami direto. Quando adicionarmos `UserRole.monitor`, basta
/// incluir o conjunto correspondente neste mapa.
const Map<UserRole, List<String>> _defaultPermissionsByRole = {
  UserRole.admin: [
    TatamiPermissions.attendanceRead,
    TatamiPermissions.attendanceWrite,
    TatamiPermissions.financialRead,
    TatamiPermissions.financialWrite,
    TatamiPermissions.studentsRead,
    TatamiPermissions.studentsWrite,
    TatamiPermissions.storeRead,
    TatamiPermissions.storeWrite,
    TatamiPermissions.notificationsSend,
  ],
  UserRole.instructor: [
    TatamiPermissions.attendanceRead,
    TatamiPermissions.attendanceWrite,
    TatamiPermissions.studentsRead,
    TatamiPermissions.studentsWrite,
    TatamiPermissions.financialRead,
    TatamiPermissions.storeRead,
    TatamiPermissions.notificationsSend,
  ],
  UserRole.student: [
    TatamiPermissions.attendanceRead,
    TatamiPermissions.studentsRead,
  ],
  UserRole.guardian: [
    TatamiPermissions.attendanceRead,
    TatamiPermissions.studentsRead,
  ],
};

extension UserRoleExtension on UserRole {
  String get value {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.instructor:
        return 'instructor';
      case UserRole.student:
        return 'student';
      case UserRole.guardian:
        return 'guardian';
    }
  }

  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Administrador';
      case UserRole.instructor:
        return 'Instrutor';
      case UserRole.student:
        return 'Aluno';
      case UserRole.guardian:
        return 'Responsavel';
    }
  }

  static UserRole fromString(String value) {
    switch (value) {
      case 'admin':
        return UserRole.admin;
      case 'instructor':
        return UserRole.instructor;
      case 'student':
        return UserRole.student;
      case 'guardian':
        return UserRole.guardian;
      default:
        return UserRole.student;
    }
  }
}

/// Account Type - whether user is linked to an academy or free
enum AccountType { free, linked }

extension AccountTypeExtension on AccountType {
  String get value {
    switch (this) {
      case AccountType.free:
        return 'free';
      case AccountType.linked:
        return 'linked';
    }
  }

  static AccountType fromString(String? value) {
    switch (value) {
      case 'linked':
        return AccountType.linked;
      case 'free':
      default:
        return AccountType.free;
    }
  }
}

/// Global User Model - ROOT /users/{uid}
/// This is the user's global identity, independent of any academy
class GlobalUser {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? phone;

  // Account type
  final AccountType accountType;

  // Personal info (for fighter profile)
  final DateTime? birthDate;
  final String? cpf;
  final double? weight;

  // Global jiu-jitsu info (highest achieved, synced from academies)
  final DateTime? jiujitsuStartDate;
  final String? highestBelt;
  final int? highestStripes;

  // Profile visibility
  final bool isProfilePublic;

  final DateTime createdAt;
  final DateTime updatedAt;

  GlobalUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phone,
    this.accountType = AccountType.free,
    this.birthDate,
    this.cpf,
    this.weight,
    this.jiujitsuStartDate,
    this.highestBelt,
    this.highestStripes,
    this.isProfilePublic = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GlobalUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GlobalUser.fromMap(doc.id, data);
  }

  factory GlobalUser.fromMap(String id, Map<String, dynamic> data) {
    return GlobalUser(
      id: id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      photoUrl: data['photoUrl'],
      phone: data['phone'],
      accountType: AccountTypeExtension.fromString(data['accountType']),
      birthDate: _parseDate(data['birthDate']),
      cpf: data['cpf'],
      weight: data['weight']?.toDouble(),
      jiujitsuStartDate: _parseDate(data['jiujitsuStartDate']),
      highestBelt: data['highestBelt'],
      highestStripes: data['highestStripes'],
      isProfilePublic: data['isProfilePublic'] ?? false,
      createdAt: _parseDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'phone': phone,
      'accountType': accountType.value,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'cpf': cpf,
      'weight': weight,
      'jiujitsuStartDate': jiujitsuStartDate != null
          ? Timestamp.fromDate(jiujitsuStartDate!)
          : null,
      'highestBelt': highestBelt,
      'highestStripes': highestStripes,
      'isProfilePublic': isProfilePublic,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
  }

  GlobalUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
    String? phone,
    AccountType? accountType,
    DateTime? birthDate,
    String? cpf,
    double? weight,
    DateTime? jiujitsuStartDate,
    String? highestBelt,
    int? highestStripes,
    bool? isProfilePublic,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GlobalUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      phone: phone ?? this.phone,
      accountType: accountType ?? this.accountType,
      birthDate: birthDate ?? this.birthDate,
      cpf: cpf ?? this.cpf,
      weight: weight ?? this.weight,
      jiujitsuStartDate: jiujitsuStartDate ?? this.jiujitsuStartDate,
      highestBelt: highestBelt ?? this.highestBelt,
      highestStripes: highestStripes ?? this.highestStripes,
      isProfilePublic: isProfilePublic ?? this.isProfilePublic,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get hasAcademy => accountType == AccountType.linked;
}

/// User-Academy Mapping - ROOT /userAcademyMapping/{uid}
/// Tracks which academies a user belongs to
class UserAcademyMapping {
  final String id;
  final List<String> academyIds;
  final String? primaryAcademyId;
  final Map<String, AcademyDetail>? academyDetails;
  final DateTime? updatedAt;

  UserAcademyMapping({
    required this.id,
    required this.academyIds,
    this.primaryAcademyId,
    this.academyDetails,
    this.updatedAt,
  });

  factory UserAcademyMapping.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserAcademyMapping.fromMap(doc.id, data);
  }

  factory UserAcademyMapping.fromMap(String id, Map<String, dynamic> data) {
    Map<String, AcademyDetail>? details;
    if (data['academyDetails'] != null) {
      details = {};
      (data['academyDetails'] as Map<String, dynamic>).forEach((key, value) {
        details![key] = AcademyDetail.fromMap(value);
      });
    }

    return UserAcademyMapping(
      id: id,
      academyIds: List<String>.from(data['academyIds'] ?? []),
      primaryAcademyId: data['primaryAcademyId'],
      academyDetails: details,
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'academyIds': academyIds,
      'primaryAcademyId': primaryAcademyId,
      'academyDetails': academyDetails?.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  bool get hasMultipleAcademies => academyIds.length > 1;
  bool get hasNoAcademy => academyIds.isEmpty;
}

/// Academy Detail - Details about user's relationship with a specific academy
class AcademyDetail {
  final String? studentId;
  final UserRole role;
  final DateTime joinedAt;
  final String status; // 'active' | 'inactive' | 'pending'
  /// Permissions granted on top of the role's defaults. Only meaningful for
  /// `instructor` — the academy owner can opt instructors into extra
  /// capabilities (e.g. financial:view) without promoting them to admin.
  /// Stored as raw strings ("financial:view") to match the web side.
  final List<String> extraPermissions;

  AcademyDetail({
    this.studentId,
    required this.role,
    required this.joinedAt,
    this.status = 'active',
    this.extraPermissions = const [],
  });

  factory AcademyDetail.fromMap(Map<String, dynamic> data) {
    return AcademyDetail(
      studentId: data['studentId'],
      role: UserRoleExtension.fromString(data['role'] ?? 'student'),
      joinedAt: _parseDate(data['joinedAt']) ?? DateTime.now(),
      status: data['status'] ?? 'active',
      extraPermissions: data['extraPermissions'] is List
          ? List<String>.from(data['extraPermissions'])
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'role': role.value,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'status': status,
      if (extraPermissions.isNotEmpty) 'extraPermissions': extraPermissions,
    };
  }
}

/// App User Model - Combined context (for backwards compatibility)
/// This represents the user in the current app context (with academy)
class AppUser {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final UserRole role;
  final String? phone;

  // Account type (new - from GlobalUser)
  final AccountType accountType;

  // Global jiu-jitsu info (new - from GlobalUser)
  final DateTime? jiujitsuStartDate;
  final String? highestBelt;
  final int? highestStripes;
  final bool isProfilePublic;

  // Academy context (current academy being used)
  final String? academyId;

  // Role-specific links (within current academy)
  final String? studentId;
  final List<String>? linkedStudentIds;
  final String? instructorId;

  // Account linking
  final String? pendingStudentLink;
  final DateTime? approvedAt;

  /// Permissões extras concedidas pelo admin da academia sobre o role default
  /// — strings no formato do contrato Tatami (`financial.read`,
  /// `notifications.send`, etc., catalogados em [TatamiPermissions]). Vazio
  /// na maioria dos casos; usado pelos checks via [hasPermission].
  final List<String> extraPermissions;

  final DateTime createdAt;
  final DateTime updatedAt;

  AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.role,
    this.phone,
    this.accountType = AccountType.linked,
    this.jiujitsuStartDate,
    this.highestBelt,
    this.highestStripes,
    this.isProfilePublic = false,
    this.academyId,
    this.studentId,
    this.linkedStudentIds,
    this.instructorId,
    this.pendingStudentLink,
    this.approvedAt,
    this.extraPermissions = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser.fromMap(doc.id, data);
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> data) {
    return AppUser(
      id: id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      photoUrl: data['photoUrl'],
      role: UserRoleExtension.fromString(data['role'] ?? 'student'),
      phone: data['phone'],
      accountType: AccountTypeExtension.fromString(data['accountType']),
      jiujitsuStartDate: _parseDate(data['jiujitsuStartDate']),
      highestBelt: data['highestBelt'],
      highestStripes: data['highestStripes'],
      isProfilePublic: data['isProfilePublic'] ?? false,
      academyId: data['academyId'],
      studentId: data['studentId'],
      linkedStudentIds: data['linkedStudentIds'] != null
          ? List<String>.from(data['linkedStudentIds'])
          : null,
      instructorId: data['instructorId'],
      pendingStudentLink: data['pendingStudentLink'],
      approvedAt: _parseDate(data['approvedAt']),
      extraPermissions: data['extraPermissions'] is List
          ? List<String>.from(data['extraPermissions'])
          : const [],
      createdAt: _parseDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updatedAt']) ?? DateTime.now(),
    );
  }

  /// Constrói um [AppUser] a partir da resposta `GET /v1/me` do Tatami.
  ///
  /// [activeAcademyId] indica qual membership materializar. Se omitido, usa
  /// o `primary_academy_id` da resposta; se a resposta também não tiver
  /// primary, usa a primeira membership ativa.
  ///
  /// Retorna `null` quando o usuário não tem nenhuma membership ativa —
  /// caller decide se trata como conta `free` ou redireciona para a tela
  /// de "vincular academia".
  ///
  /// Esta factory NÃO é usada por nenhum provider hoje — é importada pelo
  /// PR de wiring do Sprint 1 quando a flag `useTatamiIdentity` virar true.
  static AppUser? fromCurrentUserResponse(
    CurrentUserResponse r, {
    String? activeAcademyId,
  }) {
    final actives = r.activeMemberships;
    if (actives.isEmpty) return null;

    final picked = () {
      if (activeAcademyId != null) {
        for (final m in actives) {
          if (m.academyId == activeAcademyId) return m;
        }
      }
      if (r.primaryAcademyId != null) {
        for (final m in actives) {
          if (m.academyId == r.primaryAcademyId) return m;
        }
      }
      return actives.first;
    }();

    return AppUser(
      id: r.user.uid,
      email: r.user.email,
      displayName: r.user.displayName ?? '',
      photoUrl: r.user.photoUrl,
      role: _mapApiRoleToLegacy(picked.role),
      phone: r.user.phone,
      accountType: r.user.accountType == ApiAccountType.linked
          ? AccountType.linked
          : AccountType.free,
      jiujitsuStartDate: r.user.jiujitsuStartDate,
      highestBelt: r.user.highestBelt,
      highestStripes: r.user.highestStripes,
      isProfilePublic: r.user.isProfilePublic,
      academyId: picked.academyId,
      studentId: picked.studentId,
      extraPermissions: picked.extraPermissions,
      createdAt: r.user.createdAt ?? DateTime.now(),
      updatedAt: r.user.updatedAt ?? DateTime.now(),
    );
  }

  /// Create AppUser from GlobalUser + AcademyUser context
  factory AppUser.fromGlobalAndAcademy({
    required GlobalUser globalUser,
    required String academyId,
    required UserRole role,
    String? studentId,
    List<String>? linkedStudentIds,
    String? instructorId,
    String? pendingStudentLink,
    DateTime? approvedAt,
    List<String> extraPermissions = const [],
  }) {
    return AppUser(
      id: globalUser.id,
      email: globalUser.email,
      displayName: globalUser.displayName,
      photoUrl: globalUser.photoUrl,
      role: role,
      phone: globalUser.phone,
      accountType: globalUser.accountType,
      jiujitsuStartDate: globalUser.jiujitsuStartDate,
      highestBelt: globalUser.highestBelt,
      highestStripes: globalUser.highestStripes,
      isProfilePublic: globalUser.isProfilePublic,
      academyId: academyId,
      studentId: studentId,
      linkedStudentIds: linkedStudentIds,
      instructorId: instructorId,
      pendingStudentLink: pendingStudentLink,
      approvedAt: approvedAt,
      extraPermissions: extraPermissions,
      createdAt: globalUser.createdAt,
      updatedAt: globalUser.updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'role': role.value,
      'phone': phone,
      'accountType': accountType.value,
      'jiujitsuStartDate': jiujitsuStartDate != null
          ? Timestamp.fromDate(jiujitsuStartDate!)
          : null,
      'highestBelt': highestBelt,
      'highestStripes': highestStripes,
      'isProfilePublic': isProfilePublic,
      'academyId': academyId,
      'studentId': studentId,
      'linkedStudentIds': linkedStudentIds,
      'instructorId': instructorId,
      'pendingStudentLink': pendingStudentLink,
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      if (extraPermissions.isNotEmpty) 'extraPermissions': extraPermissions,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
    UserRole? role,
    String? phone,
    AccountType? accountType,
    DateTime? jiujitsuStartDate,
    String? highestBelt,
    int? highestStripes,
    bool? isProfilePublic,
    String? academyId,
    String? studentId,
    List<String>? linkedStudentIds,
    String? instructorId,
    String? pendingStudentLink,
    DateTime? approvedAt,
    List<String>? extraPermissions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      accountType: accountType ?? this.accountType,
      jiujitsuStartDate: jiujitsuStartDate ?? this.jiujitsuStartDate,
      highestBelt: highestBelt ?? this.highestBelt,
      highestStripes: highestStripes ?? this.highestStripes,
      isProfilePublic: isProfilePublic ?? this.isProfilePublic,
      academyId: academyId ?? this.academyId,
      studentId: studentId ?? this.studentId,
      linkedStudentIds: linkedStudentIds ?? this.linkedStudentIds,
      instructorId: instructorId ?? this.instructorId,
      pendingStudentLink: pendingStudentLink ?? this.pendingStudentLink,
      approvedAt: approvedAt ?? this.approvedAt,
      extraPermissions: extraPermissions ?? this.extraPermissions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isAdmin => role == UserRole.admin;
  bool get isInstructor =>
      role == UserRole.instructor || role == UserRole.admin;
  bool get isStudent => role == UserRole.student;
  bool get isGuardian => role == UserRole.guardian;
  bool get hasLinkedStudent =>
      studentId != null || (linkedStudentIds?.isNotEmpty ?? false);
  bool get hasAcademy => accountType == AccountType.linked && academyId != null;

  /// Verifica se este user tem a permission [perm] — checa primeiro o
  /// conjunto default do seu [role] e depois fallback em [extraPermissions].
  ///
  /// Use as constantes de [TatamiPermissions] como argumento, não literais:
  ///
  /// ```dart
  /// if (user.hasPermission(TatamiPermissions.financialWrite)) { ... }
  /// ```
  bool hasPermission(String perm) {
    final defaults = _defaultPermissionsByRole[role] ?? const <String>[];
    return defaults.contains(perm) || extraPermissions.contains(perm);
  }
}

/// Mapeia o role do Tatami (incluindo `monitor`, novo no Sprint H) para o
/// enum legacy do FE. `monitor` cai em `instructor` por enquanto — quando
/// o app aceitar monitor como role própria, adicionar ao enum UserRole
/// e atualizar este mapeamento (e os call-sites que checam role).
UserRole _mapApiRoleToLegacy(ApiRole r) {
  switch (r) {
    case ApiRole.admin:
      return UserRole.admin;
    case ApiRole.instructor:
    case ApiRole.monitor:
      return UserRole.instructor;
    case ApiRole.student:
      return UserRole.student;
    case ApiRole.guardian:
      return UserRole.guardian;
  }
}

/// Helper to parse dates from Firestore
DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
