import 'package:cloud_firestore/cloud_firestore.dart';

/// Type of content published in the academy Jornal.
///
/// Legacy documents created before A5 have no `postType` field and are treated
/// as [PostType.event] (see [AcademyEvent.fromFirestore]).
enum PostType { event, news, seminar }

extension PostTypeEmoji on PostType {
  /// Emoji used to prefix push/in-app notification titles.
  String get emoji {
    switch (this) {
      case PostType.event:
        return '📅';
      case PostType.news:
        return '📰';
      case PostType.seminar:
        return '🥋';
    }
  }
}

class AcademyEvent {
  final String id;
  final String academyId;
  final String title;
  final String slug;
  final String description;
  final String? coverUrl;
  final String? coverStoragePath;
  final DateTime startDate;
  final DateTime? endDate;
  final String? location;
  final String? ctaUrl;
  final String? ctaLabel;
  final bool isPublished;
  final PostType postType;
  final String? sourceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  AcademyEvent({
    required this.id,
    required this.academyId,
    required this.title,
    required this.slug,
    required this.description,
    this.coverUrl,
    this.coverStoragePath,
    required this.startDate,
    this.endDate,
    this.location,
    this.ctaUrl,
    this.ctaLabel,
    required this.isPublished,
    this.postType = PostType.event,
    this.sourceId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isUpcoming => startDate.isAfter(DateTime.now());
  bool get isOngoing =>
      startDate.isBefore(DateTime.now()) &&
      (endDate == null || endDate!.isAfter(DateTime.now()));

  factory AcademyEvent.fromFirestore(DocumentSnapshot doc) {
    return AcademyEvent.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }

  /// Build from a raw `(id, data)` pair. Used by [fromFirestore] and directly
  /// testable without a Firestore backend.
  factory AcademyEvent.fromMap(String id, Map<String, dynamic> data) {
    // Legacy docs have no `postType` -> fall back to event.
    PostType postType = PostType.event;
    final rawType = data['postType'];
    if (rawType is String) {
      try {
        postType = PostType.values.byName(rawType);
      } catch (_) {
        postType = PostType.event;
      }
    }

    return AcademyEvent(
      id: id,
      academyId: data['academyId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      slug: data['slug'] as String? ?? '',
      description: data['description'] as String? ?? '',
      coverUrl: data['coverUrl'] as String?,
      coverStoragePath: data['coverStoragePath'] as String?,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: data['endDate'] != null
          ? (data['endDate'] as Timestamp).toDate()
          : null,
      location: data['location'] as String?,
      ctaUrl: data['ctaUrl'] as String?,
      ctaLabel: data['ctaLabel'] as String?,
      isPublished: data['isPublished'] as bool? ?? false,
      postType: postType,
      sourceId: data['sourceId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Serializes this event for a Firestore write.
  ///
  /// `updatedAt` is always set to the server timestamp. `createdAt` is included
  /// only when not creating from scratch — callers that create a brand new doc
  /// should rely on [EventService.create], which stamps `createdAt` itself.
  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'academyId': academyId,
      'title': title,
      'slug': slug,
      'description': description,
      'coverUrl': coverUrl,
      'coverStoragePath': coverStoragePath,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'location': location,
      'ctaUrl': ctaUrl,
      'ctaLabel': ctaLabel,
      'isPublished': isPublished,
      'postType': postType.name,
      'sourceId': sourceId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  AcademyEvent copyWith({
    String? id,
    String? academyId,
    String? title,
    String? slug,
    String? description,
    String? coverUrl,
    String? coverStoragePath,
    DateTime? startDate,
    DateTime? endDate,
    String? location,
    String? ctaUrl,
    String? ctaLabel,
    bool? isPublished,
    PostType? postType,
    String? sourceId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AcademyEvent(
      id: id ?? this.id,
      academyId: academyId ?? this.academyId,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      coverStoragePath: coverStoragePath ?? this.coverStoragePath,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      location: location ?? this.location,
      ctaUrl: ctaUrl ?? this.ctaUrl,
      ctaLabel: ctaLabel ?? this.ctaLabel,
      isPublished: isPublished ?? this.isPublished,
      postType: postType ?? this.postType,
      sourceId: sourceId ?? this.sourceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
