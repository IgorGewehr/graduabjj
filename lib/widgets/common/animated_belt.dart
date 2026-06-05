import 'package:flutter/material.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import 'belt_badge.dart';

// ============================================
// AnimatedBelt — "evolution morph" belt widget (multi-sport)
// ============================================
//
// On mount, the belt starts as the FIRST grade of the student's sport (white /
// 0 stripes) and animates progressively up to the student's current grade: it
// sweeps the sport's grade-ladder colors in order (e.g. for BJJ
// white → blue → purple → brown → black), stopping on the student's grade, with
// a smooth crossfade between each color. Once the color has settled, the
// degrees/stripes pop in one-by-one, quickly.
//
// It is sport-aware: pass [sportId] and the widget reads that sport's grade
// ladder (from core/sports.dart) — so a Muay Thai student morphs through the
// prajied colors and shows the "ponta" adornment, a Judô/Luta Livre student
// morphs through their own colors, etc. For Muay Thai the right federation
// variant is resolved from the stored grade id, so CBMT vs CBMTT both render.
//
// The animation plays exactly once on first appearance (no infinite loops).
// Set [animate] to false to render the final state immediately (e.g. for tests
// or when the belt is off-screen).
//
// Usable both compact (home) and in evidence (profile) via [size] and
// [highlight].

class AnimatedBelt extends StatefulWidget {
  /// The student's current grade key (e.g. 'white', 'blue', 'black',
  /// 'grey-white', or a Muay Thai 'red-lightblue').
  final String belt;

  /// Number of degrees/stripes on the belt.
  final int stripes;

  /// The sport whose grade ladder drives the colors, ordering and adornments.
  /// Defaults to BJJ for backward compatibility.
  final SportId sportId;

  /// For Muay Thai only: the academy's federation system
  /// ([AcademySettings.muaythaiGradeSystem], 'cbmt' | 'cbmtt'). Used as the
  /// authoritative ladder when the stored grade id is ambiguous between the two
  /// federations (the shared starting 'white', or empty). When the stored grade
  /// is unambiguous it wins; for other sports this is ignored.
  final String? muaythaiVariant;

  /// Visual size of the belt. Defaults to [BeltSize.large] since this widget is
  /// meant to be a focal point; use [BeltSize.small]/[BeltSize.medium] for
  /// compact placements (e.g. the home header).
  final BeltSize size;

  /// When true, the belt is rendered "in evidence": a slightly larger scale.
  /// Ideal for the profile/home hero. When false, renders flat & compact.
  final bool highlight;

  /// When false, skips the morph and renders the final belt immediately.
  final bool animate;

  /// Total duration budget for the color sweep (excluding the stripe pop-in).
  final Duration sweepDuration;

  const AnimatedBelt({
    super.key,
    required this.belt,
    this.stripes = 0,
    this.sportId = SportId.bjj,
    this.muaythaiVariant,
    this.size = BeltSize.large,
    this.highlight = false,
    this.animate = true,
    this.sweepDuration = const Duration(milliseconds: 1600),
  });

  @override
  State<AnimatedBelt> createState() => _AnimatedBeltState();
}

class _AnimatedBeltState extends State<AnimatedBelt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// The ordered list of grade ids the color sweep walks through, ending on the
  /// student's current grade. It's the prefix of the sport's ladder up to (and
  /// including) the student's grade; for an unknown/above-black grade we still
  /// get a graceful fade-in from the first grade into the real color.
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
      // Defer to the next frame so the first-grade/0 initial state is painted
      // first, then morph once.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.value = 1.0;
    }
  }

  /// The ordered grade ids for the student's sport (resolving the right Muay
  /// Thai federation variant from the stored grade). Excludes above-black
  /// master ranks from the sweep PATH so the morph doesn't walk through coral/
  /// red on its way to a normal grade — but the target grade itself, even if
  /// above-black, is always honored as the final stop.
  List<String> _sportLadder() {
    String? variant;
    if (widget.sportId == SportId.muaythai) {
      final belt = widget.belt;
      // 'white' (and empty) are shared/ambiguous between the two federations, so
      // honor the academy's configured system; any other stored id unambiguously
      // belongs to one ladder and resolves itself.
      final ambiguous = belt.isEmpty || belt == 'white';
      variant = ambiguous
          ? (widget.muaythaiVariant ?? resolveMuaythaiVariant(belt))
          : resolveMuaythaiVariant(belt);
    }
    final grades = getGradesForSport(widget.sportId, muaythaiVariant: variant);
    // Exclude above-black master ranks (coral/red) from the sweep PATH so the
    // morph never crossfades through them on its way to a normal grade. The
    // target grade itself, even if above-black, is honored below.
    return grades.where((g) => !g.aboveBlack).map((g) => g.id).toList();
  }

  /// Stripes/graus to actually render, gated on the TARGET grade: zero unless
  /// the sport supports stripes AND the final grade allows them, and clamped to
  /// that grade's maxStripes. So Judô / Muay Thai / Luta Livre never show graus,
  /// and an over-count stored on a BJJ grade can't paint extra stripes.
  int get _effectiveStripes {
    final targetDef = getGradeDefinition(widget.sportId, widget.belt);
    final maxStripes = targetDef?.maxStripes ?? 0;
    final allow = getSport(widget.sportId).supportsStripes && maxStripes > 0;
    return allow ? widget.stripes.clamp(0, maxStripes) : 0;
  }

  void _buildTimeline() {
    final ladder = _sportLadder();
    final targetIndex = ladder.indexOf(widget.belt);
    if (targetIndex >= 0) {
      _sweepStops = ladder.sublist(0, targetIndex + 1);
    } else if (getGradeDefinition(widget.sportId, widget.belt)?.aboveBlack ==
            true &&
        ladder.isNotEmpty) {
      // Above-black master rank (e.g. BJJ coral/red): sweep the full normal
      // ladder, then land on the master rank as the single final crossfade.
      _sweepStops = [...ladder, widget.belt];
    } else {
      // Not on the adult ladder: it may be a kids-only grade (BJJ
      // grey/yellow/orange/green, etc.). Resolve against the kids ladder so the
      // sweep walks the full progression instead of a flat white→color fade.
      // getGradesForSport(category: 'kids') is a no-op for sports without a kids
      // ladder, so other sports fall through to the graceful 2-stop fade.
      final kidsLadder = getGradesForSport(widget.sportId, category: 'kids')
          .where((g) => !g.aboveBlack)
          .map((g) => g.id)
          .toList();
      final kidsIndex = kidsLadder.indexOf(widget.belt);
      if (kidsIndex >= 0) {
        _sweepStops = kidsLadder.sublist(0, kidsIndex + 1);
      } else {
        final first = ladder.isNotEmpty ? ladder.first : 'white';
        _sweepStops =
            first == widget.belt ? [widget.belt] : [first, widget.belt];
      }
    }

    // Split the controller timeline: most of it is the color sweep, a short tail
    // is the stripe pop-in (only if there are stripes to show).
    final hasStripes = _effectiveStripes > 0;
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
    final stripeMs = _effectiveStripes > 0 ? 150 + _effectiveStripes * 120 : 0;
    return widget.sweepDuration + Duration(milliseconds: stripeMs);
  }

  @override
  void didUpdateWidget(covariant AnimatedBelt old) {
    super.didUpdateWidget(old);
    if (old.belt != widget.belt ||
        old.stripes != widget.stripes ||
        old.sportId != widget.sportId ||
        old.muaythaiVariant != widget.muaythaiVariant ||
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

  /// Resolve the body color of a grade id within the student's sport.
  Color _gradeColor(String gradeId) =>
      getGradeColor(widget.sportId, gradeId);

  /// Resolve the belt color shown at the current sweep progress [t] in [0..1].
  /// We linearly interpolate (lerp) between adjacent grade colors so the sweep
  /// crossfades elegantly across the intermediate colors instead of
  /// hard-cutting. A smooth ease softens each crossover.
  Color _sweepColor(double t) {
    if (_sweepStops.length == 1) {
      return _gradeColor(_sweepStops.first);
    }
    final segments = _sweepStops.length - 1;
    final scaled = (t.clamp(0.0, 1.0)) * segments;
    final i = scaled.floor().clamp(0, segments - 1);
    final local = scaled - i;
    final from = _gradeColor(_sweepStops[i]);
    final to = _gradeColor(_sweepStops[i + 1]);
    // easeInOutCubic gives a calmer, more elegant settle on each color than a
    // linear crossfade.
    return Color.lerp(from, to, Curves.easeInOutCubic.transform(local)) ?? to;
  }

  /// Which grade id is "current" at sweep progress [t] — used to drive the
  /// adornments (white/black middle stripes, tip "ponta" color) so they appear
  /// only once the sweep has reached that grade.
  String _currentGradeKey(double t) {
    if (_sweepStops.length == 1) return _sweepStops.first;
    final segments = _sweepStops.length - 1;
    final scaled = (t.clamp(0.0, 1.0)) * segments;
    // floor() to match _sweepColor's segment indexing, so a grade's adornment
    // (tip color / middle stripe) only appears once the body color has actually
    // arrived at that grade — never one segment early.
    final i = scaled.floor().clamp(0, segments);
    return _sweepStops[i];
  }

  @override
  Widget build(BuildContext context) {
    // Stripe-/belt-less sports (boxing, musculação) have no grade ladder to
    // morph — render nothing rather than a meaningless white belt.
    if (getSport(widget.sportId).gradeSystem == GradeSystem.none) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final raw = _controller.value;
        // Ease the whole controller so both the sweep and the stripe phase feel
        // refined — but keep the stripe pop's own easeOutBack character by only
        // smoothing the sweep portion.
        // Sweep progress in [0..1] over the color phase, then stripe progress.
        final sweepRaw =
            (_sweepEnd <= 0) ? 1.0 : (raw / _sweepEnd).clamp(0.0, 1.0);
        final sweepT = Curves.easeInOutCubic.transform(sweepRaw);
        final stripeT = _sweepEnd >= 1.0
            ? 0.0
            : ((raw - _sweepEnd) / (1 - _sweepEnd)).clamp(0.0, 1.0);

        final beltColor = _sweepColor(sweepT);
        final gradeKey = _currentGradeKey(sweepT);
        final gradeDef = getGradeDefinition(widget.sportId, gradeKey);

        // How many stripes are currently visible, and the fractional pop of the
        // newest one (for a tiny scale-in on the leading stripe).
        final effectiveStripes = _effectiveStripes;
        final stripeFloat = stripeT * effectiveStripes;
        final fullStripes = stripeFloat.floor();
        final partial = stripeFloat - fullStripes;

        return _BeltVisual(
          beltColor: beltColor,
          gradeKey: gradeKey,
          gradeDef: gradeDef,
          sportId: widget.sportId,
          size: widget.size,
          highlight: widget.highlight,
          fullStripes: fullStripes.clamp(0, effectiveStripes),
          partialStripeFraction: partial.clamp(0.0, 1.0),
          totalStripes: effectiveStripes,
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
  final String gradeKey;
  final GradeDefinition? gradeDef;
  final SportId sportId;
  final BeltSize size;
  final bool highlight;
  final int fullStripes;
  final double partialStripeFraction;
  final int totalStripes;

  const _BeltVisual({
    required this.beltColor,
    required this.gradeKey,
    required this.gradeDef,
    required this.sportId,
    required this.size,
    required this.highlight,
    required this.fullStripes,
    required this.partialStripeFraction,
    required this.totalStripes,
  });

  @override
  Widget build(BuildContext context) {
    final config = _beltSizeConfig(size);
    // A light body (white/branca, prata, ouro, amarela, azul clara) needs a
    // border to stand out from the white page. Luminance alone is unreliable
    // here — standard yellow (~0.50) and Muay Thai light-blue (~0.36) read as
    // "dark" yet blend into the page — so we combine an honest luminance cutoff
    // with the grade's own label semantics. 'azul clara' is matched at the
    // START of the label so the red-bodied 'Vermelha ponta azul clara' stays
    // borderless.
    final luminance = beltColor.computeLuminance();
    final gradeLabel = gradeDef?.label.toLowerCase() ?? '';
    final isLightBody = luminance > 0.55 ||
        gradeLabel.contains('branca') ||
        gradeLabel.contains('prata') ||
        gradeLabel.contains('ouro') ||
        gradeLabel.contains('amarela') ||
        gradeLabel.startsWith('azul clara');
    final isBlackBelt = gradeDef?.isBlackBelt ?? (gradeKey == 'black');
    // BJJ black belts carry a RED rank bar (ponta vermelha) with white degrees,
    // the traditional faixa-preta look. Other sports keep the classic charcoal
    // tip with red degrees.
    final isBjjBlackBar = isBlackBelt && sportId == SportId.bjj;

    // The grade's "ponta" adornment color (Muay Thai prajied tip, BJJ/Judô
    // coral red, Luta Livre DAN tip). When present, the belt tip is drawn in
    // this color instead of the default black tip.
    final tipColor = gradeDef?.tipColor;

    // Compound grade ids without an explicit tipColor still carry a middle
    // stripe convention shared across sports: '-white' → white stripe,
    // '-black' → black stripe.
    final showWhiteStripe = tipColor == null && gradeKey.endsWith('-white');
    final showBlackStripe = tipColor == null && gradeKey.endsWith('-black');

    final scale = highlight ? 1.12 : 1.0;

    // The tip that holds the graus: a grade's own "ponta" color when it has one
    // (so the adornment reads as part of the belt). BJJ black belt → red rank
    // bar; other black belts → slightly lighter charcoal so red graus pop;
    // everything else → the classic black tip.
    final Color holderColor = tipColor ??
        (isBjjBlackBar
            ? const Color(0xFFB91C1C)
            : isBlackBelt
                ? const Color(0xFF2D2D2D)
                : const Color(0xFF171717));

    Widget belt = Container(
      width: config.width,
      height: config.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          // Subtle, flat depth only — no distracting colored glow.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        border: isLightBody
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

          // Tip (ponta) — full height — holds the stripes. Coloured by the
          // grade's adornment when present, else the classic black tip.
          Container(
            width: config.tipWidth,
            height: config.height,
            color: holderColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: _buildStripes(config, isBlackBelt, isLightBody),
            ),
          ),
        ],
      ),
    );

    belt = Transform.scale(scale: scale, child: belt);
    return belt;
  }

  List<Widget> _buildStripes(
    _BeltSizeConfig config,
    bool isBlackBelt,
    bool isLightBody,
  ) {
    final visible = fullStripes;
    if (visible <= 0 && partialStripeFraction <= 0) return const [];

    // White graus on the BJJ red rank bar (and on every light/colored belt);
    // red graus only on the charcoal tip of non-BJJ black belts.
    final stripeColor = (isBlackBelt && sportId != SportId.bjj)
        ? const Color(0xFFDC2626)
        : Colors.white;

    final widgets = <Widget>[];
    for (var index = 0; index < visible; index++) {
      widgets.add(_stripe(config, stripeColor, isLightBody, 1.0));
    }
    // Leading (newest) stripe scaling in.
    if (partialStripeFraction > 0 && visible < totalStripes) {
      final t = Curves.easeOutBack.transform(partialStripeFraction);
      widgets.add(_stripe(config, stripeColor, isLightBody, t));
    }
    return widgets;
  }

  Widget _stripe(
    _BeltSizeConfig config,
    Color color,
    bool isLightBody,
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
            boxShadow: isLightBody
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
        width: 168,
        height: 34,
        tipWidth: 44,
        stripeWidth: 5.5,
        stripeGap: 3,
        fontSize: 13,
      );
  }
}
