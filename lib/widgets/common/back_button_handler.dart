import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BackButtonHandler extends StatelessWidget {
  final Widget child;
  final bool isRootRoute;

  const BackButtonHandler({
    super.key,
    required this.child,
    this.isRootRoute = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isRootRoute) {
      // Rota raiz: botão voltar completamente bloqueado
      return PopScope(canPop: false, child: child);
    }

    // Sub-rotas: permite voltar normalmente via GoRouter
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (context.canPop()) context.pop();
      },
      child: child,
    );
  }
}
