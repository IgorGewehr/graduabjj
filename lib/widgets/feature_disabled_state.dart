import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'polish/polish.dart';

/// A consistent "feature unavailable" placeholder shown when an academy turned
/// a feature off. Mirrors [PolishedEmptyState] visually (tinted icon circle,
/// title, subtitle, optional CTA) but with a muted accent suited to a disabled
/// state, plus a standardized copy pattern:
///
///   'Sua academia não está usando o [feature].'
///
/// Use across the portal (Jornal, Ranking, Loja, ...) so every gated feature
/// reads the same. Pass [actionLabel] + [onAction] to surface a CTA (e.g. an
/// admin "Configurar em Funcionalidades" deep-link).
class FeatureDisabledState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Accent used for the icon + its soft circle. Defaults to a muted secondary
  /// tone to signal an inactive/disabled feature.
  final Color? accent;

  const FeatureDisabledState({
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
    final color = accent ?? AppTheme.textSecondary;

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
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    ).entrance();
  }
}
