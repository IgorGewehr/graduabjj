import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../polish/polish.dart';
import 'onboarding_slide.dart';
import 'page_dots.dart';

/// Premium full-screen welcome carousel shown on first launch / onboarding.
///
/// Renders [slides] in a swipeable [PageView] with a progress bar + "Pular"
/// shortcut up top, a large tinted-circle illustration with staggered text in
/// the center, and animated [PageDots] plus a primary CTA in the footer. The
/// CTA advances the page until the last slide, where it shimmers, fires a
/// confetti [Celebration], and calls [onDone].
///
/// Usage:
/// ```dart
/// OnboardingCarousel(
///   slides: mySlides,
///   onDone: () => context.go('/home'),
///   onSkip: _markSeen,
/// )
/// ```
class OnboardingCarousel extends StatefulWidget {
  final List<OnboardingSlide> slides;
  final VoidCallback onDone;
  final VoidCallback? onSkip;
  final String finishLabel;

  /// Dispara confete ao concluir (momento de celebração). Default true; passe
  /// false em tours que terminam navegando (ex.: "conecte sua conta"), onde a
  /// celebração seria prematura.
  final bool celebrate;

  const OnboardingCarousel({
    super.key,
    required this.slides,
    required this.onDone,
    this.onSkip,
    this.finishLabel = 'Começar',
    this.celebrate = true,
  });

  @override
  State<OnboardingCarousel> createState() => _OnboardingCarouselState();
}

class _OnboardingCarouselState extends State<OnboardingCarousel> {
  final PageController _controller = PageController();
  // Confete INLINE: o gate vive acima do Overlay do router, então o confete via
  // OverlayEntry (Celebration.confetti) seria no-op aqui — renderizamos dentro
  // do próprio Scaffold do carrossel.
  final ConfettiController _confetti =
      ConfettiController(duration: const Duration(milliseconds: 900));
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    _confetti.dispose();
    super.dispose();
  }

  int get _total => widget.slides.length;
  bool get _isLast => _page >= _total - 1;

  void _onPageChanged(int page) {
    if (page == _page) return;
    HapticFeedback.lightImpact();
    setState(() => _page = page);
  }

  void _skip() => (widget.onSkip ?? widget.onDone)();

  void _next() {
    if (_isLast) {
      if (widget.celebrate) {
        HapticFeedback.mediumImpact();
        _confetti.play();
      }
      widget.onDone();
      return;
    }
    _controller.nextPage(
      duration: PolishMotion.normal,
      curve: PolishMotion.entrance,
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0 ? 0.0 : (_page + 1) / _total;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            // ── Top: progress + skip ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedProgressBar(
                      value: progress,
                      minHeight: 6,
                      color: AppTheme.textPrimary,
                      backgroundColor: AppTheme.divider,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      minimumSize: const Size(0, 40),
                    ),
                    child: const Text('Pular'),
                  ),
                ],
              ),
            ),

            // ── Center: swipeable slides ──────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _onPageChanged,
                itemCount: _total,
                itemBuilder: (context, index) =>
                    _SlideView(slide: widget.slides[index]),
              ),
            ),

            // ── Footer: dots + CTA ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  // Dots só fazem sentido com mais de um slide.
                  if (_total > 1) ...[
                    PageDots(count: _total, currentPage: _page),
                    const SizedBox(height: 20),
                  ],
                  _cta(),
                ],
              ),
            ),
          ],
        ),
          ),
          // Confete da conclusão — jorra do topo-centro para baixo.
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirection: math.pi / 2, // para baixo
              emissionFrequency: 0.05,
              numberOfParticles: 24,
              maxBlastForce: 22,
              minBlastForce: 8,
              gravity: 0.25,
              shouldLoop: false,
              colors: const [
                AppTheme.primary,
                AppTheme.success,
                AppTheme.info,
                AppTheme.warning,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cta() {
    final button = PolishButton(
      label: _isLast ? widget.finishLabel : 'Próximo',
      icon: LucideIcons.arrowRight,
      expand: true,
      onPressed: _next,
    );
    if (!_isLast) return button;
    return button
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1800.ms,
          color: Colors.white.withValues(alpha: 0.45),
        );
  }
}

/// The centered content of a single slide: tinted illustration circle, eyebrow,
/// title and body — each revealed with a staggered [PolishEntrance].
class _SlideView extends StatelessWidget {
  final OnboardingSlide slide;

  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: slide.accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 56, color: slide.accent),
          ).entrance(index: 0),
          const SizedBox(height: 32),
          Text(
            slide.eyebrow,
            textAlign: TextAlign.center,
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ).entrance(index: 1),
          const SizedBox(height: 12),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: AppTheme.displaySmall.copyWith(fontWeight: FontWeight.w800),
          ).entrance(index: 2),
          const SizedBox(height: 12),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ).entrance(index: 3),
        ],
      ),
    );
  }
}
