import 'package:flutter/material.dart';

import '../core/brand_tokens.dart';
import '../core/constants.dart';
import '../core/fighter_theme.dart';

/// Variantes v1 do "Motor de Cards" (diagnóstico jul/2026: o app não tinha
/// NENHUM share externo — k viral = 0 por construção). Cada marco vira um
/// card 4:5 que o lutador solta no status do WhatsApp/stories: o WhatsApp
/// deixa de ser concorrente e vira canal de distribuição.
enum FighterShareCardVariant {
  /// "Treinei hoje" — disparado no reward do self-log ([DiarioScreen]).
  treino,

  /// "X semanas seguidas" — disparado a partir do card de streak do hub.
  streak,
}

/// Card compartilhável do lutador. Renderizado OFFSCREEN por
/// [ShareCardService] (RepaintBoundary + `toImage`) — nunca aparece "a cru"
/// fora do preview do bottom sheet de compartilhamento.
///
/// ## Canvas
/// Tamanho FIXO [designWidth]×[designHeight] = 360×450 (proporção 4:5),
/// pensado pra ser capturado com `pixelRatio: 3.0` → 1080×1350 exatos, o
/// formato nativo de story/feed do Instagram e do status do WhatsApp.
///
/// ## Visual
/// "Modo palco" ([FighterTheme.stageCard]): canvas ink, UM acento
/// [FighterTheme.blood] (o glow dramático no canto), a cor da faixa é a
/// única outra cor permitida — ela é "a cor do lutador", não um acento de UI
/// solto (mesmo critério de `docs/b2c/UIUX_DESIGN_PORTAL_LUTADOR_2026-06.md`).
/// Tudo em CAIXA ALTA, w900, tabular figures nos números. Zero emoji, zero
/// gradiente arco-íris — fightwear, não dashboard fitness.
class FighterShareCard extends StatelessWidget {
  const FighterShareCard({
    super.key,
    required this.variant,
    required this.fighterName,
    this.dateLabel,
    this.modalidadeLabel,
    this.totalTrainings,
    this.currentStreakWeeks,
    this.beltLabel,
    this.beltColor,
    this.comeback = false,
  });

  final FighterShareCardVariant variant;

  /// Nome do lutador exibido no rodapé — já resolvido pelo call site (mesma
  /// regra de `Student.displayName`: apelido > primeiro nome > "Lutador").
  final String fighterName;

  /// Data já formatada (ex.: '20.07.2026'). Só usada na variante [treino].
  final String? dateLabel;

  /// Rótulo curto da modalidade (ex.: 'NO-GI'). Omitido quando `null` —
  /// aluno mono-esporte ou modalidade não escolhida no registro.
  final String? modalidadeLabel;

  /// Contagem TOTAL de treinos (all-time) — usada na variante [treino].
  final int? totalTrainings;

  /// Streak semanal atual (semanas seguidas): é a MÉTRICA da variante
  /// [streak] e vira um selo secundário na [treino].
  final int? currentStreakWeeks;

  /// Rótulo da faixa já resolvido (ex.: 'AZUL'). Passe `null` quando não
  /// estiver disponível BARATO na tela — este widget nunca dispara leitura
  /// nova só pra montar o card.
  final String? beltLabel;

  /// Cor real da faixa, já com o guard de luminância aplicado pelo call
  /// site (ver `_beltColor` em diario_screen.dart). Borda o card inteiro e
  /// colore o "ponto" ao lado do nome no rodapé.
  final Color? beltColor;

  /// Volta após hiato (retenção) — troca o título da variante [treino] de
  /// 'TREINEI HOJE' pra 'DE VOLTA AO TATAME'.
  final bool comeback;

  /// 360×450 (4:5) — capturar com pixelRatio 3.0 dá 1080×1350 exatos.
  static const double designWidth = 360;
  static const double designHeight = 450;

  /// [beltColor] chega cru do call site (`AppTheme.getBeltColor` /
  /// `getGradeColor`) — nenhum dos dois sabe que vai pousar num fundo ink.
  /// Faixa preta (`0xFF171717`) tem luminância quase igual à do próprio
  /// canvas ([FighterTheme.ink]) e some sem esse guard. Note que é o guard
  /// OPOSTO ao de `_beltColor` em diario_screen.dart (aquele clareia faixa
  /// clara pra não sumir em cartão CLARO; este clareia faixa ESCURA pra não
  /// sumir em cartão ESCURO).
  Color? get _safeBeltColor {
    final c = beltColor;
    if (c == null) return null;
    return c.computeLuminance() < 0.08
        ? FighterTheme.boneText.withValues(alpha: 0.55)
        : c;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: designWidth,
      height: designHeight,
      child: DecoratedBox(
        decoration: FighterTheme.stageCard(borderColor: _safeBeltColor),
        child: ClipRRect(
          borderRadius: FighterTheme.cardRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Glow dramático no canto — a ÚNICA "textura" do fundo, no
              // próprio acento de marca (nunca introduz uma 2ª cor de UI).
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.95, -0.9),
                    radius: 1.35,
                    colors: [
                      FighterTheme.blood.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topRow(),
                    const Spacer(),
                    _headline(),
                    if (variant == FighterShareCardVariant.treino) ...[
                      const SizedBox(height: 22),
                      _hairline(),
                      const SizedBox(height: 18),
                      _statsRow(),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        _streakSubtitle,
                        style: FighterTheme.bodyVoice.copyWith(
                          color: FighterTheme.ashOnInk,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const Spacer(),
                    _hairline(),
                    const SizedBox(height: 14),
                    _footer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Topo: data + modalidade (treino) ou eyebrow (streak) ─────────────────
  Widget _topRow() {
    if (variant != FighterShareCardVariant.treino) {
      return Text(
        'SEQUÊNCIA',
        style:
            FighterTheme.heroLabelOnInk.copyWith(color: FighterTheme.blood),
      );
    }
    if (dateLabel == null && modalidadeLabel == null) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dateLabel != null)
          Text(dateLabel!.toUpperCase(), style: FighterTheme.heroLabelOnInk),
        if (modalidadeLabel != null) ...[
          if (dateLabel != null) ...[
            const SizedBox(width: 8),
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: FighterTheme.ashOnInk,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            modalidadeLabel!.toUpperCase(),
            style: FighterTheme.heroLabelOnInk
                .copyWith(color: FighterTheme.blood),
          ),
        ],
      ],
    );
  }

  // ── Manchete central: o "grito" do card ───────────────────────────────────
  Widget _headline() {
    final text = switch (variant) {
      FighterShareCardVariant.treino =>
        comeback ? 'DE VOLTA\nAO TATAME' : 'TREINEI\nHOJE',
      FighterShareCardVariant.streak => _streakHeadline,
    };
    // FittedBox blinda contra qualquer combinação de texto/tamanho — o card
    // nunca pode estourar durante uma captura offscreen.
    return SizedBox(
      height: 132,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomLeft,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 58,
            fontWeight: FontWeight.w900,
            height: 0.94,
            letterSpacing: -1.2,
            fontFeatures: Brand.tabular,
            color: FighterTheme.boneText,
          ),
        ),
      ),
    );
  }

  String get _streakHeadline {
    final n = currentStreakWeeks ?? 0;
    return n == 1 ? '1\nSEMANA\nSEGUIDA' : '$n\nSEMANAS\nSEGUIDAS';
  }

  String get _streakSubtitle => (currentStreakWeeks ?? 0) > 1
      ? 'Toda semana no tatame conta.'
      : 'Começou. Agora é manter.';

  // ── Stats: contagem total + streak (só na variante treino) ───────────────
  Widget _statsRow() {
    return Row(
      children: [
        if (totalTrainings != null) _stat('$totalTrainings', 'TREINOS'),
        if (totalTrainings != null && currentStreakWeeks != null)
          const SizedBox(width: 28),
        if (currentStreakWeeks != null)
          _stat(
            '$currentStreakWeeks',
            currentStreakWeeks == 1 ? 'SEMANA SEGUIDA' : 'SEMANAS SEGUIDAS',
          ),
      ],
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: FighterTheme.heroNumberOnInk.copyWith(fontSize: 34)),
        const SizedBox(height: 2),
        Text(label,
            style: FighterTheme.heroLabelOnInk.copyWith(fontSize: 10.5)),
      ],
    );
  }

  Widget _hairline() => Container(height: 1, color: FighterTheme.hairlineOnInk);

  // ── Rodapé: identidade do lutador + assinatura discreta do app ───────────
  Widget _footer() {
    return Row(
      children: [
        if (_safeBeltColor != null) ...[
          Container(
            width: 9,
            height: 9,
            decoration:
                BoxDecoration(color: _safeBeltColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            fighterName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: FighterTheme.boneText,
            ),
          ),
        ),
        if (beltLabel != null) ...[
          const SizedBox(width: 8),
          Text(
            'FAIXA ${beltLabel!.toUpperCase()}',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: FighterTheme.ashOnInk,
            ),
          ),
        ],
        const Spacer(),
        Text(
          AppConstants.appName.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
            color: FighterTheme.boneText.withValues(alpha: 0.42),
          ),
        ),
      ],
    );
  }
}
