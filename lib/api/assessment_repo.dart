import 'dto/student_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Assessment (avaliação de alunos kids).
///
/// As avaliações são exclusivas de alunos com categoria `kids` — o backend
/// retorna 422 para alunos adultos. Cada avaliação registra 5 critérios
/// (respeito, disciplina, pontualidade, técnica, esforço) com notas de 1-5.
///
/// Os DTOs (ApiAssessment, ApiAssessmentScores, AssessmentsPage,
/// CreateAssessmentRequest) são compartilhados com StudentRemoteRepo e
/// vivem em `dto/student_dto.dart`.
class AssessmentRemoteRepo {
  AssessmentRemoteRepo(this._api);

  final TatamiClient _api;

  /// `GET /v1/academies/{academyId}/students/{studentId}/assessments`
  ///
  /// Histórico de avaliações, paginado por cursor. A resposta é
  /// `{"items": [...]}` sem cursor quando não há mais páginas.
  Future<AssessmentsPage> getByStudent(
    String academyId,
    String studentId, {
    int limit = 20,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId/assessments',
      queryParameters: params,
    );
    return AssessmentsPage.fromJson(json);
  }

  /// `POST /v1/academies/{academyId}/students/{studentId}/assessments`
  ///
  /// Cria uma avaliação. Idempotente via Idempotency-Key — o caller pode
  /// persistir a chave e retentar com segurança após crash/restart.
  ///
  /// Erros relevantes:
  ///   - 422 → aluno adulto (assessments são only-kids)
  ///   - 404 → aluno não encontrado
  Future<ApiAssessment> create(
    String academyId,
    String studentId,
    CreateAssessmentRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId/assessments',
      data: req.toJson(),
      key: key,
    );
    return ApiAssessment.fromJson(json);
  }
}
