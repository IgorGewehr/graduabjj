import 'package:cloud_functions/cloud_functions.dart';

/// Member entry returned by [TeamService.listMembers].
class AcademyMember {
  final String userId;
  final String displayName;
  final String email;
  final String role; // 'admin' | 'instructor' | 'student'
  final List<String> extraPermissions;
  final String? studentId;

  const AcademyMember({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.role,
    this.extraPermissions = const [],
    this.studentId,
  });

  factory AcademyMember.fromMap(Map<String, dynamic> data) {
    return AcademyMember(
      userId: (data['userId'] ?? '').toString(),
      displayName: (data['displayName'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      role: (data['role'] ?? 'student').toString(),
      extraPermissions: data['extraPermissions'] is List
          ? List<String>.from(data['extraPermissions'] as List)
          : const [],
      studentId: data['studentId']?.toString(),
    );
  }
}

class AcademyMembers {
  final List<AcademyMember> admins;
  final List<AcademyMember> instructors;
  final List<AcademyMember> students;

  const AcademyMembers({
    required this.admins,
    required this.instructors,
    required this.students,
  });

  static AcademyMembers fromMap(Map<String, dynamic> data) {
    List<AcademyMember> parse(String key) {
      final raw = data[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => AcademyMember.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }

    return AcademyMembers(
      admins: parse('admins'),
      instructors: parse('instructors'),
      students: parse('students'),
    );
  }
}

/// Bridge to the membership Cloud Functions. After the hardening in
/// firestore.rules, all academy join / promote / demote / revoke operations
/// go through these callables so the server can enforce ownership + role
/// invariants that client-side rules cannot express.
class TeamService {
  final FirebaseFunctions _functions;

  TeamService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Student joining an academy via a 6-char link code. Used both for
  /// first-time signup and for adding a second/third academy to an existing
  /// account. Returns the academyId resolved server-side.
  Future<String> joinAcademy(String code) async {
    final result = await _functions
        .httpsCallable('joinAcademy')
        .call({'code': code});
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['academyId']?.toString() ?? '';
  }

  /// Instructor joining an academy via an 8-char invite code. Same flow as
  /// [joinAcademy] but writes role='instructor' with the extraPermissions
  /// stamped on the code.
  Future<String> redeemInstructorCode(String code) async {
    final result = await _functions
        .httpsCallable('redeemInstructorCode')
        .call({'code': code});
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['academyId']?.toString() ?? '';
  }

  /// Admin promoting an existing member of their academy to instructor.
  Future<void> promoteToInstructor({
    required String userId,
    required String academyId,
    List<String> extraPermissions = const [],
  }) async {
    await _functions.httpsCallable('promoteToInstructor').call({
      'userId': userId,
      'academyId': academyId,
      'extraPermissions': extraPermissions,
    });
  }

  /// Admin reverting an instructor back to student (keeps the membership).
  Future<void> demoteToStudent({
    required String userId,
    required String academyId,
  }) async {
    await _functions.httpsCallable('demoteToStudent').call({
      'userId': userId,
      'academyId': academyId,
    });
  }

  /// Admin removing a member from the academy entirely (revokes access).
  Future<void> revokeMember({
    required String userId,
    required String academyId,
  }) async {
    await _functions.httpsCallable('revokeMember').call({
      'userId': userId,
      'academyId': academyId,
    });
  }

  /// Lists active members grouped by role. Caller must be staff.
  Future<AcademyMembers> listMembers(String academyId) async {
    final result = await _functions
        .httpsCallable('listAcademyMembers')
        .call({'academyId': academyId});
    return AcademyMembers.fromMap(Map<String, dynamic>.from(result.data as Map));
  }
}

/// Singleton, mirrors the convention used by other services in this codebase
/// (globalUserService, pushNotificationService, ...).
final teamService = TeamService();
