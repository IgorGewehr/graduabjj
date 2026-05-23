import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

enum BillingPeriod {
  monthly,
  quarterly,
  semiannual,
  annual;

  int get months => switch (this) {
        BillingPeriod.monthly => 1,
        BillingPeriod.quarterly => 3,
        BillingPeriod.semiannual => 6,
        BillingPeriod.annual => 12,
      };

  String get label => switch (this) {
        BillingPeriod.monthly => 'Mensal',
        BillingPeriod.quarterly => 'Trimestral',
        BillingPeriod.semiannual => 'Semestral',
        BillingPeriod.annual => 'Anual',
      };

  String get periodLabel => switch (this) {
        BillingPeriod.monthly => 'mês',
        BillingPeriod.quarterly => 'trimestre',
        BillingPeriod.semiannual => 'semestre',
        BillingPeriod.annual => 'ano',
      };

  static BillingPeriod fromString(String? value) => switch (value) {
        'quarterly' => BillingPeriod.quarterly,
        'semiannual' => BillingPeriod.semiannual,
        'annual' => BillingPeriod.annual,
        _ => BillingPeriod.monthly,
      };
}

/// Plan Model
class Plan {
  final String id;
  final String name;
  final String? description;
  final double monthlyValue;
  final double? periodValue;
  final BillingPeriod billingPeriod;
  final int defaultDueDay;
  final int? classesPerWeek;
  final List<String> studentIds;
  final bool isActive;
  final Map<String, double> customValues;
  final Map<String, int> customDueDays;
  /// Sport id this plan applies to ('bjj', 'muaythai', ...). Null = legacy
  /// "any modality" plan from before the field existed.
  final String? sport;
  final DateTime createdAt;
  final DateTime updatedAt;

  Plan({
    required this.id,
    required this.name,
    this.description,
    required this.monthlyValue,
    this.periodValue,
    this.billingPeriod = BillingPeriod.monthly,
    this.defaultDueDay = 10,
    this.classesPerWeek,
    this.studentIds = const [],
    this.isActive = true,
    this.customValues = const {},
    this.customDueDays = const {},
    this.sport,
    required this.createdAt,
    required this.updatedAt,
  });

  /// The actual amount charged per billing cycle.
  /// For monthly plans this equals monthlyValue.
  /// For non-monthly plans this equals periodValue if set, or monthlyValue as fallback.
  double get effectivePeriodValue => periodValue ?? monthlyValue;

  /// Returns the amount this student is charged per billing cycle.
  double getStudentValue(String studentId) =>
      customValues[studentId] ?? effectivePeriodValue;

  int getStudentDueDay(String studentId) =>
      customDueDays[studentId] ?? defaultDueDay;

  Plan copyWith({
    String? id,
    String? name,
    String? description,
    double? monthlyValue,
    double? periodValue,
    BillingPeriod? billingPeriod,
    int? defaultDueDay,
    int? classesPerWeek,
    List<String>? studentIds,
    bool? isActive,
    Map<String, double>? customValues,
    Map<String, int>? customDueDays,
    String? sport,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Plan(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      monthlyValue: monthlyValue ?? this.monthlyValue,
      periodValue: periodValue ?? this.periodValue,
      billingPeriod: billingPeriod ?? this.billingPeriod,
      defaultDueDay: defaultDueDay ?? this.defaultDueDay,
      classesPerWeek: classesPerWeek ?? this.classesPerWeek,
      studentIds: studentIds ?? this.studentIds,
      isActive: isActive ?? this.isActive,
      customValues: customValues ?? this.customValues,
      customDueDays: customDueDays ?? this.customDueDays,
      sport: sport ?? this.sport,
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
      periodValue: (data['periodValue'] as num?)?.toDouble(),
      billingPeriod: BillingPeriod.fromString(data['billingPeriod']),
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
      customDueDays: data['customDueDays'] != null
          ? Map<String, int>.from(
              (data['customDueDays'] as Map).map(
                (key, value) => MapEntry(key.toString(), (value as num).toInt()),
              ),
            )
          : {},
      sport: data['sport'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  int get studentCount => studentIds.length;

  String get formattedValue {
    final value = effectivePeriodValue;
    if (billingPeriod == BillingPeriod.monthly) {
      return 'R\$ ${value.toStringAsFixed(2)}/mês';
    }
    return 'R\$ ${value.toStringAsFixed(2)}/${billingPeriod.periodLabel}';
  }
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
    double? periodValue,
    BillingPeriod billingPeriod = BillingPeriod.monthly,
    int defaultDueDay = 10,
    int? classesPerWeek,
  }) async {
    final docRef = await _plansRef.add({
      'name': name,
      'description': description,
      'monthlyValue': monthlyValue,
      if (periodValue != null) 'periodValue': periodValue,
      'billingPeriod': billingPeriod.name,
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
      'customDueDays.$studentId': FieldValue.delete(),
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

  // ============================================
  // Set Custom Due Day for Student
  // ============================================
  Future<Plan> setCustomDueDay(String planId, String studentId, int day) async {
    await _plansRef.doc(planId).update({
      'customDueDays.$studentId': day,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return (await getById(planId))!;
  }

  // ============================================
  // Remove Custom Due Day (restore plan default)
  // ============================================
  Future<Plan> removeCustomDueDay(String planId, String studentId) async {
    await _plansRef.doc(planId).update({
      'customDueDays.$studentId': FieldValue.delete(),
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
