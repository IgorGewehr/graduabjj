import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'entrance.dart';

/// A friendly, consistent empty-state: an icon in a soft tinted circle, a
/// title, an optional subtitle, and an optional action button. Fades/slides in
/// subtly so empty lists don't feel jarring.
///
/// Usage:
/// ```dart
/// PolishedEmptyState(
///   icon: LucideIcons.users,
///   title: 'Nenhum aluno ainda',
///   subtitle: 'Adicione o primeiro aluno para começar.',
///   actionLabel: 'Adicionar',
///   onAction: _add,
/// )
/// ```
class PolishedEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Accent used for the icon + its soft circle. Defaults to the theme primary.
  final Color? accent;

  const PolishedEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    ).entrance();
  }
}
