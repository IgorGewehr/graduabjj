import 'package:cloud_firestore/cloud_firestore.dart';

/// One technique in an academy's curriculum, required/taught at a given grade
/// of a given sport. Lives at `academies/{id}/syllabus/{techniqueId}`.
class SyllabusTechnique {
  final String id;
  final String sport; // SportId.value (bjj, muaythai, …)
  final String gradeId; // faixa/grau em que é exigida/ensinada
  final String category; // agrupador livre (guarda, chute, kata…)
  final String name;
  final String? description;
  final String? videoUrl;
  final int order; // ordenação dentro da faixa
  final bool active;
  final String createdBy;
  final DateTime createdAt;

  const SyllabusTechnique({
    required this.id,
    required this.sport,
    required this.gradeId,
    this.category = '',
    required this.name,
    this.description,
    this.videoUrl,
    this.order = 0,
    this.active = true,
    this.createdBy = '',
    required this.createdAt,
  });

  factory SyllabusTechnique.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SyllabusTechnique(
      id: doc.id,
      sport: (data['sport'] ?? 'bjj').toString(),
      gradeId: (data['gradeId'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      description: data['description'] as String?,
      videoUrl: data['videoUrl'] as String?,
      order: (data['order'] as num?)?.toInt() ?? 0,
      active: data['active'] as bool? ?? true,
      createdBy: (data['createdBy'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Map for create/update. `createdAt` is stamped by the service on create.
  Map<String, dynamic> toFirestore() => {
        'sport': sport,
        'gradeId': gradeId,
        'category': category,
        'name': name,
        'description': description,
        'videoUrl': videoUrl,
        'order': order,
        'active': active,
        'createdBy': createdBy,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  SyllabusTechnique copyWith({
    String? gradeId,
    String? category,
    String? name,
    String? description,
    String? videoUrl,
    int? order,
    bool? active,
  }) {
    return SyllabusTechnique(
      id: id,
      sport: sport,
      gradeId: gradeId ?? this.gradeId,
      category: category ?? this.category,
      name: name ?? this.name,
      description: description ?? this.description,
      videoUrl: videoUrl ?? this.videoUrl,
      order: order ?? this.order,
      active: active ?? this.active,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }
}
