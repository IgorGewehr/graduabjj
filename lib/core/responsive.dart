/// Camada responsiva central do GraduaBJJ — FONTE ÚNICA de breakpoints.
///
/// Substitui os `MediaQuery.of(context).size.width < 768` soltos espalhados
/// pelas telas por uma escala consistente (Material 3 window size classes,
/// adaptadas). Funções puras + extension em [BuildContext]; sem Riverpod, sem
/// estado — pode ser usada em qualquer `build`.
///
/// Uso típico:
/// ```dart
/// if (context.isDesktop) ... // medium ou maior
/// final cols = context.responsive<int>(compact: 2, expanded: 4);
/// ContentBounded(maxWidth: 1200, child: lista);
/// ```
library;

import 'package:flutter/widgets.dart';

/// Faixas de largura da janela.
enum Breakpoint {
  /// `< 600` — celular em retrato. BottomNav, conteúdo em coluna única.
  compact,

  /// `600–1024` — celular landscape / tablet. NavigationRail só-ícones.
  medium,

  /// `1024–1440` — tablet grande / desktop. Sidebar expandida + master-detail.
  expanded,

  /// `> 1440` — desktop largo. Sidebar + maior densidade.
  large,
}

/// Limites em largura lógica (dp). Mexer aqui muda o app inteiro.
const double kBreakpointMedium = 600;
const double kBreakpointExpanded = 1024;
const double kBreakpointLarge = 1440;

/// Largura máxima de conteúdo recomendada (tokens únicos — substituem os
/// 480/512/1024/1080/1280 inconsistentes que existiam pelas telas).
const double kContentMaxWidthList = 1200; // listas, tabelas, dashboards
const double kContentMaxWidthForm = 720; // formulários e leitura

/// Resolve a [Breakpoint] para uma largura lógica.
Breakpoint breakpointFor(double width) {
  if (width < kBreakpointMedium) return Breakpoint.compact;
  if (width < kBreakpointExpanded) return Breakpoint.medium;
  if (width < kBreakpointLarge) return Breakpoint.expanded;
  return Breakpoint.large;
}

/// Acesso responsivo a partir do [BuildContext]. Usa `MediaQuery.sizeOf` (só
/// reconstrói quando o TAMANHO muda, não em outras mudanças de MediaQuery).
extension ResponsiveContext on BuildContext {
  /// Largura lógica atual da janela.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Faixa responsiva atual.
  Breakpoint get breakpoint => breakpointFor(screenWidth);

  bool get isCompact => breakpoint == Breakpoint.compact;
  bool get isMedium => breakpoint == Breakpoint.medium;
  bool get isExpanded => breakpoint == Breakpoint.expanded;
  bool get isLarge => breakpoint == Breakpoint.large;

  /// "Desktop-like": `medium` ou maior — onde rail/sidebar e layouts de duas
  /// colunas fazem sentido (inclui tablet landscape, não só PC).
  bool get isDesktop => breakpoint != Breakpoint.compact;

  /// Largura suficiente para master-detail lado a lado (`expanded`+).
  bool get isWide =>
      breakpoint == Breakpoint.expanded || breakpoint == Breakpoint.large;

  /// Seleciona um valor por faixa, com FALLBACK para a faixa fornecida
  /// imediatamente menor. Ex.: `responsive(compact: 1, expanded: 3)` dá 1 em
  /// compact/medium e 3 em expanded/large. Só `compact` é obrigatório.
  T responsive<T>({
    required T compact,
    T? medium,
    T? expanded,
    T? large,
  }) {
    switch (breakpoint) {
      case Breakpoint.large:
        return large ?? expanded ?? medium ?? compact;
      case Breakpoint.expanded:
        return expanded ?? medium ?? compact;
      case Breakpoint.medium:
        return medium ?? compact;
      case Breakpoint.compact:
        return compact;
    }
  }
}

/// Centraliza e limita a largura do conteúdo a partir de `medium` — NO-OP em
/// `compact` (no celular o conteúdo usa a tela toda). Evita listas e formulários
/// esticados edge-to-edge numa janela larga de desktop.
///
/// Uma linha por tela: `ContentBounded(child: corpo)` (lista, default 1200) ou
/// `ContentBounded(maxWidth: kContentMaxWidthForm, child: form)`.
class ContentBounded extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const ContentBounded({
    super.key,
    this.maxWidth = kContentMaxWidthList,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (context.isCompact) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
