import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

/// Belt Order (adult)
const List<String> beltOrder = ['white', 'blue', 'purple', 'brown', 'black'];

/// Stripe Requirements (classes needed per stripe for each belt)
const Map<String, List<int>> stripeRequirements = {
  'white': [30, 60, 90, 120],
  'blue': [50, 100, 150, 200],
  'purple': [75, 150, 225, 300],
  'brown': [100, 200, 300, 400],
  'black': [150, 300, 450, 600],
};

/// Belt Progression Model
class BeltProgression {
  final String id;
  final String studentId;
  final String previousBelt;
  final int previousStripes;
  final String newBelt;
  final int newStripes;
  final DateTime promotionDate;
  final int totalClasses;
  final String? promotedBy;
  final String? promotedByName;
  final String? notes;
  final DateTime createdAt;

  BeltProgression({
    required this.id,
    required this.studentId,
    required this.previousBelt,
    required this.previousStripes,
    required this.newBelt,
    required this.newStripes,
    required this.promotionDate,
    required this.totalClasses,
    this.promotedBy,
    this.promotedByName,
    this.notes,
    required this.createdAt,
  });

  factory BeltProgression.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BeltProgression(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      previousBelt: data['previousBelt'] ?? 'white',
      previousStripes: data['previousStripes'] ?? 0,
      newBelt: data['newBelt'] ?? 'white',
      newStripes: data['newStripes'] ?? 0,
      promotionDate: (data['promotionDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalClasses: data['totalClasses'] ?? 0,
      promotedBy: data['promotedBy'],
      promotedByName: data['promotedByName'],
      notes: data['notes'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Computed properties
  bool get isBeltChange => previousBelt != newBelt;
  bool get isStripeChange => previousStripes != newStripes;

  // Convenience getters (for backwards compatibility)
  DateTime get date => promotionDate;
  String get belt => newBelt;
  int get stripes => newStripes;
}

/// Eligibility Check Result
class EligibilityResult {
  final bool eligible;
  final String? nextBelt;
  final int? nextStripes;
  final int currentClasses;
  final int requiredClasses;
  final int missingClasses;
  final String message;

  EligibilityResult({
    required this.eligible,
    this.nextBelt,
    this.nextStripes,
    required this.currentClasses,
    required this.requiredClasses,
    required this.missingClasses,
    required this.message,
  });
}

/// Belt Progression Service - Multi-tenant belt progression management
class BeltProgressionService {
  final String academyId;
  late final Collections _collections;

  BeltProgressionService(this.academyId) {
    _collections = Collections(academyId);
  }

  // Note: Progressions might be stored under achievements or a dedicated collection
  // For now, we'll work with what's available

  // ============================================
  // Calculate Next Promotion
  // ============================================
  Map<String, dynamic>? getNextPromotion(String currentBelt, int currentStripes) {
    if (currentStripes < 4) {
      // Next is a stripe
      return {
        'belt': currentBelt,
        'stripes': currentStripes + 1,
      };
    } else {
      // Next is a belt change
      final currentIndex = beltOrder.indexOf(currentBelt);
      if (currentIndex >= beltOrder.length - 1) {
        // Already black belt with 4 stripes
        return null;
      }
      return {
        'belt': beltOrder[currentIndex + 1],
        'stripes': 0,
      };
    }
  }

  // ============================================
  // Check Eligibility for Promotion
  // ============================================
  EligibilityResult checkEligibility({
    required String currentBelt,
    required int currentStripes,
    required int totalClasses,
  }) {
    final nextPromotion = getNextPromotion(currentBelt, currentStripes);

    if (nextPromotion == null) {
      return EligibilityResult(
        eligible: false,
        currentClasses: totalClasses,
        requiredClasses: 0,
        missingClasses: 0,
        message: 'Grau máximo atingido',
      );
    }

    final requirements = stripeRequirements[currentBelt] ?? [0, 0, 0, 0];
    final requiredClasses = requirements.length > currentStripes
        ? requirements[currentStripes]
        : 0;
    final missingClasses = (requiredClasses - totalClasses).clamp(0, requiredClasses);
    final eligible = totalClasses >= requiredClasses;

    final nextBelt = nextPromotion['belt'] as String;
    final nextStripes = nextPromotion['stripes'] as int;

    String message;
    if (eligible) {
      if (nextStripes == 0) {
        message = 'Elegível para faixa ${_getBeltName(nextBelt)}!';
      } else {
        message = 'Elegível para $nextStripesº grau!';
      }
    } else {
      if (nextStripes == 0) {
        message = 'Faltam $missingClasses aulas para faixa ${_getBeltName(nextBelt)}';
      } else {
        message = 'Faltam $missingClasses aulas para $nextStripesº grau';
      }
    }

    return EligibilityResult(
      eligible: eligible,
      nextBelt: nextBelt,
      nextStripes: nextStripes,
      currentClasses: totalClasses,
      requiredClasses: requiredClasses,
      missingClasses: missingClasses,
      message: message,
    );
  }

  // ============================================
  // Calculate Progress Percentage
  // ============================================
  double calculateProgress({
    required String currentBelt,
    required int currentStripes,
    required int totalClasses,
  }) {
    final requirements = stripeRequirements[currentBelt] ?? [0, 0, 0, 0];
    if (currentStripes >= requirements.length) return 1.0;

    final required = requirements[currentStripes];
    if (required == 0) return 0.0;

    return (totalClasses / required).clamp(0.0, 1.0);
  }

  // ============================================
  // Get Classes to Next Stripe
  // ============================================
  int getClassesToNextStripe({
    required String currentBelt,
    required int currentStripes,
    required int totalClasses,
  }) {
    final requirements = stripeRequirements[currentBelt] ?? [0, 0, 0, 0];
    if (currentStripes >= requirements.length) return 0;

    final required = requirements[currentStripes];
    return (required - totalClasses).clamp(0, required);
  }

  String _getBeltName(String belt) {
    const names = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
    };
    return names[belt] ?? belt;
  }

  // ============================================
  // Belt Label Helper (public)
  // ============================================
  String getBeltLabel(String belt) => _getBeltName(belt);

  // ============================================
  // Belt Color Hex
  // ============================================
  String getBeltColorHex(String belt) {
    const colors = {
      'white': '#F5F5F5',
      'blue': '#2563EB',
      'purple': '#7C3AED',
      'brown': '#92400E',
      'black': '#171717',
    };
    return colors[belt] ?? '#F5F5F5';
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  CollectionReference get _progressionsRef =>
      FirebaseService.firestore.collection('academies/$academyId/beltProgressions');

  CollectionReference get _studentsRef => _collections.students;
  CollectionReference get _achievementsRef => _collections.achievements;

  // ============================================
  // Get Progressions by Student
  // ============================================
  Future<List<BeltProgression>> getByStudent(String studentId) async {
    final query = await _progressionsRef
        .where('studentId', isEqualTo: studentId)
        .get();

    var progressions = query.docs.map((doc) => BeltProgression.fromFirestore(doc)).toList();
    progressions.sort((a, b) => b.promotionDate.compareTo(a.promotionDate));
    return progressions;
  }

  // ============================================
  // Get Progression by ID
  // ============================================
  Future<BeltProgression?> getById(String id) async {
    final doc = await _progressionsRef.doc(id).get();
    if (!doc.exists) return null;
    return BeltProgression.fromFirestore(doc);
  }

  // ============================================
  // Get Student Journey (timeline)
  // ============================================
  Future<Map<String, dynamic>> getStudentJourney(String studentId) async {
    final progressions = await getByStudent(studentId);

    // Get current student data
    final studentDoc = await _collections.student(studentId).get();
    final studentData = studentDoc.data() as Map<String, dynamic>?;

    return {
      'progressions': progressions,
      'currentBelt': studentData?['currentBelt'] ?? 'white',
      'currentStripes': studentData?['currentStripes'] ?? 0,
      'totalClasses': (studentData?['initialAttendanceCount'] ?? 0) +
          (studentData?['attendanceCount'] ?? 0),
    };
  }

  // ============================================
  // Promote Student (full promotion)
  // ============================================
  Future<BeltProgression> promote({
    required String studentId,
    required String studentName,
    required String newBelt,
    required int newStripes,
    required String promotedBy,
    required String promotedByName,
    String? notes,
  }) async {
    // Get current student data
    final studentDoc = await _collections.student(studentId).get();
    final studentData = studentDoc.data() as Map<String, dynamic>;
    final currentBelt = studentData['currentBelt'] ?? 'white';
    final currentStripes = studentData['currentStripes'] ?? 0;
    final totalClasses = (studentData['initialAttendanceCount'] ?? 0) +
        (studentData['attendanceCount'] ?? 0);

    // Create progression record
    final progressionRef = await _progressionsRef.add({
      'studentId': studentId,
      'previousBelt': currentBelt,
      'previousStripes': currentStripes,
      'newBelt': newBelt,
      'newStripes': newStripes,
      'promotionDate': FieldValue.serverTimestamp(),
      'totalClasses': totalClasses,
      'promotedBy': promotedBy,
      'promotedByName': promotedByName,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update student
    await _collections.student(studentId).update({
      'currentBelt': newBelt,
      'currentStripes': newStripes,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Create achievement
    final isBeltChange = currentBelt != newBelt;
    await _achievementsRef.add({
      'studentId': studentId,
      'studentName': studentName,
      'type': isBeltChange ? 'graduation' : 'stripe',
      'title': isBeltChange
          ? 'Graduação para Faixa ${_getBeltName(newBelt)}'
          : '$newStripes° Grau na Faixa ${_getBeltName(newBelt)}',
      'description': notes,
      'date': FieldValue.serverTimestamp(),
      'fromBelt': currentBelt,
      'toBelt': newBelt,
      'fromStripes': currentStripes,
      'toStripes': newStripes,
      'isPublic': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': promotedBy,
    });

    final doc = await progressionRef.get();
    return BeltProgression.fromFirestore(doc);
  }

  // ============================================
  // Add Stripe
  // ============================================
  Future<BeltProgression> addStripe({
    required String studentId,
    required String studentName,
    required String promotedBy,
    required String promotedByName,
    String? notes,
  }) async {
    final studentDoc = await _collections.student(studentId).get();
    final studentData = studentDoc.data() as Map<String, dynamic>;
    final currentBelt = studentData['currentBelt'] ?? 'white';
    final currentStripes = studentData['currentStripes'] ?? 0;

    if (currentStripes >= 4) {
      throw Exception('Aluno já possui 4 graus. Use a promoção de faixa.');
    }

    return promote(
      studentId: studentId,
      studentName: studentName,
      newBelt: currentBelt,
      newStripes: currentStripes + 1,
      promotedBy: promotedBy,
      promotedByName: promotedByName,
      notes: notes,
    );
  }

  // ============================================
  // Change Belt
  // ============================================
  Future<BeltProgression> changeBelt({
    required String studentId,
    required String studentName,
    required String newBelt,
    required String promotedBy,
    required String promotedByName,
    String? notes,
  }) async {
    return promote(
      studentId: studentId,
      studentName: studentName,
      newBelt: newBelt,
      newStripes: 0,
      promotedBy: promotedBy,
      promotedByName: promotedByName,
      notes: notes,
    );
  }

  // ============================================
  // Get Eligible Students
  // ============================================
  Future<List<Map<String, dynamic>>> getEligibleStudents() async {
    final snapshot = await _studentsRef.where('status', isEqualTo: 'active').get();
    final eligibleStudents = <Map<String, dynamic>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final currentBelt = data['currentBelt'] ?? 'white';
      final currentStripes = data['currentStripes'] ?? 0;
      final totalClasses = (data['initialAttendanceCount'] ?? 0) +
          (data['attendanceCount'] ?? 0);

      final eligibility = checkEligibility(
        currentBelt: currentBelt,
        currentStripes: currentStripes,
        totalClasses: totalClasses,
      );

      if (eligibility.eligible) {
        eligibleStudents.add({
          'id': doc.id,
          'fullName': data['fullName'],
          'currentBelt': currentBelt,
          'currentStripes': currentStripes,
          'totalClasses': totalClasses,
          'eligibility': eligibility,
        });
      }
    }

    return eligibleStudents;
  }

  // ============================================
  // Get Belt Distribution
  // ============================================
  Future<Map<String, int>> getBeltDistribution() async {
    final snapshot = await _studentsRef.where('status', isEqualTo: 'active').get();
    final distribution = <String, int>{};

    for (final belt in beltOrder) {
      distribution[belt] = 0;
    }

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final belt = data['currentBelt'] ?? 'white';
      distribution[belt] = (distribution[belt] ?? 0) + 1;
    }

    return distribution;
  }

  // ============================================
  // Get Recent Promotions
  // ============================================
  Future<List<BeltProgression>> getRecentPromotions({int limit = 10}) async {
    final snapshot = await _progressionsRef.get();
    var progressions = snapshot.docs.map((doc) => BeltProgression.fromFirestore(doc)).toList();
    progressions.sort((a, b) => b.promotionDate.compareTo(a.promotionDate));

    if (progressions.length > limit) {
      progressions = progressions.sublist(0, limit);
    }

    return progressions;
  }
}

// ============================================
// Factory Function
// ============================================
BeltProgressionService createBeltProgressionService(String academyId) {
  return BeltProgressionService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
BeltProgressionService get beltProgressionService =>
    BeltProgressionService(FirebaseService.academyId);
