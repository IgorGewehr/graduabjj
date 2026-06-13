import 'package:cloud_firestore/cloud_firestore.dart';

import 'workout_plan.dart' show WorkoutAudience;

/// One week of a simple mesocycle (E1): a short prescription + focus. No
/// per-exercise data — the prescription is free text (e.g. "4x10 leve").
class MesoWeek {
  final int index; // 1-based
  final String focus; // e.g. "Adaptação", "Força", "Deload"
  final String prescription; // e.g. "4x10 @ leve"
  final bool deload;

  const MesoWeek({
    required this.index,
    this.focus = '',
    this.prescription = '',
    this.deload = false,
  });

  factory MesoWeek.fromMap(Map<String, dynamic> m) => MesoWeek(
        index: (m['index'] as num?)?.toInt() ?? 1,
        focus: (m['focus'] ?? '').toString(),
        prescription: (m['prescription'] ?? '').toString(),
        deload: m['deload'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'index': index,
        'focus': focus,
        'prescription': prescription,
        'deload': deload,
      };

  MesoWeek copyWith({String? focus, String? prescription, bool? deload}) =>
      MesoWeek(
        index: index,
        focus: focus ?? this.focus,
        prescription: prescription ?? this.prescription,
        deload: deload ?? this.deload,
      );
}

/// A simple multi-week training cycle (E1). Targeting mirrors WorkoutPlan
/// (academy / sport / specific students). When [startDate] is set the portal
/// highlights the current week. Lives at `academies/{id}/mesocycles/{autoId}`.
class Mesocycle {
  final String id;
  final String name;
  final String? description;
  final String? sport; // SportId.value or null (any)
  final WorkoutAudience audience;
  final List<String> assignedStudentIds;
  final DateTime? startDate;
  final List<MesoWeek> weeks;
  final bool active;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Mesocycle({
    required this.id,
    required this.name,
    this.description,
    this.sport,
    this.audience = WorkoutAudience.academy,
    this.assignedStudentIds = const [],
    this.startDate,
    this.weeks = const [],
    this.active = true,
    this.createdBy = '',
    this.createdAt,
    this.updatedAt,
  });

  int get totalWeeks => weeks.length;

  factory Mesocycle.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final weeks = (data['weeks'] as List?)
            ?.map((e) => MesoWeek.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const <MesoWeek>[];
    weeks.sort((a, b) => a.index.compareTo(b.index));
    return Mesocycle(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      description: data['description'] as String?,
      sport: data['sport'] as String?,
      audience: WorkoutAudience.fromString(data['audience'] as String?),
      assignedStudentIds:
          List<String>.from(data['assignedStudentIds'] ?? const []),
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      weeks: weeks,
      active: data['active'] ?? true,
      createdBy: (data['createdBy'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'description': description,
        'sport': sport,
        'audience': audience.name,
        'assignedStudentIds': assignedStudentIds,
        'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
        'weeks': weeks.map((w) => w.toMap()).toList(),
        'active': active,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Mesocycle copyWith({
    String? name,
    String? description,
    String? sport,
    WorkoutAudience? audience,
    List<String>? assignedStudentIds,
    DateTime? startDate,
    List<MesoWeek>? weeks,
    bool? active,
  }) =>
      Mesocycle(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        sport: sport ?? this.sport,
        audience: audience ?? this.audience,
        assignedStudentIds: assignedStudentIds ?? this.assignedStudentIds,
        startDate: startDate ?? this.startDate,
        weeks: weeks ?? this.weeks,
        active: active ?? this.active,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
