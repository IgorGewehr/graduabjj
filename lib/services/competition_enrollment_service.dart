import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

/// Transport Preference
enum TransportPreference { needTransport, ownTransport, undecided }

extension TransportPreferenceExtension on TransportPreference {
  String get value {
    switch (this) {
      case TransportPreference.needTransport:
        return 'need_transport';
      case TransportPreference.ownTransport:
        return 'own_transport';
      case TransportPreference.undecided:
        return 'undecided';
    }
  }

  String get label {
    switch (this) {
      case TransportPreference.needTransport:
        return 'Preciso de transporte';
      case TransportPreference.ownTransport:
        return 'Transporte próprio';
      case TransportPreference.undecided:
        return 'A decidir';
    }
  }

  static TransportPreference fromString(String value) {
    switch (value) {
      case 'need_transport':
        return TransportPreference.needTransport;
      case 'own_transport':
        return TransportPreference.ownTransport;
      default:
        return TransportPreference.undecided;
    }
  }
}

/// Competition Enrollment Model
class CompetitionEnrollment {
  final String id;
  final String competitionId;
  final String? competitionName;
  final String studentId;
  final String studentName;
  final String? ageCategory;
  final String? weightCategory;
  final TransportPreference transportPreference;
  final DateTime enrolledAt;
  final String? enrolledBy;

  CompetitionEnrollment({
    required this.id,
    required this.competitionId,
    this.competitionName,
    required this.studentId,
    required this.studentName,
    this.ageCategory,
    this.weightCategory,
    required this.transportPreference,
    required this.enrolledAt,
    this.enrolledBy,
  });

  factory CompetitionEnrollment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CompetitionEnrollment(
      id: doc.id,
      competitionId: data['competitionId'] ?? '',
      competitionName: data['competitionName'],
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      ageCategory: data['ageCategory'],
      weightCategory: data['weightCategory'],
      transportPreference: TransportPreferenceExtension.fromString(
          data['transportPreference'] ?? 'undecided'),
      enrolledAt: (data['enrolledAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      enrolledBy: data['enrolledBy'],
    );
  }
}

/// Competition Enrollment Service - Multi-tenant enrollment management
class CompetitionEnrollmentService {
  final String academyId;
  late final Collections _collections;

  CompetitionEnrollmentService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _enrollmentsRef => _collections.competitionEnrollments;

  // ============================================
  // Get Enrollment by Competition and Student
  // ============================================
  Future<CompetitionEnrollment?> getByCompetitionAndStudent(
    String competitionId,
    String studentId,
  ) async {
    final query = await _enrollmentsRef
        .where('competitionId', isEqualTo: competitionId)
        .where('studentId', isEqualTo: studentId)
        .get();

    if (query.docs.isEmpty) return null;
    return CompetitionEnrollment.fromFirestore(query.docs.first);
  }

  // ============================================
  // Get All Enrollments for a Competition
  // ============================================
  Future<List<CompetitionEnrollment>> getByCompetition(String competitionId) async {
    final query = await _enrollmentsRef
        .where('competitionId', isEqualTo: competitionId)
        .get();

    var enrollments = query.docs
        .map((doc) => CompetitionEnrollment.fromFirestore(doc))
        .toList();
    enrollments.sort((a, b) => a.enrolledAt.compareTo(b.enrolledAt));
    return enrollments;
  }

  // ============================================
  // Get All Enrollments for a Student (History)
  // ============================================
  Future<List<CompetitionEnrollment>> getByStudent(String studentId) async {
    print('[CompetitionEnrollmentService] Querying enrollments for studentId: $studentId');
    print('[CompetitionEnrollmentService] Collection path: ${_enrollmentsRef.path}');

    final query = await _enrollmentsRef
        .where('studentId', isEqualTo: studentId)
        .get();

    print('[CompetitionEnrollmentService] Query returned ${query.docs.length} documents');

    var enrollments = query.docs
        .map((doc) => CompetitionEnrollment.fromFirestore(doc))
        .toList();
    enrollments.sort((a, b) => b.enrolledAt.compareTo(a.enrolledAt));
    return enrollments;
  }

  // ============================================
  // Check if Student is Enrolled
  // ============================================
  Future<bool> isEnrolled(String competitionId, String studentId) async {
    final enrollment = await getByCompetitionAndStudent(competitionId, studentId);
    return enrollment != null;
  }

  // ============================================
  // Get Enrollment Count for Competition
  // ============================================
  Future<int> getCount(String competitionId) async {
    final enrollments = await getByCompetition(competitionId);
    return enrollments.length;
  }

  // ============================================
  // Get Transport List (students who need transport)
  // ============================================
  Future<List<CompetitionEnrollment>> getTransportList(String competitionId) async {
    final enrollments = await getByCompetition(competitionId);
    return enrollments
        .where((e) => e.transportPreference == TransportPreference.needTransport)
        .toList();
  }

  // ============================================
  // Get Transport Stats
  // ============================================
  Future<Map<String, int>> getTransportStats(String competitionId) async {
    final enrollments = await getByCompetition(competitionId);

    final stats = {
      'needTransport': 0,
      'ownTransport': 0,
      'undecided': 0,
      'total': enrollments.length,
    };

    for (final e in enrollments) {
      switch (e.transportPreference) {
        case TransportPreference.needTransport:
          stats['needTransport'] = stats['needTransport']! + 1;
          break;
        case TransportPreference.ownTransport:
          stats['ownTransport'] = stats['ownTransport']! + 1;
          break;
        case TransportPreference.undecided:
          stats['undecided'] = stats['undecided']! + 1;
          break;
      }
    }

    return stats;
  }

  // ============================================
  // Get By Category
  // ============================================
  Future<List<CompetitionEnrollment>> getByCategory(
    String competitionId, {
    String? ageCategory,
    String? weightCategory,
  }) async {
    final enrollments = await getByCompetition(competitionId);
    return enrollments.where((e) {
      if (ageCategory != null && e.ageCategory != ageCategory) return false;
      if (weightCategory != null && e.weightCategory != weightCategory) return false;
      return true;
    }).toList();
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Enroll Student
  // ============================================
  Future<CompetitionEnrollment> enroll({
    required String competitionId,
    String? competitionName,
    required String studentId,
    required String studentName,
    String? ageCategory,
    String? weightCategory,
    TransportPreference transportPreference = TransportPreference.undecided,
    String? enrolledBy,
  }) async {
    // Check if already enrolled
    final existing = await getByCompetitionAndStudent(competitionId, studentId);
    if (existing != null) {
      throw Exception('Aluno já está inscrito neste campeonato');
    }

    final docRef = await _enrollmentsRef.add({
      'competitionId': competitionId,
      'competitionName': competitionName,
      'studentId': studentId,
      'studentName': studentName,
      'ageCategory': ageCategory,
      'weightCategory': weightCategory,
      'transportPreference': transportPreference.value,
      'enrolledAt': FieldValue.serverTimestamp(),
      'enrolledBy': enrolledBy,
    });

    final doc = await docRef.get();
    return CompetitionEnrollment.fromFirestore(doc);
  }

  // ============================================
  // Update Enrollment
  // ============================================
  Future<CompetitionEnrollment> update(String id, {
    String? ageCategory,
    String? weightCategory,
    TransportPreference? transportPreference,
  }) async {
    final data = <String, dynamic>{};
    if (ageCategory != null) data['ageCategory'] = ageCategory;
    if (weightCategory != null) data['weightCategory'] = weightCategory;
    if (transportPreference != null) data['transportPreference'] = transportPreference.value;

    await _collections.competitionEnrollment(id).update(data);

    final doc = await _collections.competitionEnrollment(id).get();
    return CompetitionEnrollment.fromFirestore(doc);
  }

  // ============================================
  // Delete Enrollment (Unenroll)
  // ============================================
  Future<void> delete(String id) async {
    await _collections.competitionEnrollment(id).delete();
  }

  // ============================================
  // Delete All Enrollments for Competition
  // ============================================
  Future<void> deleteByCompetition(String competitionId) async {
    final enrollments = await getByCompetition(competitionId);
    for (final enrollment in enrollments) {
      await delete(enrollment.id);
    }
  }
}

// ============================================
// Factory Function
// ============================================
CompetitionEnrollmentService createCompetitionEnrollmentService(String academyId) {
  return CompetitionEnrollmentService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
CompetitionEnrollmentService get competitionEnrollmentService =>
    CompetitionEnrollmentService(FirebaseService.academyId);
