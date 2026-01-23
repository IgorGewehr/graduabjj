import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

/// Competition Status
enum CompetitionStatus { upcoming, ongoing, completed, cancelled }

extension CompetitionStatusExtension on CompetitionStatus {
  String get value {
    switch (this) {
      case CompetitionStatus.upcoming:
        return 'upcoming';
      case CompetitionStatus.ongoing:
        return 'ongoing';
      case CompetitionStatus.completed:
        return 'completed';
      case CompetitionStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case CompetitionStatus.upcoming:
        return 'Próxima';
      case CompetitionStatus.ongoing:
        return 'Em Andamento';
      case CompetitionStatus.completed:
        return 'Concluída';
      case CompetitionStatus.cancelled:
        return 'Cancelada';
    }
  }

  static CompetitionStatus fromString(String value) {
    switch (value) {
      case 'upcoming':
        return CompetitionStatus.upcoming;
      case 'ongoing':
        return CompetitionStatus.ongoing;
      case 'completed':
        return CompetitionStatus.completed;
      case 'cancelled':
        return CompetitionStatus.cancelled;
      default:
        return CompetitionStatus.upcoming;
    }
  }
}

/// Transport Status
enum TransportStatus { available, full, notAvailable }

extension TransportStatusExtension on TransportStatus {
  String get value {
    switch (this) {
      case TransportStatus.available:
        return 'available';
      case TransportStatus.full:
        return 'full';
      case TransportStatus.notAvailable:
        return 'not_available';
    }
  }

  static TransportStatus fromString(String value) {
    switch (value) {
      case 'available':
        return TransportStatus.available;
      case 'full':
        return TransportStatus.full;
      default:
        return TransportStatus.notAvailable;
    }
  }
}

/// Competition Model
class Competition {
  final String id;
  final String name;
  final DateTime date;
  final String? location;
  final String? description;
  final CompetitionStatus status;
  final DateTime? registrationDeadline;
  final List<String> enrolledStudentIds;
  final TransportStatus? transportStatus;
  final String? transportNotes;
  final int? transportCapacity;
  final DateTime createdAt;
  final DateTime updatedAt;

  Competition({
    required this.id,
    required this.name,
    required this.date,
    this.location,
    this.description,
    required this.status,
    this.registrationDeadline,
    this.enrolledStudentIds = const [],
    this.transportStatus,
    this.transportNotes,
    this.transportCapacity,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Competition.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Competition(
      id: doc.id,
      name: data['name'] ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      location: data['location'],
      description: data['description'],
      status: CompetitionStatusExtension.fromString(data['status'] ?? 'upcoming'),
      registrationDeadline: data['registrationDeadline'] != null
          ? (data['registrationDeadline'] as Timestamp).toDate()
          : null,
      enrolledStudentIds: data['enrolledStudentIds'] != null
          ? List<String>.from(data['enrolledStudentIds'])
          : [],
      transportStatus: data['transportStatus'] != null
          ? TransportStatusExtension.fromString(data['transportStatus'])
          : null,
      transportNotes: data['transportNotes'],
      transportCapacity: data['transportCapacity'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Computed properties
  bool get isUpcoming => status == CompetitionStatus.upcoming;
  bool get isCompleted => status == CompetitionStatus.completed;
  bool get isRegistrationOpen =>
      registrationDeadline == null || DateTime.now().isBefore(registrationDeadline!);
  int get enrolledCount => enrolledStudentIds.length;
}

/// Competition Result Model
class CompetitionResult {
  final String id;
  final String competitionId;
  final String competitionName;
  final String studentId;
  final String studentName;
  final String position; // gold, silver, bronze, participant
  final String? beltCategory;
  final String? ageCategory;
  final String? weightCategory;
  final String? notes;
  final DateTime date;
  final DateTime createdAt;

  CompetitionResult({
    required this.id,
    required this.competitionId,
    required this.competitionName,
    required this.studentId,
    required this.studentName,
    required this.position,
    this.beltCategory,
    this.ageCategory,
    this.weightCategory,
    this.notes,
    required this.date,
    required this.createdAt,
  });

  factory CompetitionResult.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CompetitionResult(
      id: doc.id,
      competitionId: data['competitionId'] ?? '',
      competitionName: data['competitionName'] ?? '',
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      position: data['position'] ?? 'participant',
      beltCategory: data['beltCategory'],
      ageCategory: data['ageCategory'],
      weightCategory: data['weightCategory'],
      notes: data['notes'],
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Competition Service - Multi-tenant competition management
class CompetitionService {
  final String academyId;
  late final Collections _collections;

  CompetitionService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _competitionsRef => _collections.competitions;

  // ============================================
  // List All Competitions
  // ============================================
  Future<List<Competition>> list() async {
    final snapshot = await _competitionsRef.get();
    var competitions = snapshot.docs.map((doc) => Competition.fromFirestore(doc)).toList();
    competitions.sort((a, b) => b.date.compareTo(a.date));
    return competitions;
  }

  // ============================================
  // Get Competition by ID
  // ============================================
  Future<Competition?> getById(String id) async {
    final doc = await _collections.competition(id).get();
    if (!doc.exists) return null;
    return Competition.fromFirestore(doc);
  }

  // ============================================
  // Get Upcoming Competitions
  // ============================================
  Future<List<Competition>> getUpcoming() async {
    final competitions = await list();
    return competitions
        .where((c) => c.status == CompetitionStatus.upcoming)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // ============================================
  // Get Completed Competitions
  // ============================================
  Future<List<Competition>> getCompleted() async {
    final competitions = await list();
    return competitions
        .where((c) => c.status == CompetitionStatus.completed)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // ============================================
  // Get Competitions by Student
  // ============================================
  Future<List<Competition>> getByStudent(String studentId) async {
    final competitions = await list();
    return competitions
        .where((c) => c.enrolledStudentIds.contains(studentId))
        .toList();
  }

  // ============================================
  // Check if Student is Enrolled
  // ============================================
  Future<bool> isStudentEnrolled(String competitionId, String studentId) async {
    final competition = await getById(competitionId);
    return competition?.enrolledStudentIds.contains(studentId) ?? false;
  }

  // ============================================
  // Get For Student (alias)
  // ============================================
  Future<List<Competition>> getForStudent(String studentId) async {
    return getByStudent(studentId);
  }

  // ============================================
  // WRITE OPERATIONS - Competition
  // ============================================

  // ============================================
  // Create Competition
  // ============================================
  Future<Competition> create({
    required String name,
    required DateTime date,
    String? location,
    String? description,
    DateTime? registrationDeadline,
    TransportStatus? transportStatus,
    String? transportNotes,
    int? transportCapacity,
    String? createdBy,
  }) async {
    final docRef = await _competitionsRef.add({
      'name': name,
      'date': Timestamp.fromDate(date),
      'location': location,
      'description': description,
      'status': CompetitionStatus.upcoming.value,
      'registrationDeadline': registrationDeadline != null
          ? Timestamp.fromDate(registrationDeadline)
          : null,
      'enrolledStudentIds': [],
      'transportStatus': transportStatus?.value,
      'transportNotes': transportNotes,
      'transportCapacity': transportCapacity,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    });

    final doc = await docRef.get();
    return Competition.fromFirestore(doc);
  }

  // ============================================
  // Update Competition
  // ============================================
  Future<Competition> update(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _collections.competition(id).update(data);
    final updated = await getById(id);
    return updated!;
  }

  // ============================================
  // Delete Competition (and all results)
  // ============================================
  Future<void> delete(String id) async {
    // Delete all results for this competition
    final results = await getResultsForCompetition(id);
    for (final result in results) {
      await deleteResult(result.id);
    }

    // Delete the competition
    await _collections.competition(id).delete();
  }

  // ============================================
  // Update Transport Status
  // ============================================
  Future<Competition> updateTransportStatus(
    String id,
    TransportStatus status, {
    String? notes,
    int? capacity,
  }) async {
    final data = <String, dynamic>{
      'transportStatus': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (notes != null) data['transportNotes'] = notes;
    if (capacity != null) data['transportCapacity'] = capacity;

    return update(id, data);
  }

  // ============================================
  // Add Custom Weight Category
  // ============================================
  Future<Competition> addCustomWeightCategory(String id, String category) async {
    await _collections.competition(id).update({
      'customWeightCategories': FieldValue.arrayUnion([category]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final updated = await getById(id);
    return updated!;
  }

  // ============================================
  // Remove Custom Weight Category
  // ============================================
  Future<Competition> removeCustomWeightCategory(String id, String category) async {
    await _collections.competition(id).update({
      'customWeightCategories': FieldValue.arrayRemove([category]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final updated = await getById(id);
    return updated!;
  }

  // ============================================
  // Enroll Student
  // ============================================
  Future<Competition> enrollStudent(String competitionId, String studentId) async {
    await _collections.competition(competitionId).update({
      'enrolledStudentIds': FieldValue.arrayUnion([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final updated = await getById(competitionId);
    return updated!;
  }

  // ============================================
  // Unenroll Student
  // ============================================
  Future<Competition> unenrollStudent(String competitionId, String studentId) async {
    await _collections.competition(competitionId).update({
      'enrolledStudentIds': FieldValue.arrayRemove([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final updated = await getById(competitionId);
    return updated!;
  }

  // ============================================
  // Toggle Enrollment
  // ============================================
  Future<Competition> toggleEnrollment(String competitionId, String studentId) async {
    final competition = await getById(competitionId);
    if (competition == null) throw Exception('Campeonato não encontrado');

    if (competition.enrolledStudentIds.contains(studentId)) {
      return unenrollStudent(competitionId, studentId);
    } else {
      return enrollStudent(competitionId, studentId);
    }
  }

  // ============================================
  // Update Status
  // ============================================
  Future<Competition> updateStatus(String id, CompetitionStatus status) async {
    return update(id, {'status': status.value});
  }

  // ============================================
  // RESULTS OPERATIONS
  // ============================================

  CollectionReference get _resultsRef =>
      FirebaseService.firestore.collection('academies/$academyId/competitionResults');

  // ============================================
  // Add Result
  // ============================================
  Future<CompetitionResult> addResult({
    required String competitionId,
    required String competitionName,
    required String studentId,
    required String studentName,
    required String position,
    String? beltCategory,
    String? ageCategory,
    String? weightCategory,
    String? notes,
    DateTime? date,
    String? createdBy,
  }) async {
    final docRef = await _resultsRef.add({
      'competitionId': competitionId,
      'competitionName': competitionName,
      'studentId': studentId,
      'studentName': studentName,
      'position': position,
      'beltCategory': beltCategory,
      'ageCategory': ageCategory,
      'weightCategory': weightCategory,
      'notes': notes,
      'date': Timestamp.fromDate(date ?? DateTime.now()),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    });

    final doc = await docRef.get();
    return CompetitionResult.fromFirestore(doc);
  }

  // ============================================
  // Get Results for Competition
  // ============================================
  Future<List<CompetitionResult>> getResultsForCompetition(String competitionId) async {
    final query = await _resultsRef
        .where('competitionId', isEqualTo: competitionId)
        .get();

    var results = query.docs.map((doc) => CompetitionResult.fromFirestore(doc)).toList();
    results.sort((a, b) {
      const positionOrder = {'gold': 0, 'silver': 1, 'bronze': 2, 'participant': 3};
      return (positionOrder[a.position] ?? 3).compareTo(positionOrder[b.position] ?? 3);
    });
    return results;
  }

  // ============================================
  // Get Results for Student
  // ============================================
  Future<List<CompetitionResult>> getResultsForStudent(String studentId) async {
    final query = await _resultsRef
        .where('studentId', isEqualTo: studentId)
        .get();

    var results = query.docs.map((doc) => CompetitionResult.fromFirestore(doc)).toList();
    results.sort((a, b) => b.date.compareTo(a.date));
    return results;
  }

  // ============================================
  // Get Medal Count
  // ============================================
  Future<Map<String, int>> getMedalCount(String studentId) async {
    final results = await getResultsForStudent(studentId);

    final counts = {
      'gold': 0,
      'silver': 0,
      'bronze': 0,
      'total': 0,
    };

    for (final result in results) {
      if (result.position == 'gold') counts['gold'] = counts['gold']! + 1;
      if (result.position == 'silver') counts['silver'] = counts['silver']! + 1;
      if (result.position == 'bronze') counts['bronze'] = counts['bronze']! + 1;
    }

    counts['total'] = counts['gold']! + counts['silver']! + counts['bronze']!;
    return counts;
  }

  // ============================================
  // Get Result by ID
  // ============================================
  Future<CompetitionResult?> getResultById(String id) async {
    final doc = await _resultsRef.doc(id).get();
    if (!doc.exists) return null;
    return CompetitionResult.fromFirestore(doc);
  }

  // ============================================
  // Update Result
  // ============================================
  Future<CompetitionResult> updateResult(String id, Map<String, dynamic> data) async {
    await _resultsRef.doc(id).update(data);
    final updated = await getResultById(id);
    return updated!;
  }

  // ============================================
  // Delete Result
  // ============================================
  Future<void> deleteResult(String id) async {
    await _resultsRef.doc(id).delete();
  }
}

// ============================================
// Factory Function
// ============================================
CompetitionService createCompetitionService(String academyId) {
  return CompetitionService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
CompetitionService get competitionService => CompetitionService(FirebaseService.academyId);
