/// Catálogo básico de musculação (seed opcional, editável depois).
/// `equipment` opcional; valores conforme `equipmentTypes` em exercise.dart.
class ExerciseSeedItem {
  final String name;
  final String muscleGroup;
  final String? equipment;
  const ExerciseSeedItem(this.name, this.muscleGroup, [this.equipment]);
}

const List<ExerciseSeedItem> musculacaoStarterCatalog = [
  // Peito
  ExerciseSeedItem('Supino reto', 'peito', 'barra'),
  ExerciseSeedItem('Supino inclinado', 'peito', 'halter'),
  ExerciseSeedItem('Crucifixo', 'peito', 'halter'),
  ExerciseSeedItem('Crossover', 'peito', 'cabo'),
  ExerciseSeedItem('Flexão de braço', 'peito', 'peso-corporal'),
  // Costas
  ExerciseSeedItem('Puxada frente', 'costas', 'maquina'),
  ExerciseSeedItem('Remada curvada', 'costas', 'barra'),
  ExerciseSeedItem('Remada baixa', 'costas', 'maquina'),
  ExerciseSeedItem('Levantamento terra', 'costas', 'barra'),
  ExerciseSeedItem('Barra fixa', 'costas', 'peso-corporal'),
  // Pernas
  ExerciseSeedItem('Agachamento livre', 'pernas', 'barra'),
  ExerciseSeedItem('Leg press', 'pernas', 'maquina'),
  ExerciseSeedItem('Cadeira extensora', 'pernas', 'maquina'),
  ExerciseSeedItem('Mesa flexora', 'pernas', 'maquina'),
  ExerciseSeedItem('Afundo', 'pernas', 'halter'),
  ExerciseSeedItem('Panturrilha em pé', 'pernas', 'maquina'),
  // Ombros
  ExerciseSeedItem('Desenvolvimento', 'ombros', 'halter'),
  ExerciseSeedItem('Elevação lateral', 'ombros', 'halter'),
  ExerciseSeedItem('Elevação frontal', 'ombros', 'halter'),
  ExerciseSeedItem('Remada alta', 'ombros', 'barra'),
  // Braços
  ExerciseSeedItem('Rosca direta', 'bracos', 'barra'),
  ExerciseSeedItem('Rosca alternada', 'bracos', 'halter'),
  ExerciseSeedItem('Rosca scott', 'bracos', 'maquina'),
  ExerciseSeedItem('Tríceps testa', 'bracos', 'barra'),
  ExerciseSeedItem('Tríceps corda', 'bracos', 'cabo'),
  // Core
  ExerciseSeedItem('Prancha', 'core', 'peso-corporal'),
  ExerciseSeedItem('Abdominal supra', 'core', 'peso-corporal'),
  ExerciseSeedItem('Elevação de pernas', 'core', 'peso-corporal'),
];
