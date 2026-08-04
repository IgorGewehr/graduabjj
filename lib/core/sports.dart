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
  musculacao,
  // MMA has no universal belt system — tracked as a presence/check-in modality
  // (GradeSystem.none), like boxing/musculacao. Appended last so the .index of
  // existing values never shifts.
  mma;

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
  /// Master ranks above the black belt (coral / red). These are time- and
  /// honor-based (decades), so attendance-based auto-graduation must NOT reach
  /// them — they're only awarded via manual promotion by the mestre.
  final bool aboveBlack;

  const GradeDefinition({
    required this.id,
    required this.label,
    required this.color,
    this.tipColor,
    required this.maxStripes,
    this.isBlackBelt = false,
    this.kidsOnly = false,
    this.adultOnly = false,
    this.aboveBlack = false,
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

  /// Unidade de SPARRING deste esporte, no plural, minúsculo (ex.: 'rolas'
  /// p/ BJJ; 'rounds' p/ striking; 'randoris' p/ judô). `null` quando o esporte
  /// não tem sparring (musculação) — nesse caso o log vira check-in simples.
  /// Multi-modal por design: nada de terminologia fixa de jiu.
  final String? sparringNoun;

  /// Mesma unidade no singular (ex.: 'rola', 'round', 'randori'). `null` quando
  /// [sparringNoun] é `null`.
  final String? sparringNounSingular;

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
    this.sparringNoun,
    this.sparringNounSingular,
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
  GradeDefinition(id: 'black', label: 'Preta', color: Color(0xFF171717), maxStripes: 6, isBlackBelt: true),
  // Above black (manual/honorary only — décadas de faixa preta):
  GradeDefinition(id: 'red-black', label: 'Coral (7º grau)', color: Color(0xFFDC2626), tipColor: Color(0xFF171717), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
  GradeDefinition(id: 'red-white', label: 'Coral Vermelha e Branca (8º grau)', color: Color(0xFFDC2626), tipColor: Color(0xFFF5F5F5), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
  GradeDefinition(id: 'red', label: 'Vermelha (9º/10º grau)', color: Color(0xFFDC2626), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
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
//
// Muay Thai has no single official graduation — each federation defines its
// own. We ship the two most common Brazilian systems and let each academy
// pick one in Settings (see [AcademySettings.muaythaiGradeSystem]).
//
// IDs are kept DISTINCT across both systems so a stored grade always resolves
// to the right list, and lookups (label/color/definition) search both. The
// CBMT ids preserve the previous simplified ones (white/red/light-blue/
// dark-blue/black) so existing students are never orphaned.
// ============================================

/// Muay Thai grade-system identifiers (stored in academy settings).
const String muaythaiVariantCbmt = 'cbmt'; // azul system (default / legacy)
const String muaythaiVariantCbmtt = 'cbmtt'; // tradicional (branca→ouro)

/// System 1 — CBMT / CMTB (white → red → blue → black, with "ponta" steps).
// Muay Thai progride por COR do prajied (braçadeira), não por graus dentro da
// cor — por isso maxStripes: 0 em todos (igual ao judô). As etapas "ponta" já
// são cores próprias na escada.
const _muaythaiGradesCbmt = [
  GradeDefinition(id: 'white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 0),
  GradeDefinition(id: 'white-red', label: 'Branca ponta vermelha', color: Color(0xFFF5F5F5), tipColor: Color(0xFFDC2626), maxStripes: 0),
  GradeDefinition(id: 'red', label: 'Vermelha', color: Color(0xFFDC2626), maxStripes: 0),
  GradeDefinition(id: 'red-lightblue', label: 'Vermelha ponta azul clara', color: Color(0xFFDC2626), tipColor: Color(0xFF60A5FA), maxStripes: 0),
  GradeDefinition(id: 'light-blue', label: 'Azul Clara', color: Color(0xFF60A5FA), maxStripes: 0),
  GradeDefinition(id: 'lightblue-darkblue', label: 'Azul Clara ponta azul escura (Monitor)', color: Color(0xFF60A5FA), tipColor: Color(0xFF1E40AF), maxStripes: 0),
  GradeDefinition(id: 'dark-blue', label: 'Azul Escura (Instrutor Auxiliar)', color: Color(0xFF1E40AF), maxStripes: 0),
  GradeDefinition(id: 'darkblue-black', label: 'Azul Escura ponta preta (Instrutor)', color: Color(0xFF1E40AF), tipColor: Color(0xFF171717), maxStripes: 0),
  GradeDefinition(id: 'black', label: 'Preta (Professor)', color: Color(0xFF171717), maxStripes: 0, isBlackBelt: true),
  GradeDefinition(id: 'black-white', label: 'Preta ponta branca (Mestre)', color: Color(0xFF171717), tipColor: Color(0xFFF5F5F5), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
  GradeDefinition(id: 'black-white-red', label: 'Preta ponta branca e vermelha (Grão-Mestre)', color: Color(0xFF171717), tipColor: Color(0xFFDC2626), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
];

/// System 2 — CBMT Tradicional / CBMTT (white → ... → gold). IDs prefixed
/// `mt2-` to stay distinct from the CBMT system above.
const _muaythaiGradesCbmtt = [
  GradeDefinition(id: 'mt2-white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 0),
  GradeDefinition(id: 'mt2-yellow', label: 'Amarela', color: Color(0xFFEAB308), maxStripes: 0),
  GradeDefinition(id: 'mt2-yellow-white', label: 'Amarela e Branca', color: Color(0xFFEAB308), tipColor: Color(0xFFF5F5F5), maxStripes: 0),
  GradeDefinition(id: 'mt2-green', label: 'Verde', color: Color(0xFF16A34A), maxStripes: 0),
  GradeDefinition(id: 'mt2-green-white', label: 'Verde e Branca', color: Color(0xFF16A34A), tipColor: Color(0xFFF5F5F5), maxStripes: 0),
  GradeDefinition(id: 'mt2-blue', label: 'Azul', color: Color(0xFF1E40AF), maxStripes: 0),
  GradeDefinition(id: 'mt2-blue-white', label: 'Azul e Branca', color: Color(0xFF1E40AF), tipColor: Color(0xFFF5F5F5), maxStripes: 0),
  GradeDefinition(id: 'mt2-brown', label: 'Marrom', color: Color(0xFF78350F), maxStripes: 0),
  GradeDefinition(id: 'mt2-brown-white', label: 'Marrom e Branca', color: Color(0xFF78350F), tipColor: Color(0xFFF5F5F5), maxStripes: 0),
  GradeDefinition(id: 'mt2-red', label: 'Vermelha', color: Color(0xFFDC2626), maxStripes: 0),
  GradeDefinition(id: 'mt2-red-white', label: 'Vermelha e Branca', color: Color(0xFFDC2626), tipColor: Color(0xFFF5F5F5), maxStripes: 0),
  GradeDefinition(id: 'mt2-black', label: 'Preta', color: Color(0xFF171717), maxStripes: 0, isBlackBelt: true),
  GradeDefinition(id: 'mt2-black-white', label: 'Preta e Branca (Professor)', color: Color(0xFF171717), tipColor: Color(0xFFF5F5F5), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
  GradeDefinition(id: 'mt2-silver', label: 'Prata', color: Color(0xFF94A3B8), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
  GradeDefinition(id: 'mt2-gold', label: 'Ouro', color: Color(0xFFD4AF37), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
  GradeDefinition(id: 'mt2-gold-silver', label: 'Ouro e Prata', color: Color(0xFFD4AF37), tipColor: Color(0xFF94A3B8), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
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
  GradeDefinition(id: 'black', label: 'Preta', color: Color(0xFF171717), maxStripes: 10, isBlackBelt: true),
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
  // Above black (manual only): coral kōhaku (6º–8º dan) → vermelha (9º–10º dan).
  GradeDefinition(id: 'coral', label: 'Coral (6º–8º dan)', color: Color(0xFFDC2626), tipColor: Color(0xFFF5F5F5), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
  GradeDefinition(id: 'red', label: 'Vermelha (9º–10º dan)', color: Color(0xFFDC2626), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
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
  GradeDefinition(id: 'black', label: 'Preta', color: Color(0xFF171717), maxStripes: 10, isBlackBelt: true),
];

// ============================================
// Luta Livre Grades (CBLLE — Confederação Brasileira de Luta Livre Esportiva)
// Progressão por cor: Branca → Amarela → Laranja → Preta (Professor). Pós-preta
// é DAN (manual, ~1 a cada 5 anos): preta ponta vermelha → vermelha e branca.
// ============================================
const _lutalivreGrades = [
  GradeDefinition(id: 'white', label: 'Branca', color: Color(0xFFF5F5F5), maxStripes: 0),
  GradeDefinition(id: 'yellow', label: 'Amarela', color: Color(0xFFFBBF24), maxStripes: 0),
  GradeDefinition(id: 'orange', label: 'Laranja', color: Color(0xFFF97316), maxStripes: 0),
  GradeDefinition(id: 'black', label: 'Preta (Professor)', color: Color(0xFF171717), maxStripes: 0, isBlackBelt: true),
  // DAN (manual, ~5 em 5 anos): preta ponta vermelha → vermelha e branca.
  GradeDefinition(id: 'black-red', label: 'Preta ponta vermelha (DAN)', color: Color(0xFF171717), tipColor: Color(0xFFDC2626), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
  GradeDefinition(id: 'red-white', label: 'Vermelha e Branca', color: Color(0xFFDC2626), tipColor: Color(0xFFF5F5F5), maxStripes: 0, isBlackBelt: true, aboveBlack: true),
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
    sparringNoun: 'rolas',
    sparringNounSingular: 'rola',
  ),
  SportId.muaythai: SportDefinition(
    id: SportId.muaythai,
    label: 'Muay Thai',
    labelShort: 'MT',
    gradeSystem: GradeSystem.armband,
    supportsKids: false,
    supportsStripes: true,
    adultGrades: _muaythaiGradesCbmt,
    icon: Icons.flash_on_outlined,
    sparringNoun: 'rounds',
    sparringNounSingular: 'round',
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
    sparringNoun: 'kumites',
    sparringNounSingular: 'kumite',
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
    sparringNoun: 'randoris',
    sparringNounSingular: 'randori',
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
    sparringNoun: 'rounds',
    sparringNounSingular: 'round',
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
    sparringNoun: 'rounds',
    sparringNounSingular: 'round',
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
    sparringNoun: 'rolas',
    sparringNounSingular: 'rola',
  ),
  // MMA — no universal graduation. Presence/check-in modality only (like boxe).
  SportId.mma: SportDefinition(
    id: SportId.mma,
    label: 'MMA',
    labelShort: 'MMA',
    gradeSystem: GradeSystem.none,
    supportsKids: false,
    supportsStripes: false,
    adultGrades: [],
    icon: Icons.sports_mma_outlined,
    sparringNoun: 'rounds',
    sparringNounSingular: 'round',
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
  SportId.mma,
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
// Helper: Unidade de SPARRING por esporte (multi-modal)
// ============================================
/// Retorna a unidade de sparring do esporte — `(one: singular, many: plural)`,
/// minúsculo. `null` quando o esporte NÃO tem sparring (musculação): nesse caso
/// o logger vira um check-in "TREINEI" simples, sem número.
///
/// Ex.: `sparringUnit(SportId.bjj)` → `(one:'rola', many:'rolas')`;
///      `sparringUnit(SportId.muaythai)` → `(one:'round', many:'rounds')`.
///
/// A UI escolhe singular/plural pelo count e faz `.toUpperCase()`
/// (ex.: `count == 1 ? unit.one : unit.many` → "5 ROLAS", "1 ROUND").
({String one, String many})? sparringUnit(SportId sportId) {
  final s = sports[sportId]!;
  final many = s.sparringNoun;
  final one = s.sparringNounSingular;
  if (many == null || one == null) return null;
  return (one: one, many: many);
}

/// Termo de sparring já flexionado pelo [count] (default plural). Conveniência
/// sobre [sparringUnit]. Retorna `null` para esportes sem sparring.
/// Ex.: `getSparringTerm(SportId.bjj, count: 1)` → 'rola'.
String? getSparringTerm(SportId sportId, {int count = 2}) {
  final u = sparringUnit(sportId);
  if (u == null) return null;
  return count == 1 ? u.one : u.many;
}

// ============================================
// Helper: Get grades for a sport (respects kids)
//
// For Muay Thai, [muaythaiVariant] selects which federation ladder to return
// (defaults to CBMT). When building a grade selector for an EXISTING grade,
// resolve the variant from that grade id with [resolveMuaythaiVariant] so the
// dropdown matches what the student already has, even if the academy later
// switched its default system.
// ============================================
List<GradeDefinition> getGradesForSport(
  SportId sportId, {
  String category = 'adult',
  String? muaythaiVariant,
}) {
  final sport = sports[sportId]!;
  if (sportId == SportId.muaythai) {
    return muaythaiVariant == muaythaiVariantCbmtt
        ? _muaythaiGradesCbmtt
        : _muaythaiGradesCbmt;
  }
  if (category == 'kids' && sport.supportsKids && sport.kidsGrades != null) {
    return sport.kidsGrades!;
  }
  return sport.adultGrades;
}

// ============================================
// Helper: Which Muay Thai system a grade id belongs to
// ============================================
/// Returns [muaythaiVariantCbmtt] when [gradeId] is part of the CBMTT ladder,
/// otherwise [muaythaiVariantCbmt]. Lets progression/selectors pick the right
/// ladder straight from a stored grade, no academy lookup needed.
String resolveMuaythaiVariant(String gradeId) {
  return _muaythaiGradesCbmtt.any((g) => g.id == gradeId)
      ? muaythaiVariantCbmtt
      : muaythaiVariantCbmt;
}

// ============================================
// Helper: All grades searchable for label/color lookups
// ============================================
/// Every grade definition whose id could be stored for [sportId]. For Muay
/// Thai this spans BOTH federation systems so a grade still resolves after the
/// academy switches its default. Other sports use adult + kids grades.
List<GradeDefinition> _searchableGrades(SportDefinition sport) {
  if (sport.id == SportId.muaythai) {
    return const [..._muaythaiGradesCbmt, ..._muaythaiGradesCbmtt];
  }
  return [...sport.adultGrades, ...(sport.kidsGrades ?? [])];
}

// ============================================
// Helper: Get grade label for a sport
// ============================================
String getGradeLabel(SportId sportId, String gradeId) {
  final sport = sports[sportId]!;
  final allGrades = _searchableGrades(sport);
  final grade = allGrades.where((g) => g.id == gradeId).firstOrNull;
  return grade?.label ?? gradeId;
}

// ============================================
// Helper: Get grade color for a sport
// ============================================
Color getGradeColor(SportId sportId, String gradeId) {
  final sport = sports[sportId]!;
  final allGrades = _searchableGrades(sport);
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
  final allGrades = _searchableGrades(sport);
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
  SportId.mma: Color(0xFF991B1B),
  SportId.lutalivre: Color(0xFF0891B2),
  SportId.musculacao: Color(0xFF475569),
};
