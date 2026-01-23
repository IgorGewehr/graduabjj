import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/more_menu_sheet.dart';

/// Portal Shell - Main navigation structure for student portal
class PortalShell extends ConsumerStatefulWidget {
  final Widget child;

  const PortalShell({super.key, required this.child});

  @override
  ConsumerState<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends ConsumerState<PortalShell> {
  int _selectedIndex = 0;

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
      label: 'Linha do Tempo',
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
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSelectedIndex();
  }

  void _updateSelectedIndex() {
    final location = GoRouterState.of(context).matchedLocation;

    // Check bottom nav items
    for (int i = 0; i < _bottomNavItems.length - 1; i++) {
      if (location == _bottomNavItems[i].path ||
          location.startsWith('${_bottomNavItems[i].path}/')) {
        if (_selectedIndex != i) {
          setState(() => _selectedIndex = i);
        }
        return;
      }
    }

    // Check if any "more" item is active
    for (final item in _moreMenuItems) {
      if (location == item.path || location.startsWith('${item.path}/')) {
        if (_selectedIndex != 4) {
          setState(() => _selectedIndex = 4);
        }
        return;
      }
    }
  }

  void _onItemTapped(int index) {
    if (index == 4) {
      // Show "Mais" bottom sheet
      _showMoreMenu();
    } else {
      context.go(_bottomNavItems[index].path);
    }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MoreMenuSheet(
        items: _moreMenuItems
            .map((item) => MoreMenuItem(
                  label: item.label,
                  icon: item.icon,
                  path: item.path,
                  isActive: GoRouterState.of(context).matchedLocation == item.path,
                ))
            .toList(),
        onLogout: () async {
          Navigator.pop(context);
          final authService = ref.read(authServiceProvider);
          await authService.signOut();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth state for reactive updates
    ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            // Logo
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'G',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Academy name + slogan
            Expanded(
              child: Text(
                'GraduaBJJ',
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
          color: AppTheme.surface.withOpacity(0.95),
          border: const Border(
            top: BorderSide(color: AppTheme.divider, width: 1),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                _bottomNavItems.length,
                (index) => _BottomNavItem(
                  item: _bottomNavItems[index],
                  isSelected: _selectedIndex == index,
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

/// Bottom nav item widget - Fintech style with pill indicator
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with pill background when selected
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                item.icon,
                size: 20,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
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
            ),
          ],
        ),
      ),
    );
  }
}
