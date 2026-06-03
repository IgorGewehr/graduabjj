import 'package:flutter/material.dart';

/// A button that shows an inline progress indicator while [isLoading] is true,
/// and disables itself in the meantime.
///
/// Sprint 6 helper — replaces the recurring pattern of `if (isLoading) ...
/// CircularProgressIndicator else Text('Salvar')` scattered across screens.
/// Wraps the swap in a 200ms [AnimatedSwitcher] so the change feels organic
/// instead of a hard pop.
///
/// Usage:
/// ```dart
/// LoadingButton(
///   isLoading: _isSaving,
///   onPressed: _save,
///   child: const Text('Salvar'),
/// )
/// ```
class LoadingButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;

  /// Color of the inline spinner. Defaults to [Colors.white] which matches the
  /// foreground color of the default ElevatedButton on a primary background.
  final Color spinnerColor;

  const LoadingButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    required this.child,
    this.style,
    this.spinnerColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = !isLoading && onPressed != null;

    return ElevatedButton(
      style: style,
      // Fire the real callback directly; stays null while loading/disabled so
      // the button greys out and ignores taps.
      onPressed: enabled ? onPressed : null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeOut,
        // Combine a fade with a gentle scale so the spinner/label swap feels
        // organic instead of a hard pop.
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
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
                ),
              )
            : KeyedSubtree(key: const ValueKey('content'), child: child),
      ),
    );
  }
}
