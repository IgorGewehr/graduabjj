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

/// User Model
class AppUser {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final UserRole role;
  final String? phone;

  // Academy (multi-tenant)
  final String? academyId;

  // Role-specific links
  final String? studentId;
  final List<String>? linkedStudentIds;
  final String? instructorId;

  // Account linking
  final String? pendingStudentLink;
  final DateTime? approvedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.role,
    this.phone,
    this.academyId,
    this.studentId,
    this.linkedStudentIds,
    this.instructorId,
    this.pendingStudentLink,
    this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      id: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      photoUrl: data['photoUrl'],
      role: UserRoleExtension.fromString(data['role'] ?? 'student'),
      phone: data['phone'],
      academyId: data['academyId'],
      studentId: data['studentId'],
      linkedStudentIds: data['linkedStudentIds'] != null
          ? List<String>.from(data['linkedStudentIds'])
          : null,
      instructorId: data['instructorId'],
      pendingStudentLink: data['pendingStudentLink'],
      approvedAt: data['approvedAt'] != null
          ? (data['approvedAt'] as Timestamp).toDate()
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'role': role.value,
      'phone': phone,
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
  bool get isInstructor => role == UserRole.instructor;
  bool get isStudent => role == UserRole.student;
  bool get isGuardian => role == UserRole.guardian;
  bool get hasLinkedStudent => studentId != null || (linkedStudentIds?.isNotEmpty ?? false);
}
