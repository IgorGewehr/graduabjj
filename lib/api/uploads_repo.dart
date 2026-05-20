import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'dto/upload_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório do contexto Uploads — fluxo de 2 etapas (sign + PUT).
///
/// Por que 2 etapas em vez de POST multipart pelo backend:
///   * Bytes não passam pelo BE — bandwidth escala com GCS, não com nossas
///     réplicas. Crítico para fotos de competição (até 10MB cada).
///   * O domínio que consome o upload (competition, student, store) é
///     responsável por linkar o storage_path ao recurso na própria chamada.
///
/// O método [uploadFile] orquestra sign + PUT e retorna o upload_path.
/// Screens devem chamar [uploadFile] e depois a API de domínio (ex:
/// createPhoto, updateStudent) para confirmar.
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

  // NOTE: There is no /v1/uploads/finalize endpoint in the backend.
  // The sign response contains upload_path which the domain-level
  // caller (createPhoto, updateStudent, etc.) uses directly.

  /// Helper de alto nível: sign → PUT GCS. Retorna o upload_path
  /// para uso pelo caller na chamada de domínio subsequente.
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

    // The backend has no /v1/uploads/finalize endpoint — the sign
    // response already contains the upload_path. The domain-level
    // caller (e.g. createPhoto, updateStudent) is responsible for
    // linking the storage path to the resource.
    return ApiUploadedFile(
      fileId: '',
      internalPath: signed.uploadPath,
      publicUrl: null,
    );
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
