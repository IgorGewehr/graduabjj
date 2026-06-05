import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/strength_goal.dart';
import 'firebase_service.dart';

/// Per-student per-exercise load goals (E2). Students upsert/read their own;
/// staff read. Deterministic doc id makes setting a goal idempotent.
class StrengthGoalService {
  final String academyId;
  late final Collections _collections;

  StrengthGoalService(this.academyId) {
    _collections = Collections.forAcademy(academyId);
  }

  CollectionReference get _ref => _collections.strengthGoals;

  Future<void> setGoal({
    required String studentId,
    required String exerciseName,
    required double targetLoadKg,
  }) async {
    final id = StrengthGoal.docId(studentId, exerciseName);
    await _ref.doc(id).set(
          StrengthGoal(
            id: id,
            studentId: studentId,
            exerciseName: exerciseName,
            targetLoadKg: targetLoadKg,
          ).toFirestore(),
          SetOptions(merge: true),
        );
  }

  Future<void> clearGoal(String studentId, String exerciseName) =>
      _ref.doc(StrengthGoal.docId(studentId, exerciseName)).delete();

  Future<StrengthGoal?> getOne(String studentId, String exerciseName) async {
    final doc =
        await _ref.doc(StrengthGoal.docId(studentId, exerciseName)).get();
    return doc.exists ? StrengthGoal.fromFirestore(doc) : null;
  }

  Future<List<StrengthGoal>> getForStudent(String studentId) async {
    final snap = await _ref.where('studentId', isEqualTo: studentId).get();
    return snap.docs.map(StrengthGoal.fromFirestore).toList();
  }
}
