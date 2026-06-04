import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/strength_math.dart';

/// Uma série executada: reps × carga (kg), com RPE opcional (1–10).
class SetEntry {
  final int reps;
  final double load;
  final int? rpe;

  const SetEntry({required this.reps, required this.load, this.rpe});

  factory SetEntry.fromMap(Map<String, dynamic> m) => SetEntry(
        reps: (m['reps'] as num?)?.toInt() ?? 0,
        load: (m['load'] as num?)?.toDouble() ?? 0,
        rpe: (m['rpe'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
        'reps': reps,
        'load': load,
        if (rpe != null) 'rpe': rpe,
      };

  SetTuple get tuple => (reps: reps, load: load);
}

/// Registro de execução de um exercício numa sessão (A6).
/// Lives at `academies/{id}/workoutExecutions/{id}`.
class WorkoutExecution {
  final String id;
  final String studentId;
  final String planId;
  final int dayIndex;
  final int exerciseIndex;
  final String? exerciseId; // do catálogo, se houver
  final String exerciseName; // snapshot
  final DateTime date;
  final List<SetEntry> sets;
  final String? notes;
  final DateTime createdAt;

  const WorkoutExecution({
    required this.id,
    required this.studentId,
    required this.planId,
    required this.dayIndex,
    required this.exerciseIndex,
    this.exerciseId,
    required this.exerciseName,
    required this.date,
    this.sets = const [],
    this.notes,
    required this.createdAt,
  });

  factory WorkoutExecution.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WorkoutExecution(
      id: doc.id,
      studentId: (data['studentId'] ?? '').toString(),
      planId: (data['planId'] ?? '').toString(),
      dayIndex: (data['dayIndex'] as num?)?.toInt() ?? 0,
      exerciseIndex: (data['exerciseIndex'] as num?)?.toInt() ?? 0,
      exerciseId: data['exerciseId'] as String?,
      exerciseName: (data['exerciseName'] ?? '').toString(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      sets: ((data['sets'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SetEntry.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      notes: data['notes'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'studentId': studentId,
        'planId': planId,
        'dayIndex': dayIndex,
        'exerciseIndex': exerciseIndex,
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'date': Timestamp.fromDate(date),
        'sets': sets.map((s) => s.toMap()).toList(),
        'notes': notes,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  // Derivados (via strength_math).
  List<SetTuple> get _tuples => sets.map((s) => s.tuple).toList();
  double get bestLoadKg => bestLoad(_tuples);
  double get best1RMKg => best1RM(_tuples);
  double get volume => sessionVolume(_tuples);
}
