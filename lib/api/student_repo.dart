import 'dto/student_dto.dart';
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

  /// `GET /v1/academies/{academyId}/students/{studentId}/eligibility` —
  /// avaliação server-side de elegibilidade pra próxima graduação. Antes
  /// o cliente fazia a comparação threshold-vs-attendances localmente.
  Future<ApiEligibilityView> getEligibility(
    String academyId,
    String studentId,
  ) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId/eligibility',
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
}
