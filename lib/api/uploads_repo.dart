import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'dto/upload_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório do contexto Uploads — fluxo de 2 etapas (sign + finalize)
/// com PUT direto pra GCS no meio.
///
/// Por que 2 etapas em vez de POST multipart pelo backend:
///   * Bytes não passam pelo BE — bandwidth escala com GCS, não com nossas
///     réplicas. Crítico para fotos de competição (até 10MB cada).
///   * /finalize dá hook pra metadata + AV (futuro) + linkar ao recurso
///     de domínio sem o BE saber o tipo upfront.
///
/// O método [uploadFile] orquestra os 3 passos (sign + PUT + finalize) e é
/// o que screens devem chamar. [sign] e [finalize] separados ficam expostos
/// pra cenários avançados (upload retomável, batch, etc.).
class UploadsRemoteRepo {
  UploadsRemoteRepo(this._api, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final TatamiClient _api;
  final http.Client _http;

  /// `POST /v1/uploads/sign` — minta URL PUT GCS pré-assinada (TTL ~10min).
  Future<SignUploadResponse> sign(
    SignUploadRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/uploads/sign',
      data: req.toJson(),
      key: key,
    );
    return SignUploadResponse.fromJson(json);
  }

  /// `POST /v1/uploads/finalize` — confirma que objeto chegou em GCS,
  /// move pro path canônico, registra metadata.
  ///
  /// Erros relevantes:
  ///   - 400 → upload_path malformado
  ///   - 403 → caller não é dono do upload (UID mismatch) ou fora da academy
  ///   - 404 → signed URL minted mas FE nunca PUT-ou os bytes
  ///   - 413 → tamanho real excede cap do purpose
  ///   - 415 → MIME type real diverge do declarado
  Future<ApiUploadedFile> finalize(
    FinalizeUploadRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/uploads/finalize',
      data: req.toJson(),
      key: key,
    );
    return ApiUploadedFile.fromJson(json);
  }

  /// Helper de alto nível: sign → PUT GCS → finalize. Retorna o arquivo
  /// finalizado.
  ///
  /// O PUT em GCS NÃO usa o tatamiClient (Dio) — bypass do Firebase auth
  /// header e do retry 401, porque a URL pré-assinada já carrega a
  /// autorização e GCS não conhece o nosso bearer.
  Future<ApiUploadedFile> uploadFile({
    required ApiUploadPurpose purpose,
    required String filename,
    required String contentType,
    required Uint8List bytes,
    String? academyId,
    String? targetId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final signed = await sign(SignUploadRequest(
      purpose: purpose,
      filename: filename,
      contentType: contentType,
      maxBytes: bytes.length,
      academyId: academyId,
    ));

    // Size sanity-check antes do PUT pra dar erro melhor que o 413 do GCS.
    if (bytes.length > signed.maxBytes) {
      throw UploadSizeLimitException(
        actual: bytes.length,
        limit: signed.maxBytes,
      );
    }

    final putRes = await _http.put(
      Uri.parse(signed.uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
      throw GcsUploadException(
        statusCode: putRes.statusCode,
        body: putRes.body,
      );
    }
    onProgress?.call(bytes.length, bytes.length);

    return finalize(FinalizeUploadRequest(
      uploadPath: signed.uploadPath,
      targetId: targetId,
    ));
  }

  /// Variante de [uploadFile] que lê de um [File]. Útil em pickers que
  /// retornam path no disco em vez de bytes em memória.
  Future<ApiUploadedFile> uploadFileFromDisk({
    required ApiUploadPurpose purpose,
    required File file,
    required String contentType,
    String? academyId,
    String? targetId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    final filename = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'upload';
    return uploadFile(
      purpose: purpose,
      filename: filename,
      contentType: contentType,
      bytes: bytes,
      academyId: academyId,
      targetId: targetId,
      onProgress: onProgress,
    );
  }
}

/// Lançada quando o arquivo escolhido excede o cap resolvido pelo BE.
/// Capturada cedo pra dar erro melhor que o 413 cru do GCS.
class UploadSizeLimitException implements Exception {
  const UploadSizeLimitException({required this.actual, required this.limit});
  final int actual;
  final int limit;

  @override
  String toString() =>
      'UploadSizeLimitException: $actual bytes (limit $limit)';
}

/// Lançada quando o PUT em GCS volta non-2xx (raro — assinatura é válida
/// por construção, mas pode acontecer em redes flaky ou se o BE expirar
/// o URL antes do PUT chegar).
class GcsUploadException implements Exception {
  const GcsUploadException({required this.statusCode, required this.body});
  final int statusCode;
  final String body;

  @override
  String toString() =>
      'GcsUploadException: status=$statusCode body=$body';
}
