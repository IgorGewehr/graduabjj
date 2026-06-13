import 'package:cloud_firestore/cloud_firestore.dart';

/// Skill levels for striking combinations (C2). Ordered iniciante < intermediário
/// < avançado; used to group/sort the library.
const comboLevels = ['iniciante', 'intermediario', 'avancado'];

String comboLevelLabel(String? v) {
  switch (v) {
    case 'intermediario':
      return 'Intermediário';
    case 'avancado':
      return 'Avançado';
    case 'iniciante':
    default:
      return 'Iniciante';
  }
}

int comboLevelOrder(String? v) {
  final i = comboLevels.indexOf(v ?? 'iniciante');
  return i < 0 ? 0 : i;
}

/// A striking combination — a named sequence of strikes (e.g. "Jab · Direto ·
/// Cruzado") for a sport + level, with an optional demo video. Shared library
/// per academy (mirrors Exercise/SyllabusTechnique). Lives at
/// `academies/{id}/combos/{autoId}`.
class Combo {
  final String id;
  final String name;
  final String sport; // SportId.value (muaythai/boxing/kickboxing)
  final String level; // one of comboLevels
  final List<String> strikes; // ordered sequence
  final String? description;
  final String? videoUrl;
  final int order;
  final bool active;
  final String createdBy;
  final DateTime? createdAt;

  const Combo({
    required this.id,
    required this.name,
    required this.sport,
    this.level = 'iniciante',
    this.strikes = const [],
    this.description,
    this.videoUrl,
    this.order = 0,
    this.active = true,
    this.createdBy = '',
    this.createdAt,
  });

  factory Combo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Combo(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      sport: (data['sport'] ?? 'muaythai').toString(),
      level: (data['level'] ?? 'iniciante').toString(),
      strikes: (data['strikes'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      description: data['description'] as String?,
      videoUrl: data['videoUrl'] as String?,
      order: (data['order'] as num?)?.toInt() ?? 0,
      active: data['active'] ?? true,
      createdBy: (data['createdBy'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'sport': sport,
        'level': level,
        'strikes': strikes,
        'description': description,
        'videoUrl': videoUrl,
        'order': order,
        'active': active,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Combo copyWith({
    String? name,
    String? sport,
    String? level,
    List<String>? strikes,
    String? description,
    String? videoUrl,
    int? order,
    bool? active,
  }) =>
      Combo(
        id: id,
        name: name ?? this.name,
        sport: sport ?? this.sport,
        level: level ?? this.level,
        strikes: strikes ?? this.strikes,
        description: description ?? this.description,
        videoUrl: videoUrl ?? this.videoUrl,
        order: order ?? this.order,
        active: active ?? this.active,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
