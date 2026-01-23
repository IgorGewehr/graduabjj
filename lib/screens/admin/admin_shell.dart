import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Admin Navigation Shell - Main navigation for admin screens
class AdminShell extends StatelessWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar for larger screens
          if (MediaQuery.of(context).size.width >= 768)
            AdminSidebar(currentPath: location),
          // Main content
          Expanded(child: child),
        ],
      ),
      // Drawer for mobile
      drawer: MediaQuery.of(context).size.width < 768
          ? Drawer(child: AdminSidebar(currentPath: location))
          : null,
      bottomNavigationBar: MediaQuery.of(context).size.width < 768
          ? AdminBottomNav(currentPath: location)
          : null,
    );
  }
}

/// Admin Sidebar Navigation
class AdminSidebar extends StatelessWidget {
  final String currentPath;

  const AdminSidebar({super.key, required this.currentPath});

  @override
  Widget build(BuildContext context) {
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
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.sports_martial_arts, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Text(
                  'GraduaBJJ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
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
                  icon: Icons.military_tech_outlined,
                  activeIcon: Icons.military_tech,
                  label: 'Graduação',
                  path: '/admin/graduacao',
                  currentPath: currentPath,
                ),
                _NavItem(
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart,
                  label: 'Relatórios',
                  path: '/admin/relatorios',
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
            leading: const CircleAvatar(
              backgroundColor: AppTheme.primary,
              child: Icon(Icons.person, color: Colors.white, size: 20),
            ),
            title: const Text('Admin', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Administrador', style: TextStyle(fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                // TODO: Implement logout
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

/// Admin Bottom Navigation (for mobile)
class AdminBottomNav extends StatelessWidget {
  final String currentPath;

  const AdminBottomNav({super.key, required this.currentPath});

  int _getSelectedIndex() {
    if (currentPath == '/admin') return 0;
    if (currentPath.startsWith('/admin/alunos')) return 1;
    if (currentPath.startsWith('/admin/chamada')) return 2;
    if (currentPath.startsWith('/admin/financeiro')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _getSelectedIndex(),
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            context.go('/admin');
            break;
          case 1:
            context.go('/admin/alunos');
            break;
          case 2:
            context.go('/admin/chamada');
            break;
          case 3:
            context.go('/admin/financeiro');
            break;
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Alunos',
        ),
        NavigationDestination(
          icon: Icon(Icons.check_circle_outline),
          selectedIcon: Icon(Icons.check_circle),
          label: 'Chamada',
        ),
        NavigationDestination(
          icon: Icon(Icons.attach_money_outlined),
          selectedIcon: Icon(Icons.attach_money),
          label: 'Financeiro',
        ),
      ],
    );
  }
}
