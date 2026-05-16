import 'package:dio/dio.dart';

import 'tatami_exception.dart';

/// Interceptor que converte respostas de erro do Tatami em [TatamiException].
///
/// O Tatami devolve erros como `application/problem+json` (RFC 7807). Este
/// interceptor lê o payload e troca o erro do `DioException` por um
/// [TatamiException] tipado (acessível via `.error` no chamador).
///
/// Uso típico no chamador:
/// ```dart
/// try {
///   await api.delete('/v1/academies/$aid/students/$sid');
/// } on DioException catch (e) {
///   if (e.error is TatamiException) {
///     final t = e.error as TatamiException;
///     showSnack(t.forUser());
///   } else {
///     rethrow;
///   }
/// }
/// ```
Interceptor problemInterceptor() => InterceptorsWrapper(
      onError: (error, handler) {
        // Erros de conexão / timeout não têm response — sinalizamos com
        // status=0 para o helper `isNetworkError` da TatamiException.
        if (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout) {
          return handler.next(error.copyWith(
            error: const TatamiException(
              status: 0,
              type: 'https://tatami.dev/errors/network',
              title: 'Sem conexão',
            ),
          ));
        }

        final response = error.response;
        if (response != null) {
          return handler.next(error.copyWith(
            error: TatamiException.fromResponse(
              response.statusCode ?? 500,
              response.data,
            ),
          ));
        }
        handler.next(error);
      },
    );
