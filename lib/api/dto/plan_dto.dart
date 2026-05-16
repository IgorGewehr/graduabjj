// DTOs do contexto Plan, alinhados 1:1 com api/openapi/financial.yaml (Plan*).
//
// Plans vivem dentro do bounded-context "financial" no backend (lógica
// monetária + due_day), mas o FE chama esses endpoints de telas de academia
// (Configurações > Planos). Por isso o repo correspondente é plan_repo.dart,
// não financial_repo.dart.

/// Quantia decimal serializada como string para preservar precisão
/// monetária. Validada server-side pelo pattern `^-?\d+(\.\d{1,2})?$`.
typedef DecimalString = String;

class ApiPlan {
  const ApiPlan({
    required this.id,
    required this.academyId,
    required this.name,
    required this.monthlyValue,
    required this.defaultDueDay,
    required this.classesPerWeek,
    required this.isActive,
    this.description,
    this.customValues = const {},
    this.customDueDays = const {},
    this.studentIds = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String academyId;
  final String name;
  final String? description;
  final DecimalString monthlyValue;
  final int defaultDueDay;
  final int classesPerWeek;
  final Map<String, DecimalString> customValues;
  final Map<String, int> customDueDays;
  final bool isActive;
  final List<String> studentIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 0 classes_per_week é a convenção do backend para "ilimitado".
  bool get isUnlimited => classesPerWeek == 0;

  factory ApiPlan.fromJson(Map<String, dynamic> j) => ApiPlan(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        monthlyValue: j['monthly_value'] as String,
        defaultDueDay: (j['default_due_day'] as num).toInt(),
        classesPerWeek: (j['classes_per_week'] as num?)?.toInt() ?? 0,
        customValues: ((j['custom_values'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v as String)),
        customDueDays: ((j['custom_due_days'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).toInt())),
        isActive: j['is_active'] as bool? ?? true,
        studentIds:
            (j['student_ids'] as List?)?.whereType<String>().toList() ??
                const [],
        createdAt: _parseDate(j['created_at']),
        updatedAt: _parseDate(j['updated_at']),
      );
}

class CreatePlanRequest {
  const CreatePlanRequest({
    required this.name,
    required this.monthlyValue,
    required this.defaultDueDay,
    this.description,
    this.classesPerWeek,
    this.customValues,
    this.customDueDays,
    this.isActive,
  });

  final String name;
  final DecimalString monthlyValue;
  final int defaultDueDay;
  final String? description;
  final int? classesPerWeek;
  final Map<String, DecimalString>? customValues;
  final Map<String, int>? customDueDays;
  final bool? isActive;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'name': name,
      'monthly_value': monthlyValue,
      'default_due_day': defaultDueDay,
    };
    if (description != null) m['description'] = description;
    if (classesPerWeek != null) m['classes_per_week'] = classesPerWeek;
    if (customValues != null) m['custom_values'] = customValues;
    if (customDueDays != null) m['custom_due_days'] = customDueDays;
    if (isActive != null) m['is_active'] = isActive;
    return m;
  }
}

class UpdatePlanRequest {
  const UpdatePlanRequest({
    this.name,
    this.monthlyValue,
    this.defaultDueDay,
    this.description,
    this.classesPerWeek,
    this.customValues,
    this.customDueDays,
    this.isActive,
  });

  final String? name;
  final DecimalString? monthlyValue;
  final int? defaultDueDay;
  final String? description;
  final int? classesPerWeek;
  final Map<String, DecimalString>? customValues;
  final Map<String, int>? customDueDays;
  final bool? isActive;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (name != null) m['name'] = name;
    if (monthlyValue != null) m['monthly_value'] = monthlyValue;
    if (defaultDueDay != null) m['default_due_day'] = defaultDueDay;
    if (description != null) m['description'] = description;
    if (classesPerWeek != null) m['classes_per_week'] = classesPerWeek;
    if (customValues != null) m['custom_values'] = customValues;
    if (customDueDays != null) m['custom_due_days'] = customDueDays;
    if (isActive != null) m['is_active'] = isActive;
    return m;
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
