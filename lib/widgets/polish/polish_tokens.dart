import 'package:flutter/material.dart';

/// Centralized motion tokens for the visual-polish kit.
///
/// Every duration/curve used by entrances, transitions and micro-interactions
/// lives here so the whole app animates with one consistent rhythm. Downstream
/// screens should reference these instead of hand-rolling magic numbers.
///
/// Taste rules baked in: subtle + fast (150–400ms), gentle easing, and
/// staggers that cap quickly so long lists never feel sluggish.
class PolishMotion {
  PolishMotion._();

  // ── Durations ────────────────────────────────────────────────────────────
  /// Snappy tap / press feedback.
  static const Duration fast = Duration(milliseconds: 150);

  /// Default entrance + transition duration.
  static const Duration normal = Duration(milliseconds: 320);

  /// Slightly slower, for hero-ish first appearances.
  static const Duration slow = Duration(milliseconds: 400);

  /// Count-up animation for stat numbers.
  static const Duration countUp = Duration(milliseconds: 600);

  // ── Stagger ──────────────────────────────────────────────────────────────
  /// Per-index delay added to staggered list entrances.
  static const Duration staggerStep = Duration(milliseconds: 55);

  /// Hard cap so deep lists don't keep delaying past the first viewport.
  static const int staggerMaxIndex = 6;

  /// Resolve the stagger delay for [index], capped at [staggerMaxIndex].
  static Duration staggerDelay(int index) {
    final capped = index < 0
        ? 0
        : (index > staggerMaxIndex ? staggerMaxIndex : index);
    return staggerStep * capped;
  }

  // ── Curves ───────────────────────────────────────────────────────────────
  /// Default entrance curve.
  static const Curve entrance = Curves.easeOutCubic;

  /// Default transition curve.
  static const Curve transition = Curves.easeOut;

  /// Press-down / spring-back curve.
  static const Curve press = Curves.easeOut;

  // ── Geometry ─────────────────────────────────────────────────────────────
  /// Vertical slide travel for entrances, as a fraction of widget height.
  static const double slideBegin = 0.06;

  /// Scale a [Pressable] shrinks to on tap-down.
  static const double pressScale = 0.97;
}
