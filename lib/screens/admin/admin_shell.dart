import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../widgets/common/more_menu_sheet.dart';

/// Admin Navigation Shell - Main navigation for admin screens
class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.valueOrNull;
    final settingsAsync = ref.watch(academySettingsProvider);
    final settings = settingsAsync.valueOrNull;

    return Scaffold(
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
                      color: (settings?.logoUrl ?? '').isEmpty ? AppTheme.textPrimary : null,
                      borderRadius: BorderRadius.circular(6),
                      image: (settings?.logoUrl ?? '').isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(settings!.logoUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
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
                        : null,
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
                        if (settings?.portalSlogan != null && settings!.portalSlogan!.isNotEmpty)
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
              actions: [
                IconButton(
                  icon: const Icon(LucideIcons.bell, size: 20),
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
              ],
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
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.valueOrNull;

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
                    color: (settings?.logoUrl ?? '').isEmpty ? AppTheme.primary : null,
                    borderRadius: BorderRadius.circular(8),
                    image: (settings?.logoUrl ?? '').isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(settings!.logoUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
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
                      : null,
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
                _NavItem(
                  icon: Icons.emoji_events_outlined,
                  activeIcon: Icons.emoji_events,
                  label: 'Campeonatos',
                  path: '/admin/campeonatos',
                  currentPath: currentPath,
                ),
                _NavItem(
                  icon: Icons.attach_money_outlined,
                  activeIcon: Icons.attach_money,
                  label: 'Financeiro',
                  path: '/admin/financeiro',
                  currentPath: currentPath,
                ),
                _NavItem(
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart,
                  label: 'Relatórios',
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
                const Divider(),
                _NavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  label: 'Configurações',
                  path: '/admin/configuracoes',
                  currentPath: currentPath,
                ),
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
  // Navigation items for bottom nav (first 4 + "Mais")
  static const List<_AdminNavItem> _bottomNavItems = [
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
    _AdminNavItem(
      label: 'Financeiro',
      icon: LucideIcons.dollarSign,
      path: '/admin/financeiro',
    ),
    _AdminNavItem(
      label: 'Mais',
      icon: LucideIcons.moreHorizontal,
      path: '', // Special case for bottom sheet
    ),
  ];

  // Items for "Mais" menu
  static const List<_AdminNavItem> _moreMenuItems = [
    _AdminNavItem(
      label: 'Turmas',
      icon: LucideIcons.calendar,
      path: '/admin/turmas',
    ),
    _AdminNavItem(
      label: 'Competicoes',
      icon: LucideIcons.trophy,
      path: '/admin/campeonatos',
    ),
    _AdminNavItem(
      label: 'Relatorios',
      icon: LucideIcons.barChart3,
      path: '/admin/relatorios',
    ),
    _AdminNavItem(
      label: 'Loja',
      icon: LucideIcons.store,
      path: '/admin/loja',
    ),
    _AdminNavItem(
      label: 'Carteira',
      icon: LucideIcons.wallet,
      path: '/admin/carteira',
    ),
    _AdminNavItem(
      label: 'Configuracoes',
      icon: LucideIcons.settings,
      path: '/admin/configuracoes',
    ),
  ];

  int _getSelectedIndex() {
    final location = widget.currentPath;

    // Check bottom nav items (except "Mais")
    for (int i = 0; i < _bottomNavItems.length - 1; i++) {
      final path = _bottomNavItems[i].path;
      // Exact match for /admin, prefix match for others
      if (path == '/admin') {
        if (location == path) return i;
      } else if (location == path || location.startsWith('$path/')) {
        return i;
      }
    }

    // Check if any "more" item is active
    for (final item in _moreMenuItems) {
      if (location == item.path || location.startsWith('${item.path}/')) {
        return 4; // "Mais" index
      }
    }

    return 0;
  }

  void _onItemTapped(int index) {
    if (index == 4) {
      _showMoreMenu();
    } else {
      context.go(_bottomNavItems[index].path);
    }
  }

  void _showMoreMenu() {
    final currentLocation = widget.currentPath;
    final navigator = GoRouter.of(context);

    // Get academy settings to check if store/abacatepay is enabled
    final settings = ref.read(academySettingsProvider).valueOrNull;
    final isStoreEnabled = settings?.storeEnabled ?? false;
    final isAbacatePayEnabled = settings?.abacatePayEnabled ?? false;

    // Get current user to check role
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final isAdmin = currentUser?.isAdmin ?? false;

    // Filter menu items based on conditions
    final filteredItems = _moreMenuItems.where((item) {
      // Loja only shows if store is enabled
      if (item.path == '/admin/loja') {
        return isStoreEnabled;
      }
      // Carteira only shows if AbacatePay is enabled
      if (item.path == '/admin/carteira') {
        return isAbacatePayEnabled;
      }
      return true;
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => MoreMenuSheet(
        items: filteredItems
            .map((item) => MoreMenuItem(
                  label: item.label,
                  icon: item.icon,
                  path: item.path,
                  isActive: currentLocation == item.path,
                ))
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
    final selectedIndex = _getSelectedIndex();

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
              _bottomNavItems.length,
              (index) => _AdminBottomNavItem(
                item: _bottomNavItems[index],
                isSelected: selectedIndex == index,
                onTap: () => _onItemTapped(index),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
                  color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
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
