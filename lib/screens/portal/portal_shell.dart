import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../widgets/common/more_menu_sheet.dart';

/// Portal Shell - Main navigation structure for student portal
class PortalShell extends ConsumerStatefulWidget {
  final Widget child;

  const PortalShell({super.key, required this.child});

  @override
  ConsumerState<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends ConsumerState<PortalShell> {
  // Navigation items for bottom nav (first 4 + "Mais")
  static const List<_NavItem> _bottomNavItems = [
    _NavItem(
      label: 'Inicio',
      icon: LucideIcons.layoutDashboard,
      path: '/portal',
    ),
    _NavItem(
      label: 'Perfil',
      icon: LucideIcons.user,
      path: '/portal/perfil',
    ),
    _NavItem(
      label: 'Presencas',
      icon: LucideIcons.clipboardCheck,
      path: '/portal/presencas',
    ),
    _NavItem(
      label: 'Competicoes',
      icon: LucideIcons.trophy,
      path: '/portal/competicoes',
    ),
    _NavItem(
      label: 'Mais',
      icon: LucideIcons.moreHorizontal,
      path: '', // Special case for bottom sheet
    ),
  ];

  // Items for "Mais" menu
  static const List<_NavItem> _moreMenuItems = [
    _NavItem(
      label: 'Horarios',
      icon: LucideIcons.calendar,
      path: '/portal/horarios',
    ),
    _NavItem(
      label: 'Jornada',
      icon: LucideIcons.history,
      path: '/portal/linha-do-tempo',
    ),
    _NavItem(
      label: 'Comportamento',
      icon: LucideIcons.star,
      path: '/portal/comportamento',
    ),
    _NavItem(
      label: 'Financeiro',
      icon: LucideIcons.dollarSign,
      path: '/portal/financeiro',
    ),
    _NavItem(
      label: 'Loja',
      icon: LucideIcons.store,
      path: '/portal/loja',
    ),
  ];

  int _getSelectedIndex(String location) {
    // Check bottom nav items (except "Mais")
    for (int i = 0; i < _bottomNavItems.length - 1; i++) {
      final path = _bottomNavItems[i].path;
      // Exact match for /portal, prefix match for others
      if (path == '/portal') {
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

    // Check monitor routes
    if (location.startsWith('/portal/chamada') || location.startsWith('/portal/alunos')) {
      return 4; // "Mais" index
    }

    return 0; // Default to first item
  }

  void _onItemTapped(int index) {
    if (index == 4) {
      // Show "Mais" bottom sheet
      _showMoreMenu();
    } else {
      context.go(_bottomNavItems[index].path);
    }
  }

  Widget _buildAppBarTitle(WidgetRef ref) {
    final settingsAsync = ref.watch(academySettingsProvider);

    return settingsAsync.when(
      data: (settings) {
        final name = settings?.name ?? 'GraduaBJJ';
        final slogan = settings?.portalSlogan;
        final logoUrl = settings?.logoUrl;

        return Row(
          children: [
            // Logo
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: logoUrl == null ? AppTheme.primary : null,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: logoUrl != null
                  ? Image.network(
                      logoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildDefaultLogo(name),
                    )
                  : _buildDefaultLogo(name),
            ),
            const SizedBox(width: 12),
            // Academy name + slogan
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (slogan != null && slogan.isNotEmpty)
                    Text(
                      slogan,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 100,
            height: 16,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
      error: (_, __) => Row(
        children: [
          _buildDefaultLogo('GraduaBJJ'),
          const SizedBox(width: 12),
          Text(
            'GraduaBJJ',
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultLogo(String name) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'G',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _showMoreMenu() {
    // Capture current location BEFORE opening bottom sheet
    // (bottom sheet context doesn't have GoRouter)
    final currentLocation = GoRouterState.of(context).matchedLocation;
    final navigator = GoRouter.of(context);

    // Get student to check if they're a kid (for showing Comportamento)
    final student = ref.read(currentStudentProvider).valueOrNull;
    final isKids = student?.category == StudentCategory.kids;

    // Get academy settings to check if store is enabled and monitors
    final settings = ref.read(academySettingsProvider).valueOrNull;
    final isStoreEnabled = settings?.storeEnabled ?? false;

    // Check if user is a monitor
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final studentId = currentUser?.studentId;
    final linkedStudentIds = currentUser?.linkedStudentIds ?? [];
    final allStudentIds = studentId != null ? [studentId, ...linkedStudentIds] : linkedStudentIds;
    final monitorIds = settings?.monitorIds ?? [];
    final isMonitor = allStudentIds.any((id) => monitorIds.contains(id));

    // Build filtered items list
    final List<_NavItem> filteredItems = [];

    // Add monitor-specific items first if user is a monitor
    if (isMonitor) {
      filteredItems.add(const _NavItem(
        label: 'Chamada',
        icon: LucideIcons.clipboardCheck,
        path: '/portal/chamada',
      ));
      filteredItems.add(const _NavItem(
        label: 'Alunos',
        icon: LucideIcons.users,
        path: '/portal/alunos',
      ));
    }

    // Filter and add standard menu items
    for (final item in _moreMenuItems) {
      // Comportamento only shows for kids
      if (item.path == '/portal/comportamento' && !isKids) {
        continue;
      }
      // Loja only shows if store is enabled
      if (item.path == '/portal/loja' && !isStoreEnabled) {
        continue;
      }
      filteredItems.add(item);
    }

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
    // Watch auth state for reactive updates
    ref.watch(currentUserProvider);

    // Get current location from GoRouter
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _getSelectedIndex(location);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: _buildAppBarTitle(ref),
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
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: List.generate(
                _bottomNavItems.length,
                (index) => _BottomNavItem(
                  item: _bottomNavItems[index],
                  isSelected: selectedIndex == index,
                  onTap: () => _onItemTapped(index),
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
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon without background
              Icon(
                item.icon,
                size: 22,
                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
              const SizedBox(height: 4),
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
              const SizedBox(height: 4),
              // Dot indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
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
