import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'polish_tokens.dart';

/// Standardized entrance presets so every screen animates identically.
///
/// Built on flutter_animate; durations/curves come from [PolishMotion].
extension PolishEntrance on Widget {
  /// Fade + small slide-up entrance with an optional per-[index] stagger.
  ///
  /// The stagger is capped (see [PolishMotion.staggerMaxIndex]) so long lists
  /// never feel sluggish — only the first viewport meaningfully staggers.
  ///
  /// Usage: `MyCard().entrance(index: i)`
  Widget entrance({int index = 0}) {
    return animate(delay: PolishMotion.staggerDelay(index))
        .fadeIn(duration: PolishMotion.normal, curve: PolishMotion.entrance)
        .slideY(
          begin: PolishMotion.slideBegin,
          end: 0,
          duration: PolishMotion.normal,
          curve: PolishMotion.entrance,
        );
  }

  /// Plain quick fade-in, no movement — for headers, labels, hero blocks.
  ///
  /// Usage: `Text('Olá').fadeInQuick()`
  Widget fadeInQuick() {
    return animate().fadeIn(
      duration: PolishMotion.fast,
      curve: PolishMotion.transition,
    );
  }
}
