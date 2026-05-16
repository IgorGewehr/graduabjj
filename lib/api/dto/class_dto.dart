// DTOs do contexto Class, alinhados 1:1 com api/openapi/attendance.yaml.
//
// Compartilha `ApiBelt` com student_dto.dart (importado por baixo). Se essa
// reutilização cruzada crescer, vale promover ApiBelt para um shared_dto.

import 'student_dto.dart' show ApiBelt, ApiBeltX;

enum ApiClassCategory { kids, adult, mixed }

extension ApiClassCategoryX on ApiClassCategory {
  String get wire => name;
  static ApiClassCategory fromWire(String? value) {
    for (final c in ApiClassCategory.values) {
      if (c.name == value) return c;
    }
    return ApiClassCategory.mixed;
  }
}

/// Entrada de horário de uma turma. `day_of_week`: 0=domingo, 6=sábado.
/// `start_time`/`end_time` em "HH:MM" (24h, hora local da academia).
class ApiScheduleEntry {
  const ApiScheduleEntry({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  final int dayOfWeek;
  final String startTime;
  final String endTime;

  factory ApiScheduleEntry.fromJson(Map<String, dynamic> j) => ApiScheduleEntry(
        dayOfWeek: (j['day_of_week'] as num).toInt(),
        startTime: j['start_time'] as String,
        endTime: j['end_time'] as String,
      );

  Map<String, dynamic> toJson() => {
        'day_of_week': dayOfWeek,
        'start_time': startTime,
        'end_time': endTime,
      };
}

class ApiClass {
  const ApiClass({
    required this.id,
    required this.academyId,
    required this.name,
    required this.category,
    required this.sport,
    required this.maxStudents,
    required this.weight,
    required this.isActive,
    required this.schedule,
    required this.studentIds,
    this.description,
    this.instructorUid,
    this.instructorName,
    this.minBelt,
    this.maxBelt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String academyId;
  final String name;
  final String? description;
  final String? instructorUid;
  final String? instructorName;
  final List<ApiScheduleEntry> schedule;
  final ApiClassCategory category;
  final String sport;
  final ApiBelt? minBelt;
  final ApiBelt? maxBelt;

  /// 0 = ilimitado.
  final int maxStudents;

  /// Multiplicador de atendimento (decimal-string). Default "1.000".
  final String weight;
  final bool isActive;
  final List<String> studentIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isUnlimited => maxStudents == 0;

  factory ApiClass.fromJson(Map<String, dynamic> j) => ApiClass(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        instructorUid: j['instructor_uid'] as String?,
        instructorName: j['instructor_name'] as String?,
        schedule: (j['schedule'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiScheduleEntry.fromJson)
            .toList(),
        category: ApiClassCategoryX.fromWire(j['category'] as String?),
        sport: j['sport'] as String? ?? 'bjj',
        minBelt: j['min_belt'] == null
            ? null
            : ApiBeltX.fromWire(j['min_belt'] as String?),
        maxBelt: j['max_belt'] == null
            ? null
            : ApiBeltX.fromWire(j['max_belt'] as String?),
        maxStudents: (j['max_students'] as num?)?.toInt() ?? 0,
        weight: j['weight'] as String? ?? '1.000',
        isActive: j['is_active'] as bool? ?? true,
        studentIds: (j['student_ids'] as List?)?.whereType<String>().toList() ??
            const [],
        createdAt: _parseDate(j['created_at']),
        updatedAt: _parseDate(j['updated_at']),
      );
}

class ClassesPage {
  const ClassesPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiClass> items;
  final String? nextCursor;
  final bool hasMore;

  factory ClassesPage.fromJson(Map<String, dynamic> j) => ClassesPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiClass.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class CreateClassRequest {
  const CreateClassRequest({
    required this.name,
    required this.category,
    required this.schedule,
    this.description,
    this.instructorUid,
    this.instructorName,
    this.sport,
    this.minBelt,
    this.maxBelt,
    this.maxStudents,
    this.weight,
  });

  final String name;
  final ApiClassCategory category;
  final List<ApiScheduleEntry> schedule;
  final String? description;
  final String? instructorUid;
  final String? instructorName;
  final String? sport;
  final ApiBelt? minBelt;
  final ApiBelt? maxBelt;
  final int? maxStudents;
  final String? weight;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'name': name,
      'category': category.wire,
      'schedule': schedule.map((e) => e.toJson()).toList(),
    };
    if (description != null) m['description'] = description;
    if (instructorUid != null) m['instructor_uid'] = instructorUid;
    if (instructorName != null) m['instructor_name'] = instructorName;
    if (sport != null) m['sport'] = sport;
    if (minBelt != null) m['min_belt'] = minBelt!.wire;
    if (maxBelt != null) m['max_belt'] = maxBelt!.wire;
    if (maxStudents != null) m['max_students'] = maxStudents;
    if (weight != null) m['weight'] = weight;
    return m;
  }
}

class UpdateClassRequest {
  const UpdateClassRequest({
    this.name,
    this.description,
    this.instructorUid,
    this.instructorName,
    this.schedule,
    this.category,
    this.sport,
    this.minBelt,
    this.maxBelt,
    this.maxStudents,
    this.weight,
    this.isActive,
  });

  final String? name;
  final String? description;
  final String? instructorUid;
  final String? instructorName;
  final List<ApiScheduleEntry>? schedule;
  final ApiClassCategory? category;
  final String? sport;
  final ApiBelt? minBelt;
  final ApiBelt? maxBelt;
  final int? maxStudents;
  final String? weight;
  final bool? isActive;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (name != null) m['name'] = name;
    if (description != null) m['description'] = description;
    if (instructorUid != null) m['instructor_uid'] = instructorUid;
    if (instructorName != null) m['instructor_name'] = instructorName;
    if (schedule != null) {
      m['schedule'] = schedule!.map((e) => e.toJson()).toList();
    }
    if (category != null) m['category'] = category!.wire;
    if (sport != null) m['sport'] = sport;
    if (minBelt != null) m['min_belt'] = minBelt!.wire;
    if (maxBelt != null) m['max_belt'] = maxBelt!.wire;
    if (maxStudents != null) m['max_students'] = maxStudents;
    if (weight != null) m['weight'] = weight;
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
