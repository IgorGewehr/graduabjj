import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/syllabus_technique.dart';
import 'firebase_service.dart';

// Re-export so callers using the services barrel get the model too.
export '../models/syllabus_technique.dart';

/// CRUD + queries for an academy's curriculum
/// (`academies/{id}/syllabus`). Staff writes; any member reads.
class SyllabusService {
  final String academyId;
  late final Collections _collections;

  SyllabusService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _ref => _collections.syllabus;

  /// Creates a technique, stamping `createdAt`. Returns the new doc id.
  Future<String> create(SyllabusTechnique t) async {
    final data = t.toFirestore()..['createdAt'] = FieldValue.serverTimestamp();
    final doc = await _ref.add(data);
    return doc.id;
  }

  Future<void> update(String id, SyllabusTechnique t) =>
      _collections.syllabusTechnique(id).update(t.toFirestore());

  Future<void> delete(String id) =>
      _collections.syllabusTechnique(id).delete();

  /// Active techniques of a sport, ordered. Callers group by `gradeId`.
  /// Needs the composite index (sport ASC, order ASC).
  Future<List<SyllabusTechnique>> getBySport(String sport) async {
    final snap =
        await _ref.where('sport', isEqualTo: sport).orderBy('order').get();
    return snap.docs
        .map(SyllabusTechnique.fromFirestore)
        .where((t) => t.active)
        .toList();
  }
}
