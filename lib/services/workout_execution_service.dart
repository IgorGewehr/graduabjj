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

  /// Upsert idempotente do registro de execução de um exercício no dia.
  /// Usa o id determinístico `WorkoutExecution.docId(...)`, então re-registrar
  /// o mesmo exercício no mesmo dia ATUALIZA em vez de duplicar. Retorna o id.
  Future<String> upsert(WorkoutExecution e) async {
    final id = WorkoutExecution.docId(
        e.studentId, e.planId, e.dayIndex, e.exerciseIndex, e.date);
    // `date`/`updatedAt` (no toFirestore) são o que importa; sem createdAt
    // para o merge não reescrever a cada edição.
    await _collections
        .workoutExecution(id)
        .set(e.toFirestore(), SetOptions(merge: true));
    return id;
  }

  Future<void> delete(String id) =>
      _collections.workoutExecution(id).delete();

  /// Execuções de um plano num dia (mapa "dayIndex:exerciseIndex" → execução).
  /// Range de documentId pelo prefixo do dia (sentinela 0xF8FF como limite
  /// superior) — sem índice composto.
  Future<Map<String, WorkoutExecution>> getByPlanForDay(
    String studentId,
    String planId,
    DateTime date,
  ) async {
    final prefix = WorkoutExecution.dayPrefix(studentId, planId, date);
    final upper = prefix + String.fromCharCode(0xf8ff);
    final snap = await _ref
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
        .where(FieldPath.documentId, isLessThan: upper)
        .get();
    final out = <String, WorkoutExecution>{};
    for (final d in snap.docs) {
      final e = WorkoutExecution.fromFirestore(d);
      out['${e.dayIndex}:${e.exerciseIndex}'] = e;
    }
    return out;
  }

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
