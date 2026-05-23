import 'package:cloud_firestore/cloud_firestore.dart';

/// User Roles
enum UserRole { admin, instructor, student, guardian }

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

  /// Extra permissions granted on top of the role for the current academy
  /// (e.g. 'financial:view' for an instructor). Empty for admins (who have
  /// everything) and for students.
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
      createdAt: _parseDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updatedAt']) ?? DateTime.now(),
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

  /// Returns true when the user can access [permission] for the current
  /// academy. Admins can do everything; instructors need the permission in
  /// `extraPermissions`; students always return false.
  bool hasPermission(String permission) {
    if (role == UserRole.admin) return true;
    if (role == UserRole.instructor) {
      return extraPermissions.contains(permission);
    }
    return false;
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
}

/// Helper to parse dates from Firestore
DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
