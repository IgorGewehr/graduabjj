import 'dto/academy_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Preview de um link code sem consumi-lo.
///
/// Endpoint: GET /v1/link-codes/{code}
class LinkCodePreview {
  final String academyId;
  final String academyName;
  final String academyLogoUrl;
  final String role;
  final String? studentId;
  final String? studentName;
  final DateTime expiresAt;

  const LinkCodePreview({
    required this.academyId,
    required this.academyName,
    required this.academyLogoUrl,
    required this.role,
    required this.studentId,
    required this.expiresAt,
    this.studentName,
  });

  factory LinkCodePreview.fromJson(Map<String, dynamic> json) => LinkCodePreview(
        academyId: json['academy_id'] as String,
        academyName: json['academy_name'] as String,
        academyLogoUrl: json['academy_logo_url'] as String? ?? '',
        role: json['role'] as String,
        studentId: json['student_id'] as String?,
        studentName: json['student_name'] as String?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

/// Repositório remoto para link codes — códigos curtos pra
/// vincular um Firebase user a uma academia.
///
/// Endpoints:
/// - GET  /v1/link-codes/{code}                       (preview sem consumir)
/// - POST /v1/academies/{id}/link-codes              (aluno, TTL 24h default)
/// - POST /v1/academies/{id}/instructor-link-codes   (instrutor, TTL 30min)
/// - POST /v1/link-codes/{code}/redeem               (ATÔMICO — SELECT FOR UPDATE)
///
/// O legacy do FE fazia 5 writes Firestore não-atômicos no redeem. Aqui é
/// uma chamada só; o backend garante consistência.
class LinkCodeRemoteRepo {
  LinkCodeRemoteRepo(this._api);

  final TatamiClient _api;

  /// Gera um link code de aluno (TTL padrão 24h). Caller (admin) já está
  /// autenticado e dentro da academia.
  Future<ApiLinkCode> createForStudent(
    String academyId, {
    String? studentId,
    int? ttlSeconds,
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final req = CreateLinkCodeRequest(
      role: ApiLinkCodeRole.student,
      studentId: studentId,
      ttlSeconds: ttlSeconds,
    );
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/link-codes',
      data: req.toJson(),
      key: key,
    );
    return ApiLinkCode.fromJson(json);
  }

  /// Gera um link code de instrutor (TTL padrão 30min — backend define).
  Future<ApiInstructorLinkCode> createForInstructor(
    String academyId, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/instructor-link-codes',
      data: const <String, dynamic>{},
      key: key,
    );
    return ApiInstructorLinkCode.fromJson(json);
  }

  /// Retorna um preview do link code sem consumi-lo. Útil para exibir
  /// nome/logo da academia antes do usuário confirmar o vínculo.
  Future<LinkCodePreview> getPreview(String code) async {
    final json = await _api.get<Map<String, dynamic>>('/v1/link-codes/$code');
    return LinkCodePreview.fromJson(json);
  }

  /// Resgata um link code. Atômico server-side — se dois clientes resgatarem
  /// o mesmo código simultaneamente, um recebe 200 e o outro 409 com
  /// `problem.type=link-code-already-used`.
  ///
  /// [profile] é opcional: se o código não referencia um student existente,
  /// o BE cria um Student row com esses dados.
  Future<RedeemLinkCodeResponse> redeem(
    String code, {
    RedeemLinkCodeRequest profile = const RedeemLinkCodeRequest(),
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/link-codes/$code/redeem',
      data: profile.toJson(),
    );
    return RedeemLinkCodeResponse.fromJson(json);
  }
}
