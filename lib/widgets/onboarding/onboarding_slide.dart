import 'package:flutter/widgets.dart';

/// Immutable data model for a single welcome-carousel slide.
///
/// Pure presentation: an [icon] rendered large inside a tinted circle, an
/// [accent] color that tints that circle (and the icon), plus three text
/// fields — a small [eyebrow] kicker, a bold [title], and a supporting [body].
///
/// Usage:
/// ```dart
/// const OnboardingSlide(
///   icon: LucideIcons.userCheck,
///   accent: AppTheme.info,
///   eyebrow: 'PASSO 1 DE 3',
///   title: 'Bem-vindo ao tatame',
///   body: 'Acompanhe sua evolução faixa a faixa.',
/// )
/// ```
class OnboardingSlide {
  final IconData icon;
  final Color accent;
  final String eyebrow;
  final String title;
  final String body;

  const OnboardingSlide({
    required this.icon,
    required this.accent,
    required this.eyebrow,
    required this.title,
    required this.body,
  });
}
