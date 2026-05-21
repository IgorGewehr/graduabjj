// DTOs do contexto Uploads — alinhados 1:1 com api/openapi/uploads.yaml
// (backend Go, bounded context `internal/uploads`).
//
// Fluxo de 2 etapas:
//   1. POST /v1/uploads/sign      → SignUploadResponse com upload_url GCS
//   2. PUT  <upload_url>          → bytes vão FE→GCS direto (não passa pelo BE)
//   3. POST /v1/uploads/finalize  → BE confirma + registra metadata
//
// O wire format `purpose` é um enum stringificado; mantemos como ApiUploadPurpose
// para tipagem forte no Dart.

enum ApiUploadPurpose {
  studentPhoto,
  storeProduct,
  academySettings,
  competitionPhoto,
}

extension ApiUploadPurposeX on ApiUploadPurpose {
  /// Wire format snake_case esperado pelo BE.
  String get wire {
    switch (this) {
      case ApiUploadPurpose.studentPhoto:
        return 'student_photo';
      case ApiUploadPurpose.storeProduct:
        return 'store_product';
      case ApiUploadPurpose.academySettings:
        return 'academy_settings';
      case ApiUploadPurpose.competitionPhoto:
        return 'competition_photo';
    }
  }

  /// Content-types aceitos pelo BE para este purpose. Útil pra filtrar
  /// no picker antes de o usuário escolher arquivo inválido — o BE também
  /// rejeita server-side (415) se o cliente enviar tipo errado.
  List<String> get allowedContentTypes {
    switch (this) {
      case ApiUploadPurpose.studentPhoto:
      case ApiUploadPurpose.storeProduct:
        return const ['image/jpeg', 'image/png', 'image/webp'];
      case ApiUploadPurpose.academySettings:
        return const ['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml'];
      case ApiUploadPurpose.competitionPhoto:
        return const ['image/jpeg', 'image/png'];
    }
  }
}

/// Body do POST /v1/uploads/sign.
class SignUploadRequest {
  const SignUploadRequest({
    required this.purpose,
    required this.filename,
    required this.contentType,
    this.maxBytes,
    this.academyId,
  });

  final ApiUploadPurpose purpose;

  /// Basename do arquivo (sem path). Apenas a extensão é preservada no
  /// GCS path final; o BE rejeita `..`, slashes, control chars.
  final String filename;

  /// IANA media type. Deve estar na whitelist do [purpose].
  final String contentType;

  /// Cap opcional em bytes. `null` ou 0 → BE usa default do purpose.
  final int? maxBytes;

  /// Requerido se o caller tem membership em mais de uma academia.
  final String? academyId;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'purpose': purpose.wire,
      'filename': filename,
      'content_type': contentType,
    };
    if (maxBytes != null) m['max_bytes'] = maxBytes;
    if (academyId != null) m['academy_id'] = academyId;
    return m;
  }
}

/// Resposta do POST /v1/uploads/sign.
class SignUploadResponse {
  const SignUploadResponse({
    required this.uploadUrl,
    required this.uploadPath,
    required this.expiresAt,
    required this.maxBytes,
  });

  /// URL PUT assinada — single-use, expira em `expiresAt`. O FE deve
  /// PUT-ar os bytes direto aqui (com header Content-Type idêntico ao
  /// que pediu em [SignUploadRequest.contentType]).
  final String uploadUrl;

  /// Chave opaca do bucket. Eco verbatim no /finalize.
  final String uploadPath;

  final DateTime expiresAt;

  /// Cap resolvido (valor do caller OU default do purpose). FE deve
  /// validar tamanho antes de PUT.
  final int maxBytes;

  factory SignUploadResponse.fromJson(Map<String, dynamic> j) =>
      SignUploadResponse(
        uploadUrl: j['upload_url'] as String,
        uploadPath: j['upload_path'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        maxBytes: (j['max_bytes'] as num?)?.toInt() ?? 0,
      );
}

/// Body do POST /v1/uploads/finalize.
class FinalizeUploadRequest {
  const FinalizeUploadRequest({required this.uploadPath, this.targetId});

  final String uploadPath;

  /// Opcional: id do recurso de domínio que vai apontar pra este arquivo
  /// (ex: student id pra student_photo). O contexto dono atualiza a FK
  /// inversa (ex: `students.photo_file_id`).
  final String? targetId;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'upload_path': uploadPath};
    if (targetId != null) m['target_id'] = targetId;
    return m;
  }
}

/// Resposta do POST /v1/uploads/finalize.
class ApiUploadedFile {
  const ApiUploadedFile({
    required this.fileId,
    required this.internalPath,
    this.publicUrl,
  });

  final String fileId;

  /// Path estável per-purpose (ex: `student_photo/{academy_id}/{file_id}.jpg`).
  final String internalPath;

  /// CDN URL quando o bucket é publicamente legível. `null` em buckets
  /// privados — FE deve solicitar URL assinada via outro endpoint se
  /// precisar acessar.
  final String? publicUrl;

  factory ApiUploadedFile.fromJson(Map<String, dynamic> j) => ApiUploadedFile(
        fileId: j['file_id'] as String,
        internalPath: j['internal_path'] as String,
        publicUrl: j['public_url'] as String?,
      );
}
