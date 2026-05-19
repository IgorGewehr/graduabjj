import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';

/// Menu item data for MoreMenuSheet
class MoreMenuItem {
  final String label;
  final IconData icon;
  final String path;
  final bool isActive;

  const MoreMenuItem({
    required this.label,
    required this.icon,
    required this.path,
    this.isActive = false,
  });
}

/// Bottom sheet with "More" menu options
class MoreMenuSheet extends StatelessWidget {
  final List<MoreMenuItem> items;
  final VoidCallback onLogout;
  final void Function(String path) onNavigate;

  const MoreMenuSheet({
    super.key,
    required this.items,
    required this.onLogout,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Close button
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(LucideIcons.x, size: 20),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.surfaceVariant,
                ),
              ),
            ),
          ),

          // Menu items (scrollable when list is long)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...items.map((item) => _MenuItemTile(
                        item: item,
                        onTap: () => onNavigate(item.path),
                      )),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  // Logout button
                  _MenuItemTile(
                    item: const MoreMenuItem(
                      label: 'Sair',
                      icon: LucideIcons.logOut,
                      path: '',
                    ),
                    isLogout: true,
                    onTap: onLogout,
                  ),
                ],
              ),
            ),
          ),

          // Safe area padding
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// Individual menu item tile
class _MenuItemTile extends StatelessWidget {
  final MoreMenuItem item;
  final VoidCallback onTap;
  final bool isLogout;

  const _MenuItemTile({
    required this.item,
    required this.onTap,
    this.isLogout = false,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = item.isActive;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isActive
            ? AppTheme.primary
            : isLogout
                ? AppTheme.errorLight.withValues(alpha: 0.5)
                : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.1)
                        : isLogout
                            ? AppTheme.errorLight
                            : AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.icon,
                    size: 20,
                    color: isActive
                        ? Colors.white
                        : isLogout
                            ? AppTheme.error
                            : AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    item.label,
                    style: AppTheme.titleMedium.copyWith(
                      color: isActive
                          ? Colors.white
                          : isLogout
                              ? AppTheme.error
                              : AppTheme.textPrimary,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: isActive
                      ? Colors.white
                      : isLogout
                          ? AppTheme.error
                          : AppTheme.textDisabled,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
