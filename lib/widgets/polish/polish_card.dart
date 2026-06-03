import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'pressable.dart';

/// A consistent, elegant card: theme radius, soft shadow, optional gradient or
/// border, and optional tap feedback via [Pressable].
///
/// Drop-in replacement for the many ad-hoc `Container(decoration: BoxDecoration
/// (borderRadius..., border...))` cards. When [onTap] is set it gains the
/// standard press micro-interaction for free.
///
/// Usage: `PolishCard(onTap: _open, child: Text('Conteúdo'))`
class PolishCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Inner padding. Defaults to 16 on all sides.
  final EdgeInsetsGeometry padding;

  /// Outer margin. Defaults to none.
  final EdgeInsetsGeometry? margin;

  /// Corner radius. Defaults to the app's 12px card radius.
  final double radius;

  /// Solid background. Ignored when [gradient] is provided. Defaults to surface.
  final Color? color;

  /// Optional background gradient (overrides [color]).
  final Gradient? gradient;

  /// Optional border. When null, a subtle divider-colored hairline is drawn
  /// (unless [elevated] is true, which uses a shadow instead of a border).
  final BoxBorder? border;

  /// When true, drops the hairline border and uses a soft drop shadow instead.
  final bool elevated;

  const PolishCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = 12,
    this.color,
    this.gradient,
    this.border,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorder = border ??
        (elevated ? null : Border.all(color: AppTheme.divider));

    final card = Container(
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppTheme.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: effectiveBorder,
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Pressable(onTap: onTap, child: card);
  }
}
