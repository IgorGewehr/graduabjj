import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/workout_execution.dart';
import 'firebase_service.dart';

// Re-export so callers using the services barrel get the model too.
export '../models/workout_execution.dart';

/// Registro de execução de treino (A6). `academies/{id}/workoutExecutions`.
/// O aluno escreve/le os seus; staff lê.
class WorkoutExecutionService {
  final String academyId;
  late final Collections _collections;

  WorkoutExecutionService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _ref => _collections.workoutExecutions;

  /// Cria/atualiza o registro. Retorna o id (novo no create).
  Future<String> create(WorkoutExecution e) async {
    final data = e.toFirestore()..['createdAt'] = FieldValue.serverTimestamp();
    final doc = await _ref.add(data);
    return doc.id;
  }

  Future<void> update(String id, WorkoutExecution e) =>
      _collections.workoutExecution(id).update(e.toFirestore());

  Future<void> delete(String id) =>
      _collections.workoutExecution(id).delete();

  /// Histórico de um exercício (por nome — consistente p/ livre e catálogo),
  /// mais recente primeiro. Índice composto (studentId, exerciseName, date DESC).
  Future<List<WorkoutExecution>> getHistoryForExercise(
    String studentId,
    String exerciseName, {
    int? limit,
  }) async {
    Query q = _ref
        .where('studentId', isEqualTo: studentId)
        .where('exerciseName', isEqualTo: exerciseName)
        .orderBy('date', descending: true);
    if (limit != null) q = q.limit(limit);
    final snap = await q.get();
    return snap.docs.map(WorkoutExecution.fromFirestore).toList();
  }

  /// PR do exercício: maior carga e maior 1RM estimado em todo o histórico.
  Future<({double bestLoad, double best1RM})> getPR(
    String studentId,
    String exerciseName,
  ) async {
    final hist = await getHistoryForExercise(studentId, exerciseName);
    double bl = 0, br = 0;
    for (final e in hist) {
      if (e.bestLoadKg > bl) bl = e.bestLoadKg;
      if (e.best1RMKg > br) br = e.best1RMKg;
    }
    return (bestLoad: bl, best1RM: br);
  }
}
