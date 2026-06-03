import 'package:flutter/material.dart';

import 'polish_tokens.dart';

/// Animates a number from 0 up to [value] on first build (and on value change),
/// over [PolishMotion.countUp]. Great for stat tiles and dashboard counters.
///
/// Pass [decimals] > 0 for doubles; default 0 renders an int.
///
/// Usage: `AnimatedCountUp(value: studentCount)`  // "0 → 248"
/// Usage: `AnimatedCountUp(value: 4.5, decimals: 1, suffix: '★')`
class AnimatedCountUp extends StatelessWidget {
  final num value;
  final int decimals;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  const AnimatedCountUp({
    super.key,
    required this.value,
    this.decimals = 0,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.duration = PolishMotion.countUp,
    this.curve = PolishMotion.entrance,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: curve,
      builder: (context, v, _) {
        final text = decimals > 0
            ? v.toStringAsFixed(decimals)
            : v.round().toString();
        return Text('$prefix$text$suffix', style: style);
      },
    );
  }
}
