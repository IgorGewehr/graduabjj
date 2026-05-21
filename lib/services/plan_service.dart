import '../api/dto/plan_dto.dart' as api;
import '../api/plan_repo.dart';

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
  final Map<String, int> customDueDays;
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
    this.customDueDays = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns the value a specific student pays in this plan.
  /// If the student has a custom value, returns it; otherwise returns monthlyValue.
  double getStudentValue(String studentId) =>
      customValues[studentId] ?? monthlyValue;

  int getStudentDueDay(String studentId) =>
      customDueDays[studentId] ?? defaultDueDay;

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
    Map<String, int>? customDueDays,
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
      customDueDays: customDueDays ?? this.customDueDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Constrói a partir do DTO Tatami.
  ///
  /// Conversões:
  /// - `monthlyValue`: decimal-string → double. Mensagem do BE garante
  ///   formato `^-?\d+(\.\d{1,2})?$`; `tryParse` fallback para 0.
  /// - `classesPerWeek`: API usa 0 = ilimitado; legacy é nullable (null =
  ///   sem restrição) — mapeamos 0 → null pra preservar a semântica
  ///   atual dos call-sites.
  /// - `customValues`: `Map<String,String>` → `Map<String,double>` via parse.
  factory Plan.fromApi(api.ApiPlan p) {
    final cw = p.classesPerWeek == 0 ? null : p.classesPerWeek;
    return Plan(
      id: p.id,
      name: p.name,
      description: p.description,
      monthlyValue: double.tryParse(p.monthlyValue) ?? 0.0,
      defaultDueDay: p.defaultDueDay,
      classesPerWeek: cw,
      studentIds: p.studentIds,
      isActive: p.isActive,
      customValues: p.customValues
          .map((k, v) => MapEntry(k, double.tryParse(v) ?? 0.0)),
      customDueDays: p.customDueDays,
      createdAt: p.createdAt ?? DateTime.now(),
      updatedAt: p.updatedAt ?? DateTime.now(),
    );
  }

  // Computed properties
  int get studentCount => studentIds.length;
  String get formattedValue => 'R\$ ${monthlyValue.toStringAsFixed(2)}';
}

/// Plan Service - Multi-tenant plan management via Tatami HTTP API.
///
/// Todos os métodos delegam para [PlanRemoteRepo]; não há mais acesso
/// direto ao Firestore neste serviço.
class PlanService {
  final String academyId;
  final PlanRemoteRepo _repo;

  PlanService(this.academyId, {required PlanRemoteRepo repo}) : _repo = repo;

  // ============================================
  // List All Plans
  // ============================================
  Future<List<Plan>> list() async {
    final dtos = await _repo.list(academyId);
    var plans = dtos.map(Plan.fromApi).toList();
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
    try {
      final dto = await _repo.getById(academyId, id);
      return Plan.fromApi(dto);
    } catch (_) {
      return null;
    }
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
    final dto = await _repo.create(
      academyId,
      api.CreatePlanRequest(
        name: name,
        description: description,
        monthlyValue: monthlyValue.toStringAsFixed(2),
        defaultDueDay: defaultDueDay,
        classesPerWeek: classesPerWeek,
        isActive: true,
      ),
    );
    return Plan.fromApi(dto);
  }

  // ============================================
  // Update Plan
  // ============================================
  Future<Plan> update(String id, Map<String, dynamic> data) async {
    // Translate legacy Map keys to UpdatePlanRequest fields.
    final dto = await _repo.update(
      academyId,
      id,
      api.UpdatePlanRequest(
        name: data['name'] as String?,
        description: data['description'] as String?,
        monthlyValue: data['monthlyValue'] != null
            ? (data['monthlyValue'] as num).toDouble().toStringAsFixed(2)
            : null,
        defaultDueDay: data['defaultDueDay'] as int?,
        classesPerWeek: data['classesPerWeek'] as int?,
        isActive: data['isActive'] as bool?,
      ),
    );
    return Plan.fromApi(dto);
  }

  // ============================================
  // Delete Plan
  // ============================================
  Future<void> delete(String id) async {
    await _repo.delete(academyId, id);
  }

  // ============================================
  // Add Student to Plan
  // ============================================
  Future<Plan> addStudent(String planId, String studentId) async {
    await _repo.assignStudent(academyId, planId, studentId);
    return (await getById(planId))!;
  }

  // ============================================
  // Remove Student from Plan
  // ============================================
  Future<Plan> removeStudent(String planId, String studentId) async {
    await _repo.unassignStudent(academyId, planId, studentId);
    return (await getById(planId))!;
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
  Future<Plan> setCustomValue(
      String planId, String studentId, double value) async {
    await _repo.setStudentCustomValue(
      academyId,
      planId,
      studentId,
      customValue: value.toStringAsFixed(2),
    );
    return (await getById(planId))!;
  }

  // ============================================
  // Remove Custom Value (restore plan default)
  //
  // Envia custom_value: null explicitamente — o backend interpreta
  // campos null como "remover override".
  // ============================================
  Future<Plan> removeCustomValue(String planId, String studentId) async {
    await _repo.clearStudentCustomValues(academyId, planId, studentId);
    return (await getById(planId))!;
  }

  // ============================================
  // Set Custom Due Day for Student
  // ============================================
  Future<Plan> setCustomDueDay(
      String planId, String studentId, int day) async {
    await _repo.setStudentCustomValue(
      academyId,
      planId,
      studentId,
      customDueDay: day,
    );
    return (await getById(planId))!;
  }

  // ============================================
  // Remove Custom Due Day (restore plan default)
  // ============================================
  Future<Plan> removeCustomDueDay(String planId, String studentId) async {
    await _repo.clearStudentCustomValues(academyId, planId, studentId);
    return (await getById(planId))!;
  }
}

// ============================================
// Factory Function
// ============================================
PlanService createPlanService(String academyId, {required PlanRemoteRepo repo}) {
  return PlanService(academyId, repo: repo);
}
