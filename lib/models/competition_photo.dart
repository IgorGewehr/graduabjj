import 'package:cloud_firestore/cloud_firestore.dart';

/// Competition Position (Medal Type)
enum CompetitionPosition { gold, silver, bronze, participant }

extension CompetitionPositionExtension on CompetitionPosition {
  String get value {
    switch (this) {
      case CompetitionPosition.gold:
        return 'gold';
      case CompetitionPosition.silver:
        return 'silver';
      case CompetitionPosition.bronze:
        return 'bronze';
      case CompetitionPosition.participant:
        return 'participant';
    }
  }

  String get label {
    switch (this) {
      case CompetitionPosition.gold:
        return 'Ouro';
      case CompetitionPosition.silver:
        return 'Prata';
      case CompetitionPosition.bronze:
        return 'Bronze';
      case CompetitionPosition.participant:
        return 'Participante';
    }
  }

  static CompetitionPosition fromString(String value) {
    switch (value) {
      case 'gold':
        return CompetitionPosition.gold;
      case 'silver':
        return CompetitionPosition.silver;
      case 'bronze':
        return CompetitionPosition.bronze;
      default:
        return CompetitionPosition.participant;
    }
  }
}

/// Competition Photo Model
class CompetitionPhoto {
  final String id;
  final String competitionId;
  final String competitionName;
  final String studentId;
  final String studentName;
  final String url;
  final String storagePath;
  final String? caption;
  final int likes;
  final bool isHighlight;
  final CompetitionPosition? medalType;
  final String? photoType; // 'student' | 'team'
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  CompetitionPhoto({
    required this.id,
    required this.competitionId,
    required this.competitionName,
    required this.studentId,
    required this.studentName,
    required this.url,
    required this.storagePath,
    this.caption,
    this.likes = 0,
    this.isHighlight = false,
    this.medalType,
    this.photoType,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  factory CompetitionPhoto.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CompetitionPhoto(
      id: doc.id,
      competitionId: data['competitionId'] ?? '',
      competitionName: data['competitionName'] ?? '',
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      url: data['url'] ?? '',
      storagePath: data['storagePath'] ?? '',
      caption: data['caption'],
      likes: data['likes'] ?? 0,
      isHighlight: data['isHighlight'] ?? false,
      medalType: data['medalType'] != null
          ? CompetitionPositionExtension.fromString(data['medalType'])
          : null,
      photoType: data['photoType'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'competitionId': competitionId,
      'competitionName': competitionName,
      'studentId': studentId,
      'studentName': studentName,
      'url': url,
      'storagePath': storagePath,
      'caption': caption,
      'likes': likes,
      'isHighlight': isHighlight,
      'medalType': medalType?.value,
      'photoType': photoType,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
    };
  }

  CompetitionPhoto copyWith({
    String? id,
    String? competitionId,
    String? competitionName,
    String? studentId,
    String? studentName,
    String? url,
    String? storagePath,
    String? caption,
    int? likes,
    bool? isHighlight,
    CompetitionPosition? medalType,
    String? photoType,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return CompetitionPhoto(
      id: id ?? this.id,
      competitionId: competitionId ?? this.competitionId,
      competitionName: competitionName ?? this.competitionName,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      url: url ?? this.url,
      storagePath: storagePath ?? this.storagePath,
      caption: caption ?? this.caption,
      likes: likes ?? this.likes,
      isHighlight: isHighlight ?? this.isHighlight,
      medalType: medalType ?? this.medalType,
      photoType: photoType ?? this.photoType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  String toString() {
    return 'CompetitionPhoto(id: $id, competitionName: $competitionName, studentName: $studentName)';
  }
}
