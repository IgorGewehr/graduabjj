import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'problem_interceptor.dart';

/// Cliente HTTP para o backend Tatami.
///
/// Responsabilidades:
///   1. Anexar `Authorization: Bearer <firebase_id_token>` em toda chamada.
///   2. Em 401, forçar refresh do token Firebase UMA vez e retentar.
///   3. Converter respostas de erro em [TatamiException] via [problemInterceptor].
///
/// Não conhece domínio — repositórios específicos (IdentityRepo, StudentRepo)
/// chamam .get/.post/.patch/.delete por cima.
class TatamiClient {
  TatamiClient({required this.baseUrl, Dio? dio, FirebaseAuth? auth})
      : _dio = dio ?? Dio(),
        _auth = auth ?? FirebaseAuth.instance {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);

    _dio.interceptors.add(_authInterceptor());
    _dio.interceptors.add(problemInterceptor());
  }

  final String baseUrl;
  final Dio _dio;
  final FirebaseAuth _auth;

  Interceptor _authInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) async {
          final user = _auth.currentUser;
          if (user != null) {
            // `false`: aceita o token cacheado. Firebase SDK refresca
            // automaticamente nos 5 min antes de expirar.
            final token = await user.getIdToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          // 401: tenta UMA vez com token forçado, depois desiste.
          if (error.response?.statusCode == 401) {
            final retried = error.requestOptions.extra['__retried_auth'] == true;
            final user = _auth.currentUser;
            if (user != null && !retried) {
              try {
                final fresh = await user.getIdToken(true);
                if (fresh != null) {
                  final opts = error.requestOptions
                    ..headers['Authorization'] = 'Bearer $fresh'
                    ..extra['__retried_auth'] = true;
                  final resp = await _dio.fetch(opts);
                  return handler.resolve(resp);
                }
              } catch (_) {
                // Cai para o próximo handler com o erro original.
              }
            }
          }
          handler.next(error);
        },
      );

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final r = await _dio.get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
    return r.data as T;
  }

  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final r = await _dio.post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
    return r.data as T;
  }

  Future<T> patch<T>(
    String path, {
    Object? data,
    Options? options,
  }) async {
    final r = await _dio.patch<dynamic>(path, data: data, options: options);
    return r.data as T;
  }

  Future<T> put<T>(
    String path, {
    Object? data,
    Options? options,
  }) async {
    final r = await _dio.put<dynamic>(path, data: data, options: options);
    return r.data as T;
  }

  Future<void> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    await _dio.delete<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// Health check útil em smoke tests e na splash screen.
  Future<bool> healthz() async {
    try {
      await _dio.get<dynamic>('/healthz');
      return true;
    } catch (_) {
      return false;
    }
  }
}
