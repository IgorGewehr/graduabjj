import 'package:cloud_firestore/cloud_firestore.dart';

/// How well a student has learned a technique. Only [dominado] counts toward
/// graduation progress.
enum SkillLevel { aprendendo, praticando, dominado }

extension SkillLevelExtension on SkillLevel {
  String get value {
    switch (this) {
      case SkillLevel.aprendendo:
        return 'aprendendo';
      case SkillLevel.praticando:
        return 'praticando';
      case SkillLevel.dominado:
        return 'dominado';
    }
  }

  String get label {
    switch (this) {
      case SkillLevel.aprendendo:
        return 'Aprendendo';
      case SkillLevel.praticando:
        return 'Praticando';
      case SkillLevel.dominado:
        return 'Dominado';
    }
  }

  bool get isMastered => this == SkillLevel.dominado;

  static SkillLevel? fromString(String? v) {
    switch (v) {
      case 'aprendendo':
        return SkillLevel.aprendendo;
      case 'praticando':
        return SkillLevel.praticando;
      case 'dominado':
        return SkillLevel.dominado;
      default:
        return null;
    }
  }
}

/// A student's progress on one technique. One doc per (studentId, techniqueId)
/// — the doc id is deterministic (`{studentId}__{techniqueId}`) so updates
/// upsert cleanly. Lives at `academies/{id}/skillProgress/{id}`.
class SkillProgress {
  final String id;
  final String studentId;
  final String sport; // SportId.value (denormalised for filtering)
  final String gradeId; // grade the technique belongs to (denormalised)
  final String techniqueId;
  final SkillLevel level;
  final String? notes; // per-technique feedback (B4)
  final String ratedBy;
  final String ratedByName;
  final DateTime updatedAt;

  const SkillProgress({
    required this.id,
    required this.studentId,
    required this.sport,
    required this.gradeId,
    required this.techniqueId,
    required this.level,
    this.notes,
    this.ratedBy = '',
    this.ratedByName = '',
    required this.updatedAt,
  });

  /// Deterministic doc id for a (student, technique) pair.
  static String docId(String studentId, String techniqueId) =>
      '${studentId}__$techniqueId';

  factory SkillProgress.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SkillProgress(
      id: doc.id,
      studentId: (data['studentId'] ?? '').toString(),
      sport: (data['sport'] ?? 'bjj').toString(),
      gradeId: (data['gradeId'] ?? '').toString(),
      techniqueId: (data['techniqueId'] ?? '').toString(),
      level: SkillLevelExtension.fromString(data['level'] as String?) ??
          SkillLevel.aprendendo,
      notes: data['notes'] as String?,
      ratedBy: (data['ratedBy'] ?? '').toString(),
      ratedByName: (data['ratedByName'] ?? '').toString(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'studentId': studentId,
        'sport': sport,
        'gradeId': gradeId,
        'techniqueId': techniqueId,
        'level': level.value,
        'notes': notes,
        'ratedBy': ratedBy,
        'ratedByName': ratedByName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
