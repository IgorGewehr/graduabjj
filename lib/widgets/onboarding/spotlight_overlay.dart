import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../polish/polish.dart';

/// Reusable spotlight / coachmark overlay.
///
/// Darkens the whole screen except a rounded "hole" cut around a target widget,
/// and floats a tip balloon (title + message + a small "Entendi" button) above
/// or below the target depending on available space. Tapping anywhere — or the
/// button — dismisses it.
///
/// HOW TO USE:
///  1. Give the widget you want to highlight a `GlobalKey`:
///       final myKey = GlobalKey();
///       IconButton(key: myKey, ...);
///  2. After the target is laid out (e.g. in a post-frame callback or on a
///     user action), call:
///       await SpotlightOverlay.show(
///         context,
///         targetKey: myKey,
///         title: 'Marque presença',
///         message: 'Toque aqui para registrar sua presença na aula.',
///       );
///
/// SAFE NO-OP: if the target key has no current context / no laid-out RenderBox
/// (e.g. the widget isn't mounted yet), [show] returns immediately without
/// throwing — so it's safe to fire optimistically.
class SpotlightOverlay {
  SpotlightOverlay._();

  /// Show the coachmark over the widget referenced by [targetKey].
  ///
  /// Completes when the overlay is dismissed (tap or button). [onDismiss] also
  /// fires at that moment.
  static Future<void> show(
    BuildContext context, {
    required GlobalKey targetKey,
    required String title,
    required String message,
    String dismissLabel = 'Entendi',
    VoidCallback? onDismiss,
  }) async {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    // Resolve the target rect on screen. Bail out safely if it isn't laid out.
    final targetContext = targetKey.currentContext;
    final renderObject = targetContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final size = renderObject.size;
    if (size.isEmpty) return;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final targetRect = topLeft & size;

    final completer = Completer<void>();
    late OverlayEntry entry;

    void dismiss() {
      if (completer.isCompleted) return;
      entry.remove();
      completer.complete();
      onDismiss?.call();
    }

    entry = OverlayEntry(
      builder: (_) => _SpotlightContent(
        targetRect: targetRect,
        title: title,
        message: message,
        dismissLabel: dismissLabel,
        onDismiss: dismiss,
      ),
    );

    overlay.insert(entry);
    return completer.future;
  }
}

class _SpotlightContent extends StatelessWidget {
  final Rect targetRect;
  final String title;
  final String message;
  final String dismissLabel;
  final VoidCallback onDismiss;

  const _SpotlightContent({
    required this.targetRect,
    required this.title,
    required this.message,
    required this.dismissLabel,
    required this.onDismiss,
  });

  // Geometry of the cut-out hole around the target.
  static const double _holePadding = 8;
  static const double _holeRadius = 16;
  static const double _balloonGap = 16;
  static const double _balloonMaxWidth = 320;
  static const double _screenMargin = 20;

  Rect get _holeRect => targetRect.inflate(_holePadding);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final hole = _holeRect;

    // Decide whether the balloon sits below or above the hole based on space.
    final spaceBelow = screen.height - hole.bottom;
    final spaceAbove = hole.top;
    final placeBelow = spaceBelow >= spaceAbove;

    // Horizontal placement: center on the hole, clamped to screen margins.
    final balloonWidth =
        (screen.width - 2 * _screenMargin).clamp(0.0, _balloonMaxWidth);
    var left = hole.center.dx - balloonWidth / 2;
    left = left.clamp(
      _screenMargin,
      (screen.width - _screenMargin - balloonWidth).clamp(_screenMargin,
          double.infinity),
    );

    final balloon = _TipBalloon(
      width: balloonWidth,
      title: title,
      message: message,
      dismissLabel: dismissLabel,
      onDismiss: onDismiss,
    );

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Stack(
          children: [
            // Dimming scrim with the cut-out hole + pulsing ring.
            Positioned.fill(
              child: _PulsingScrim(holeRect: hole),
            ),
            // The tip balloon, positioned above or below the hole.
            Positioned(
              left: left,
              top: placeBelow ? hole.bottom + _balloonGap : null,
              bottom: placeBelow
                  ? null
                  : screen.height - hole.top + _balloonGap,
              child: balloon,
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrim that darkens everything except the rounded hole, with a softly
/// pulsing ring around the hole to draw the eye.
class _PulsingScrim extends StatelessWidget {
  final Rect holeRect;

  const _PulsingScrim({required this.holeRect});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SpotlightPainter(holeRect: holeRect, ringOpacity: 0.9),
      size: Size.infinite,
    )
        .animate()
        .fadeIn(duration: PolishMotion.normal, curve: PolishMotion.entrance)
        .then()
        .custom(
          duration: 1400.ms,
          curve: Curves.easeInOut,
          builder: (context, value, child) => CustomPaint(
            painter: _SpotlightPainter(
              holeRect: holeRect,
              ringOpacity: 0.35 + 0.55 * (1 - (value - 0.5).abs() * 2),
            ),
            size: Size.infinite,
          ),
        );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect holeRect;
  final double ringOpacity;

  _SpotlightPainter({required this.holeRect, required this.ringOpacity});

  static const double _holeRadius = _SpotlightContent._holeRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      holeRect,
      const Radius.circular(_holeRadius),
    );

    // Dark scrim everywhere minus the hole.
    final scrim = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(rrect);
    final masked = Path.combine(PathOperation.difference, scrim, hole);
    canvas.drawPath(
      masked,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );

    // Pulsing accent ring hugging the hole edge.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: ringOpacity.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.holeRect != holeRect ||
      oldDelegate.ringOpacity != ringOpacity;
}

class _TipBalloon extends StatelessWidget {
  final double width;
  final String title;
  final String message;
  final String dismissLabel;
  final VoidCallback onDismiss;

  const _TipBalloon({
    required this.width,
    required this.title,
    required this.message,
    required this.dismissLabel,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Swallow taps on the balloon body so only the button/scrim dismiss.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: PolishButton(
                label: dismissLabel,
                expand: false,
                verticalPadding: 10,
                onPressed: onDismiss,
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: PolishMotion.normal, curve: PolishMotion.entrance)
        .scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          duration: PolishMotion.normal,
          curve: Curves.easeOutBack,
        );
  }
}
