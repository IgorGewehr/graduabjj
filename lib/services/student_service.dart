import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/sports.dart';
import '../models/student.dart';
import 'firebase_service.dart';

/// Student Service - Multi-tenant student data management
class StudentService {
  final String academyId;
  late final Collections _collections;

  StudentService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _studentsRef => _collections.students;

  // ============================================
  // Get Student by ID
  // ============================================
  Future<Student?> getById(String id) async {
    final doc = await _collections.student(id).get();
    if (!doc.exists) return null;
    return Student.fromFirestore(doc);
  }

  // ============================================
  // Get Student by Linked User ID
  // ============================================
  Future<Student?> getByLinkedUserId(String userId) async {
    final query = await _studentsRef
        .where('linkedUserId', isEqualTo: userId)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return Student.fromFirestore(query.docs.first);
  }

  // ============================================
  // List All Students (sorted by attendance)
  // ============================================
  Future<List<Student>> listAll({
    StudentStatus? status,
    StudentCategory? category,
    String? belt,
    int? limit,
  }) async {
    Query query = _studentsRef;

    if (status != null) {
      query = query.where('status', isEqualTo: status.value);
    }
    if (category != null) {
      query = query.where('category', isEqualTo: category.value);
    }
    if (belt != null) {
      query = query.where('currentBelt', isEqualTo: belt);
    }

    final snapshot = await query.get();
    var students = snapshot.docs
        .map((doc) => Student.fromFirestore(doc))
        .toList();

    // Sort by total attendance count (descending)
    students.sort((a, b) {
      final totalA = a.totalAttendanceCount;
      final totalB = b.totalAttendanceCount;
      if (totalB != totalA) return totalB.compareTo(totalA);
      return a.fullName.compareTo(b.fullName);
    });

    if (limit != null && students.length > limit) {
      students = students.sublist(0, limit);
    }

    return students;
  }

  // ============================================
  // Get Active Students
  // ============================================
  Future<List<Student>> getActive() async {
    return listAll(status: StudentStatus.active);
  }

  // ============================================
  // Get Students by Status
  // ============================================
  Future<List<Student>> getByStatus(StudentStatus status) async {
    return listAll(status: status);
  }

  // ============================================
  // Get Students by Category
  // ============================================
  Future<List<Student>> getByCategory(StudentCategory category) async {
    return listAll(category: category, status: StudentStatus.active);
  }

  // ============================================
  // Get Students by Belt
  // ============================================
  Future<List<Student>> getByBelt(String belt) async {
    return listAll(belt: belt, status: StudentStatus.active);
  }

  // ============================================
  // Search Students by Name
  // ============================================
  Future<List<Student>> searchByName(
    String searchTerm, {
    StudentStatus? status,
    StudentCategory? category,
    String? belt,
  }) async {
    final students = await listAll(
      status: status,
      category: category,
      belt: belt,
    );

    final term = searchTerm.toLowerCase().trim();
    return students
        .where(
          (s) =>
              s.fullName.toLowerCase().contains(term) ||
              (s.nickname?.toLowerCase().contains(term) ?? false),
        )
        .toList();
  }

  // ============================================
  // Get Dashboard Stats
  // ============================================
  Future<Map<String, dynamic>> getDashboardStats() async {
    final snapshot = await _studentsRef.get();

    final stats = {
      'total': 0,
      'byStatus': {'active': 0, 'injured': 0, 'inactive': 0, 'suspended': 0},
      'byCategory': {'kids': 0, 'adult': 0},
    };

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      stats['total'] = (stats['total'] as int) + 1;

      final status = data['status'] as String?;
      if (status != null && (stats['byStatus'] as Map).containsKey(status)) {
        (stats['byStatus'] as Map)[status] =
            ((stats['byStatus'] as Map)[status] as int) + 1;
      }

      final category = data['category'] as String?;
      if (category != null &&
          (stats['byCategory'] as Map).containsKey(category)) {
        (stats['byCategory'] as Map)[category] =
            ((stats['byCategory'] as Map)[category] as int) + 1;
      }
    }

    return stats;
  }

  // ============================================
  // Update Student
  // ============================================
  Future<Student> update(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _collections.student(id).update(data);
    final updated = await getById(id);
    return updated!;
  }

  // ============================================
  // Update Belt/Stripes
  // ============================================
  Future<Student> updateBelt(String id, String newBelt, int newStripes) async {
    return update(id, {'currentBelt': newBelt, 'currentStripes': newStripes});
  }

  // ============================================
  // Update Grade (multi-sport aware)
  // ============================================
  Future<Student> updateGrade(
    String id,
    SportId sportId,
    String grade,
    int stripes,
  ) async {
    final data = <String, dynamic>{};
    // Always update legacy fields for BJJ (backward compat with marcusjj)
    if (sportId == SportId.bjj) {
      data['currentBelt'] = grade;
      data['currentStripes'] = stripes;
    }
    // Write to sportData
    data['sportData.${sportId.value}.currentGrade'] = grade;
    data['sportData.${sportId.value}.currentStripes'] = stripes;
    return update(id, data);
  }

  // ============================================
  // Update Sports List
  // ============================================
  Future<Student> updateSports(String id, List<SportId> sportIds) async {
    return update(id, {'sports': sportIds.map((s) => s.value).toList()});
  }

  // ============================================
  // Update Primary Sport
  // ============================================
  Future<Student> updatePrimarySport(String id, SportId sportId) async {
    return update(id, {'primarySport': sportId.value});
  }

  // ============================================
  // Update Photo URL
  // ============================================
  Future<void> updatePhotoUrl(String id, String photoUrl) async {
    await _collections.student(id).update({
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Link Student to User
  // ============================================
  Future<void> linkToUser(String studentId, String userId) async {
    await _collections.student(studentId).update({
      'linkedUserId': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Unlink Student from User
  // ============================================
  Future<void> unlinkFromUser(String studentId) async {
    await _collections.student(studentId).update({
      'linkedUserId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Create Student
  // ============================================
  Future<Student> create(Student student, {String? createdBy}) async {
    final data = student.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['createdBy'] = createdBy;
    data['attendanceCount'] = 0;

    final docRef = await _studentsRef.add(data);
    final doc = await docRef.get();
    return Student.fromFirestore(doc);
  }

  // ============================================
  // Create Student from Map (for forms)
  // ============================================
  Future<Student> createFromMap(
    Map<String, dynamic> data, {
    String? createdBy,
  }) async {
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['createdBy'] = createdBy;
    data['attendanceCount'] = data['attendanceCount'] ?? 0;

    final docRef = await _studentsRef.add(data);
    final doc = await docRef.get();
    return Student.fromFirestore(doc);
  }

  // ============================================
  // Quick Create (minimal data)
  //
  // Requires at least one sport. The first entry in [sports] becomes the
  // primary sport. For each sport, the student is seeded with the first
  // grade in that sport's grade list for the requested category (kids/adult).
  // Legacy `currentBelt`/`currentStripes` are written from the primary
  // sport for backward compatibility with older read paths.
  // ============================================
  Future<Student> quickCreate({
    required String fullName,
    required List<SportId> sports,
    String? phone,
    String? email,
    StudentCategory category = StudentCategory.adult,
    String? createdBy,
  }) async {
    if (sports.isEmpty) {
      throw ArgumentError('Pelo menos uma modalidade deve ser informada');
    }

    final primary = sports.first;
    final sportData = <String, dynamic>{};
    String legacyBelt = 'white';
    int legacyStripes = 0;
    for (final sport in sports) {
      final grades = getGradesForSport(sport, category: category.value);
      final firstGradeId = grades.isNotEmpty ? grades.first.id : 'white';
      sportData[sport.value] = {
        'currentGrade': firstGradeId,
        'currentStripes': 0,
      };
      if (sport == primary) {
        legacyBelt = firstGradeId;
        legacyStripes = 0;
      }
    }

    final now = DateTime.now();
    final data = {
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'category': category.value,
      'status': StudentStatus.active.value,
      'currentBelt': legacyBelt,
      'currentStripes': legacyStripes,
      'sports': sports.map((s) => s.value).toList(),
      'sportData': sportData,
      'primarySport': primary.value,
      'startDate': Timestamp.fromDate(now),
      'tuitionValue': 0.0,
      'tuitionDay': 10,
      'isProfilePublic': false,
      'attendanceCount': 0,
      'initialAttendanceCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    };

    final docRef = await _studentsRef.add(data);
    final doc = await docRef.get();
    return Student.fromFirestore(doc);
  }

  // ============================================
  // Delete Student (Soft Delete - set inactive)
  // ============================================
  Future<void> delete(String id) async {
    await _collections.student(id).update({
      'status': StudentStatus.inactive.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Hard Delete Student (permanent)
  // ============================================
  Future<void> hardDelete(String id) async {
    await _collections.student(id).delete();
  }

  // ============================================
  // Get All Students (for reports, no limit)
  // ============================================
  Future<List<Student>> getAll() async {
    final snapshot = await _studentsRef.get();
    var students = snapshot.docs
        .map((doc) => Student.fromFirestore(doc))
        .toList();
    students.sort((a, b) => a.fullName.compareTo(b.fullName));
    return students;
  }

  // ============================================
  // Get All Students — PAGINATED (Sprint 5)
  //
  // Server-side cursor pagination using `startAfterDocument`. Designed for
  // infinite-scroll lists (admin/monitor student lists with hundreds of
  // entries) where loading the full collection upfront would be wasteful.
  //
  // Sorted by `fullName` ascending so paginated chunks stay alphabetically
  // ordered without a client-side merge step. A single-field index on
  // `fullName` is auto-created by Firestore — no manual index entry needed.
  //
  // Optional `status` filter is supported. When combined with `fullName`,
  // Firestore will warn at runtime if a composite index is missing — see
  // TODO note in `firestore.indexes.json` for the recommended index.
  // ============================================
  Future<({List<Student> items, DocumentSnapshot? lastDoc})> getAllPaginated({
    int limit = 20,
    DocumentSnapshot? startAfter,
    StudentStatus? status,
  }) async {
    Query query = _studentsRef;
    if (status != null) {
      query = query.where('status', isEqualTo: status.value);
    }
    query = query.orderBy('fullName').limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    final items = snap.docs.map((doc) => Student.fromFirestore(doc)).toList();
    return (items: items, lastDoc: snap.docs.isEmpty ? null : snap.docs.last);
  }

  // ============================================
  // Get Count by Status
  // ============================================
  Future<Map<StudentStatus, int>> getCountByStatus() async {
    final snapshot = await _studentsRef.get();
    final counts = {
      StudentStatus.active: 0,
      StudentStatus.injured: 0,
      StudentStatus.inactive: 0,
      StudentStatus.suspended: 0,
    };

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = StudentStatusExtension.fromString(
        data['status'] ?? 'active',
      );
      counts[status] = counts[status]! + 1;
    }

    return counts;
  }

  // ============================================
  // Sync Attendance Counts from Records
  // ============================================
  Future<void> syncAttendanceCounts() async {
    final students = await getAll();
    final attendanceRef = _collections.attendance;

    for (final student in students) {
      final attendanceQuery = await attendanceRef
          .where('studentId', isEqualTo: student.id)
          .get();

      await _collections.student(student.id).update({
        'attendanceCount': attendanceQuery.size,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ============================================
  // Update Status
  // ============================================
  Future<Student> updateStatus(
    String id,
    StudentStatus status, {
    String? note,
  }) async {
    final data = <String, dynamic>{
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (note != null) {
      data['statusNote'] = note;
    }
    return update(id, data);
  }
}

// ============================================
// Factory Function
// ============================================
StudentService createStudentService(String academyId) {
  return StudentService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
StudentService get studentService => StudentService(FirebaseService.academyId);
