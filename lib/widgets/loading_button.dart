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
    return ElevatedButton(
      style: style,
      onPressed: isLoading ? null : onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
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
