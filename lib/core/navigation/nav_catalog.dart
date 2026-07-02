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
  evolution, // Evolução    -> AcademySettings.physicalEvolutionEnabled
  booking, // Reservar aula -> AcademySettings.bookingEnabled
  striking, // Trocação      -> AcademySettings.strikingEnabled
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
  multiSport, // só quando o aluno treina +1 modalidade
  multipleAcademies, // só quando o aluno pertence a +1 academia
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

  /// Requires the academy to have Mercado Pago connected (AcademySettings
  /// .mpConnected). Not satisfied => `hidden`. Used by admin_assinaturas: sem MP
  /// o professor não recebe pelo app, então o item de assinaturas não faz
  /// sentido. Independe de feature/permissão (são checados em conjunto).
  final bool requiresMpConnected;

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
    this.requiresMpConnected = false,
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
    requiresAnyPermission: [
      'students:create',
      'students:edit',
      'students:delete',
      'students:manage',
    ],
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
    key: 'admin_social',
    label: 'Social',
    icon: LucideIcons.flame,
    route: '/admin/social',
    section: NavSection.gestao,
    // No feature gate: rankingVisibleToStudents só controla a visão do ALUNO.
    // Sem requiresPermission/adminOnly: professor (instrutor) E admin veem o
    // ranking E a atividade (com moderação) dos seus alunos.
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
    // Auditoria jornal/eventos: NÃO gatear por FeatureId.journal — essa flag
    // (journalVisibleToStudents) controla só a visão do ALUNO; gateá-la aqui
    // travava o próprio staff de GERIR o jornal ao escondê-lo dos alunos (o
    // cenário de rascunho onde a gestão é mais necessária). Gateado só por
    // papel/permissão, espelhando admin_ranking.
    requiresPermission: 'events:manage',
    adminBypassesPermission: true,
  ),
  NavEntry(
    key: 'admin_financeiro',
    label: 'Financeiro',
    icon: LucideIcons.dollarSign,
    route: '/admin/financeiro',
    section: NavSection.financeiro,
    requiresPermission: 'financial:view',
    adminBypassesPermission: false,
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
    key: 'admin_assinaturas',
    label: 'Assinaturas',
    icon: LucideIcons.repeat,
    route: '/admin/assinaturas',
    section: NavSection.financeiro,
    requiresPermission: 'financial:view',
    adminBypassesPermission: false,
    // Sem Mercado Pago conectado o professor não recebe pelo app, então o item
    // de Assinaturas desaparece do menu (não há recorrência a gerir).
    requiresMpConnected: true,
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
    key: 'admin_combinacoes',
    label: 'Combinações',
    icon: Icons.sports_mma_outlined,
    route: '/admin/combinacoes',
    section: NavSection.conteudo,
    feature: FeatureId.striking,
  ),
  NavEntry(
    key: 'admin_periodizacao',
    label: 'Periodização',
    icon: LucideIcons.calendarRange,
    route: '/admin/periodizacao',
    section: NavSection.conteudo,
    feature: FeatureId.workouts,
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
    feature: FeatureId.evolution,
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
    portalGate: PortalContextGate.multiSport,
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
    key: 'portal_trocacao',
    label: 'Trocação',
    icon: Icons.sports_mma_outlined,
    route: '/portal/trocacao',
    section: NavSection.treinos,
    feature: FeatureId.striking,
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
    // Auditoria menu: gateado por storeEnabled (feature) E storePublished
    // (portalGate). Antes só checava published, então uma loja desligada com
    // published obsoleto=true ainda vazava para o aluno.
    feature: FeatureId.store,
    portalGate: PortalContextGate.storePublished,
  ),
  NavEntry(
    key: 'portal_academias',
    label: 'Academias',
    icon: LucideIcons.school,
    route: '/portal/academias',
    section: NavSection.conta,
    portalGate: PortalContextGate.multipleAcademies,
  ),
];
