import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/fight_record.dart';
import 'firebase_service.dart';

/// CRUD for the official fight record/cartel (C3). Staff write; the student and
/// their responsible read (enforced by firestore.rules).
class FightRecordService {
  final String academyId;
  late final Collections _collections;

  FightRecordService(this.academyId) {
    _collections = Collections.forAcademy(academyId);
  }

  CollectionReference get _ref => _collections.fightRecords;

  Future<String> create(FightRecord record) async {
    final doc = await _ref.add(record.toFirestore());
    return doc.id;
  }

  Future<void> update(String id, FightRecord record) =>
      _ref.doc(id).update(record.toFirestore());

  Future<void> delete(String id) => _ref.doc(id).delete();

  /// A student's fights, most recent first.
  Future<List<FightRecord>> getByStudent(String studentId) async {
    final snap = await _ref
        .where('studentId', isEqualTo: studentId)
        .orderBy('date', descending: true)
        .get();
    return snap.docs.map(FightRecord.fromFirestore).toList();
  }
}
