import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/navigation/nav_catalog.dart';
import '../../core/theme.dart';
import '../polish/polish.dart';

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

  /// When true the item renders in the discovery/locked state (dimmed icon,
  /// padlock + "Ative" badge) and a tap routes to settings instead of the
  /// destination. Defaults to false (preserves the current appearance).
  final bool locked;

  /// Feature backing a [locked] item — used by [MoreMenuSheet.onLockedTap] for
  /// the settings deep-link. null for unlocked items.
  final FeatureId? feature;

  const MoreMenuItem({
    required this.label,
    required this.icon,
    required this.path,
    this.isActive = false,
    this.category,
    this.subtitle,
    this.accent,
    this.locked = false,
    this.feature,
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

  /// Called when a [MoreMenuItem.locked] item is tapped (deep-link to settings
  /// for the backing feature). When null, locked items fall back to
  /// [onNavigate] so callers that don't opt in keep working.
  final void Function(FeatureId feature)? onLockedTap;

  const MoreMenuSheet({
    super.key,
    required this.items,
    required this.onLogout,
    required this.onNavigate,
    this.headerTitle,
    this.headerSubtitle,
    this.onLockedTap,
  });

  /// Routes a tap on [item] to the locked deep-link or normal navigation.
  void _handleTap(MoreMenuItem item) {
    if (item.locked && item.feature != null && onLockedTap != null) {
      onLockedTap!(item.feature!);
    } else {
      onNavigate(item.path);
    }
  }

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
      children: [
        for (final entry in items.asMap().entries)
          _MenuItemTile(
            item: entry.value,
            onTap: () => _handleTap(entry.value),
          ).entrance(index: entry.key),
      ],
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
        onTap: _handleTap,
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
  final void Function(MoreMenuItem item) onTap;

  const _SectionGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const spacing = 10.0;
        final tileWidth = (c.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final entry in items.asMap().entries)
              SizedBox(
                width: tileWidth,
                child: _SectionTile(
                  item: entry.value,
                  onTap: () => onTap(entry.value),
                ).entrance(index: entry.key),
              ),
          ],
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
    final locked = item.locked;
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: locked
                          ? AppTheme.textDisabled.withValues(alpha: 0.12)
                          : isActive
                              ? accent
                              : accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      item.icon,
                      color: locked
                          ? AppTheme.textDisabled
                          : isActive
                              ? Colors.white
                              : accent,
                      size: 20,
                    ),
                  ),
                  if (locked) const _LockedBadge(),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.label,
                style: AppTheme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: locked
                      ? AppTheme.textDisabled
                      : isActive
                          ? accent
                          : AppTheme.textPrimary,
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

/// Small "Ative" pill with a padlock, shown on locked discovery entries.
class _LockedBadge extends StatelessWidget {
  const _LockedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.lock, size: 11, color: AppTheme.warning),
          const SizedBox(width: 4),
          Text(
            'Ative',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.warning,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
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
    final locked = item.locked && !isLogout;

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
                    color: locked
                        ? AppTheme.textDisabled.withValues(alpha: 0.12)
                        : isActive
                            ? Colors.white.withValues(alpha: 0.15)
                            : isLogout
                                ? AppTheme.errorLight
                                : AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.icon,
                    size: 20,
                    color: locked
                        ? AppTheme.textDisabled
                        : isActive
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
                      color: locked
                          ? AppTheme.textDisabled
                          : isActive
                              ? Colors.white
                              : isLogout
                                  ? AppTheme.error
                                  : AppTheme.textPrimary,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (locked)
                  const _LockedBadge()
                else
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
