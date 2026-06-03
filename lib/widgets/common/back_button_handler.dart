import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/feedback_utils.dart';

/// Caminho "pai" removendo o último segmento da rota [path].
///
/// Ex.: `/admin/alunos/123` → `/admin/alunos`; `/admin/alunos` → `/admin`.
/// Retorna null quando já é uma aba-raiz (um único segmento) ou sem path.
///
/// Função pura extraída para permitir testes unitários — o widget delega aqui.
String? parentLocation(String? path) {
  if (path == null || path.isEmpty) return null;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length <= 1) return null; // já é raiz (/admin, /portal)
  segments.removeLast();
  return '/${segments.join('/')}';
}

/// Widget que gerencia o comportamento do botão voltar do sistema.
///
/// Como a navegação do app usa `context.go(...)` (que substitui a pilha) com
/// rotas planas, as sub-telas ficam sem histórico de Navigator — `canPop()` é
/// false. Sem tratamento, o voltar do sistema fecharia o app. Este handler:
/// - Faz pop real quando há histórico (dialogs, sheets, páginas empilhadas).
/// - Em sub-telas sem histórico, navega para o caminho "pai" (ex.:
///   `/admin/alunos/123` → `/admin/alunos`) em vez de fechar.
/// - Só na aba-raiz (`/admin`, `/portal`) aplica "pressione 2x para sair".
///
/// ---------------------------------------------------------------------------
/// CONTRATO COM POPSCOPES FILHOS (auditoria Sprint B2)
/// ---------------------------------------------------------------------------
/// Este handler tem `canPop: false` e é o PopScope MAIS EXTERNO. O Flutter
/// entrega a intenção de voltar ao PopScope MAIS INTERNO primeiro. Logo, todo
/// PopScope dentro de uma tela DEVE consumir o gesto por completo e NUNCA
/// deixar a saída do app "vazar" para este handler.
///
/// Telas com PopScope próprio auditadas (lib/screens):
///   - admin/settings_screen.dart           (dirty = `_isDirty` via snapshot)
///   - admin/physical_assessment_form_screen.dart (dirty = `_isDirty` do form)
///
/// Regras que cada PopScope filho deve seguir:
///   - `canPop: !hasUnsavedChanges` — `true` SÓ quando o form está limpo;
///     `false` quando sujo, para interceptar o gesto.
///   - `onPopInvokedWithResult`: `if (didPop) return;` então, se sujo, mostra
///     um diálogo de confirmar-descarte. CONFIRMAR → `Navigator/context.pop()`
///     (descarta e sai da tela; este handler resolve então o pai). CANCELAR →
///     não faz nada (permanece).
///   - Form LIMPO (`canPop: true`): a rota faz pop normal para a tela pai (NÃO
///     fecha o app, pois há histórico de navigator abaixo deste shell). Sem
///     diálogo.
///   - NUNCA chamar `SystemNavigator.pop` de um PopScope filho; nunca
///     `canPop: true` enquanto sujo.
/// ---------------------------------------------------------------------------
class BackButtonHandler extends StatefulWidget {
  final Widget child;
  final bool isRootRoute;

  /// Caminho atual (ex.: `/admin/alunos/123`). Usado para calcular o "pai".
  /// Quando ausente, sub-telas caem no comportamento de saída por double-tap.
  final String? currentLocation;
  final String? exitMessage;

  const BackButtonHandler({
    super.key,
    required this.child,
    this.isRootRoute = false,
    this.currentLocation,
    this.exitMessage,
  });

  @override
  State<BackButtonHandler> createState() => _BackButtonHandlerState();
}

class _BackButtonHandlerState extends State<BackButtonHandler> {
  DateTime? _lastBackPressTime;
  static const _backPressInterval = Duration(seconds: 2);

  /// Caminho "pai" da rota atual. Delega para a função pura [parentLocation].
  String? _parentLocation() => parentLocation(widget.currentLocation);

  /// Lógica de "double tap to exit": retorna true só no segundo toque dentro
  /// do intervalo. No primeiro toque, registra e mostra a mensagem.
  bool _shouldExitNow() {
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > _backPressInterval) {
      _lastBackPressTime = now;
      if (mounted) {
        final message =
            widget.exitMessage ?? 'Pressione voltar novamente para sair';
        FeedbackUtils.showInfo(context, message);
      }
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Sempre intercepta o pop
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        // Se já fez pop (por algum motivo), não faz nada.
        if (didPop) return;

        // 1) Pop real quando há histórico (dialogs/sheets/páginas empilhadas).
        if (context.canPop()) {
          context.pop();
          return;
        }

        // 2) Sub-tela sem histórico: vai para o "pai" em vez de fechar o app.
        if (!widget.isRootRoute) {
          final parent = _parentLocation();
          if (parent != null) {
            context.go(parent);
            return;
          }
        }

        // 3) Aba-raiz (ou sem pai calculável): double-tap para sair.
        if (_shouldExitNow()) {
          SystemNavigator.pop();
        }
      },
      child: widget.child,
    );
  }
}
