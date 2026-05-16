import 'dto/academy_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto para link codes — códigos curtos pra
/// vincular um Firebase user a uma academia.
///
/// Endpoints:
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
