import 'dto/student_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Student.
///
/// Esta fase (Sprint 2 / leituras pesadas) só expõe métodos READ. Os
/// métodos de mutação (create/update/delete + belt-progressions/assessments
/// create) entram no Sprint 3, no mesmo arquivo.
///
/// Convenção: TODAS as listagens são paginadas por cursor. O cursor é
/// opaco para o cliente — basta repassar verbatim na próxima chamada.
class StudentRemoteRepo {
  StudentRemoteRepo(this._api);

  final TatamiClient _api;

  /// `GET /v1/academies/{academyId}/students` paginado.
  /// Substitui `student_service.getAll()` e `searchByName()` em uma só API.
  Future<StudentsPage> list(
    String academyId, {
    StudentFilter filter = const StudentFilter(),
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/students',
      queryParameters: filter.toQueryParameters(),
    );
    return StudentsPage.fromJson(json);
  }

  /// `GET /v1/academies/{academyId}/students/{studentId}`.
  Future<ApiStudent> getById(String academyId, String studentId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId',
    );
    return ApiStudent.fromJson(json);
  }

  /// `GET /v1/academies/{academyId}/students/stats` — KPIs do dashboard.
  /// Substitui `student_service.getDashboardStats()` (que rodava N reads
  /// no Firestore e calculava em memória).
  Future<ApiStudentStats> getStats(String academyId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/stats',
    );
    return ApiStudentStats.fromJson(json);
  }

  /// `GET /v1/academies/{academyId}/students/{studentId}/graduation-eligibility`
  /// — avaliação server-side de elegibilidade pra próxima graduação. Antes
  /// o cliente fazia a comparação threshold-vs-attendances localmente. O
  /// path explícito "graduation-eligibility" (vs só "eligibility") evita
  /// colisão semântica com checks de entitlement em outros contextos.
  Future<ApiEligibilityView> getEligibility(
    String academyId,
    String studentId,
  ) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId/graduation-eligibility',
    );
    return ApiEligibilityView.fromJson(json);
  }

  /// `GET /v1/academies/{academyId}/students/{studentId}/belt-progressions`.
  /// Lista o histórico de promoções de graduação. Paginação por cursor.
  Future<BeltProgressionsPage> listBeltProgressions(
    String academyId,
    String studentId, {
    int limit = 20,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId/belt-progressions',
      queryParameters: params,
    );
    return BeltProgressionsPage.fromJson(json);
  }

  /// `GET /v1/academies/{academyId}/students/{studentId}/assessments` —
  /// histórico de avaliações (kids). Paginação por cursor.
  Future<AssessmentsPage> listAssessments(
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

  // ===========================================================================
  // Mutations (Sprint 3 — escritas de baixo risco).
  //
  // POST /students é IDEMPOTENT — gera ou reusa Idempotency-Key. PATCH e
  // DELETE são naturalmente idempotentes pelo verbo HTTP.
  // ===========================================================================

  /// `POST /v1/academies/{academyId}/students`.
  /// Se [idempotencyKey] não for passada, uma é gerada — o caller pode
  /// persistir essa chave (toString()) para retentar com segurança após
  /// crash/restart.
  Future<ApiStudent> create(
    String academyId,
    CreateStudentRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/students',
      data: req.toJson(),
      key: key,
    );
    return ApiStudent.fromJson(json);
  }

  /// `PATCH /v1/academies/{academyId}/students/{studentId}` — atualização
  /// parcial. Campos null em [req] não são enviados.
  Future<ApiStudent> update(
    String academyId,
    String studentId,
    UpdateStudentRequest req,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId',
      data: req.toJson(),
    );
    return ApiStudent.fromJson(json);
  }

  /// `DELETE /v1/academies/{academyId}/students/{studentId}`.
  /// Soft-delete: o registro permanece com status='removed'. O backend
  /// suporta `?hard=true` (admin) — não exposto aqui de propósito; chamadas
  /// destrutivas devem ser explícitas.
  Future<void> delete(String academyId, String studentId) async {
    await _api.delete('/v1/academies/$academyId/students/$studentId');
  }

  /// `POST /v1/academies/{academyId}/students/{studentId}/belt-progressions`.
  /// Cria a promoção E atualiza `students.current_belt/current_stripes` na
  /// mesma transação no backend — o caller não precisa de duas chamadas.
  Future<ApiBeltProgression> createBeltProgression(
    String academyId,
    String studentId,
    CreateBeltProgressionRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId/belt-progressions',
      data: req.toJson(),
      key: key,
    );
    return ApiBeltProgression.fromJson(json);
  }

  /// `POST /v1/academies/{academyId}/students/{studentId}/assessments`.
  /// Avaliação (kids) — 5 scores 1-5 + notas. Idempotent.
  Future<ApiAssessment> createAssessment(
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
