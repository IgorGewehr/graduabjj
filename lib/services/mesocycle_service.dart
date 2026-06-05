import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/sports.dart';
import '../models/mesocycle.dart';
import '../models/workout_plan.dart' show WorkoutAudience;
import 'firebase_service.dart';

/// CRUD + targeted reads for simple mesocycles (E1). Targeting mirrors
/// WorkoutPlanService (academy / sport / specific students).
class MesocycleService {
  final String academyId;
  late final Collections _collections;

  MesocycleService(this.academyId) {
    _collections = Collections.forAcademy(academyId);
  }

  CollectionReference get _ref => _collections.mesocycles;

  Future<List<Mesocycle>> listAll() async {
    final snap = await _ref.get();
    final list = snap.docs.map(Mesocycle.fromFirestore).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<Mesocycle?> getById(String id) async {
    final doc = await _ref.doc(id).get();
    return doc.exists ? Mesocycle.fromFirestore(doc) : null;
  }

  Future<String> create(Mesocycle m) async {
    final doc = await _ref.add(m.toFirestore());
    return doc.id;
  }

  Future<void> update(String id, Mesocycle m) =>
      _ref.doc(id).update(m.toFirestore());

  Future<void> delete(String id) => _ref.doc(id).delete();

  /// Mesocycles visible to a student: academy-wide + sport-library (matching one
  /// of their sports) + personally assigned. Mirrors the firestore.rules read
  /// branches so the two queries only return readable docs.
  Future<List<Mesocycle>> getForStudent({
    required String studentId,
    required List<SportId> sports,
  }) async {
    // No `active` filter in the queries — combining whereIn/array-contains with
    // another equality needs a composite index. We filter active in memory
    // (mirrors WorkoutPlanService.getForStudent, which is index-free).
    final results = await Future.wait([
      _ref.where('audience', whereIn: [
        WorkoutAudience.academy.name,
        WorkoutAudience.sport.name,
      ]).get(),
      _ref.where('assignedStudentIds', arrayContains: studentId).get(),
    ]);

    final byId = <String, Mesocycle>{};
    for (final snap in results) {
      for (final doc in snap.docs) {
        byId[doc.id] = Mesocycle.fromFirestore(doc);
      }
    }

    final sportValues = sports.map((s) => s.value).toSet();
    final visible = byId.values.where((m) {
      if (!m.active) return false;
      if (m.audience == WorkoutAudience.sport) {
        return m.sport == null || sportValues.contains(m.sport);
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return visible;
  }
}
