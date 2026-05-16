import 'dto/plan_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Plan.
///
/// Endpoints: `/v1/academies/{academyId}/plans*`. Plans + atribuição de
/// alunos ao plano. A relação "qual plano um aluno tem" também pode ser
/// alterada via PATCH no aluno (`plan_id`) — vide StudentRemoteRepo.update.
class PlanRemoteRepo {
  PlanRemoteRepo(this._api);

  final TatamiClient _api;

  Future<List<ApiPlan>> list(String academyId) async {
    final json = await _api.get<dynamic>(
      '/v1/academies/$academyId/plans',
    );
    // Endpoint pode devolver lista direta OU envelope { items: [...] }
    // dependendo da versão do BE. Aceita ambos.
    if (json is List) {
      return json
          .whereType<Map<String, dynamic>>()
          .map(ApiPlan.fromJson)
          .toList();
    }
    if (json is Map<String, dynamic>) {
      final items = (json['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ApiPlan.fromJson)
          .toList();
      return items;
    }
    return const [];
  }

  Future<ApiPlan> getById(String academyId, String planId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/plans/$planId',
    );
    return ApiPlan.fromJson(json);
  }

  Future<ApiPlan> create(
    String academyId,
    CreatePlanRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/plans',
      data: req.toJson(),
      key: key,
    );
    return ApiPlan.fromJson(json);
  }

  Future<ApiPlan> update(
    String academyId,
    String planId,
    UpdatePlanRequest req,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/plans/$planId',
      data: req.toJson(),
    );
    return ApiPlan.fromJson(json);
  }

  Future<void> delete(String academyId, String planId) async {
    await _api.delete('/v1/academies/$academyId/plans/$planId');
  }

  /// Assina N alunos no plano em uma única chamada (transação no backend).
  /// Substitui o loop FE-side de N writes que o app legacy fazia.
  Future<void> assignStudents(
    String academyId,
    String planId,
    List<String> studentIds,
  ) async {
    await _api.post<dynamic>(
      '/v1/academies/$academyId/plans/$planId/students',
      data: {'student_ids': studentIds},
    );
  }

  /// Remove um aluno do plano (não deleta o aluno).
  Future<void> unassignStudent(
    String academyId,
    String planId,
    String studentId,
  ) async {
    await _api.delete(
      '/v1/academies/$academyId/plans/$planId/students/$studentId',
    );
  }
}
