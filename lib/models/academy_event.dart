import 'package:cloud_firestore/cloud_firestore.dart';

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
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isUpcoming => startDate.isAfter(DateTime.now());
  bool get isOngoing =>
      startDate.isBefore(DateTime.now()) &&
      (endDate == null || endDate!.isAfter(DateTime.now()));

  factory AcademyEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AcademyEvent(
      id: doc.id,
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
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
