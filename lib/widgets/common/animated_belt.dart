import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'belt_badge.dart';

// ============================================
// AnimatedBelt — "evolution morph" belt widget
// ============================================
//
// On mount, the belt starts as WHITE / 0 stripes and animates progressively up
// to the student's current belt: it sweeps the adult belt colors in order
// (white → blue → purple → brown → black), stopping on the student's belt, with
// a smooth crossfade between each color. Once the color has settled, the stripes
// pop in one-by-one, quickly.
//
// The animation plays exactly once on first appearance (no infinite loops).
// Set [animate] to false to render the final state immediately (e.g. for tests
// or when the belt is off-screen).
//
// Usable both compact (home) and in evidence (profile) via [size] and
// [highlight].

/// Adult belt color progression, in graduation order. The morph sweeps through
/// this list up to (and including) the student's belt. Belts outside this list
/// (kids colors, coral/red master ranks) skip the sweep and simply fade in at
/// their own color.
const List<String> _beltProgression = ['white', 'blue', 'purple', 'brown', 'black'];

class AnimatedBelt extends StatefulWidget {
  /// The student's current belt key (e.g. 'white', 'blue', 'black', 'grey-white').
  final String belt;

  /// Number of degrees/stripes on the belt.
  final int stripes;

  /// Visual size of the belt. Defaults to [BeltSize.large] since this widget is
  /// meant to be a focal point; use [BeltSize.small]/[BeltSize.medium] for
  /// compact placements (e.g. the home header).
  final BeltSize size;

  /// When true, the belt is rendered "in evidence": a slightly larger scale, a
  /// soft glow in the belt's own color, and the label shown below. Ideal for
  /// the profile hero. When false, renders flat & compact (good for the home).
  final bool highlight;

  /// Whether to show the textual label (belt name + degrees) below the belt.
  /// Defaults to following [highlight].
  final bool? showLabel;

  /// When false, skips the morph and renders the final belt immediately.
  final bool animate;

  /// Total duration budget for the color sweep (excluding the stripe pop-in).
  final Duration sweepDuration;

  const AnimatedBelt({
    super.key,
    required this.belt,
    this.stripes = 0,
    this.size = BeltSize.large,
    this.highlight = false,
    this.showLabel,
    this.animate = true,
    this.sweepDuration = const Duration(milliseconds: 1400),
  });

  @override
  State<AnimatedBelt> createState() => _AnimatedBeltState();
}

class _AnimatedBeltState extends State<AnimatedBelt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// The ordered list of belt keys the color sweep walks through, ending on the
  /// student's belt. For belts in [_beltProgression] this is the prefix up to
  /// the belt; for any other belt (kids/coral) it's just `['white', belt]` so we
  /// still get a graceful fade-in.
  late List<String> _sweepStops;

  /// Fraction of the controller [0..1] reserved for the color sweep; the
  /// remainder animates the stripes popping in.
  late double _sweepEnd;

  @override
  void initState() {
    super.initState();
    _buildTimeline();

    _controller = AnimationController(
      vsync: this,
      duration: _totalDuration(),
    );

    if (widget.animate) {
      // Defer to the next frame so the white/0 initial state is painted first,
      // then morph once.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.value = 1.0;
    }
  }

  void _buildTimeline() {
    final targetIndex = _beltProgression.indexOf(widget.belt);
    if (targetIndex >= 0) {
      _sweepStops = _beltProgression.sublist(0, targetIndex + 1);
    } else {
      // Kids / coral / unknown belts: just fade from white into the real color.
      _sweepStops = ['white', widget.belt];
    }

    // Split the controller timeline: most of it is the color sweep, a short tail
    // is the stripe pop-in (only if there are stripes to show).
    final hasStripes = widget.stripes > 0;
    final hasMultipleStops = _sweepStops.length > 1;
    if (hasStripes && hasMultipleStops) {
      _sweepEnd = 0.7;
    } else if (hasStripes) {
      _sweepEnd = 0.45;
    } else {
      _sweepEnd = 1.0;
    }
  }

  Duration _totalDuration() {
    // The stripe tail scales with the number of stripes so each one gets a
    // perceptible (but quick) pop. Keep it short.
    final stripeMs = widget.stripes > 0 ? 150 + widget.stripes * 120 : 0;
    return widget.sweepDuration + Duration(milliseconds: stripeMs);
  }

  @override
  void didUpdateWidget(covariant AnimatedBelt old) {
    super.didUpdateWidget(old);
    if (old.belt != widget.belt ||
        old.stripes != widget.stripes ||
        old.sweepDuration != widget.sweepDuration) {
      _buildTimeline();
      _controller.duration = _totalDuration();
      _controller.value = 0;
      if (widget.animate) {
        _controller.forward();
      } else {
        _controller.value = 1.0;
      }
    } else if (old.animate != widget.animate && !widget.animate) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Resolve the belt color shown at the current sweep progress [t] in [0..1].
  /// We linearly interpolate (lerp) between adjacent belt colors so the sweep
  /// crossfades elegantly instead of hard-cutting.
  Color _sweepColor(double t) {
    if (_sweepStops.length == 1) {
      return AppTheme.getBeltColor(_sweepStops.first);
    }
    final segments = _sweepStops.length - 1;
    final scaled = (t.clamp(0.0, 1.0)) * segments;
    final i = scaled.floor().clamp(0, segments - 1);
    final local = scaled - i;
    final from = AppTheme.getBeltColor(_sweepStops[i]);
    final to = AppTheme.getBeltColor(_sweepStops[i + 1]);
    return Color.lerp(from, to, Curves.easeInOut.transform(local)) ?? to;
  }

  /// Which belt key is "current" at sweep progress [t] — used to drive the
  /// white-belt border, the black-belt red stripes, and combo middle-stripes
  /// so they appear only once the sweep has reached that belt.
  String _currentBeltKey(double t) {
    if (_sweepStops.length == 1) return _sweepStops.first;
    final segments = _sweepStops.length - 1;
    final scaled = (t.clamp(0.0, 1.0)) * segments;
    final i = scaled.round().clamp(0, segments);
    return _sweepStops[i];
  }

  @override
  Widget build(BuildContext context) {
    final showLabel = widget.showLabel ?? widget.highlight;
    final finalColor = AppTheme.getBeltColor(widget.belt);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        // Sweep progress in [0..1] over the color phase, then stripe progress.
        final sweepT = (_sweepEnd <= 0) ? 1.0 : (v / _sweepEnd).clamp(0.0, 1.0);
        final stripeT = _sweepEnd >= 1.0
            ? 0.0
            : ((v - _sweepEnd) / (1 - _sweepEnd)).clamp(0.0, 1.0);

        final beltColor = _sweepColor(sweepT);
        final beltKey = _currentBeltKey(sweepT);

        // How many stripes are currently visible, and the fractional pop of the
        // newest one (for a tiny scale-in on the leading stripe).
        final stripeFloat = stripeT * widget.stripes;
        final fullStripes = stripeFloat.floor();
        final partial = stripeFloat - fullStripes;

        return _BeltVisual(
          beltColor: beltColor,
          beltKey: beltKey,
          finalBeltKey: widget.belt,
          size: widget.size,
          highlight: widget.highlight,
          fullStripes: fullStripes.clamp(0, widget.stripes),
          partialStripeFraction: partial.clamp(0.0, 1.0),
          totalStripes: widget.stripes,
          showLabel: showLabel,
          glowColor: finalColor,
          // Glow fades in as the sweep completes (only when highlighting).
          glowStrength: widget.highlight ? sweepT : 0.0,
        );
      },
    );
  }
}

// ============================================
// _BeltVisual — pure render of one belt frame
// ============================================
class _BeltVisual extends StatelessWidget {
  final Color beltColor;
  final String beltKey;
  final String finalBeltKey;
  final BeltSize size;
  final bool highlight;
  final int fullStripes;
  final double partialStripeFraction;
  final int totalStripes;
  final bool showLabel;
  final Color glowColor;
  final double glowStrength;

  const _BeltVisual({
    required this.beltColor,
    required this.beltKey,
    required this.finalBeltKey,
    required this.size,
    required this.highlight,
    required this.fullStripes,
    required this.partialStripeFraction,
    required this.totalStripes,
    required this.showLabel,
    required this.glowColor,
    required this.glowStrength,
  });

  @override
  Widget build(BuildContext context) {
    final config = _beltSizeConfig(size);
    final isWhiteBelt = beltKey == 'white';
    final isBlackBelt = beltKey == 'black';
    final showWhiteStripe = beltKey.endsWith('-white') || beltKey == 'coral';
    final showBlackStripe = beltKey.endsWith('-black');

    final scale = highlight ? 1.12 : 1.0;

    Widget belt = Container(
      width: config.width,
      height: config.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
          // Soft colored glow when in evidence.
          if (highlight && glowStrength > 0)
            BoxShadow(
              color: glowColor.withValues(alpha: 0.45 * glowStrength),
              blurRadius: 18 * glowStrength,
              spreadRadius: 1 * glowStrength,
            ),
        ],
        border: isWhiteBelt
            ? Border.all(color: AppTheme.divider, width: 1)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // Belt body (colored part)
          Expanded(
            child: Container(
              color: beltColor,
              child: Stack(
                children: [
                  if (showWhiteStripe)
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          height: config.height * 0.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (showBlackStripe)
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          height: config.height * 0.2,
                          color: const Color(0xFF171717),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Black tip (ponta preta) — full height — holds the stripes.
          Container(
            width: config.tipWidth,
            height: config.height,
            color: isBlackBelt
                ? const Color(0xFF2D2D2D)
                : const Color(0xFF171717),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: _buildStripes(config, isBlackBelt, isWhiteBelt),
            ),
          ),
        ],
      ),
    );

    belt = Transform.scale(scale: scale, child: belt);

    if (!showLabel) return belt;

    final label = getBeltLabel(finalBeltKey);
    final shownStripes = fullStripes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        belt,
        SizedBox(height: highlight ? 10 : 4),
        Text(
          shownStripes > 0 ? '$label  $shownStripes°' : label,
          style: TextStyle(
            fontSize: highlight ? config.fontSize + 2 : config.fontSize,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStripes(
    _BeltSizeConfig config,
    bool isBlackBelt,
    bool isWhiteBelt,
  ) {
    final visible = fullStripes;
    if (visible <= 0 && partialStripeFraction <= 0) return const [];

    final stripeColor =
        isBlackBelt ? const Color(0xFFDC2626) : Colors.white;

    final widgets = <Widget>[];
    for (var index = 0; index < visible; index++) {
      widgets.add(_stripe(config, stripeColor, isWhiteBelt, 1.0));
    }
    // Leading (newest) stripe scaling in.
    if (partialStripeFraction > 0 && visible < totalStripes) {
      final t = Curves.easeOutBack.transform(partialStripeFraction);
      widgets.add(_stripe(config, stripeColor, isWhiteBelt, t));
    }
    return widgets;
  }

  Widget _stripe(
    _BeltSizeConfig config,
    Color color,
    bool isWhiteBelt,
    double scale,
  ) {
    return Transform.scale(
      scale: scale.clamp(0.0, 1.0),
      child: Opacity(
        opacity: scale.clamp(0.0, 1.0),
        child: Container(
          width: config.stripeWidth,
          height: config.height * 0.65,
          margin: EdgeInsets.symmetric(horizontal: config.stripeGap / 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
            boxShadow: isWhiteBelt
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

// ============================================
// Local size geometry (mirrors BeltBadge's config)
// ============================================
class _BeltSizeConfig {
  final double width;
  final double height;
  final double tipWidth;
  final double stripeWidth;
  final double stripeGap;
  final double fontSize;

  const _BeltSizeConfig({
    required this.width,
    required this.height,
    required this.tipWidth,
    required this.stripeWidth,
    required this.stripeGap,
    required this.fontSize,
  });
}

_BeltSizeConfig _beltSizeConfig(BeltSize size) {
  switch (size) {
    case BeltSize.small:
      return const _BeltSizeConfig(
        width: 70,
        height: 16,
        tipWidth: 20,
        stripeWidth: 2.5,
        stripeGap: 1.5,
        fontSize: 10,
      );
    case BeltSize.medium:
      return const _BeltSizeConfig(
        width: 100,
        height: 22,
        tipWidth: 28,
        stripeWidth: 3.5,
        stripeGap: 2,
        fontSize: 11,
      );
    case BeltSize.large:
      return const _BeltSizeConfig(
        width: 140,
        height: 28,
        tipWidth: 38,
        stripeWidth: 5,
        stripeGap: 2.5,
        fontSize: 13,
      );
  }
}
