import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../widgets/common/back_button_handler.dart';
import '../../widgets/academy_switcher.dart';

class PortalShell extends ConsumerStatefulWidget {
  final Widget child;

  const PortalShell({super.key, required this.child});

  @override
  ConsumerState<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends ConsumerState<PortalShell> {
  static const List<_NavItem> _bottomNavItems = [
    _NavItem(
      label: 'Inicio',
      icon: LucideIcons.layoutDashboard,
      path: '/portal',
    ),
    _NavItem(
      label: 'Presencas',
      icon: LucideIcons.clipboardCheck,
      path: '/portal/presencas',
    ),
    _NavItem(
      label: 'Financeiro',
      icon: LucideIcons.dollarSign,
      path: '/portal/financeiro',
    ),
    _NavItem(
      label: 'Perfil',
      icon: LucideIcons.user,
      path: '/portal/perfil',
    ),
  ];

  int _getSelectedIndex(String location) {
    for (int i = 0; i < _bottomNavItems.length; i++) {
      final path = _bottomNavItems[i].path;
      if (path == '/portal') {
        if (location == path) return i;
      } else if (location == path || location.startsWith('$path/')) {
        return i;
      }
    }
    return 0;
  }

  Widget _buildAppBarTitle(WidgetRef ref) {
    return const AcademySwitcher();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserProvider);

    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _getSelectedIndex(location);
    final isRootRoute = location == '/portal';

    return BackButtonHandler(
      isRootRoute: isRootRoute,
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
        floatingActionButton: SizedBox(
          width: 56,
          height: 56,
          child: FloatingActionButton(
            onPressed: () => context.go('/portal/qr-scan'),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(LucideIcons.qrCode, size: 24),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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
                children: [
                  _BottomNavItem(
                    item: _bottomNavItems[0],
                    isSelected: selectedIndex == 0,
                    onTap: () => context.go(_bottomNavItems[0].path),
                  ),
                  _BottomNavItem(
                    item: _bottomNavItems[1],
                    isSelected: selectedIndex == 1,
                    onTap: () => context.go(_bottomNavItems[1].path),
                  ),
                  const Expanded(child: SizedBox()),
                  _BottomNavItem(
                    item: _bottomNavItems[2],
                    isSelected: selectedIndex == 2,
                    onTap: () => context.go(_bottomNavItems[2].path),
                  ),
                  _BottomNavItem(
                    item: _bottomNavItems[3],
                    isSelected: selectedIndex == 3,
                    onTap: () => context.go(_bottomNavItems[3].path),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
              Icon(
                item.icon,
                size: 20,
                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
              const SizedBox(height: 2),
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
