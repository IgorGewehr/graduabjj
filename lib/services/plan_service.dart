import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

/// Plan Model
class Plan {
  final String id;
  final String name;
  final String? description;
  final double monthlyValue;
  final int defaultDueDay;
  final int? classesPerWeek;
  final List<String> studentIds;
  final bool isActive;
  final Map<String, double> customValues;
  final DateTime createdAt;
  final DateTime updatedAt;

  Plan({
    required this.id,
    required this.name,
    this.description,
    required this.monthlyValue,
    this.defaultDueDay = 10,
    this.classesPerWeek,
    this.studentIds = const [],
    this.isActive = true,
    this.customValues = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns the value a specific student pays in this plan.
  /// If the student has a custom value, returns it; otherwise returns monthlyValue.
  double getStudentValue(String studentId) =>
      customValues[studentId] ?? monthlyValue;

  Plan copyWith({
    String? id,
    String? name,
    String? description,
    double? monthlyValue,
    int? defaultDueDay,
    int? classesPerWeek,
    List<String>? studentIds,
    bool? isActive,
    Map<String, double>? customValues,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Plan(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      monthlyValue: monthlyValue ?? this.monthlyValue,
      defaultDueDay: defaultDueDay ?? this.defaultDueDay,
      classesPerWeek: classesPerWeek ?? this.classesPerWeek,
      studentIds: studentIds ?? this.studentIds,
      isActive: isActive ?? this.isActive,
      customValues: customValues ?? this.customValues,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Plan.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Plan(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      monthlyValue: (data['monthlyValue'] ?? 0).toDouble(),
      defaultDueDay: data['defaultDueDay'] ?? 10,
      classesPerWeek: data['classesPerWeek'],
      studentIds: data['studentIds'] != null
          ? List<String>.from(data['studentIds'])
          : [],
      isActive: data['isActive'] ?? true,
      customValues: data['customValues'] != null
          ? Map<String, double>.from(
              (data['customValues'] as Map).map(
                (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
              ),
            )
          : {},
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Computed properties
  int get studentCount => studentIds.length;
  String get formattedValue => 'R\$ ${monthlyValue.toStringAsFixed(2)}';
}

/// Plan Service - Multi-tenant plan management
class PlanService {
  final String academyId;
  late final Collections _collections;

  PlanService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _plansRef => _collections.plans;

  // ============================================
  // List All Plans
  // ============================================
  Future<List<Plan>> list() async {
    final snapshot = await _plansRef.get();
    var plans = snapshot.docs.map((doc) => Plan.fromFirestore(doc)).toList();
    plans.sort((a, b) => a.monthlyValue.compareTo(b.monthlyValue));
    return plans;
  }

  // ============================================
  // Get Active Plans
  // ============================================
  Future<List<Plan>> getActive() async {
    final plans = await list();
    return plans.where((p) => p.isActive).toList();
  }

  // ============================================
  // Get Plan by ID
  // ============================================
  Future<Plan?> getById(String id) async {
    final doc = await _collections.plan(id).get();
    if (!doc.exists) return null;
    return Plan.fromFirestore(doc);
  }

  // ============================================
  // Get Plans for Student (multiple plans)
  // ============================================
  Future<List<Plan>> getPlansForStudent(String studentId) async {
    final plans = await list();
    return plans.where((p) => p.studentIds.contains(studentId)).toList();
  }

  /// Legacy wrapper — returns the first plan for a student (or null).
  Future<Plan?> getPlanForStudent(String studentId) async {
    final plans = await getPlansForStudent(studentId);
    return plans.firstOrNull;
  }

  // ============================================
  // Check if Student has a Plan
  // ============================================
  Future<bool> studentHasPlan(String studentId) async {
    final plan = await getPlanForStudent(studentId);
    return plan != null;
  }

  // ============================================
  // Get Students by Plan
  // ============================================
  Future<List<String>> getStudentsByPlan(String planId) async {
    final plan = await getById(planId);
    return plan?.studentIds ?? [];
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Create Plan
  // ============================================
  Future<Plan> create({
    required String name,
    String? description,
    required double monthlyValue,
    int defaultDueDay = 10,
    int? classesPerWeek,
  }) async {
    final docRef = await _plansRef.add({
      'name': name,
      'description': description,
      'monthlyValue': monthlyValue,
      'defaultDueDay': defaultDueDay,
      'classesPerWeek': classesPerWeek,
      'studentIds': [],
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final doc = await docRef.get();
    return Plan.fromFirestore(doc);
  }

  // ============================================
  // Update Plan
  // ============================================
  Future<Plan> update(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _collections.plan(id).update(data);

    final updated = await getById(id);
    return updated!;
  }

  // ============================================
  // Delete Plan
  // ============================================
  Future<void> delete(String id) async {
    await _collections.plan(id).delete();
  }

  // ============================================
  // Add Student to Plan
  // ============================================
  Future<Plan> addStudent(String planId, String studentId) async {
    await _collections.plan(planId).update({
      'studentIds': FieldValue.arrayUnion([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final updated = await getById(planId);
    return updated!;
  }

  // ============================================
  // Remove Student from Plan
  // ============================================
  Future<Plan> removeStudent(String planId, String studentId) async {
    await _collections.plan(planId).update({
      'studentIds': FieldValue.arrayRemove([studentId]),
      'customValues.$studentId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final updated = await getById(planId);
    return updated!;
  }

  // ============================================
  // Toggle Student in Plan
  // ============================================
  Future<Plan> toggleStudent(String planId, String studentId) async {
    final plan = await getById(planId);
    if (plan == null) throw Exception('Plano não encontrado');

    if (plan.studentIds.contains(studentId)) {
      return removeStudent(planId, studentId);
    } else {
      return addStudent(planId, studentId);
    }
  }

  // ============================================
  // Set Custom Value for Student
  // ============================================
  Future<Plan> setCustomValue(String planId, String studentId, double value) async {
    await _plansRef.doc(planId).update({
      'customValues.$studentId': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return (await getById(planId))!;
  }

  // ============================================
  // Remove Custom Value (restore plan default)
  // ============================================
  Future<Plan> removeCustomValue(String planId, String studentId) async {
    await _plansRef.doc(planId).update({
      'customValues.$studentId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return (await getById(planId))!;
  }
}

// ============================================
// Factory Function
// ============================================
PlanService createPlanService(String academyId) {
  return PlanService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
PlanService get planService => PlanService(FirebaseService.academyId);
