import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/striking_session.dart';
import 'firebase_service.dart';

/// CRUD for student-logged striking sessions (C1). Students write/read their
/// own; staff read (mirrors workoutExecutions).
class StrikingSessionService {
  final String academyId;
  late final Collections _collections;

  StrikingSessionService(this.academyId) {
    _collections = Collections.forAcademy(academyId);
  }

  CollectionReference get _ref => _collections.strikingSessions;

  Future<String> create(StrikingSession session) async {
    final doc = await _ref.add(session.toFirestore());
    return doc.id;
  }

  Future<void> delete(String id) => _ref.doc(id).delete();

  /// A student's sessions, most recent first.
  Future<List<StrikingSession>> getByStudent(String studentId,
      {int? limit}) async {
    Query q = _ref
        .where('studentId', isEqualTo: studentId)
        .orderBy('date', descending: true);
    if (limit != null) q = q.limit(limit);
    final snap = await q.get();
    return snap.docs.map(StrikingSession.fromFirestore).toList();
  }
}
