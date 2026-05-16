import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'tatami_client.dart';

/// Chave de idempotência para POSTs que criam estado no Tatami.
///
/// Gere uma chave ANTES da primeira tentativa e reuse em retries — o backend
/// retorna a mesma resposta (cacheada por 24h) se a chave já foi vista.
class IdempotencyKey {
  const IdempotencyKey._(this.value);

  factory IdempotencyKey.generate() =>
      IdempotencyKey._(const Uuid().v4());

  /// Permite reconstruir a chave a partir de uma string persistida
  /// (ex: após restart do app com retry pendente).
  factory IdempotencyKey.fromString(String value) => IdempotencyKey._(value);

  final String value;

  @override
  String toString() => value;
}

/// Extensão para POSTs idempotentes — header `Idempotency-Key` é o contrato
/// padrão do Tatami para criação de recursos seguros contra duplicação.
extension TatamiClientIdempotent on TatamiClient {
  Future<T> postIdempotent<T>(
    String path, {
    required Object data,
    required IdempotencyKey key,
    Options? options,
  }) {
    final merged = (options ?? Options()).copyWith(
      headers: <String, dynamic>{
        ...?options?.headers,
        'Idempotency-Key': key.value,
      },
    );
    return post<T>(path, data: data, options: merged);
  }
}
