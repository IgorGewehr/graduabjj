import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'polish_tokens.dart';

/// The standardized primary action button for the polish kit.
///
/// One button to cover the recurring "label, optional leading icon, and an
/// inline spinner while busy" pattern — so every screen's main CTA behaves and
/// animates the same way:
///
///  * disables + greys out while [isLoading] (and while [onPressed] is null);
///  * swaps label⇄spinner through a gentle fade+scale [AnimatedSwitcher]
///    (no hard pop);
///  * fires a light [HapticFeedback] selection tick on a real tap.
///
/// It complements the lower-level `LoadingButton` (which only swaps a child):
/// [PolishButton] owns the label/icon/styling so call sites stay tiny.
///
/// Usage:
/// ```dart
/// PolishButton(
///   label: 'Salvar',
///   icon: LucideIcons.check,
///   isLoading: _saving,
///   onPressed: _save,
/// )
/// ```
class PolishButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  /// Stretch to the full available width. Defaults to true (the common CTA).
  final bool expand;

  /// Background color. Defaults to the theme primary.
  final Color? color;

  /// Foreground (label/icon/spinner) color. Defaults to white.
  final Color foreground;

  /// Vertical padding inside the button. Defaults to 16.
  final double verticalPadding;

  /// Corner radius. Defaults to the kit's 14px action radius.
  final double radius;

  /// Emit a light haptic tick on tap. Defaults to true.
  final bool haptic;

  const PolishButton({
    super.key,
    required this.label,
    this.icon,
    this.isLoading = false,
    required this.onPressed,
    this.expand = true,
    this.color,
    this.foreground = Colors.white,
    this.verticalPadding = 16,
    this.radius = 14,
    this.haptic = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppTheme.primary;
    final enabled = !isLoading && onPressed != null;

    final button = ElevatedButton(
      onPressed: enabled
          ? () {
              if (haptic) HapticFeedback.selectionClick();
              onPressed!();
            }
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: foreground,
        disabledBackgroundColor: bg.withValues(alpha: 0.5),
        disabledForegroundColor: foreground.withValues(alpha: 0.8),
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      child: AnimatedSwitcher(
        duration: PolishMotion.fast,
        switchInCurve: PolishMotion.transition,
        switchOutCurve: PolishMotion.transition,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: isLoading
            ? SizedBox(
                key: const ValueKey('loading'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(foreground),
                ),
              )
            : Row(
                key: const ValueKey('content'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
      ),
    );

    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
