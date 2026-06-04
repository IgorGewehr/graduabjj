import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/exercise.dart';
import 'firebase_service.dart';

// Re-export so callers using the services barrel get the model too.
export '../models/exercise.dart';

/// CRUD + queries do catálogo de exercícios da academia (A5).
/// `academies/{id}/exercises`. Staff escreve; qualquer membro lê.
class ExerciseService {
  final String academyId;
  late final Collections _collections;

  ExerciseService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _ref => _collections.exercises;

  Future<String> create(Exercise e) async {
    final data = e.toFirestore()..['createdAt'] = FieldValue.serverTimestamp();
    final doc = await _ref.add(data);
    return doc.id;
  }

  Future<void> update(String id, Exercise e) =>
      _collections.exercise(id).update(e.toFirestore());

  Future<void> delete(String id) => _collections.exercise(id).delete();

  /// Todos os exercícios ativos, ordenados por nome. Filtro por grupo muscular
  /// é client-side (catálogo é pequeno → uma query, sem índice composto).
  Future<List<Exercise>> listAll() async {
    final snap = await _ref.orderBy('name').get();
    return snap.docs
        .map(Exercise.fromFirestore)
        .where((e) => e.active)
        .toList();
  }

  Future<Exercise?> getById(String id) async {
    final doc = await _collections.exercise(id).get();
    return doc.exists ? Exercise.fromFirestore(doc) : null;
  }

  /// Bulk-create atômico (usado pelo seed).
  Future<void> createMany(List<Exercise> items) async {
    final batch = FirebaseService.firestore.batch();
    for (final e in items) {
      batch.set(_ref.doc(),
          e.toFirestore()..['createdAt'] = FieldValue.serverTimestamp());
    }
    await batch.commit();
  }
}
