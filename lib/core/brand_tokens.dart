import 'package:flutter/material.dart';

/// Tokens de marca canônicos do GraduaBJJ — **um DNA, duas vozes**.
///
/// ## Filosofia (§5 do plano Repaginada)
/// O app tem dois "modos de voz":
///
/// - **Voz de tatame** (aluno/fighter) — editorial, identidade portátil,
///   palco; implementada pelo [FighterTheme].
/// - **Voz de ferramenta** (admin/professor) — densidade, leitura rápida,
///   fundo claro; implementada pelo [AppTheme].
///
/// Ambas compartilham o **mesmo DNA cromático e tipográfico** definido aqui.
/// Telas específicas NÃO devem declarar cores de marca localmente — importem
/// [Brand] e deixem o sistema de tokens trabalhar.
///
/// ## Paleta canônica
/// | Token        | Hex        | Papel                                  |
/// |--------------|------------|----------------------------------------|
/// | [blood]      | B91C1C     | Único acento de marca (CTAs, streak)   |
/// | [bloodDeep]  | 7F1D1D     | Variante pressed/hover e fundos escuros|
/// | [bone]       | F4F3EF     | Canvas warm-white padrão (light mode)  |
/// | [ink]        | 0A0A0A     | Preto estrutural — texto primário      |
/// | [ash]        | 6B6B6B     | Cinza neutro — texto secundário/muted  |
///
/// ## Tokens que NÃO estão aqui
/// - `AppTheme.error` (`0xFFDC2626`) permanece como cor semântica de erro.
///   **Erro ≠ marca** — nunca use [blood] para sinalizar falha.
/// - Cores de faixa: sistema sagrado separado em `AppTheme.getBeltColor`.
abstract final class Brand {
  Brand._();

  // ── Paleta cromática ────────────────────────────────────────────────────────

  /// Acento de marca canônico — vermelho "sangue seco", `0xFFB91C1C`.
  ///
  /// O único acento cromático do app: CTAs primárias, streak ativo, marca no
  /// card de faixa. Análogo ao "laranja Strava" no contexto do BJJ.
  ///
  /// **Não confundir com `AppTheme.error` (`0xFFDC2626`) — erro ≠ marca.**
  /// Morrem: `0xFFB3261E` (admin_social) e `0xFFE0301E` (create_academy).
  static const Color blood = Color(0xFFB91C1C);

  /// Variante mais escura do [blood] (`0xFF7F1D1D`) — estados pressed/hover
  /// e preenchimentos de acento sobre fundos escuros (modo palco / stage mode).
  static const Color bloodDeep = Color(0xFF7F1D1D);

  /// Canvas warm-white "gi branco / tatame" (`0xFFF4F3EF`).
  ///
  /// **Canônico de produção visual** — valor que está em uso real no portal
  /// do aluno. O token anterior `0xFFFAFAF7` do [FighterTheme] era um drift;
  /// este é o valor correto.
  static const Color bone = Color(0xFFF4F3EF);

  /// Preto estrutural (`0xFF0A0A0A`) — texto primário, ícones, "placa" hero.
  static const Color ink = Color(0xFF0A0A0A);

  /// Cinza neutro (`0xFF6B6B6B`) — texto secundário, rótulos muted, ícones de
  /// suporte. Projetado para não competir com [blood] nem com cores de faixa.
  static const Color ash = Color(0xFF6B6B6B);

  // ── Tipografia de display ───────────────────────────────────────────────────

  /// Figuras tabulares — compartilhadas entre [display] e qualquer [TextStyle]
  /// que exiba métricas numéricas (KPIs, contadores, streaks).
  ///
  /// Uso: `TextStyle(fontFeatures: Brand.tabular, ...)`.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Base tipográfica de display: w900, figuras tabulares, uppercase-ready.
  ///
  /// Esta constante define o **peso, tracking e features** do "grito" do app.
  /// Ajuste [TextStyle.fontSize] e [TextStyle.color] via `.copyWith()` no
  /// call site. Para o efeito ALL-CAPS, aplique `.toUpperCase()` no texto —
  /// [TextStyle] não tem transform de caixa.
  ///
  /// Exemplo:
  /// ```dart
  /// Text(
  ///   'ACADEMIA CRIADA'.toUpperCase(),
  ///   style: Brand.display.copyWith(fontSize: 26, color: Brand.ink),
  /// )
  /// ```
  static const TextStyle display = TextStyle(
    fontWeight: FontWeight.w900,
    letterSpacing: 0.5,
    height: 1.05,
    fontFeatures: tabular,
    color: ink,
  );
}
