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
  final String? teamPosition; // 'gold' | 'silver' | 'bronze'
  final String? teamNotes;
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
    this.teamPosition,
    this.teamNotes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Competition.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Safe timestamp parser — handles Timestamp, null, or invalid types
    DateTime? safeTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return null;
    }

    // Safe list parser
    List<String> safeStringList(dynamic value) {
      if (value == null) return [];
      if (value is List) return value.map((e) => e.toString()).toList();
      return [];
    }

    return Competition(
      id: doc.id,
      name: data['name'] ?? '',
      date: safeTimestamp(data['date']) ?? DateTime.now(),
      location: data['location']?.toString(),
      description: data['description']?.toString(),
      status: CompetitionStatusExtension.fromString(data['status'] ?? 'upcoming'),
      registrationDeadline: safeTimestamp(data['registrationDeadline']),
      enrolledStudentIds: safeStringList(data['enrolledStudentIds']),
      transportStatus: data['transportStatus'] != null
          ? TransportStatusExtension.fromString(data['transportStatus'].toString())
          : null,
      transportNotes: data['transportNotes']?.toString(),
      transportCapacity: data['transportCapacity'] is int ? data['transportCapacity'] : null,
      teamPosition: data['teamPosition']?.toString(),
      teamNotes: data['teamNotes']?.toString(),
      createdAt: safeTimestamp(data['createdAt']) ?? DateTime.now(),
      updatedAt: safeTimestamp(data['updatedAt']) ?? DateTime.now(),
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
  final String? modality; // gi, nogi
  final String? divisionType; // weight, absolute
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
    this.modality,
    this.divisionType,
    this.notes,
    required this.date,
    required this.createdAt,
  });

  factory CompetitionResult.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    DateTime? safeTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return null;
    }

    return CompetitionResult(
      id: doc.id,
      competitionId: data['competitionId'] ?? '',
      competitionName: data['competitionName'] ?? '',
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      position: data['position'] ?? 'participant',
      beltCategory: data['beltCategory']?.toString(),
      ageCategory: data['ageCategory']?.toString(),
      weightCategory: data['weightCategory']?.toString(),
      modality: data['modality']?.toString(),
      divisionType: data['divisionType']?.toString(),
      notes: data['notes']?.toString(),
      date: safeTimestamp(data['date']) ?? DateTime.now(),
      createdAt: safeTimestamp(data['createdAt']) ?? DateTime.now(),
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
    CompetitionStatus? status,
    DateTime? registrationDeadline,
    TransportStatus? transportStatus,
    String? transportNotes,
    int? transportCapacity,
    String? createdBy,
  }) async {
    final effectiveStatus = status ?? (date.isBefore(DateTime.now()) ? CompetitionStatus.completed : CompetitionStatus.upcoming);
    final docRef = await _competitionsRef.add({
      'name': name,
      'date': Timestamp.fromDate(date),
      'location': location,
      'description': description,
      'status': effectiveStatus.value,
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
    // Quando a data muda mas nenhum status explícito é informado, deriva o
    // status da data (espelha o create) para o campeonato não cair na aba errada.
    if (data.containsKey('date') && !data.containsKey('status')) {
      final rawDate = data['date'];
      DateTime? parsedDate;
      if (rawDate is Timestamp) {
        parsedDate = rawDate.toDate();
      } else if (rawDate is DateTime) {
        parsedDate = rawDate;
        // Normaliza para Timestamp por paridade com o create.
        data['date'] = Timestamp.fromDate(rawDate);
      }
      if (parsedDate != null) {
        data['status'] = parsedDate.isBefore(DateTime.now())
            ? CompetitionStatus.completed.value
            : CompetitionStatus.upcoming.value;
      }
    }
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _collections.competition(id).update(data);
    final updated = await getById(id);
    return updated!;
  }

  // ============================================
  // Delete Competition (cascade: results + enrollments + doc)
  // ============================================
  Future<void> delete(String id) async {
    // Busca todos os documentos dependentes para apagar em cascata.
    final resultsSnapshot =
        await _resultsRef.where('competitionId', isEqualTo: id).get();
    final enrollmentsSnapshot = await _collections.competitionEnrollments
        .where('competitionId', isEqualTo: id)
        .get();

    // Reúne todas as referências (results + enrollments + o doc do campeonato).
    final refs = <DocumentReference>[
      ...resultsSnapshot.docs.map((doc) => doc.reference),
      ...enrollmentsSnapshot.docs.map((doc) => doc.reference),
      _collections.competition(id),
    ];

    // Apaga em WriteBatch atômico, chunkando em lotes de 500 (limite do Firestore).
    const chunkSize = 500;
    for (var i = 0; i < refs.length; i += chunkSize) {
      final batch = FirebaseService.firestore.batch();
      final end = (i + chunkSize < refs.length) ? i + chunkSize : refs.length;
      for (var j = i; j < end; j++) {
        batch.delete(refs[j]);
      }
      await batch.commit();
    }
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
    String? modality,
    String? divisionType,
    String? notes,
    DateTime? date,
    String? createdBy,
  }) async {
    final data = <String, dynamic>{
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
    };
    if (modality != null) data['modality'] = modality;
    if (divisionType != null) data['divisionType'] = divisionType;
    final docRef = await _resultsRef.add(data);

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
