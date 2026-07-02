import 'package:flutter/material.dart';

/// Design tokens for the **Fighter App** (Portal do Lutador) — the anti-"AI-slop"
/// visual language defined in `docs/b2c/UIUX_DESIGN_PORTAL_LUTADOR_2026-06.md`.
///
/// This is **additive**: it does NOT touch [AppTheme]. Screens that belong to
/// the portable fighter identity (passaporte, jornada, estrada da faixa,
/// ranking/cena, share cards) opt into these tokens; everything else keeps
/// using [AppTheme].
///
/// ## North star
/// "Linhagem": ink-on-bone editorial contrast, one blood-red brand accent, the
/// 10 belt colors kept sacred (they only ever represent a real belt — never
/// semantic UI). Reads like fightwear / a credential, not a wellness dashboard.
///
/// ## Non-negotiables baked in
/// - **One accent only:** [blood]. No purple in the chrome, no rainbow
///   gradients, no multicolor confetti.
/// - **Belt colors are a separate sacred system** — resolved via
///   `AppTheme.getBeltColor`, never reused here for semantic meaning.
/// - **Tabular figures on every metric** so numbers read like an instrument.
/// - **ALL-CAPS heavy heroes** — uppercase is applied at the widget level
///   (e.g. `Text(value.toUpperCase(), style: FighterTheme.heroLabel)`), since
///   `TextStyle` has no casing transform.
/// - **8px radius**, rectangular chips, decided 1px hairlines.
///
/// ## Typography note (follow-up)
/// The condensed industrial display face (Archivo / Anton / Druk-like) is a
/// **follow-up** — it needs a bundled font asset and is intentionally out of
/// scope here (no new assets in `pubspec.yaml`). Until then the "condensed
/// industrial" look is approximated with the system font + `FontWeight.w900` +
/// positive `letterSpacing` + uppercase (at call site) + tabular figures.
class FighterTheme {
  FighterTheme._();

  // ── Core palette ───────────────────────────────────────────────────────────

  /// Warm near-white "raw gi / tatame" canvas. The light-mode background.
  static const Color bone = Color(0xFFFAFAF7);

  /// True black canvas. Dark mode + "stage mode" share cards live here.
  static const Color ink = Color(0xFF0A0A0A);

  /// The single owned brand accent — dried blood-red. CTAs, live streak, the
  /// brand mark on a card. The "Strava orange" of BJJ.
  static const Color blood = Color(0xFFB91C1C);

  /// Deeper blood, for pressed/hover states and accent fills on dark.
  static const Color bloodDeep = Color(0xFF7F1D1D);

  /// Decided 1px hairline on light surfaces (a real line, not timid grey).
  static const Color hairline = Color(0xFF1A1A1A);

  /// Pure white, for the rare surface that must lift off [bone].
  static const Color paper = Color(0xFFFFFFFF);

  /// Neutral ash grey — secondary text / muted labels. Neutral by design so it
  /// never competes with [blood] or a belt color.
  static const Color ash = Color(0xFF6B6B6B);

  // ── Derived neutrals (kept minimal & reusable) ─────────────────────────────

  /// Bone-tinted "ink" used as primary text/foreground on dark (stage) surfaces.
  static const Color boneText = Color(0xFFF5F1E8);

  /// Hairline on dark surfaces — a faint bone line at low opacity reads better
  /// than pure grey on [ink].
  static Color get hairlineOnInk => boneText.withValues(alpha: 0.12);

  /// Muted ash on dark surfaces (secondary text in stage mode).
  static const Color ashOnInk = Color(0xFF8A8A85);

  // ── Geometry ───────────────────────────────────────────────────────────────

  /// Card / surface radius — reads as fightwear, not a pastel pill.
  static const double radius = 8.0;

  /// Chip radius — rectangular, credential-like.
  static const double chipRadius = 6.0;

  /// Standard rounded rectangle for cards.
  static const BorderRadius cardRadius =
      BorderRadius.all(Radius.circular(radius));

  /// Standard rounded rectangle for chips.
  static const BorderRadius chipBorderRadius =
      BorderRadius.all(Radius.circular(chipRadius));

  // ── Typography ─────────────────────────────────────────────────────────────
  //
  // No `fontFamily` is set: these inherit the system font (Inter via [AppTheme]
  // when used inside the app). The condensed/industrial feel comes from weight,
  // tracking, casing (at call site) and tabular figures — not a new asset.

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// Colossal hero number for milestones / share cards (e.g. "287", "1.000").
  /// Number-first: pair with a micro-caps [heroLabel] underneath.
  static const TextStyle heroNumber = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w900,
    height: 1.0,
    letterSpacing: -1.0,
    fontFeatures: _tabular,
    color: ink,
  );

  /// Micro-caps section/hero label. Apply `.toUpperCase()` at the call site —
  /// `TextStyle` cannot transform casing. Heavy tracking-out for the
  /// industrial credential look.
  static const TextStyle heroLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.5,
    height: 1.1,
    color: ink,
  );

  /// A single metric value (mat-time, streak, presenças). Tabular so columns of
  /// numbers stay perfectly aligned.
  static const TextStyle metric = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.1,
    fontFeatures: _tabular,
    color: ink,
  );

  /// Body / "voz de tatame" copy — empty states, captions, the verbal layer.
  /// Tone: oss / respeito / fechou, never fitness exclamation.
  static const TextStyle bodyVoice = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: ash,
  );

  // ── "Modo palco" (stage mode) ──────────────────────────────────────────────
  //
  // Dark, near-black surface where the belt color "jumps". Used by pride cards
  // and shareable assets ("o tatame à noite"). The belt — resolved via
  // `AppTheme.getBeltColor` — is meant to be the ONLY chromatic color on a
  // stage surface; everything else stays ink/bone.

  /// Box decoration for a dark "stage" card: ink canvas, 8px radius, faint
  /// bone hairline border. Pass a [borderColor] (typically the fighter's belt
  /// color) to let the belt own the edge.
  static BoxDecoration stageCard({Color? borderColor}) {
    return BoxDecoration(
      color: ink,
      borderRadius: cardRadius,
      border: Border.all(
        color: borderColor ?? hairlineOnInk,
        width: borderColor != null ? 1.5 : 1.0,
      ),
    );
  }

  /// Hero number recolored for stage mode (bone-ink on the dark canvas).
  static const TextStyle heroNumberOnInk = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w900,
    height: 1.0,
    letterSpacing: -1.0,
    fontFeatures: _tabular,
    color: boneText,
  );

  /// Hero label recolored for stage mode. Apply `.toUpperCase()` at call site.
  static const TextStyle heroLabelOnInk = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.5,
    height: 1.1,
    color: boneText,
  );

  // ── Light surface helper ───────────────────────────────────────────────────

  /// Box decoration for a standard light fighter card: bone-tinted surface,
  /// 8px radius, decided hairline border.
  static BoxDecoration lightCard({Color? borderColor}) {
    return BoxDecoration(
      color: paper,
      borderRadius: cardRadius,
      border: Border.all(
        color: borderColor ?? hairline.withValues(alpha: 0.12),
        width: 1.0,
      ),
    );
  }
}
