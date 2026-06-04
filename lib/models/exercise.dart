import 'package:cloud_firestore/cloud_firestore.dart';

/// Grupos musculares sugeridos (valor → label pt-BR). Campo livre no modelo,
/// mas o picker do catálogo usa esta lista.
const Map<String, String> muscleGroups = {
  'peito': 'Peito',
  'costas': 'Costas',
  'pernas': 'Pernas',
  'ombros': 'Ombros',
  'bracos': 'Braços',
  'core': 'Core/Abdômen',
  'cardio': 'Cardio',
  'corpo-todo': 'Corpo todo',
  'outro': 'Outro',
};

/// Equipamentos sugeridos (valor → label).
const Map<String, String> equipmentTypes = {
  'barra': 'Barra',
  'halter': 'Halteres',
  'maquina': 'Máquina',
  'cabo': 'Cabo/Polia',
  'peso-corporal': 'Peso corporal',
  'outro': 'Outro',
};

/// Um exercício do catálogo da academia (A5).
/// Lives at `academies/{id}/exercises/{exerciseId}`.
class Exercise {
  final String id;
  final String name;
  final String? description;
  final String? videoUrl;
  final String muscleGroup; // chave de [muscleGroups] (livre)
  final String? equipment; // chave de [equipmentTypes]
  final bool active;
  final String createdBy;
  final DateTime createdAt;

  const Exercise({
    required this.id,
    required this.name,
    this.description,
    this.videoUrl,
    this.muscleGroup = 'outro',
    this.equipment,
    this.active = true,
    this.createdBy = '',
    required this.createdAt,
  });

  factory Exercise.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Exercise(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      description: data['description'] as String?,
      videoUrl: data['videoUrl'] as String?,
      muscleGroup: (data['muscleGroup'] ?? 'outro').toString(),
      equipment: data['equipment'] as String?,
      active: data['active'] as bool? ?? true,
      createdBy: (data['createdBy'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// `createdAt` é carimbado pelo serviço no create.
  Map<String, dynamic> toFirestore() => {
        'name': name,
        'description': description,
        'videoUrl': videoUrl,
        'muscleGroup': muscleGroup,
        'equipment': equipment,
        'active': active,
        'createdBy': createdBy,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  String get muscleGroupLabel => muscleGroups[muscleGroup] ?? muscleGroup;
  String? get equipmentLabel =>
      equipment == null ? null : (equipmentTypes[equipment] ?? equipment);

  Exercise copyWith({
    String? name,
    String? description,
    String? videoUrl,
    String? muscleGroup,
    String? equipment,
    bool? active,
  }) {
    return Exercise(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      videoUrl: videoUrl ?? this.videoUrl,
      muscleGroup: muscleGroup ?? this.muscleGroup,
      equipment: equipment ?? this.equipment,
      active: active ?? this.active,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }
}
