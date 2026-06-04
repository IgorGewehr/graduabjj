import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/sports.dart';

/// Who a workout plan is delivered to.
/// - [academy]: every member of the academy.
/// - [sport]: every student who practices [WorkoutPlan.sport] (library content).
/// - [students]: only the students listed in [WorkoutPlan.assignedStudentIds]
///   (personal plans — private to those students).
enum WorkoutAudience {
  academy,
  sport,
  students;

  String get value => name;

  static WorkoutAudience fromString(String? value) {
    return WorkoutAudience.values.firstWhere(
      (a) => a.name == value,
      orElse: () => WorkoutAudience.academy,
    );
  }
}

/// One exercise line. Numeric-ish fields are stored as free text so the
/// instructor can write "8-12", "até a falha", "60kg cada lado", etc.
class WorkoutExercise {
  final String name;
  final String? sets;
  final String? reps;
  final String? load;
  final String? rest;
  final String? notes;
  /// Vínculo opcional com o catálogo (A5). Null = exercício de texto livre
  /// (legado). Quando presente, habilita vídeo de demonstração + agregação de PR.
  final String? exerciseId;

  const WorkoutExercise({
    required this.name,
    this.sets,
    this.reps,
    this.load,
    this.rest,
    this.notes,
    this.exerciseId,
  });

  factory WorkoutExercise.fromMap(Map<String, dynamic> m) => WorkoutExercise(
        name: (m['name'] ?? '').toString(),
        sets: m['sets'] as String?,
        reps: m['reps'] as String?,
        load: m['load'] as String?,
        rest: m['rest'] as String?,
        notes: m['notes'] as String?,
        exerciseId: m['exerciseId'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        if (sets != null && sets!.isNotEmpty) 'sets': sets,
        if (reps != null && reps!.isNotEmpty) 'reps': reps,
        if (load != null && load!.isNotEmpty) 'load': load,
        if (rest != null && rest!.isNotEmpty) 'rest': rest,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (exerciseId != null && exerciseId!.isNotEmpty)
          'exerciseId': exerciseId,
      };

  WorkoutExercise copyWith({
    String? name,
    String? sets,
    String? reps,
    String? load,
    String? rest,
    String? notes,
    String? exerciseId,
  }) =>
      WorkoutExercise(
        name: name ?? this.name,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        load: load ?? this.load,
        rest: rest ?? this.rest,
        notes: notes ?? this.notes,
        exerciseId: exerciseId ?? this.exerciseId,
      );
}

/// A day/block within a plan, e.g. "Treino A — Peito e Tríceps".
class WorkoutDay {
  final String name;
  final List<WorkoutExercise> exercises;

  const WorkoutDay({required this.name, this.exercises = const []});

  factory WorkoutDay.fromMap(Map<String, dynamic> m) => WorkoutDay(
        name: (m['name'] ?? '').toString(),
        exercises: ((m['exercises'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => WorkoutExercise.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'exercises': exercises.map((e) => e.toMap()).toList(),
      };

  WorkoutDay copyWith({String? name, List<WorkoutExercise>? exercises}) =>
      WorkoutDay(name: name ?? this.name, exercises: exercises ?? this.exercises);
}

/// A structured training plan. Lives at
/// `academies/{academyId}/workoutPlans/{planId}`. Works for any modality;
/// musculação is the primary use case.
class WorkoutPlan {
  final String id;
  final String title;
  final String? description;

  /// SportId value ('musculacao', 'bjj', ...) or null for "any modality".
  final String? sport;

  final WorkoutAudience audience;

  /// Students this plan is assigned to when [audience] is [WorkoutAudience.students].
  /// Always serialized (empty for other audiences) so security rules can safely
  /// evaluate `studentId in assignedStudentIds`.
  final List<String> assignedStudentIds;

  final List<WorkoutDay> days;

  /// File-based plan: when [fileUrl] is set the plan is an uploaded PDF/image
  /// instead of a structured day/exercise list. [fileStoragePath] lets the file
  /// be deleted; [fileKind] is 'pdf' or 'image'.
  final String? fileUrl;
  final String? fileStoragePath;
  final String? fileKind;

  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WorkoutPlan({
    required this.id,
    required this.title,
    this.description,
    this.sport,
    this.audience = WorkoutAudience.academy,
    this.assignedStudentIds = const [],
    this.days = const [],
    this.fileUrl,
    this.fileStoragePath,
    this.fileKind,
    this.createdBy = '',
    this.createdByName = '',
    this.createdAt,
    this.updatedAt,
  });

  SportId? get sportId => sport == null ? null : SportId.fromString(sport!);

  /// Whether this plan is an uploaded file rather than a structured plan.
  bool get isFile => fileUrl != null && fileUrl!.isNotEmpty;

  int get exerciseCount =>
      days.fold(0, (sum, d) => sum + d.exercises.length);

  factory WorkoutPlan.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WorkoutPlan(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: data['description'] as String?,
      sport: data['sport'] as String?,
      audience: WorkoutAudience.fromString(data['audience'] as String?),
      assignedStudentIds: List<String>.from(data['assignedStudentIds'] ?? const []),
      days: ((data['days'] as List?) ?? const [])
          .whereType<Map>()
          .map((d) => WorkoutDay.fromMap(Map<String, dynamic>.from(d)))
          .toList(),
      fileUrl: data['fileUrl'] as String?,
      fileStoragePath: data['fileStoragePath'] as String?,
      fileKind: data['fileKind'] as String?,
      createdBy: (data['createdBy'] ?? '').toString(),
      createdByName: (data['createdByName'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'description': description,
        'sport': sport,
        'audience': audience.value,
        // Always present (empty unless audience == students) so rules can
        // evaluate `in assignedStudentIds` without missing-field errors.
        'assignedStudentIds':
            audience == WorkoutAudience.students ? assignedStudentIds : const [],
        'days': days.map((d) => d.toMap()).toList(),
        'fileUrl': fileUrl,
        'fileStoragePath': fileStoragePath,
        'fileKind': fileKind,
        'createdBy': createdBy,
        'createdByName': createdByName,
      };

  WorkoutPlan copyWith({
    String? title,
    String? description,
    String? sport,
    bool clearSport = false,
    WorkoutAudience? audience,
    List<String>? assignedStudentIds,
    List<WorkoutDay>? days,
  }) =>
      WorkoutPlan(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        sport: clearSport ? null : (sport ?? this.sport),
        audience: audience ?? this.audience,
        assignedStudentIds: assignedStudentIds ?? this.assignedStudentIds,
        days: days ?? this.days,
        fileUrl: fileUrl,
        fileStoragePath: fileStoragePath,
        fileKind: fileKind,
        createdBy: createdBy,
        createdByName: createdByName,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
