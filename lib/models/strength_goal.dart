import 'package:cloud_firestore/cloud_firestore.dart';

/// A student's target load for one exercise (E2). One doc per (student,
/// exercise) — deterministic id so setting a goal upserts. Lives at
/// `academies/{id}/strengthGoals/{id}`. The student owns it; staff can read.
class StrengthGoal {
  final String id;
  final String studentId;
  final String exerciseName;
  final double targetLoadKg;
  final DateTime? createdAt;

  const StrengthGoal({
    required this.id,
    required this.studentId,
    required this.exerciseName,
    required this.targetLoadKg,
    this.createdAt,
  });

  /// Deterministic doc id for a (student, exercise) pair. The exercise name is
  /// sanitized to a Firestore-safe key (no slashes/whitespace).
  static String docId(String studentId, String exerciseName) {
    final key = exerciseName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${studentId}__$key';
  }

  factory StrengthGoal.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return StrengthGoal(
      id: doc.id,
      studentId: (data['studentId'] ?? '').toString(),
      exerciseName: (data['exerciseName'] ?? '').toString(),
      targetLoadKg: (data['targetLoadKg'] as num?)?.toDouble() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'studentId': studentId,
        'exerciseName': exerciseName,
        'targetLoadKg': targetLoadKg,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
