import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../providers/subscription_provider.dart';
import '../paywall_screen.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/more_menu_sheet.dart';
import '../../widgets/common/back_button_handler.dart';

/// Admin Navigation Shell - Main navigation for admin screens
class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    ref.watch(currentUserProvider);
    final settingsAsync = ref.watch(academySettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final hasAccess = ref.watch(hasSubscriptionAccessProvider);

    if (!hasAccess) return const PaywallScreen();

    // Check if this is the root route (/admin)
    final isRootRoute = location == '/admin';

    return BackButtonHandler(
      isRootRoute: isRootRoute,
      exitMessage: 'Pressione voltar novamente para sair',
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: MediaQuery.of(context).size.width < 768
            ? AppBar(
                backgroundColor: AppTheme.surface,
                elevation: 0,
                scrolledUnderElevation: 0,
                title: Row(
                  children: [
                    // Logo
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: (settings?.logoUrl ?? '').isEmpty
                            ? AppTheme.textPrimary
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: (settings?.logoUrl ?? '').isEmpty
                          ? Center(
                              child: Text(
                                settings?.name.isNotEmpty == true
                                    ? settings!.name[0].toUpperCase()
                                    : 'A',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : AppCachedImage(
                              imageUrl: settings!.logoUrl,
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                            ),
                    ),
                    const SizedBox(width: 10),
                    // Academy name and slogan
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            settings?.name ?? 'Minha Academia',
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (settings?.portalSlogan != null &&
                              settings!.portalSlogan!.isNotEmpty)
                            Text(
                              settings.portalSlogan!,
                              style: AppTheme.labelSmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [_AdminNotificationBell(), const SizedBox(width: 8)],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(height: 1, color: AppTheme.divider),
                ),
              )
            : null,
        body: Row(
          children: [
            // Sidebar for larger screens
            if (MediaQuery.of(context).size.width >= 768)
              AdminSidebar(currentPath: location),
            // Main content
            Expanded(child: child),
          ],
        ),
        bottomNavigationBar: MediaQuery.of(context).size.width < 768
            ? AdminBottomNav(currentPath: location)
            : null,
      ),
    );
  }
}

/// Admin Sidebar Navigation
class AdminSidebar extends ConsumerWidget {
  final String currentPath;

  const AdminSidebar({super.key, required this.currentPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(academySettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final isStoreEnabled = settings?.storeEnabled ?? false;
    final isGraduationEnabled = settings?.autoGraduationEnabled ?? false;
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.valueOrNull;
    // Permission gates. Admins always pass; instructors need the explicit
    // extraPermissions entry granted at promotion time.
    final canSeeFinancial = user?.hasPermission('financial:view') == true;
    final canSeeReports = user?.hasPermission('reports:view') == true;
    final isAdminUser = user?.isAdmin == true;

    return Container(
      width: 250,
      color: AppTheme.surface,
      child: Column(
        children: [
          // Header/Logo
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (settings?.logoUrl ?? '').isEmpty
                        ? AppTheme.primary
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (settings?.logoUrl ?? '').isEmpty
                      ? Center(
                          child: Text(
                            settings?.name.isNotEmpty == true
                                ? settings!.name[0].toUpperCase()
                                : 'A',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        )
                      : AppCachedImage(
                          imageUrl: settings!.logoUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    settings?.name ?? 'Minha Academia',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  label: 'Dashboard',
                  path: '/admin',
                  currentPath: currentPath,
                ),
                _NavItem(
                  icon: Icons.people_outline,
                  activeIcon: Icons.people,
                  label: 'Alunos',
                  path: '/admin/alunos',
                  currentPath: currentPath,
                ),
                // 'Chamada' abre a chamada normal. O FAB 'Chamada por QR'
                // dentro da propria tela leva pra projecao — sem precisar
                // de duas entradas na sidebar.
                _NavItem(
                  icon: Icons.check_circle_outline,
                  activeIcon: Icons.check_circle,
                  label: 'Chamada',
                  path: '/admin/chamada',
                  currentPath: currentPath,
                ),
                _NavItem(
                  icon: Icons.calendar_month_outlined,
                  activeIcon: Icons.calendar_month,
                  label: 'Turmas',
                  path: '/admin/turmas',
                  currentPath: currentPath,
                ),
                if (isGraduationEnabled)
                  _NavItem(
                    icon: Icons.military_tech_outlined,
                    activeIcon: Icons.military_tech,
                    label: 'Graduação',
                    path: '/admin/graduacao',
                    currentPath: currentPath,
                  ),
                _NavItem(
                  icon: Icons.emoji_events_outlined,
                  activeIcon: Icons.emoji_events,
                  label: 'Campeonatos',
                  path: '/admin/campeonatos',
                  currentPath: currentPath,
                ),
                if (canSeeFinancial)
                  _NavItem(
                    icon: Icons.attach_money_outlined,
                    activeIcon: Icons.attach_money,
                    label: 'Financeiro',
                    path: '/admin/financeiro',
                    currentPath: currentPath,
                  ),
                if (canSeeFinancial)
                  _NavItem(
                    icon: Icons.receipt_long_outlined,
                    activeIcon: Icons.receipt_long,
                    label: 'Cobranca',
                    path: '/admin/cobranca',
                    currentPath: currentPath,
                  ),
                if (canSeeReports)
                  _NavItem(
                    icon: Icons.bar_chart_outlined,
                    activeIcon: Icons.bar_chart,
                    label: 'Relatorios',
                    path: '/admin/relatorios',
                    currentPath: currentPath,
                  ),
                if (isStoreEnabled)
                  _NavItem(
                    icon: Icons.store_outlined,
                    activeIcon: Icons.store,
                    label: 'Loja',
                    path: '/admin/loja',
                    currentPath: currentPath,
                  ),
                // Configurações + código de equipe are admin-only — instructors
                // never touch academy-wide settings or generate invites.
                if (isAdminUser) ...[
                  const Divider(),
                  _NavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'Configurações',
                    path: '/admin/configuracoes',
                    currentPath: currentPath,
                  ),
                  _NavItem(
                    icon: Icons.key_outlined,
                    activeIcon: Icons.key,
                    label: 'Código de equipe',
                    path: '/codigo-equipe',
                    currentPath: currentPath,
                  ),
                ],
              ],
            ),
          ),

          // User section
          const Divider(height: 1),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary,
              child: Text(
                user?.displayName.isNotEmpty == true
                    ? user!.displayName[0].toUpperCase()
                    : 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            title: Text(
              user?.displayName ?? 'Admin',
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              user?.isAdmin == true ? 'Administrador' : 'Instrutor',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                final authService = ref.read(authServiceProvider);
                await authService.signOut();
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Navigation Item Widget
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
  final String currentPath;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.path,
    required this.currentPath,
  });

  bool get isActive => currentPath == path || currentPath.startsWith('$path/');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          isActive ? activeIcon : icon,
          color: isActive ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isActive ? AppTheme.primary : AppTheme.textPrimary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: isActive,
        selectedTileColor: AppTheme.primary.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context); // Close drawer on mobile
          }
          context.go(path);
        },
      ),
    );
  }
}

/// Admin Bottom Navigation (for mobile) - Fintech style matching webapp
class AdminBottomNav extends ConsumerStatefulWidget {
  final String currentPath;

  const AdminBottomNav({super.key, required this.currentPath});

  @override
  ConsumerState<AdminBottomNav> createState() => _AdminBottomNavState();
}

class _AdminBottomNavState extends ConsumerState<AdminBottomNav> {
  // Navigation items for bottom nav (first 4 + "Mais"). The 4th item is
  // permission-gated below — instructors without financial:view see Turmas
  // there instead of Financeiro.
  static const List<_AdminNavItem> _baseBottomNavItems = [
    _AdminNavItem(
      label: 'Dashboard',
      icon: LucideIcons.layoutDashboard,
      path: '/admin',
    ),
    _AdminNavItem(
      label: 'Chamada',
      icon: LucideIcons.clipboardCheck,
      path: '/admin/chamada',
    ),
    _AdminNavItem(
      label: 'Alunos',
      icon: LucideIcons.users,
      path: '/admin/alunos',
    ),
  ];

  static const _AdminNavItem _financialBottomNavItem = _AdminNavItem(
    label: 'Financeiro',
    icon: LucideIcons.dollarSign,
    path: '/admin/financeiro',
  );
  static const _AdminNavItem _turmasBottomNavItem = _AdminNavItem(
    label: 'Turmas',
    icon: LucideIcons.calendar,
    path: '/admin/turmas',
  );
  static const _AdminNavItem _menuBottomNavItem = _AdminNavItem(
    label: 'Menu',
    icon: LucideIcons.layoutGrid,
    path: '', // Special case for bottom sheet
  );

  /// Returns the current bottom nav list, gated by permissions on the user.
  List<_AdminNavItem> _bottomNavItemsFor(WidgetRef ref) {
    final user = ref.read(currentUserProvider).valueOrNull;
    final canSeeFinancial = user?.hasPermission('financial:view') == true;
    return <_AdminNavItem>[
      ..._baseBottomNavItems,
      canSeeFinancial ? _financialBottomNavItem : _turmasBottomNavItem,
      _menuBottomNavItem,
    ];
  }

  /// Catalog of everything that lives behind the "Menu" tile, tagged by
  /// section and tagged with the permission needed to see it. The shell
  /// applies the filter at render time so each role only sees what's
  /// actually theirs.
  static const List<_AdminMenuEntry> _menuCatalog = [
    // Gestão — primary academy operations
    _AdminMenuEntry(
      label: 'Turmas',
      icon: LucideIcons.calendar,
      path: '/admin/turmas',
      section: 'Gestão',
    ),
    _AdminMenuEntry(
      label: 'Graduação',
      icon: LucideIcons.award,
      path: '/admin/graduacao',
      section: 'Gestão',
      requiresGraduation: true,
    ),
    _AdminMenuEntry(
      label: 'Campeonatos',
      icon: LucideIcons.trophy,
      path: '/admin/campeonatos',
      section: 'Gestão',
    ),
    // Financeiro
    _AdminMenuEntry(
      label: 'Cobrança',
      icon: LucideIcons.receipt,
      path: '/admin/cobranca',
      section: 'Financeiro',
      requiresPermission: 'financial:view',
    ),
    _AdminMenuEntry(
      label: 'Carteira',
      icon: LucideIcons.wallet,
      path: '/admin/carteira',
      section: 'Financeiro',
      requiresPermission: 'financial:view',
      requiresPayment: true,
    ),
    _AdminMenuEntry(
      label: 'Relatórios',
      icon: LucideIcons.barChart3,
      path: '/admin/relatorios',
      section: 'Financeiro',
      requiresPermission: 'reports:view',
    ),
    // Conteúdo
    _AdminMenuEntry(
      label: 'Loja',
      icon: LucideIcons.store,
      path: '/admin/loja',
      section: 'Conteúdo',
      requiresStore: true,
    ),
    // Conta — admin-only
    _AdminMenuEntry(
      label: 'Configurações',
      icon: LucideIcons.settings,
      path: '/admin/configuracoes',
      section: 'Conta',
      adminOnly: true,
    ),
    _AdminMenuEntry(
      label: 'Código de equipe',
      icon: LucideIcons.key,
      path: '/codigo-equipe',
      section: 'Conta',
      adminOnly: true,
    ),
  ];

  int _getSelectedIndex(List<_AdminNavItem> items) {
    final location = widget.currentPath;

    // Check bottom nav items (except "Mais")
    for (int i = 0; i < items.length - 1; i++) {
      final path = items[i].path;
      // Exact match for /admin, prefix match for others
      if (path == '/admin') {
        if (location == path) return i;
      } else if (location == path || location.startsWith('$path/')) {
        return i;
      }
    }

    // Check if any menu entry is active
    for (final entry in _menuCatalog) {
      if (location == entry.path || location.startsWith('${entry.path}/')) {
        return items.length - 1; // "Menu" index
      }
    }

    return 0;
  }

  void _onItemTapped(int index, List<_AdminNavItem> items) {
    if (index == items.length - 1) {
      _showMoreMenu();
    } else {
      context.go(items[index].path);
    }
  }

  /// Resolves the menu catalog against the current user/settings and returns
  /// only the entries this role is allowed to see.
  List<_AdminMenuEntry> _visibleMenuEntries() {
    final settings = ref.read(academySettingsProvider).valueOrNull;
    final isStoreEnabled = settings?.storeEnabled ?? false;
    final isGraduationEnabled = settings?.autoGraduationEnabled ?? false;
    final isPaymentEnabled =
        (settings?.abacatePayEnabled ?? false) ||
        (settings?.asaasEnabled ?? false);
    final user = ref.read(currentUserProvider).valueOrNull;
    final isAdminUser = user?.isAdmin == true;

    return _menuCatalog.where((e) {
      if (e.adminOnly && !isAdminUser) return false;
      if (e.requiresStore && !isStoreEnabled) return false;
      if (e.requiresGraduation && !isGraduationEnabled) return false;
      if (e.requiresPayment && !isPaymentEnabled) return false;
      if (e.requiresPermission != null &&
          user?.hasPermission(e.requiresPermission!) != true) {
        return false;
      }
      return true;
    }).toList();
  }

  void _showMoreMenu() {
    final currentLocation = widget.currentPath;
    final navigator = GoRouter.of(context);
    final entries = _visibleMenuEntries();
    final settings = ref.read(academySettingsProvider).valueOrNull;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => MoreMenuSheet(
        headerTitle: 'Menu',
        headerSubtitle: settings?.name ?? 'Administração',
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
          Navigator.pop(sheetContext);
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
    final items = _bottomNavItemsFor(ref);
    final selectedIndex = _getSelectedIndex(items);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: List.generate(
              items.length,
              (index) => _AdminBottomNavItem(
                item: items[index],
                isSelected: selectedIndex == index,
                onTap: () => _onItemTapped(index, items),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Navigation item data
class _AdminNavItem {
  final String label;
  final IconData icon;
  final String path;

  const _AdminNavItem({
    required this.label,
    required this.icon,
    required this.path,
  });
}

/// One entry in the admin "Menu" sheet catalog. Each entry declares the
/// section it belongs to plus the gates required to surface it.
class _AdminMenuEntry {
  final String label;
  final IconData icon;
  final String path;
  final String section;
  final bool adminOnly;
  final bool requiresStore;
  final bool requiresGraduation;
  final bool requiresPayment;
  final String? requiresPermission;

  const _AdminMenuEntry({
    required this.label,
    required this.icon,
    required this.path,
    required this.section,
    this.adminOnly = false,
    this.requiresStore = false,
    this.requiresGraduation = false,
    this.requiresPayment = false,
    this.requiresPermission,
  });
}

/// Bottom nav item widget - Fintech style with pill indicator
class _AdminBottomNavItem extends StatelessWidget {
  final _AdminNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _AdminBottomNavItem({
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
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with pill background when selected
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.textPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  item.icon,
                  size: 20,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              // Label
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin notification bell with unread badge
class _AdminNotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount =
        ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

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
      onPressed: () => context.push('/admin/notificacoes'),
    );
  }
}
