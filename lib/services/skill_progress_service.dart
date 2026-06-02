import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/skill_progress.dart';
import 'firebase_service.dart';

// Re-export so callers using the services barrel get the model too.
export '../models/skill_progress.dart';

/// Upsert + queries for per-student technique mastery
/// (`academies/{id}/skillProgress`). Staff writes; student/responsible reads.
class SkillProgressService {
  final String academyId;
  late final Collections _collections;

  SkillProgressService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _ref => _collections.skillProgress;

  /// Upserts the level (+ optional feedback) for a (student, technique) pair.
  /// Deterministic doc id keeps it idempotent.
  Future<void> setLevel({
    required String studentId,
    required String sport,
    required String gradeId,
    required String techniqueId,
    required SkillLevel level,
    String? notes,
    String ratedBy = '',
    String ratedByName = '',
  }) {
    final id = SkillProgress.docId(studentId, techniqueId);
    final sp = SkillProgress(
      id: id,
      studentId: studentId,
      sport: sport,
      gradeId: gradeId,
      techniqueId: techniqueId,
      level: level,
      notes: notes,
      ratedBy: ratedBy,
      ratedByName: ratedByName,
      updatedAt: DateTime.now(),
    );
    return _collections
        .skillProgressDoc(id)
        .set(sp.toFirestore(), SetOptions(merge: true));
  }

  /// Removes a student's progress on a technique (back to "not started").
  Future<void> clear(String studentId, String techniqueId) =>
      _collections
          .skillProgressDoc(SkillProgress.docId(studentId, techniqueId))
          .delete();

  /// All progress entries of a student (optionally filtered by sport
  /// client-side — keeps it to a single-field query, no composite index).
  Future<List<SkillProgress>> getByStudent(String studentId,
      {String? sport}) async {
    final snap = await _ref.where('studentId', isEqualTo: studentId).get();
    final all = snap.docs.map(SkillProgress.fromFirestore).toList();
    if (sport == null) return all;
    return all.where((s) => s.sport == sport).toList();
  }
}
