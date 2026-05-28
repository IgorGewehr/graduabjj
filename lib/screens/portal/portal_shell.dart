import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../widgets/common/more_menu_sheet.dart';
import '../../widgets/common/back_button_handler.dart';
import '../../widgets/academy_switcher.dart';

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
  static const _NavItem _homeNavItem = _NavItem(
    label: 'Inicio',
    icon: LucideIcons.layoutDashboard,
    path: '/portal',
  );
  static const _NavItem _scheduleNavItem = _NavItem(
    label: 'Horarios',
    icon: LucideIcons.calendar,
    path: '/portal/horarios',
  );
  static const _NavItem _presencasNavItem = _NavItem(
    label: 'Presencas',
    icon: LucideIcons.clipboardCheck,
    path: '/portal/presencas',
  );
  static const _NavItem _chamadaNavItem = _NavItem(
    label: 'Chamada',
    icon: LucideIcons.clipboardCheck,
    path: '/portal/chamada',
  );
  static const _NavItem _alunosNavItem = _NavItem(
    label: 'Alunos',
    icon: LucideIcons.users,
    path: '/portal/alunos',
  );
  static const _NavItem _profileNavItem = _NavItem(
    label: 'Perfil',
    icon: LucideIcons.user,
    path: '/portal/perfil',
  );
  static const _NavItem _menuNavItem = _NavItem(
    label: 'Menu',
    icon: LucideIcons.layoutGrid,
    path: '', // Special case for bottom sheet
  );

  /// Builds the bottom nav for the current role. Monitors (or users with
  /// attendance:take) get Chamada and Alunos as primary entries; students get
  /// Horários in that slot.
  List<_NavItem> _bottomNavItemsFor({
    required bool isMonitor,
    required bool hasAttendancePerm,
  }) {
    if (isMonitor || hasAttendancePerm) {
      return const [
        _homeNavItem,
        _chamadaNavItem,
        _alunosNavItem,
        _profileNavItem,
        _menuNavItem,
      ];
    }
    return const [
      _homeNavItem,
      _scheduleNavItem,
      _presencasNavItem,
      _profileNavItem,
      _menuNavItem,
    ];
  }

  /// Catalog of secondary items reached via the Menu sheet. Each entry
  /// declares the section it lives in plus its activation gate.
  static const List<_PortalMenuEntry> _menuCatalog = [
    // Treinos — academic life
    _PortalMenuEntry(
      label: 'Horarios',
      icon: LucideIcons.calendar,
      path: '/portal/horarios',
      section: 'Treinos',
      hideWhen: _PortalGate.monitor, // monitors already have it elsewhere? no
    ),
    _PortalMenuEntry(
      label: 'Presencas',
      icon: LucideIcons.clipboardCheck,
      path: '/portal/presencas',
      section: 'Treinos',
    ),
    _PortalMenuEntry(
      label: 'Jornada',
      icon: LucideIcons.history,
      path: '/portal/linha-do-tempo',
      section: 'Treinos',
    ),
    _PortalMenuEntry(
      label: 'Treinos',
      icon: Icons.fitness_center,
      path: '/portal/treinos',
      section: 'Treinos',
    ),
    _PortalMenuEntry(
      label: 'Vídeos',
      icon: Icons.play_circle_outline,
      path: '/portal/videos',
      section: 'Treinos',
    ),
    // Conquistas
    _PortalMenuEntry(
      label: 'Competicoes',
      icon: LucideIcons.trophy,
      path: '/portal/competicoes',
      section: 'Conquistas',
    ),
    _PortalMenuEntry(
      label: 'Comportamento',
      icon: LucideIcons.star,
      path: '/portal/comportamento',
      section: 'Conquistas',
      requiresKidsCategory: true,
    ),
    // Conta
    _PortalMenuEntry(
      label: 'Financeiro',
      icon: LucideIcons.dollarSign,
      path: '/portal/financeiro',
      section: 'Conta',
      requiresPlan: true,
    ),
    _PortalMenuEntry(
      label: 'Loja',
      icon: LucideIcons.store,
      path: '/portal/loja',
      section: 'Conta',
      requiresStorePublished: true,
    ),
    _PortalMenuEntry(
      label: 'Academias',
      icon: LucideIcons.school,
      path: '/portal/academias',
      section: 'Conta',
    ),
  ];

  int _getSelectedIndex(String location, List<_NavItem> items) {
    final menuIndex = items.length - 1;
    // Check bottom nav items (except the Menu slot).
    for (int i = 0; i < items.length - 1; i++) {
      final path = items[i].path;
      if (path == '/portal') {
        if (location == path) return i;
      } else if (location == path || location.startsWith('$path/')) {
        return i;
      }
    }

    // Any deeper portal route → highlight Menu
    for (final entry in _menuCatalog) {
      if (location == entry.path || location.startsWith('${entry.path}/')) {
        return menuIndex;
      }
    }

    return 0;
  }

  void _onItemTapped(int index, List<_NavItem> items) {
    if (index == items.length - 1) {
      _showMoreMenu();
    } else {
      context.go(items[index].path);
    }
  }

  Widget _buildAppBarTitle(WidgetRef ref) {
    // Use the AcademySwitcher widget which handles single and multi-academy display
    return const AcademySwitcher();
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

    final entries = _menuCatalog.where((e) {
      if (e.requiresKidsCategory && !isKids) return false;
      if (e.requiresStorePublished && !isStorePublished) return false;
      if (e.requiresPlan && !hasPlan) return false;
      if (e.hideWhen == _PortalGate.monitor && (isMonitor || hasAttendancePermMenu)) return false;
      return true;
    }).toList();

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
                path: e.path,
                isActive: currentLocation == e.path,
                category: e.section,
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

    // Check if this is the root route (/portal)
    final isRootRoute = location == '/portal';

    return BackButtonHandler(
      isRootRoute: isRootRoute,
      currentLocation: location,
      exitMessage: 'Pressione voltar novamente para sair',
      child: Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: _buildAppBarTitle(ref),
        actions: [
          _NotificationBell(),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppTheme.divider,
          ),
        ),
      ),
        body: widget.child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.95),
            border: const Border(
              top: BorderSide(color: AppTheme.divider, width: 1),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
        ),
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

/// Optional gate to hide an entry for a specific portal role.
enum _PortalGate { monitor }

/// One entry in the portal "Menu" sheet catalog. Gates compose: if any one
/// of the *requires* flags is false, the entry is filtered out at render.
class _PortalMenuEntry {
  final String label;
  final IconData icon;
  final String path;
  final String section;
  final bool requiresKidsCategory;
  final bool requiresStorePublished;
  final bool requiresPlan;
  final _PortalGate? hideWhen;

  const _PortalMenuEntry({
    required this.label,
    required this.icon,
    required this.path,
    required this.section,
    this.requiresKidsCategory = false,
    this.requiresStorePublished = false,
    this.requiresPlan = false,
    this.hideWhen,
  });
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
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
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
