import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/academy_event.dart';
import 'firebase_service.dart';
import 'notification_dispatcher.dart';

/// Pure payload describing the notification fired when a Jornal post is
/// published. Kept as a plain value object so it can be unit-tested without
/// touching Firestore / FCM.
class PublishNotification {
  final String title;
  final String message;
  final Map<String, String> data;

  const PublishNotification({
    required this.title,
    required this.message,
    required this.data,
  });

  String get route => data['route']!;
}

class EventService {
  final String academyId;
  final FirebaseStorage _storage;

  EventService(this.academyId, {FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  CollectionReference get _ref =>
      FirebaseService.firestore.collection('academies/$academyId/events');

  String _coverPath(String id) => 'academies/$academyId/events/$id/cover.jpg';

  // ============================================
  // Reads (existing behavior UNCHANGED)
  // ============================================

  Future<List<AcademyEvent>> listPublished() async {
    final snap = await _ref
        .where('isPublished', isEqualTo: true)
        .orderBy('startDate')
        .get();
    return snap.docs.map((d) => AcademyEvent.fromFirestore(d)).toList();
  }

  /// Returns only events that haven't ended yet (upcoming + ongoing).
  Future<List<AcademyEvent>> listUpcoming({int limit = 5}) async {
    final all = await listPublished();
    final now = DateTime.now();
    return all
        .where((e) => e.endDate == null
            ? e.startDate.isAfter(now.subtract(const Duration(hours: 3)))
            : e.endDate!.isAfter(now))
        .take(limit)
        .toList();
  }

  /// Fetch a single post by id, or null if it doesn't exist.
  Future<AcademyEvent?> getById(String id) async {
    final doc = await _ref.doc(id).get();
    if (!doc.exists) return null;
    return AcademyEvent.fromFirestore(doc);
  }

  /// Admin listing: drafts + published, newest startDate first.
  Future<List<AcademyEvent>> listAll({bool includeUnpublished = true}) async {
    Query query = _ref.orderBy('startDate', descending: true);
    if (!includeUnpublished) {
      query = _ref
          .where('isPublished', isEqualTo: true)
          .orderBy('startDate', descending: true);
    }
    final snap = await query.get();
    return snap.docs.map((d) => AcademyEvent.fromFirestore(d)).toList();
  }

  // ============================================
  // Writes
  // ============================================

  /// Create a new Jornal post.
  ///
  /// - Generates a slug-based id from the title (deduplicating with a numeric
  ///   suffix if that id already exists).
  /// - Writes the doc via [AcademyEvent.toFirestore] (plus a `createdAt` stamp).
  /// - Uploads [cover] to `academies/{academyId}/events/{id}/cover.jpg` and
  ///   writes `coverUrl` / `coverStoragePath` onto the doc.
  /// - When [notify] is true, dispatches an academy notification.
  ///
  /// Returns the generated document id.
  Future<String> create(
    AcademyEvent event, {
    File? cover,
    bool notify = false,
  }) async {
    final id = await _uniqueSlugId(event.title);
    final docRef = _ref.doc(id);

    final data = event.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    await docRef.set(data);

    if (cover != null) {
      final uploaded = await _uploadCover(id, cover);
      await docRef.update({
        'coverUrl': uploaded.url,
        'coverStoragePath': uploaded.path,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (notify) {
      await _notifyOnPublish(event.copyWith(id: id));
    }

    return id;
  }

  /// Update an existing post. Optionally replaces the cover image.
  ///
  /// Null-valued fields are stripped before writing so a partial edit (e.g. an
  /// admin form that doesn't re-supply the existing cover) never wipes stored
  /// data. Pass a new [cover] to replace the image, or clear a field explicitly
  /// via Firestore if intentional removal is ever needed.
  Future<void> update(String id, AcademyEvent event, {File? cover}) async {
    final docRef = _ref.doc(id);
    final data = event.toFirestore()..removeWhere((_, v) => v == null);

    if (cover != null) {
      final uploaded = await _uploadCover(id, cover);
      data['coverUrl'] = uploaded.url;
      data['coverStoragePath'] = uploaded.path;
    }

    await docRef.update(data);
  }

  /// Delete the post doc and its cover from storage (ignoring a missing file).
  Future<void> delete(String id) async {
    try {
      await _storage.ref().child(_coverPath(id)).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
    await _ref.doc(id).delete();
  }

  /// Publish a post (sets isPublished = true).
  Future<void> publish(String id) async {
    await _ref.doc(id).update({
      'isPublished': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Unpublish a post (sets isPublished = false).
  Future<void> unpublish(String id) async {
    await _ref.doc(id).update({
      'isPublished': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Internals
  // ============================================

  /// Build the (pure) notification payload for a published post. Exposed as a
  /// static helper so it can be unit-tested without Firestore.
  static PublishNotification buildPublishNotification(AcademyEvent event) {
    return PublishNotification(
      title: '${event.postType.emoji} ${event.title}',
      message: event.description,
      data: {'route': '/portal/eventos/${event.id}'},
    );
  }

  Future<void> _notifyOnPublish(AcademyEvent event) async {
    final payload = buildPublishNotification(event);
    final dispatcher = NotificationDispatcher(academyId);
    final userId = FirebaseService.currentUserId;
    if (userId == null) return;
    await dispatcher.sendAcademyNotification(
      userId: userId,
      title: payload.title,
      message: payload.message,
      data: payload.data,
    );
  }

  /// Upload result tuple.
  Future<_Uploaded> _uploadCover(String id, File cover) async {
    if (!await cover.exists()) {
      throw Exception('Arquivo de capa não encontrado');
    }
    final path = _coverPath(id);
    final ref = _storage.ref().child(path);
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: 'public, max-age=3600, must-revalidate',
    );
    final snapshot = await ref.putFile(cover, metadata);
    final url = await snapshot.ref.getDownloadURL();
    return _Uploaded(url: url, path: path);
  }

  /// Slugify the title and ensure the resulting doc id is unique within the
  /// collection (appends -2, -3, ... on collision).
  Future<String> _uniqueSlugId(String title) async {
    final base = slugify(title);
    var candidate = base;
    var n = 1;
    while ((await _ref.doc(candidate).get()).exists) {
      n++;
      candidate = '$base-$n';
    }
    return candidate;
  }

  /// Convert a free-text title into a URL/id-safe slug.
  static String slugify(String input) {
    var s = input.toLowerCase().trim();
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    s = s.replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'post' : s;
  }
}

class _Uploaded {
  final String url;
  final String path;
  const _Uploaded({required this.url, required this.path});
}

EventService createEventService(String academyId) => EventService(academyId);
