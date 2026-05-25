import 'package:flutter/material.dart';

// ============================================
// Sports Constants — Multi-Sport Support
// GraduaBJJ / MarcusJJ
// ============================================

/// Sport identifiers (matches Firestore values in marcusjj)
enum SportId {
  bjj,
  muaythai,
  karate,
  judo,
  kickboxing,
  boxing,
  lutalivre,
  musculacao;

  String get value => name;

  static SportId fromString(String value) {
    return SportId.values.firstWhere(
      (s) => s.name == value,
      orElse: () => SportId.bjj,
    );
  }
}

/// Grade system types
enum GradeSystem { belt, armband, none }

/// Grade definition for a specific rank within a sport
class GradeDefinition {
  final String id;
  final String label;
  final Color color;
  final Color? tipColor; // For armband tips (Muay Thai)
  final int maxStripes;
  final bool isBlackBelt;
  final bool kidsOnly;
  final bool adultOnly;

  const GradeDefinition({
    required this.id,
    required this.label,
    required this.color,
    this.tipColor,
    required this.maxStripes,
    this.isBlackBelt = false,
    this.kidsOnly = false,
    this.adultOnly = false,
  });
}

/// Sport definition with all metadata
class SportDefinition {
  final SportId id;
  final String label;
  final String labelShort;
  final GradeSystem gradeSystem;
  final bool supportsKids;
  final bool supportsStripes;
  final List<GradeDefinition> adultGrades;
  final List<GradeDefinition>? kidsGrades;
  final IconData icon;

  const SportDefinition({
    required this.id,
    required this.label,
    required this.labelShort,
    required this.gradeSystem,
    required this.supportsKids,
    required this.supportsStripes,
    required this.adultGrades,
    this.kidsGrades,
    required this.icon,
  });
}

// ============================================
// BJJ Adult Grades
// ============================================
const _bjjAdultGrades = [
  GradeDefinition(id: 'white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 4),
  GradeDefinition(id: 'blue', label: 'Azul', color: Color(0xFF1E40AF), maxStripes: 4),
  GradeDefinition(id: 'purple', label: 'Roxa', color: Color(0xFF7C3AED), maxStripes: 4),
  GradeDefinition(id: 'brown', label: 'Marrom', color: Color(0xFF78350F), maxStripes: 4),
  GradeDefinition(id: 'black', label: 'Preta', color: Color(0xFF171717), maxStripes: 4, isBlackBelt: true),
];

// ============================================
// BJJ Kids Grades
// ============================================
const _bjjKidsGrades = [
  GradeDefinition(id: 'white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'grey', label: 'Cinza', color: Color(0xFF6B7280), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'grey-white', label: 'Cinza/Branca', color: Color(0xFF6B7280), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'grey-black', label: 'Cinza/Preta', color: Color(0xFF6B7280), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'yellow', label: 'Amarela', color: Color(0xFFEAB308), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'yellow-white', label: 'Amarela/Branca', color: Color(0xFFEAB308), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'yellow-black', label: 'Amarela/Preta', color: Color(0xFFEAB308), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'orange', label: 'Laranja', color: Color(0xFFEA580C), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'orange-white', label: 'Laranja/Branca', color: Color(0xFFEA580C), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'orange-black', label: 'Laranja/Preta', color: Color(0xFFEA580C), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'green', label: 'Verde', color: Color(0xFF16A34A), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'green-white', label: 'Verde/Branca', color: Color(0xFF16A34A), maxStripes: 4, kidsOnly: true),
  GradeDefinition(id: 'green-black', label: 'Verde/Preta', color: Color(0xFF16A34A), maxStripes: 4, kidsOnly: true),
];

// ============================================
// Muay Thai Grades (Armbands / Prajied)
// ============================================
const _muaythaiGrades = [
  GradeDefinition(id: 'white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 1),
  GradeDefinition(id: 'red', label: 'Vermelha', color: Color(0xFFDC2626), maxStripes: 1),
  GradeDefinition(id: 'light-blue', label: 'Azul Clara', color: Color(0xFF60A5FA), maxStripes: 1),
  GradeDefinition(id: 'dark-blue', label: 'Azul Escura', color: Color(0xFF1E40AF), maxStripes: 1),
  GradeDefinition(id: 'black', label: 'Preta', color: Color(0xFF171717), maxStripes: 2, isBlackBelt: true),
];

// ============================================
// Karate Grades
// ============================================
const _karateGrades = [
  GradeDefinition(id: 'white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 1),
  GradeDefinition(id: 'yellow', label: 'Amarela', color: Color(0xFFEAB308), maxStripes: 1),
  GradeDefinition(id: 'orange', label: 'Laranja', color: Color(0xFFEA580C), maxStripes: 1),
  GradeDefinition(id: 'green', label: 'Verde', color: Color(0xFF16A34A), maxStripes: 1),
  GradeDefinition(id: 'blue', label: 'Azul', color: Color(0xFF1E40AF), maxStripes: 1),
  GradeDefinition(id: 'purple', label: 'Roxa', color: Color(0xFF7C3AED), maxStripes: 1),
  GradeDefinition(id: 'brown', label: 'Marrom', color: Color(0xFF78350F), maxStripes: 1),
  GradeDefinition(id: 'black', label: 'Preta', color: Color(0xFF171717), maxStripes: 4, isBlackBelt: true),
];

// ============================================
// Judo Grades
// ============================================
const _judoGrades = [
  GradeDefinition(id: 'white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 0),
  GradeDefinition(id: 'grey', label: 'Cinza', color: Color(0xFF6B7280), maxStripes: 0),
  GradeDefinition(id: 'blue', label: 'Azul', color: Color(0xFF1E40AF), maxStripes: 0),
  GradeDefinition(id: 'yellow', label: 'Amarela', color: Color(0xFFEAB308), maxStripes: 0),
  GradeDefinition(id: 'orange', label: 'Laranja', color: Color(0xFFEA580C), maxStripes: 0),
  GradeDefinition(id: 'green', label: 'Verde', color: Color(0xFF16A34A), maxStripes: 0),
  GradeDefinition(id: 'purple', label: 'Roxa', color: Color(0xFF7C3AED), maxStripes: 0),
  GradeDefinition(id: 'brown', label: 'Marrom', color: Color(0xFF78350F), maxStripes: 0),
  GradeDefinition(id: 'black', label: 'Preta', color: Color(0xFF171717), maxStripes: 0, isBlackBelt: true),
  GradeDefinition(id: 'coral', label: 'Coral', color: Color(0xFFE11D48), maxStripes: 0),
];

// ============================================
// Kickboxing Grades
// ============================================
const _kickboxingGrades = [
  GradeDefinition(id: 'white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 1),
  GradeDefinition(id: 'yellow', label: 'Amarela', color: Color(0xFFEAB308), maxStripes: 1),
  GradeDefinition(id: 'orange', label: 'Laranja', color: Color(0xFFEA580C), maxStripes: 1),
  GradeDefinition(id: 'green', label: 'Verde', color: Color(0xFF16A34A), maxStripes: 1),
  GradeDefinition(id: 'blue', label: 'Azul', color: Color(0xFF1E40AF), maxStripes: 1),
  GradeDefinition(id: 'brown', label: 'Marrom', color: Color(0xFF78350F), maxStripes: 1),
  GradeDefinition(id: 'black', label: 'Preta', color: Color(0xFF171717), maxStripes: 4, isBlackBelt: true),
];

// ============================================
// Luta Livre Grades (FNLL)
// ============================================
const _lutalivreGrades = [
  GradeDefinition(id: 'white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 4),
  GradeDefinition(id: 'yellow', label: 'Amarela', color: Color(0xFFFBBF24), maxStripes: 4),
  GradeDefinition(id: 'orange', label: 'Laranja', color: Color(0xFFF97316), maxStripes: 4),
  GradeDefinition(id: 'green', label: 'Verde', color: Color(0xFF16A34A), maxStripes: 4),
  GradeDefinition(id: 'blue', label: 'Azul', color: Color(0xFF1E40AF), maxStripes: 4),
  GradeDefinition(id: 'purple', label: 'Roxa', color: Color(0xFF7C3AED), maxStripes: 4),
  GradeDefinition(id: 'brown', label: 'Marrom', color: Color(0xFF78350F), maxStripes: 4),
  GradeDefinition(id: 'black', label: 'Preta', color: Color(0xFF171717), maxStripes: 4, isBlackBelt: true),
];

// ============================================
// Sports Registry
// ============================================
const Map<SportId, SportDefinition> sports = {
  SportId.bjj: SportDefinition(
    id: SportId.bjj,
    label: 'Jiu-Jitsu Brasileiro',
    labelShort: 'BJJ',
    gradeSystem: GradeSystem.belt,
    supportsKids: true,
    supportsStripes: true,
    adultGrades: _bjjAdultGrades,
    kidsGrades: _bjjKidsGrades,
    icon: Icons.shield_outlined,
  ),
  SportId.muaythai: SportDefinition(
    id: SportId.muaythai,
    label: 'Muay Thai',
    labelShort: 'MT',
    gradeSystem: GradeSystem.armband,
    supportsKids: false,
    supportsStripes: true,
    adultGrades: _muaythaiGrades,
    icon: Icons.flash_on_outlined,
  ),
  SportId.karate: SportDefinition(
    id: SportId.karate,
    label: 'Karate',
    labelShort: 'KRT',
    gradeSystem: GradeSystem.belt,
    supportsKids: false,
    supportsStripes: true,
    adultGrades: _karateGrades,
    icon: Icons.shield_outlined,
  ),
  SportId.judo: SportDefinition(
    id: SportId.judo,
    label: 'Judo',
    labelShort: 'JDO',
    gradeSystem: GradeSystem.belt,
    supportsKids: false,
    supportsStripes: false,
    adultGrades: _judoGrades,
    icon: Icons.people_outlined,
  ),
  SportId.kickboxing: SportDefinition(
    id: SportId.kickboxing,
    label: 'Kickboxing',
    labelShort: 'KB',
    gradeSystem: GradeSystem.belt,
    supportsKids: false,
    supportsStripes: true,
    adultGrades: _kickboxingGrades,
    icon: Icons.sports_mma_outlined,
  ),
  SportId.boxing: SportDefinition(
    id: SportId.boxing,
    label: 'Boxe',
    labelShort: 'BOX',
    gradeSystem: GradeSystem.none,
    supportsKids: false,
    supportsStripes: false,
    adultGrades: [],
    icon: Icons.sports_mma_outlined,
  ),
  SportId.lutalivre: SportDefinition(
    id: SportId.lutalivre,
    label: 'Luta Livre',
    labelShort: 'LL',
    gradeSystem: GradeSystem.belt,
    supportsKids: false,
    supportsStripes: true,
    adultGrades: _lutalivreGrades,
    icon: Icons.sports_kabaddi_outlined,
  ),
  // Musculação has no graduation system (GradeSystem.none) and no class
  // schedule — check-in and display are handled differently from martial arts.
  SportId.musculacao: SportDefinition(
    id: SportId.musculacao,
    label: 'Musculação',
    labelShort: 'MUSC',
    gradeSystem: GradeSystem.none,
    supportsKids: false,
    supportsStripes: false,
    adultGrades: [],
    icon: Icons.fitness_center,
  ),
};

/// Ordered list for dropdowns/selectors
const List<SportId> sportOptions = [
  SportId.bjj,
  SportId.muaythai,
  SportId.karate,
  SportId.judo,
  SportId.kickboxing,
  SportId.boxing,
  SportId.lutalivre,
  SportId.musculacao,
];

// ============================================
// Helper: Get sport definition
// ============================================
SportDefinition getSport(SportId sportId) {
  return sports[sportId]!;
}

// ============================================
// Helper: Get grades for a sport (respects kids)
// ============================================
List<GradeDefinition> getGradesForSport(SportId sportId, {String category = 'adult'}) {
  final sport = sports[sportId]!;
  if (category == 'kids' && sport.supportsKids && sport.kidsGrades != null) {
    return sport.kidsGrades!;
  }
  return sport.adultGrades;
}

// ============================================
// Helper: Get grade label for a sport
// ============================================
String getGradeLabel(SportId sportId, String gradeId) {
  final sport = sports[sportId]!;
  final allGrades = [...sport.adultGrades, ...(sport.kidsGrades ?? [])];
  final grade = allGrades.where((g) => g.id == gradeId).firstOrNull;
  return grade?.label ?? gradeId;
}

// ============================================
// Helper: Get grade color for a sport
// ============================================
Color getGradeColor(SportId sportId, String gradeId) {
  final sport = sports[sportId]!;
  final allGrades = [...sport.adultGrades, ...(sport.kidsGrades ?? [])];
  final grade = allGrades.where((g) => g.id == gradeId).firstOrNull;
  if (grade != null) return grade.color;
  // Fallback: extract base color for compound grade ids (e.g. 'grey-white')
  final basePart = gradeId.split('-').first;
  final baseGrade = allGrades.where((g) => g.id == basePart).firstOrNull;
  return baseGrade?.color ?? const Color(0xFFF5F5F5);
}

// ============================================
// Helper: Get grade definition
// ============================================
GradeDefinition? getGradeDefinition(SportId sportId, String gradeId) {
  final sport = sports[sportId]!;
  final allGrades = [...sport.adultGrades, ...(sport.kidsGrades ?? [])];
  return allGrades.where((g) => g.id == gradeId).firstOrNull;
}

// ============================================
// Sport chip colors (for SportChip widget)
// ============================================
const Map<SportId, Color> sportChipColors = {
  SportId.bjj: Color(0xFF1E40AF),
  SportId.muaythai: Color(0xFFDC2626),
  SportId.karate: Color(0xFF7C3AED),
  SportId.judo: Color(0xFF16A34A),
  SportId.kickboxing: Color(0xFFEA580C),
  SportId.boxing: Color(0xFF171717),
  SportId.lutalivre: Color(0xFF0891B2),
  SportId.musculacao: Color(0xFF475569),
};
