import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';

/// Menu item shown inside [MoreMenuSheet]. When grouped, [category]
/// controls which section header it lands under; flat lists leave it null.
class MoreMenuItem {
  final String label;
  final IconData icon;
  final String path;
  final bool isActive;
  final String? category;
  final String? subtitle;
  final Color? accent;

  const MoreMenuItem({
    required this.label,
    required this.icon,
    required this.path,
    this.isActive = false,
    this.category,
    this.subtitle,
    this.accent,
  });
}

/// Modal sheet used by both the admin shell and the student portal as the
/// landing point for everything that doesn't fit in the bottom nav.
///
/// Two render modes:
///  - Flat list when none of the items declare [MoreMenuItem.category] —
///    used for older callers that haven't been categorized yet.
///  - Sectioned grid when at least one item has a category. Items are
///    grouped by their category, in the order each category first appears.
class MoreMenuSheet extends StatelessWidget {
  final List<MoreMenuItem> items;
  final VoidCallback onLogout;
  final void Function(String path) onNavigate;
  final String? headerTitle;
  final String? headerSubtitle;

  const MoreMenuSheet({
    super.key,
    required this.items,
    required this.onLogout,
    required this.onNavigate,
    this.headerTitle,
    this.headerSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final hasCategories = items.any((i) => i.category != null);

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          if (headerTitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerTitle!,
                          style: AppTheme.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (headerSubtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            headerSubtitle!,
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.surfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
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

          // Items
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: hasCategories
                  ? _buildCategorized(context)
                  : _buildFlat(context),
            ),
          ),

          // Logout — anchored at the bottom so it's always reachable.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _MenuItemTile(
              item: const MoreMenuItem(
                label: 'Sair',
                icon: LucideIcons.logOut,
                path: '',
              ),
              isLogout: true,
              onTap: onLogout,
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }

  Widget _buildFlat(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: items
          .map(
            (item) => _MenuItemTile(
              item: item,
              onTap: () => onNavigate(item.path),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCategorized(BuildContext context) {
    // Preserve insertion order of categories.
    final byCategory = <String, List<MoreMenuItem>>{};
    for (final item in items) {
      final key = item.category ?? 'Mais';
      byCategory.putIfAbsent(key, () => []).add(item);
    }

    final sections = <Widget>[];
    var first = true;
    byCategory.forEach((category, sectionItems) {
      if (!first) sections.add(const SizedBox(height: 16));
      first = false;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            category.toUpperCase(),
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      );
      sections.add(_SectionGrid(
        items: sectionItems,
        onNavigate: onNavigate,
      ));
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }
}

/// 2-column grid of action tiles inside a category. Tiles are visual and
/// tappable; they're more scannable than a stack of full-width rows.
class _SectionGrid extends StatelessWidget {
  final List<MoreMenuItem> items;
  final void Function(String path) onNavigate;

  const _SectionGrid({required this.items, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const spacing = 10.0;
        final tileWidth = (c.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map(
                (i) => SizedBox(
                  width: tileWidth,
                  child: _SectionTile(
                    item: i,
                    onTap: () => onNavigate(i.path),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SectionTile extends StatelessWidget {
  final MoreMenuItem item;
  final VoidCallback onTap;

  const _SectionTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = item.accent ?? AppTheme.primary;
    final isActive = item.isActive;
    return Material(
      color: isActive
          ? accent.withValues(alpha: 0.12)
          : AppTheme.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isActive ? accent : accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.icon,
                  color: isActive ? Colors.white : accent,
                  size: 20,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.label,
                style: AppTheme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isActive ? accent : AppTheme.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.subtitle!,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Flat-mode tile (legacy + the logout button). Same look as before so
/// callers that haven't migrated to categories don't visually regress.
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
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.15)
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
                const SizedBox(width: 14),
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
