import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../tatami_exception.dart';

/// Widget padrão para renderizar erros vindos do Tatami. Lê o
/// [TatamiException] anexado em `DioException.error` e usa a mensagem
/// PT-BR de `forUser()`, mais um link "Mostrar detalhes" que copia o
/// `trace_id` para o clipboard quando presente — facilita suporte.
///
/// Uso típico:
/// ```dart
/// asyncValue.when(
///   data: (page) => MyList(page),
///   loading: () => const Center(child: CircularProgressIndicator()),
///   error: (e, st) => ApiErrorView(error: e, onRetry: () => ref.invalidate(myProvider)),
/// );
/// ```
class ApiErrorView extends StatelessWidget {
  const ApiErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  TatamiException? get _tatami {
    final e = error;
    if (e is TatamiException) return e;
    if (e is DioException && e.error is TatamiException) {
      return e.error as TatamiException;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = _tatami;
    final message =
        t?.forUser() ?? 'Algo deu errado. Tente novamente.';
    final traceId = t?.traceId;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
            if (traceId != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Código de suporte: $traceId',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar de novo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
