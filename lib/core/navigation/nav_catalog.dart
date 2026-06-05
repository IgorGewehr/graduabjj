import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Canonical feature ids used by both the navigation gate and the
/// deep-link/highlight mechanism. Every gateable [NavEntry] references one.
enum FeatureId {
  store, // Loja            -> AcademySettings.storeEnabled
  ranking, // Ranking       -> AcademySettings.rankingVisibleToStudents
  journal, // Jornal        -> AcademySettings.journalVisibleToStudents
  graduation, // Graduação  -> AcademySettings.autoGraduationEnabled
  payments, // Mercado Pago -> AcademySettings.isPaymentEnabled
  musculacao, // Musculação -> AcademySettings.musculacaoEnabled
  workouts, // Treinos      -> AcademySettings.workoutPlansEnabled
  videos, // Vídeos         -> AcademySettings.trainingVideosEnabled
  booking, // Reservar aula -> AcademySettings.bookingEnabled
}

extension FeatureIdX on FeatureId {
  /// Stable id used in the deep-link query string (`?feature=<id>`).
  /// MUST match [FeatureId.name] (store, ranking, journal, graduation,
  /// payments, musculacao, workouts, videos).
  String get id => name;

  static FeatureId? fromId(String? raw) => raw == null
      ? null
      : FeatureId.values.firstWhereOrNull((f) => f.name == raw);
}

/// Navigation sections. The displayed (UPPERCASE) label comes from [label].
enum NavSection {
  // Admin
  gestao('Gestão'),
  financeiro('Financeiro'),
  conteudo('Conteúdo'),
  conta('Conta'),
  // Portal
  treinos('Treinos'),
  comunidade('Comunidade'),
  conquistas('Conquistas');
  // (portal also reuses `conta`)

  final String label;
  const NavSection(this.label);
}

/// Portal context gates that do not derive from AcademySettings.
/// Evaluated by the portal resolver. null = no requirement.
enum PortalContextGate {
  kidsOnly, // requiresKidsCategory
  hasPlan, // requiresPlan
  storePublished, // requiresStorePublished
  hideForMonitor, // hideWhen == monitor
}

@immutable
class NavEntry {
  /// Stable identity of the entry (for keys/diagnostics). E.g.: 'admin_loja'.
  final String key;
  final String label;

  /// Primary icon (prefer Lucide). Material only where Lucide has no match.
  final IconData icon;

  /// Optional active icon (used only by the desktop sidebar, which swaps
  /// outlined<->filled). When null, [icon] is used for both states.
  final IconData? activeIcon;

  /// go_router destination route (e.g.: '/admin/loja').
  final String route;

  final NavSection section;

  /// Feature gate of the entry. null = unconditional entry (Dashboard, Turmas,
  /// Perfil, etc.) — always visible as long as permission/context allow.
  final FeatureId? feature;

  /// When true and [feature] is OFF: the entry does NOT disappear — it becomes
  /// `locked` (discovery). When false (or no feature): OFF => `hidden`.
  /// Only meaningful with [feature] != null.
  final bool lockable;

  /// Required permission (user.hasPermission). null = no requirement.
  /// Not satisfied => `hidden` (never `locked`).
  final String? requiresPermission;

  /// Satisfied if ANY of these permissions is held. null = unused.
  /// Used by admin_alunos (students:create OR students:delete).
  final List<String>? requiresAnyPermission;

  /// If true, user.isAdmin satisfies [requiresPermission]/[requiresAnyPermission]
  /// without the explicit permission. If false, the permission is required even
  /// for admin (preserves the current financial/reports/graduation behavior).
  /// Default true.
  final bool adminBypassesPermission;

  /// Admin only (user.isAdmin). Instructor => `hidden`.
  final bool adminOnly;

  /// Context gate of the portal that does not derive from AcademySettings.
  /// Evaluated by the portal resolver. null = no requirement.
  final PortalContextGate? portalGate;

  const NavEntry({
    required this.key,
    required this.label,
    required this.icon,
    required this.route,
    required this.section,
    this.activeIcon,
    this.feature,
    this.lockable = false,
    this.requiresPermission,
    this.requiresAnyPermission,
    this.adminBypassesPermission = true,
    this.adminOnly = false,
    this.portalGate,
  });
}

enum NavEntryState { visible, locked, hidden }

@immutable
class ResolvedNavEntry {
  final NavEntry entry;
  final NavEntryState state;
  const ResolvedNavEntry(this.entry, this.state);

  bool get isVisible => state == NavEntryState.visible;
  bool get isLocked => state == NavEntryState.locked;
  bool get isHidden => state == NavEntryState.hidden;
}

/// Deep-link to Settings > Funcionalidades, scrolling to and highlighting the
/// card that backs [f].
String settingsDeepLinkFor(FeatureId f) =>
    '/admin/configuracoes?feature=${f.id}';

/// Admin navigation catalog — single source of truth for the sidebar (desktop)
/// and the mobile "Mais"/sheet menu. Order within a section = declaration order.
const List<NavEntry> kAdminNavCatalog = <NavEntry>[
  NavEntry(
    key: 'admin_dashboard',
    label: 'Dashboard',
    icon: LucideIcons.layoutDashboard,
    route: '/admin',
    section: NavSection.gestao,
  ),
  NavEntry(
    key: 'admin_alunos',
    label: 'Alunos',
    icon: LucideIcons.users,
    route: '/admin/alunos',
    section: NavSection.gestao,
    requiresAnyPermission: ['students:create', 'students:delete'],
  ),
  NavEntry(
    key: 'admin_chamada',
    label: 'Chamada',
    icon: LucideIcons.clipboardCheck,
    route: '/admin/chamada',
    section: NavSection.gestao,
    requiresPermission: 'attendance:take',
  ),
  NavEntry(
    key: 'admin_turmas',
    label: 'Turmas',
    icon: LucideIcons.calendar,
    route: '/admin/turmas',
    section: NavSection.gestao,
  ),
  NavEntry(
    key: 'admin_reservas',
    label: 'Reservas',
    icon: LucideIcons.calendarCheck,
    route: '/admin/reservas',
    section: NavSection.gestao,
    feature: FeatureId.booking,
  ),
  NavEntry(
    key: 'admin_graduacao',
    label: 'Graduação',
    icon: LucideIcons.award,
    route: '/admin/graduacao',
    section: NavSection.gestao,
    feature: FeatureId.graduation,
    lockable: true,
    requiresPermission: 'graduation:manage',
    adminBypassesPermission: false,
  ),
  NavEntry(
    key: 'admin_campeonatos',
    label: 'Campeonatos',
    icon: LucideIcons.trophy,
    route: '/admin/campeonatos',
    section: NavSection.gestao,
    requiresPermission: 'competitions:create',
  ),
  NavEntry(
    key: 'admin_musculacao',
    label: 'Musculação',
    icon: Icons.fitness_center,
    route: '/admin/musculacao',
    section: NavSection.gestao,
    feature: FeatureId.musculacao,
    lockable: false,
  ),
  NavEntry(
    key: 'admin_jornal',
    label: 'Jornal da Academia',
    icon: LucideIcons.newspaper,
    route: '/admin/jornal',
    section: NavSection.gestao,
    feature: FeatureId.journal,
    lockable: true,
    requiresPermission: 'events:manage',
    adminBypassesPermission: false,
  ),
  NavEntry(
    key: 'admin_importar',
    label: 'Importar alunos',
    icon: Icons.upload_file,
    route: '/admin/importar-alunos',
    section: NavSection.gestao,
  ),
  NavEntry(
    key: 'admin_cobranca',
    label: 'Cobrança',
    icon: LucideIcons.receipt,
    route: '/admin/cobranca',
    section: NavSection.financeiro,
    requiresPermission: 'financial:view',
    adminBypassesPermission: false,
  ),
  NavEntry(
    key: 'admin_relatorios',
    label: 'Relatórios',
    icon: LucideIcons.barChart3,
    route: '/admin/relatorios',
    section: NavSection.financeiro,
    requiresPermission: 'reports:view',
    adminBypassesPermission: false,
  ),
  NavEntry(
    key: 'admin_treinos',
    label: 'Treinos',
    icon: Icons.assignment_outlined,
    route: '/admin/treinos',
    section: NavSection.conteudo,
    feature: FeatureId.workouts,
    lockable: true,
  ),
  NavEntry(
    key: 'admin_videos',
    label: 'Vídeos',
    icon: Icons.play_circle_outline,
    route: '/admin/videos',
    section: NavSection.conteudo,
    feature: FeatureId.videos,
    lockable: true,
  ),
  NavEntry(
    key: 'admin_loja',
    label: 'Loja',
    icon: LucideIcons.store,
    route: '/admin/loja',
    section: NavSection.conteudo,
    feature: FeatureId.store,
    lockable: true,
  ),
  NavEntry(
    key: 'admin_config',
    label: 'Configurações',
    icon: LucideIcons.settings,
    route: '/admin/configuracoes',
    section: NavSection.conta,
    adminOnly: true,
  ),
  NavEntry(
    key: 'admin_codigo_equipe',
    label: 'Código de equipe',
    icon: LucideIcons.key,
    route: '/codigo-equipe',
    section: NavSection.conta,
    adminOnly: true,
  ),
];

/// Portal navigation catalog — single source of truth for the portal sheet
/// menu. Gate model is simple (OFF/context-not-met => hidden); the portal never
/// shows `locked` entries. Ranking uses `medal` to avoid colliding with the
/// `trophy` of Competições.
const List<NavEntry> kPortalNavCatalog = <NavEntry>[
  NavEntry(
    key: 'portal_horarios',
    label: 'Horários',
    icon: LucideIcons.calendar,
    route: '/portal/horarios',
    section: NavSection.treinos,
    portalGate: PortalContextGate.hideForMonitor,
  ),
  NavEntry(
    key: 'portal_presencas',
    label: 'Presenças',
    icon: LucideIcons.clipboardCheck,
    route: '/portal/presencas',
    section: NavSection.treinos,
  ),
  NavEntry(
    key: 'portal_reservas',
    label: 'Reservar aula',
    icon: LucideIcons.calendarCheck,
    route: '/portal/reservas',
    section: NavSection.treinos,
    feature: FeatureId.booking,
    portalGate: PortalContextGate.hideForMonitor,
  ),
  NavEntry(
    key: 'portal_jornada',
    label: 'Jornada',
    icon: LucideIcons.history,
    route: '/portal/linha-do-tempo',
    section: NavSection.treinos,
  ),
  NavEntry(
    key: 'portal_evolucao',
    label: 'Evolução',
    icon: LucideIcons.trendingUp,
    route: '/portal/evolucao',
    section: NavSection.treinos,
  ),
  NavEntry(
    key: 'portal_graduacao',
    label: 'Graduação',
    icon: LucideIcons.award,
    route: '/portal/graduacao',
    section: NavSection.treinos,
  ),
  NavEntry(
    key: 'portal_modalidades',
    label: 'Minhas Modalidades',
    icon: LucideIcons.dumbbell,
    route: '/portal/minhas-modalidades',
    section: NavSection.treinos,
  ),
  NavEntry(
    key: 'portal_treinos',
    label: 'Treinos',
    icon: Icons.assignment_outlined,
    route: '/portal/treinos',
    section: NavSection.treinos,
    feature: FeatureId.workouts,
  ),
  NavEntry(
    key: 'portal_videos',
    label: 'Vídeos',
    icon: Icons.play_circle_outline,
    route: '/portal/videos',
    section: NavSection.treinos,
    feature: FeatureId.videos,
  ),
  NavEntry(
    key: 'portal_ranking',
    label: 'Ranking',
    icon: LucideIcons.medal,
    route: '/portal/ranking',
    section: NavSection.comunidade,
    feature: FeatureId.ranking,
  ),
  NavEntry(
    key: 'portal_competicoes',
    label: 'Competições',
    icon: LucideIcons.trophy,
    route: '/portal/competicoes',
    section: NavSection.conquistas,
  ),
  NavEntry(
    key: 'portal_comportamento',
    label: 'Comportamento',
    icon: LucideIcons.star,
    route: '/portal/comportamento',
    section: NavSection.conquistas,
    portalGate: PortalContextGate.kidsOnly,
  ),
  NavEntry(
    key: 'portal_financeiro',
    label: 'Financeiro',
    icon: LucideIcons.dollarSign,
    route: '/portal/financeiro',
    section: NavSection.conta,
    portalGate: PortalContextGate.hasPlan,
  ),
  NavEntry(
    key: 'portal_loja',
    label: 'Loja',
    icon: LucideIcons.store,
    route: '/portal/loja',
    section: NavSection.conta,
    portalGate: PortalContextGate.storePublished,
  ),
  NavEntry(
    key: 'portal_academias',
    label: 'Academias',
    icon: LucideIcons.school,
    route: '/portal/academias',
    section: NavSection.conta,
  ),
];
