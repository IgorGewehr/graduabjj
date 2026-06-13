import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/combo.dart';
import 'firebase_service.dart';

/// CRUD for the striking combinations library (C2). Staff write; academy members
/// read (firestore.rules). Mirrors ExerciseService/SyllabusService.
class ComboService {
  final String academyId;
  late final Collections _collections;

  ComboService(this.academyId) {
    _collections = Collections.forAcademy(academyId);
  }

  CollectionReference get _ref => _collections.combos;

  Future<String> create(Combo combo) async {
    final doc = await _ref.add(combo.toFirestore());
    return doc.id;
  }

  Future<void> update(String id, Combo combo) =>
      _ref.doc(id).update(combo.toFirestore());

  Future<void> delete(String id) => _ref.doc(id).delete();

  /// Atomic batch insert (for seeding).
  Future<void> createMany(List<Combo> combos) async {
    final batch = FirebaseService.firestore.batch();
    for (final c in combos) {
      batch.set(_ref.doc(), c.toFirestore());
    }
    await batch.commit();
  }

  Future<List<Combo>> listAll() async {
    final snap = await _ref.orderBy('order').get();
    return snap.docs.map(Combo.fromFirestore).toList();
  }

  /// All combos for a sport, ordered (grouping by level is done client-side).
  Future<List<Combo>> getBySport(String sport) async {
    final snap =
        await _ref.where('sport', isEqualTo: sport).orderBy('order').get();
    return snap.docs.map(Combo.fromFirestore).toList();
  }
}
