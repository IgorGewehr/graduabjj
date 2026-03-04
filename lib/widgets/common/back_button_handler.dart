import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/feedback_utils.dart';

/// Widget que gerencia o comportamento do botão voltar do sistema
///
/// Implementa:
/// - Previne fechamento acidental do app nas telas principais
/// - Sistema "double tap to exit" (pressione 2x em 2 segundos para sair)
/// - Permite voltar normalmente em sub-rotas
/// - Dialogs e bottom sheets funcionam normalmente (fecham primeiro)
class BackButtonHandler extends StatefulWidget {
  final Widget child;
  final bool isRootRoute;
  final String? exitMessage;

  const BackButtonHandler({
    super.key,
    required this.child,
    this.isRootRoute = false,
    this.exitMessage,
  });

  @override
  State<BackButtonHandler> createState() => _BackButtonHandlerState();
}

class _BackButtonHandlerState extends State<BackButtonHandler> {
  DateTime? _lastBackPressTime;
  static const _backPressInterval = Duration(seconds: 2);

  /// Lida com o evento de voltar
  ///
  /// Retorna:
  /// - true: Permite o pop (fecha o app ou volta)
  /// - false: Previne o pop
  Future<bool> _onWillPop() async {
    // Se não é rota raiz, permite voltar normalmente
    if (!widget.isRootRoute) {
      return true;
    }

    // Lógica de "double tap to exit" para rota raiz
    final now = DateTime.now();

    // Verifica se houve um tap anterior nos últimos 2 segundos
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > _backPressInterval) {
      // Primeiro tap: registra e mostra mensagem
      _lastBackPressTime = now;

      if (mounted) {
        final message = widget.exitMessage ?? 'Pressione voltar novamente para sair';
        FeedbackUtils.showInfo(context, message);
      }

      return false; // Previne o pop
    }

    // Segundo tap dentro do intervalo: permite sair
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Sempre intercepta o pop
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        // Se já fez pop (por algum motivo), não faz nada
        if (didPop) {
          return;
        }

        // Verifica se pode fazer pop
        final shouldPop = await _onWillPop();

        // Verifica mounted antes de usar o context
        if (!mounted) return;

        if (shouldPop) {
          if (widget.isRootRoute) {
            // Na rota raiz, fecha o app
            SystemNavigator.pop();
          } else {
            // Usa o GoRouter para navegar — evita dessincronia com o estado interno do router
            if (context.canPop()) {
              context.pop();
            } else {
              SystemNavigator.pop();
            }
          }
        }
      },
      child: widget.child,
    );
  }
}
