import 'package:flutter/material.dart';

import 'polish_tokens.dart';

/// A [LinearProgressIndicator] that sweeps from 0 up to [value] on first build
/// (and re-animates on value change), over [PolishMotion.countUp] with
/// [PolishMotion.entrance] (easeOutCubic) easing — matching the count-up rhythm
/// used by [AnimatedCountUp] so progress and numbers feel in sync.
///
/// [value] is clamped to 0..1. Pass [color]/[backgroundColor] to theme it, or
/// leave null to inherit from the ambient [ProgressIndicatorTheme]. A non-null
/// [borderRadius] (default a pill) rounds the track.
///
/// Usage: `AnimatedProgressBar(value: 0.65)`        // sweeps 0 → 65%
/// Usage: `AnimatedProgressBar(value: gradedRatio, minHeight: 8)`
class AnimatedProgressBar extends StatelessWidget {
  final double value;
  final Color? color;
  final Color? backgroundColor;
  final double minHeight;
  final BorderRadius borderRadius;
  final Duration duration;
  final Curve curve;

  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.color,
    this.backgroundColor,
    this.minHeight = 6,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.duration = PolishMotion.countUp,
    this.curve = PolishMotion.entrance,
  });

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: duration,
      curve: curve,
      builder: (context, v, _) {
        return ClipRRect(
          borderRadius: borderRadius,
          child: LinearProgressIndicator(
            value: v,
            minHeight: minHeight,
            color: color,
            backgroundColor: backgroundColor,
          ),
        );
      },
    );
  }
}
