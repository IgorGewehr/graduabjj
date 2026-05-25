import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/sports.dart';
import '../models/training_video.dart';
import '../models/workout_plan.dart' show WorkoutAudience;
import 'firebase_service.dart';

/// CRUD + delivery + upload for training videos
/// (`academies/{academyId}/content`). Mirrors [WorkoutPlanService] for the
/// query/targeting strategy. Uploaded files live in Firebase Storage under
/// `academies/{academyId}/content/videos/{uuid}.mp4`.
class TrainingVideoService {
  final String academyId;
  late final Collections _collections;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  TrainingVideoService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _ref => _collections.content;

  Future<List<TrainingVideo>> listAll() async {
    final snap = await _ref.get();
    final list = snap.docs.map(TrainingVideo.fromFirestore).toList();
    _sortByNewest(list);
    return list;
  }

  Future<TrainingVideo?> getById(String id) async {
    final doc = await _ref.doc(id).get();
    if (!doc.exists) return null;
    return TrainingVideo.fromFirestore(doc);
  }

  Future<String> create(TrainingVideo video) async {
    final ref = await _ref.add({
      ...video.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update(String id, TrainingVideo video) async {
    await _ref.doc(id).update({
      ...video.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes the doc and, for uploads, the underlying Storage object.
  Future<void> delete(TrainingVideo video) async {
    if (video.storagePath != null && video.storagePath!.isNotEmpty) {
      try {
        await _storage.ref().child(video.storagePath!).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
    }
    await _ref.doc(video.id).delete();
  }

  /// Uploads a local video file to Storage and returns its download URL and
  /// object path (the path is stored so the file can be deleted later).
  Future<({String url, String path})> uploadVideoFile(File file) async {
    final id = const Uuid().v4();
    final path = 'academies/$academyId/content/videos/$id.mp4';
    final ref = _storage.ref().child(path);
    final snapshot = await ref.putFile(
      file,
      SettableMetadata(contentType: 'video/mp4'),
    );
    final url = await snapshot.ref.getDownloadURL();
    return (url: url, path: path);
  }

  /// Videos visible to a student: academy-wide + sport-library (filtered to the
  /// student's modalities) + personal. Two rule-compatible queries, merged.
  Future<List<TrainingVideo>> getForStudent({
    required String studentId,
    required List<SportId> sports,
  }) async {
    final results = await Future.wait([
      _ref.where('audience', whereIn: ['academy', 'sport']).get(),
      _ref.where('assignedStudentIds', arrayContains: studentId).get(),
    ]);

    final byId = <String, TrainingVideo>{};
    for (final snap in results) {
      for (final doc in snap.docs) {
        byId[doc.id] = TrainingVideo.fromFirestore(doc);
      }
    }

    final sportValues = sports.map((s) => s.value).toSet();
    final visible = byId.values.where((v) {
      switch (v.audience) {
        case WorkoutAudience.academy:
        case WorkoutAudience.students:
          return true;
        case WorkoutAudience.sport:
          return v.sport == null || sportValues.contains(v.sport);
      }
    }).toList();

    _sortByNewest(visible);
    return visible;
  }

  void _sortByNewest(List<TrainingVideo> list) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort((a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
  }
}
