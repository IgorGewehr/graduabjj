import 'package:cloud_firestore/cloud_firestore.dart';

/// Kind of striking work logged in a session (C1).
enum StrikingType { bag, pads, sparring, clinch, technique }

extension StrikingTypeX on StrikingType {
  String get value => name;

  String get label {
    switch (this) {
      case StrikingType.bag:
        return 'Saco';
      case StrikingType.pads:
        return 'Manoplas';
      case StrikingType.sparring:
        return 'Sparring';
      case StrikingType.clinch:
        return 'Clinch';
      case StrikingType.technique:
        return 'Técnica';
    }
  }

  static StrikingType fromString(String? v) {
    return StrikingType.values.firstWhere(
      (t) => t.name == v,
      orElse: () => StrikingType.bag,
    );
  }
}

/// A student-logged striking training session. Lives at
/// `academies/{id}/strikingSessions/{autoId}` (several per day allowed).
class StrikingSession {
  final String id;
  final String studentId;
  final String studentName;
  final String sport; // SportId.value (muaythai/boxing/kickboxing)
  final StrikingType type;
  final int rounds;
  final int? roundDurationSec;
  final int? totalMinutes;
  final int? rpe; // perceived effort 1-10
  final String? notes;
  final DateTime date;
  final DateTime? createdAt;

  const StrikingSession({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.sport,
    required this.type,
    required this.rounds,
    this.roundDurationSec,
    this.totalMinutes,
    this.rpe,
    this.notes,
    required this.date,
    this.createdAt,
  });

  factory StrikingSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return StrikingSession(
      id: doc.id,
      studentId: (data['studentId'] ?? '').toString(),
      studentName: (data['studentName'] ?? '').toString(),
      sport: (data['sport'] ?? 'muaythai').toString(),
      type: StrikingTypeX.fromString(data['type'] as String?),
      rounds: (data['rounds'] as num?)?.toInt() ?? 0,
      roundDurationSec: (data['roundDurationSec'] as num?)?.toInt(),
      totalMinutes: (data['totalMinutes'] as num?)?.toInt(),
      rpe: (data['rpe'] as num?)?.toInt(),
      notes: data['notes'] as String?,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'studentId': studentId,
        'studentName': studentName,
        'sport': sport,
        'type': type.value,
        'rounds': rounds,
        'roundDurationSec': roundDurationSec,
        'totalMinutes': totalMinutes,
        'rpe': rpe,
        'notes': notes,
        'date': Timestamp.fromDate(date),
        'createdAt': FieldValue.serverTimestamp(),
      };
}
