import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'polish_tokens.dart';

/// Wraps any widget so it scales down slightly on tap-down with a light haptic,
/// then springs back — the standard tactile feedback for cards/tiles/buttons.
///
/// A no-op (no scale, no haptic) when [onTap] is null, so it's safe to wrap
/// conditionally-tappable content.
///
/// Usage: `Pressable(onTap: _open, child: PolishCard(...))`
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Fired on long-press (optional). Long-press does not trigger the scale.
  final VoidCallback? onLongPress;

  /// Scale reached on tap-down. Defaults to [PolishMotion.pressScale].
  final double scale;

  /// Emit a [HapticFeedback.lightImpact] on tap-down. Defaults to true.
  final bool haptic;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = PolishMotion.pressScale,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setDown(bool value) {
    if (!_enabled || _down == value) return;
    if (value && widget.haptic) HapticFeedback.lightImpact();
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: PolishMotion.fast,
        curve: PolishMotion.press,
        child: widget.child,
      ),
    );
  }
}
