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

  /// Atribui um único aluno ao plano.
  ///
  /// `POST /v1/academies/{academyId}/plans/{planId}/students/{studentId}`
  ///
  /// O backend NÃO tem rota bulk sem studentId no path — cada aluno deve
  /// ser atribuído individualmente. Para N alunos use [assignStudents].
  Future<void> assignStudent(
    String academyId,
    String planId,
    String studentId,
  ) async {
    await _api.post<dynamic>(
      '/v1/academies/$academyId/plans/$planId/students/$studentId',
    );
  }

  /// Atribui N alunos ao plano chamando o endpoint individual por aluno.
  ///
  /// Cada chamada vai para
  /// `POST /v1/academies/{academyId}/plans/{planId}/students/{studentId}`.
  /// As chamadas são feitas em paralelo via [Future.wait] para minimizar
  /// latência percebida.
  Future<void> assignStudents(
    String academyId,
    String planId,
    List<String> studentIds,
  ) async {
    await Future.wait(
      studentIds.map(
        (sid) => _api.post<dynamic>(
          '/v1/academies/$academyId/plans/$planId/students/$sid',
        ),
      ),
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

  /// `PATCH /v1/academies/{academyId}/plans/{planId}/students/{studentId}`
  ///
  /// Atualiza valor customizado e/ou dia de vencimento de um aluno no plano.
  /// Campos null não são enviados — somente os campos presentes são alterados.
  /// Para remover um override (voltar ao padrão do plano), passe `null` como
  /// valor — o backend interpreta campos ausentes como "manter" e campos
  /// explicitamente `null` como "remover override".
  Future<void> setStudentCustomValue(
    String academyId,
    String planId,
    String studentId, {
    String? customValue, // decimal string ex: "99.90" — backend rejects numbers
    int? customDueDay,
  }) async {
    final body = <String, dynamic>{};
    if (customValue != null) {
      body['custom_value'] = customValue;
    }
    if (customDueDay != null) {
      body['custom_due_day'] = customDueDay;
    }
    await _api.patch<dynamic>(
      '/v1/academies/$academyId/plans/$planId/students/$studentId',
      data: body,
    );
  }

  /// Alias semântico que envia `custom_value: null` e `custom_due_day: null`
  /// para remover todos os overrides do aluno e voltar ao padrão do plano.
  Future<void> clearStudentCustomValues(
    String academyId,
    String planId,
    String studentId,
  ) async {
    await _api.patch<dynamic>(
      '/v1/academies/$academyId/plans/$planId/students/$studentId',
      data: {'custom_value': null, 'custom_due_day': null},
    );
  }
}
