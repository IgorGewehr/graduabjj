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
    required this.createdAt,
    required this.updatedAt,
  });

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
  // Get Plan for Student
  // ============================================
  Future<Plan?> getPlanForStudent(String studentId) async {
    final plans = await list();
    return plans.where((p) => p.studentIds.contains(studentId)).firstOrNull;
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

    // Check if value or due day changed to sync students
    final oldPlan = await getById(id);
    final valueChanged = data.containsKey('monthlyValue') &&
        data['monthlyValue'] != oldPlan?.monthlyValue;
    final dueDayChanged = data.containsKey('defaultDueDay') &&
        data['defaultDueDay'] != oldPlan?.defaultDueDay;

    await _collections.plan(id).update(data);

    // Sync students if value or due day changed
    if ((valueChanged || dueDayChanged) && oldPlan != null) {
      for (final studentId in oldPlan.studentIds) {
        final studentData = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (valueChanged && data.containsKey('monthlyValue')) {
          studentData['tuitionValue'] = data['monthlyValue'];
        }
        if (dueDayChanged && data.containsKey('defaultDueDay')) {
          studentData['tuitionDay'] = data['defaultDueDay'];
        }
        await _collections.student(studentId).update(studentData);
      }
    }

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
    // First remove from any other plan
    final currentPlan = await getPlanForStudent(studentId);
    if (currentPlan != null && currentPlan.id != planId) {
      await removeStudent(currentPlan.id, studentId);
    }

    // Add to new plan
    await _collections.plan(planId).update({
      'studentIds': FieldValue.arrayUnion([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update student with plan values
    final plan = await getById(planId);
    if (plan != null) {
      await _collections.student(studentId).update({
        'tuitionValue': plan.monthlyValue,
        'tuitionDay': plan.defaultDueDay,
        'planId': planId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final updated = await getById(planId);
    return updated!;
  }

  // ============================================
  // Remove Student from Plan
  // ============================================
  Future<Plan> removeStudent(String planId, String studentId) async {
    await _collections.plan(planId).update({
      'studentIds': FieldValue.arrayRemove([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Remove plan reference from student
    await _collections.student(studentId).update({
      'planId': FieldValue.delete(),
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
