import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/physical_assessment.dart';
import 'firebase_service.dart';

/// CRUD + queries for physical/anthropometric assessments
/// (`academies/{id}/physicalAssessments`). Staff writes; the student reads their
/// own (enforced by Firestore rules). Mirrors the shape of `AssessmentService`.
class PhysicalAssessmentService {
  final String academyId;
  late final Collections _collections;

  PhysicalAssessmentService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _ref => _collections.physicalAssessments;

  /// Creates an assessment, stamping `createdAt`. Returns the new doc id.
  Future<String> create(PhysicalAssessment assessment) async {
    final data = assessment.toFirestore()
      ..['createdAt'] = FieldValue.serverTimestamp();
    final doc = await _ref.add(data);
    return doc.id;
  }

  Future<void> update(String id, PhysicalAssessment assessment) {
    return _collections.physicalAssessment(id).update(assessment.toFirestore());
  }

  Future<void> delete(String id) {
    return _collections.physicalAssessment(id).delete();
  }

  /// All assessments of a student, most recent first. Needs the composite index
  /// (studentId ASC, date DESC) declared in firestore.indexes.json.
  Future<List<PhysicalAssessment>> getByStudent(
    String studentId, {
    int? limit,
  }) async {
    Query query = _ref
        .where('studentId', isEqualTo: studentId)
        .orderBy('date', descending: true);
    if (limit != null) query = query.limit(limit);
    final snap = await query.get();
    return snap.docs.map(PhysicalAssessment.fromFirestore).toList();
  }

  /// The most recent assessment of a student (or null).
  Future<PhysicalAssessment?> getLatest(String studentId) async {
    final list = await getByStudent(studentId, limit: 1);
    return list.isEmpty ? null : list.first;
  }

  /// Time series `(date, value)` of one metric, oldest→newest, for charts.
  /// [metric] extracts the value from each assessment (null entries skipped).
  Future<List<({DateTime date, double value})>> series(
    String studentId,
    double? Function(PhysicalAssessment) metric,
  ) async {
    final all = await getByStudent(studentId);
    final points = <({DateTime date, double value})>[];
    for (final a in all.reversed) {
      final v = metric(a);
      if (v != null) points.add((date: a.date, value: v));
    }
    return points;
  }
}
