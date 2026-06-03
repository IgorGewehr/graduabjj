import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import 'polish_tokens.dart';

/// Celebration helpers — fire ONLY on genuine wins (graduation, payment
/// success). Two flavours:
///  - [Celebration.confetti] — a one-shot confetti burst overlay.
///  - [SuccessCheck] — an animated success checkmark widget.
class Celebration {
  Celebration._();

  /// Fire a one-shot confetti burst from the top-center of the screen.
  ///
  /// Self-contained: it inserts an [OverlayEntry], plays once, and cleans
  /// itself up — no controller lifecycle to manage at the call site.
  ///
  /// Usage: `Celebration.confetti(context);`  // on graduation success
  static void confetti(BuildContext context) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final controller =
        ConfettiController(duration: const Duration(milliseconds: 800));
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: controller,
              blastDirection: math.pi / 2, // downward
              emissionFrequency: 0.0,
              numberOfParticles: 24,
              maxBlastForce: 18,
              minBlastForce: 8,
              gravity: 0.25,
              shouldLoop: false,
              colors: const [
                AppTheme.primary,
                AppTheme.success,
                AppTheme.warning,
                AppTheme.info,
                AppTheme.beltPurple,
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    controller.play();

    // Remove the overlay once the burst has finished + drifted off.
    Future.delayed(const Duration(milliseconds: 2200), () {
      controller.dispose();
      entry.remove();
    });
  }
}

/// An animated success checkmark: a tinted circle that pops in with a gentle
/// scale + fade. Use inside success dialogs/sheets after a genuine win.
///
/// Usage: `const SuccessCheck()` or `SuccessCheck(size: 96)`
class SuccessCheck extends StatelessWidget {
  final double size;
  final Color? color;

  const SuccessCheck({super.key, this.size = 72, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.success;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check_rounded, size: size * 0.55, color: c),
    )
        .animate()
        .scale(
          begin: const Offset(0.6, 0.6),
          end: const Offset(1, 1),
          duration: PolishMotion.slow,
          curve: Curves.easeOutBack,
        )
        .fadeIn(duration: PolishMotion.normal);
  }
}
