import 'package:cloud_firestore/cloud_firestore.dart';

double? _toD(dynamic v) => v is num ? v.toDouble() : null;

/// Parses a `{key: number}` map keeping only numeric, present entries.
Map<String, double> _toNumMap(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, double>{};
  raw.forEach((k, v) {
    final d = _toD(v);
    if (d != null) out[k.toString()] = d;
  });
  return out;
}

/// One progress photo attached to a physical assessment.
/// Stored PRIVATELY (only staff + the student) — never public.
class AssessmentPhoto {
  final String url;
  final String storagePath;
  final String angle; // 'front' | 'side' | 'back'
  final DateTime? takenAt;

  const AssessmentPhoto({
    required this.url,
    required this.storagePath,
    required this.angle,
    this.takenAt,
  });

  factory AssessmentPhoto.fromMap(Map<String, dynamic> m) => AssessmentPhoto(
        url: (m['url'] ?? '').toString(),
        storagePath: (m['storagePath'] ?? '').toString(),
        angle: (m['angle'] ?? 'front').toString(),
        takenAt: (m['takenAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'url': url,
        'storagePath': storagePath,
        'angle': angle,
        if (takenAt != null) 'takenAt': Timestamp.fromDate(takenAt!),
      };
}

/// Physical / anthropometric assessment of a student (measurements over time +
/// progress photos). DISTINCT from the technical 1-5 assessment in
/// `assessment_service.dart` — lives in its own collection `physicalAssessments`.
///
/// All measurement fields are optional. `measurements` (cm) and `skinfolds` (mm)
/// store ONLY the keys the instructor filled in.
class PhysicalAssessment {
  final String id;
  final String studentId;
  final String studentName;
  final DateTime date;

  // Basics
  final double? weightKg;
  final double? heightCm;

  // Body composition (optional)
  final double? bodyFatPct;
  final double? leanMassKg;
  final double? fatMassKg;
  // Bioimpedance extras (optional; typed manually from a device like InBody).
  final double? visceralFatLevel;
  final double? bmrKcal; // basal metabolic rate

  // Girths (cm) and skinfolds (mm) — only filled keys present.
  final Map<String, double> measurements;
  final Map<String, double> skinfolds;

  final List<AssessmentPhoto> photos;

  // Context
  final String? goal; // hipertrofia | emagrecimento | condicionamento | manutencao
  final String? notes;

  final String assessedBy;
  final String assessedByName;
  final DateTime createdAt;

  const PhysicalAssessment({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.date,
    this.weightKg,
    this.heightCm,
    this.bodyFatPct,
    this.leanMassKg,
    this.fatMassKg,
    this.visceralFatLevel,
    this.bmrKcal,
    this.measurements = const {},
    this.skinfolds = const {},
    this.photos = const [],
    this.goal,
    this.notes,
    this.assessedBy = '',
    this.assessedByName = '',
    required this.createdAt,
  });

  /// Canonical girth keys (cm), in display order. Optional — only filled ones
  /// are persisted, but this drives the form/labels.
  static const List<String> girthKeys = [
    'neck', 'shoulder', 'chest', 'waist', 'abdomen', 'hip',
    'armR', 'armL', 'forearmR', 'forearmL',
    'thighR', 'thighL', 'calfR', 'calfL',
  ];

  /// BMI = weight / height_m². Null if weight/height missing.
  double? get bmi {
    final w = weightKg, h = heightCm;
    if (w == null || h == null || h == 0) return null;
    final m = h / 100.0;
    return w / (m * m);
  }

  /// WHO BMI classification (pt-BR). Null if BMI can't be computed.
  String? get bmiClass {
    final b = bmi;
    if (b == null) return null;
    if (b < 18.5) return 'Abaixo do peso';
    if (b < 25) return 'Peso normal';
    if (b < 30) return 'Sobrepeso';
    if (b < 35) return 'Obesidade grau I';
    if (b < 40) return 'Obesidade grau II';
    return 'Obesidade grau III';
  }

  factory PhysicalAssessment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PhysicalAssessment(
      id: doc.id,
      studentId: (data['studentId'] ?? '').toString(),
      studentName: (data['studentName'] ?? '').toString(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      weightKg: _toD(data['weightKg']),
      heightCm: _toD(data['heightCm']),
      bodyFatPct: _toD(data['bodyFatPct']),
      leanMassKg: _toD(data['leanMassKg']),
      fatMassKg: _toD(data['fatMassKg']),
      visceralFatLevel: _toD(data['visceralFatLevel']),
      bmrKcal: _toD(data['bmrKcal']),
      measurements: _toNumMap(data['measurements']),
      skinfolds: _toNumMap(data['skinfolds']),
      photos: ((data['photos'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AssessmentPhoto.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      goal: data['goal'] as String?,
      notes: data['notes'] as String?,
      assessedBy: (data['assessedBy'] ?? '').toString(),
      assessedByName: (data['assessedByName'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Map for create/update. Scalars are written even when null so an edit that
  /// clears a field persists the clear; `measurements`/`skinfolds` are replaced
  /// wholesale (only filled keys), so removing a value works too.
  Map<String, dynamic> toFirestore() => {
        'studentId': studentId,
        'studentName': studentName,
        'date': Timestamp.fromDate(date),
        'weightKg': weightKg,
        'heightCm': heightCm,
        'bodyFatPct': bodyFatPct,
        'leanMassKg': leanMassKg,
        'fatMassKg': fatMassKg,
        'visceralFatLevel': visceralFatLevel,
        'bmrKcal': bmrKcal,
        'measurements': measurements,
        'skinfolds': skinfolds,
        'photos': photos.map((p) => p.toMap()).toList(),
        'goal': goal,
        'notes': notes,
        'assessedBy': assessedBy,
        'assessedByName': assessedByName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
