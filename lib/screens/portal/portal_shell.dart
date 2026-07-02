import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/navigation/nav_catalog.dart';
import '../../core/navigation/nav_resolver.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../widgets/common/more_menu_sheet.dart';
import '../../widgets/common/back_button_handler.dart';
import '../../widgets/academy_switcher.dart';
import '../../widgets/update_banner.dart';
import '../../widgets/polish/polish.dart';

/// Portal Shell - Main navigation structure for student portal
class PortalShell extends ConsumerStatefulWidget {
  final Widget child;

  const PortalShell({super.key, required this.child});

  @override
  ConsumerState<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends ConsumerState<PortalShell> {
  // Base bottom-nav items shared by every portal role. The 4th slot below
  // adapts (Chamada for monitors, Horários for students). The last slot is
  // the categorized "Menu" sheet.
  // B2C fighter-first: [ Lutador | Cena | Treinei | Academia | Perfil ].
  // Lutador = identidade portátil (global); Cena = social/descoberta (global);
  // Treinei = a ação central (Diário/check-in); Academia = o ÚNICO contexto de
  // academia (switcher + telas contextuais); Perfil = conta.
  static const _NavItem _lutadorNavItem = _NavItem(
    label: 'Lutador',
    icon: LucideIcons.shield,
    path: '/portal',
  );
  static const _NavItem _cenaNavItem = _NavItem(
    label: 'Galera',
    icon: LucideIcons.users,
    path: '/portal/cena',
  );
  static const _NavItem _treineiNavItem = _NavItem(
    label: 'Treinei',
    icon: LucideIcons.flame,
    path: '/portal/diario',
  );
  static const _NavItem _academiaNavItem = _NavItem(
    label: 'Academia',
    icon: LucideIcons.building2,
    path: '/portal/academia',
  );
  static const _NavItem _profileNavItem = _NavItem(
    label: 'Perfil',
    icon: LucideIcons.user,
    path: '/portal/perfil',
  );

  /// Bottom nav fighter-first (igual para todo papel do portal). Monitores
  /// acessam chamada/alunos pela aba Academia (cockpit) — follow-up.
  List<_NavItem> _bottomNavItemsFor({
    required bool isMonitor,
    required bool hasAttendancePerm,
  }) {
    return const [
      _lutadorNavItem,
      _cenaNavItem,
      _treineiNavItem,
      _academiaNavItem,
      _profileNavItem,
    ];
  }

  int _getSelectedIndex(String location, List<_NavItem> items) {
    for (int i = 0; i < items.length; i++) {
      final path = items[i].path;
      if (path == '/portal') {
        if (location == path) return i;
      } else if (location == path || location.startsWith('$path/')) {
        return i;
      }
    }
    return 0; // default: Lutador
  }

  void _onItemTapped(int index, List<_NavItem> items) {
    context.go(items[index].path);
  }

  Widget _buildAppBarTitle(WidgetRef ref) {
    // Fighter-first: o seletor de academia NÃO vive mais na AppBar global —
    // ele é exclusivo da aba Academia. Cada tab tem seu próprio header.
    return const SizedBox.shrink();
  }

  /// Entradas visíveis do portal (mesmos feature-flags + gates contextuais do
  /// menu "Mais"), usadas pela rail do desktop. Mobile não chama (usa BottomNav).
  List<NavEntry> _resolveVisiblePortalEntries() {
    final student = ref.read(currentStudentProvider).valueOrNull;
    final settings = ref.read(academySettingsProvider).valueOrNull;
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final isKids = student?.category == StudentCategory.kids;
    final studentId = currentUser?.studentId;
    final linkedStudentIds = currentUser?.linkedStudentIds ?? const <String>[];
    final allStudentIds =
        studentId != null ? [studentId, ...linkedStudentIds] : linkedStudentIds;
    final monitorIds = settings?.monitorIds ?? const <String>[];
    final isMonitor = allStudentIds.any(monitorIds.contains);
    final hasAttendancePerm =
        currentUser?.hasPermission('attendance:take') == true;
    final studentDocId = student?.id;
    final hasPlan = studentDocId != null &&
        ref.read(studentPlanProvider(studentDocId)).valueOrNull != null;
    final ctx = PortalNavContext(
      isKids: isKids,
      isMonitorOrAttendance: isMonitor || hasAttendancePerm,
      hasPlan: hasPlan,
      storePublished: settings?.storePublished ?? false,
      graduationProgressVisible:
          settings?.graduationProgressVisibleToStudents ?? false,
      multiSport: (student?.getSports().length ?? 0) > 1,
      hasMultipleAcademies: ref.read(hasMultipleAcademiesProvider),
    );
    return resolvePortalCatalog(
      catalog: kPortalNavCatalog,
      settings: settings,
      ctx: ctx,
    ).where((r) => r.isVisible).map((r) => r.entry).toList();
  }

  void _showMoreMenu() {
    final currentLocation = GoRouterState.of(context).matchedLocation;
    final navigator = GoRouter.of(context);

    final student = ref.read(currentStudentProvider).valueOrNull;
    final isKids = student?.category == StudentCategory.kids;

    final settings = ref.read(academySettingsProvider).valueOrNull;
    final isStorePublished = settings?.storePublished ?? false;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final studentId = currentUser?.studentId;
    final linkedStudentIds = currentUser?.linkedStudentIds ?? const <String>[];
    final allStudentIds = studentId != null
        ? [studentId, ...linkedStudentIds]
        : linkedStudentIds;
    final monitorIds = settings?.monitorIds ?? const <String>[];
    final isMonitor = allStudentIds.any(monitorIds.contains);
    final hasAttendancePermMenu =
        currentUser?.hasPermission('attendance:take') == true;

    final studentDocId = student?.id;
    final hasPlan = studentDocId != null &&
        ref.read(studentPlanProvider(studentDocId)).valueOrNull != null;

    final graduationVisible =
        settings?.graduationProgressVisibleToStudents ?? false;

    // Resolve the portal catalog (feature flags + contextual gates). The portal
    // model is simple: a feature OFF or an unmet gate => the entry is hidden
    // (the student never sees a "locked" entry — discovery is admin-only).
    final ctx = PortalNavContext(
      isKids: isKids,
      isMonitorOrAttendance: isMonitor || hasAttendancePermMenu,
      hasPlan: hasPlan,
      storePublished: isStorePublished,
      graduationProgressVisible: graduationVisible,
      multiSport: (student?.getSports().length ?? 0) > 1,
      hasMultipleAcademies: ref.read(hasMultipleAcademiesProvider),
    );
    final resolved = resolvePortalCatalog(
      catalog: kPortalNavCatalog,
      settings: settings,
      ctx: ctx,
    );
    final entries =
        resolved.where((r) => r.isVisible).map((r) => r.entry).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => MoreMenuSheet(
        headerTitle: 'Menu',
        headerSubtitle: settings?.name ?? 'Meu Portal',
        items: entries
            .map(
              (e) => MoreMenuItem(
                label: e.label,
                icon: e.icon,
                path: e.route,
                isActive: currentLocation == e.route,
                category: e.section.label,
              ),
            )
            .toList(),
        onLogout: () async {
          final confirmed = await FeedbackUtils.showConfirmDialog(
            sheetContext,
            title: 'Sair da conta',
            message: 'Tem certeza que deseja sair?',
            confirmText: 'Sair',
            icon: Icons.logout,
          );
          if (!confirmed) return;
          if (sheetContext.mounted) Navigator.pop(sheetContext);
          final authService = ref.read(authServiceProvider);
          await authService.signOut();
        },
        onNavigate: (path) {
          Navigator.pop(sheetContext);
          navigator.go(path);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth state for reactive updates
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    // Pre-load student plan so it's available synchronously in _showMoreMenu
    final student = ref.watch(currentStudentProvider).valueOrNull;
    if (student != null) {
      ref.watch(studentPlanProvider(student.id));
    }

    // Detect monitor role to pick the right bottom-nav layout.
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final studentIds = <String>[
      if (currentUser?.studentId != null) currentUser!.studentId!,
      ...(currentUser?.linkedStudentIds ?? const <String>[]),
    ];
    final monitorIds = settings?.monitorIds ?? const <String>[];
    final isMonitor = studentIds.any(monitorIds.contains);
    final hasAttendancePerm =
        currentUser?.hasPermission('attendance:take') == true;
    final bottomNavItems = _bottomNavItemsFor(
      isMonitor: isMonitor,
      hasAttendancePerm: hasAttendancePerm,
    );

    // Get current location from GoRouter
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _getSelectedIndex(location, bottomNavItems);

    // Rail do desktop: só resolve o catálogo quando há largura para ela.
    final navEntries = context.isDesktop
        ? _resolveVisiblePortalEntries()
        : const <NavEntry>[];

    // Check if this is the root route (/portal)
    final isRootRoute = location == '/portal';

    return BackButtonHandler(
      isRootRoute: isRootRoute,
      currentLocation: location,
      exitMessage: 'Pressione voltar novamente para sair',
      child: Scaffold(
      // Fundo bone (igual ao fighter): a área da ilha mostra esse fundo.
      backgroundColor: const Color(0xFFF4F3EF),
      // Sem AppBar global (fighter-first): acabava o "header com espaço em
      // branco". Mas um SafeArea no topo dá a folga da ilha/status bar a TODAS
      // as telas (legadas e fighter) — sem isso os headers das telas da
      // academia colidiam com a Dynamic Island.
        body: Row(
          children: [
            // Desktop (medium+): rail só-ícones à esquerda, do catálogo do portal.
            if (context.isDesktop)
              _PortalRail(entries: navEntries, currentPath: location),
            Expanded(
              child: SafeArea(
                top: true,
                bottom: false,
                child: Column(
                  children: [
                    const UpdateBanner(),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          ],
        ),
        // BottomNav só no compact; no desktop a navegação vive na rail lateral.
        bottomNavigationBar: context.isCompact
            ? Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.95),
                  border: const Border(
                    top: BorderSide(color: AppTheme.divider, width: 1),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: List.generate(
                        bottomNavItems.length,
                        (index) => _BottomNavItem(
                          item: bottomNavItems[index],
                          isSelected: selectedIndex == index,
                          onTap: () => _onItemTapped(index, bottomNavItems),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Navigation item data
class _NavItem {
  final String label;
  final IconData icon;
  final String path;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.path,
  });
}

/// NavigationRail do portal (desktop): rail só-ícones (72px) a partir das
/// entradas visíveis do catálogo do portal. A AppBar (com o seletor de academia
/// e o sino) é mantida; a rail só cuida da navegação que o BottomNav fazia.
class _PortalRail extends StatelessWidget {
  final List<NavEntry> entries;
  final String currentPath;

  const _PortalRail({required this.entries, required this.currentPath});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final e in entries)
            _PortalRailItem(entry: e, currentPath: currentPath),
        ],
      ),
    );
  }
}

class _PortalRailItem extends StatelessWidget {
  final NavEntry entry;
  final String currentPath;

  const _PortalRailItem({required this.entry, required this.currentPath});

  bool get isActive =>
      currentPath == entry.route || currentPath.startsWith('${entry.route}/');

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppTheme.primary : AppTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Tooltip(
        message: entry.label,
        preferBelow: false,
        child: Material(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go(entry.route),
            child: SizedBox(
              height: 48,
              child: Icon(
                isActive ? (entry.activeIcon ?? entry.icon) : entry.icon,
                color: color,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom nav item widget - Dot indicator style
class _BottomNavItem extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon without background
              Icon(
                item.icon,
                size: 20,
                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
              const SizedBox(height: 2),
              // Label
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Dot indicator (smaller spacing)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(top: 2),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.textPrimary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notification bell icon with unread badge
class _NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return IconButton(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(LucideIcons.bell, size: 20),
          if (unreadCount > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: () => context.push('/portal/notificacoes'),
    );
  }
}
