import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/sports.dart';
import '../models/workout_plan.dart';
import 'firebase_service.dart';

/// CRUD + delivery queries for structured workout plans
/// (`academies/{academyId}/workoutPlans`). Plans work for any modality;
/// musculação is the primary use case.
class WorkoutPlanService {
  final String academyId;
  late final Collections _collections;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  WorkoutPlanService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _ref => _collections.workoutPlans;

  /// All plans for the academy (staff view), newest first.
  Future<List<WorkoutPlan>> listAll() async {
    final snap = await _ref.get();
    final list = snap.docs.map(WorkoutPlan.fromFirestore).toList();
    _sortByNewest(list);
    return list;
  }

  Future<WorkoutPlan?> getById(String id) async {
    final doc = await _ref.doc(id).get();
    if (!doc.exists) return null;
    return WorkoutPlan.fromFirestore(doc);
  }

  Future<String> create(WorkoutPlan plan) async {
    final ref = await _ref.add({
      ...plan.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update(String id, WorkoutPlan plan) async {
    await _ref.doc(id).update({
      ...plan.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) async {
    final plan = await getById(id);
    final path = plan?.fileStoragePath;
    if (path != null && path.isNotEmpty) {
      try {
        await _storage.ref().child(path).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
    }
    await _ref.doc(id).delete();
  }

  /// Uploads a plan file (PDF or image) to Storage and returns its download URL
  /// and object path. [isPdf] selects the extension/content-type.
  Future<({String url, String path})> uploadPlanFile(
    File file, {
    required bool isPdf,
  }) async {
    final id = const Uuid().v4();
    final path = 'academies/$academyId/content/plans/$id.${isPdf ? 'pdf' : 'jpg'}';
    final ref = _storage.ref().child(path);
    final snapshot = await ref.putFile(
      file,
      SettableMetadata(contentType: isPdf ? 'application/pdf' : 'image/jpeg'),
    );
    final url = await snapshot.ref.getDownloadURL();
    return (url: url, path: path);
  }

  // ============================================
  // Per-day completion log (student "mark exercise as done")
  // ============================================
  // Stored at workoutLogs/{studentId}_{planId}_{YYYYMMDD} with a `completed`
  // list of "dayIndex:exerciseIndex" keys. Per-day so each session starts fresh.

  String _logId(String studentId, String planId, DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${studentId}_${planId}_$y$m$day';
  }

  /// Today's completed-exercise keys for [studentId] on [planId].
  Future<Set<String>> getTodayLog(String studentId, String planId) async {
    final doc = await _collections.workoutLogs
        .doc(_logId(studentId, planId, DateTime.now()))
        .get();
    if (!doc.exists) return <String>{};
    final data = doc.data() as Map<String, dynamic>;
    return Set<String>.from(data['completed'] ?? const <String>[]);
  }

  /// Upserts today's completed-exercise keys for [studentId] on [planId].
  Future<void> saveTodayLog(
    String studentId,
    String planId,
    Set<String> completed,
  ) async {
    final now = DateTime.now();
    await _collections.workoutLogs.doc(_logId(studentId, planId, now)).set({
      'studentId': studentId,
      'planId': planId,
      'date': Timestamp.fromDate(now),
      'completed': completed.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Plans visible to a student: academy-wide and sport-library plans (the
  /// latter filtered to the student's modalities) plus personal plans assigned
  /// to them. Runs two rule-compatible queries and merges/de-dupes the results.
  ///
  /// - `where('audience', whereIn: ['academy','sport'])` → matches the library
  ///   read rule branch.
  /// - `where('assignedStudentIds', arrayContains: studentId)` → matches the
  ///   personal read rule branch.
  Future<List<WorkoutPlan>> getForStudent({
    required String studentId,
    required List<SportId> sports,
  }) async {
    final results = await Future.wait([
      _ref.where('audience', whereIn: ['academy', 'sport']).get(),
      _ref.where('assignedStudentIds', arrayContains: studentId).get(),
    ]);

    final byId = <String, WorkoutPlan>{};
    for (final snap in results) {
      for (final doc in snap.docs) {
        byId[doc.id] = WorkoutPlan.fromFirestore(doc);
      }
    }

    final sportValues = sports.map((s) => s.value).toSet();
    final visible = byId.values.where((p) {
      switch (p.audience) {
        case WorkoutAudience.academy:
        case WorkoutAudience.students:
          // Academy-wide, or assigned to me (the query already filtered).
          return true;
        case WorkoutAudience.sport:
          // Library plan: show when it matches one of the student's sports
          // (or has no specific sport).
          return p.sport == null || sportValues.contains(p.sport);
      }
    }).toList();

    _sortByNewest(visible);
    return visible;
  }

  void _sortByNewest(List<WorkoutPlan> list) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort((a, b) =>
        (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
  }
}
