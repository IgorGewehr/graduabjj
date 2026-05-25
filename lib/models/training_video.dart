import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/sports.dart';
import 'workout_plan.dart' show WorkoutAudience;

/// Where a video lives. [link] = external URL (YouTube/Vimeo/etc.) played by
/// launching it externally; [upload] = file hosted in Firebase Storage, played
/// from its download URL.
enum VideoSource {
  link,
  upload;

  String get value => name;

  static VideoSource fromString(String? value) {
    return VideoSource.values.firstWhere(
      (s) => s.name == value,
      orElse: () => VideoSource.link,
    );
  }
}

/// A training video delivered to students. Lives at
/// `academies/{academyId}/content/{videoId}`. Targeting reuses
/// [WorkoutAudience] (academy / sport / specific students) so the same read
/// rules and query strategy as workout plans apply.
class TrainingVideo {
  final String id;
  final String title;
  final String? description;

  /// SportId value ('musculacao', 'bjj', ...) or null for "any modality".
  final String? sport;

  final WorkoutAudience audience;

  /// Always serialized (empty unless audience == students) so rules can safely
  /// evaluate `studentId in assignedStudentIds`.
  final List<String> assignedStudentIds;

  final VideoSource source;

  /// External URL (link) or Storage download URL (upload).
  final String url;

  /// Storage object path — only set for uploads, so the file can be deleted.
  final String? storagePath;

  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TrainingVideo({
    required this.id,
    required this.title,
    this.description,
    this.sport,
    this.audience = WorkoutAudience.academy,
    this.assignedStudentIds = const [],
    this.source = VideoSource.link,
    required this.url,
    this.storagePath,
    this.createdBy = '',
    this.createdByName = '',
    this.createdAt,
    this.updatedAt,
  });

  SportId? get sportId => sport == null ? null : SportId.fromString(sport!);

  factory TrainingVideo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TrainingVideo(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: data['description'] as String?,
      sport: data['sport'] as String?,
      audience: WorkoutAudience.fromString(data['audience'] as String?),
      assignedStudentIds:
          List<String>.from(data['assignedStudentIds'] ?? const []),
      source: VideoSource.fromString(data['source'] as String?),
      url: (data['url'] ?? '').toString(),
      storagePath: data['storagePath'] as String?,
      createdBy: (data['createdBy'] ?? '').toString(),
      createdByName: (data['createdByName'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'description': description,
        'sport': sport,
        'audience': audience.value,
        'assignedStudentIds':
            audience == WorkoutAudience.students ? assignedStudentIds : const [],
        'type': 'video',
        'source': source.value,
        'url': url,
        'storagePath': storagePath,
        'createdBy': createdBy,
        'createdByName': createdByName,
      };
}
