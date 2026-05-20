import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';

/// Item descriptor for a quick action tile.
class _QuickActionItem {
  final IconData icon;
  final String label;
  final String route;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}

const List<_QuickActionItem> _kActions = [
  _QuickActionItem(
    icon: LucideIcons.shoppingBag,
    label: 'Loja',
    route: '/portal/loja',
  ),
  _QuickActionItem(
    icon: LucideIcons.trophy,
    label: 'Competicoes',
    route: '/portal/competicoes',
  ),
  _QuickActionItem(
    icon: LucideIcons.calendar,
    label: 'Horarios',
    route: '/portal/horarios',
  ),
  _QuickActionItem(
    icon: LucideIcons.history,
    label: 'Jornada',
    route: '/portal/linha-do-tempo',
  ),
  _QuickActionItem(
    icon: LucideIcons.clipboardCheck,
    label: 'Comportamento',
    route: '/portal/comportamento',
  ),
  _QuickActionItem(
    icon: LucideIcons.package,
    label: 'Meus Pedidos',
    route: '/portal/loja',
  ),
];

/// Grid 3×2 de acesso rapido as features que saíram do bottom nav.
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acesso rapido',
          style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _kActions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            final item = _kActions[index];
            return _QuickActionTile(item: item)
                .animate(delay: (index * 60).ms)
                .fadeIn(duration: 200.ms)
                .slideY(begin: 0.15, end: 0);
          },
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatefulWidget {
  final _QuickActionItem item;

  const _QuickActionTile({required this.item});

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        context.go(widget.item.route);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.item.icon,
                size: 28,
                color: AppTheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                widget.item.label,
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
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
