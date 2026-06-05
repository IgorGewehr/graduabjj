import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/cartel.dart';

/// One fight in a student's official record/cartel (C3). Staff-written; the
/// student/responsible reads. Lives at `academies/{id}/fightRecords/{autoId}`.
class FightRecord {
  final String id;
  final String studentId;
  final String studentName;
  final String? sport; // SportId.value (muaythai/boxing/kickboxing)
  final FightResult result;
  final FightMethod method;
  final String event;
  final DateTime date;
  final String? opponent;
  final String? weightClass;
  final int? rounds;
  final String? videoUrl;
  final String? notes;
  final String createdBy;
  final DateTime? createdAt;

  const FightRecord({
    required this.id,
    required this.studentId,
    required this.studentName,
    this.sport,
    required this.result,
    required this.method,
    required this.event,
    required this.date,
    this.opponent,
    this.weightClass,
    this.rounds,
    this.videoUrl,
    this.notes,
    this.createdBy = '',
    this.createdAt,
  });

  factory FightRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FightRecord(
      id: doc.id,
      studentId: (data['studentId'] ?? '').toString(),
      studentName: (data['studentName'] ?? '').toString(),
      sport: data['sport'] as String?,
      result: FightResultX.fromString(data['result'] as String?),
      method: FightMethodX.fromString(data['method'] as String?),
      event: (data['event'] ?? '').toString(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      opponent: data['opponent'] as String?,
      weightClass: data['weightClass'] as String?,
      rounds: (data['rounds'] as num?)?.toInt(),
      videoUrl: data['videoUrl'] as String?,
      notes: data['notes'] as String?,
      createdBy: (data['createdBy'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'studentId': studentId,
        'studentName': studentName,
        'sport': sport,
        'result': result.value,
        'method': method.value,
        'event': event,
        'date': Timestamp.fromDate(date),
        'opponent': opponent,
        'weightClass': weightClass,
        'rounds': rounds,
        'videoUrl': videoUrl,
        'notes': notes,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// As a summarizable pair for `summarizeCartel`.
  ({FightResult result, FightMethod method}) get pair =>
      (result: result, method: method);
}
