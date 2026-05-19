import 'dto/student_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto BeltProgression (graduações).
///
/// Cobre três endpoints:
///   - histórico de promoções do aluno (paginado por cursor)
///   - elegibilidade para próxima graduação (cálculo server-side)
///   - criação de promoção (atualiza current_belt/stripes na mesma transação)
///
/// Os DTOs (ApiBeltProgression, BeltProgressionsPage, ApiEligibilityView,
/// CreateBeltProgressionRequest) são compartilhados com StudentRemoteRepo
/// e vivem em `dto/student_dto.dart`.
class BeltProgressionRemoteRepo {
  BeltProgressionRemoteRepo(this._api);

  final TatamiClient _api;

  /// `GET /v1/academies/{academyId}/students/{studentId}/belt-progressions`
  ///
  /// Retorna o histórico de promoções paginado por cursor, da mais recente
  /// para a mais antiga. Usar [cursor] retornado na resposta anterior para
  /// buscar a próxima página.
  Future<BeltProgressionsPage> getHistory(
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

  /// `GET /v1/academies/{academyId}/students/{studentId}/graduation-eligibility`
  ///
  /// Avaliação server-side de elegibilidade para próxima graduação. Inclui
  /// contagem de presenças atual vs threshold, faixa atual/próxima e flag
  /// `eligible`. Antes o cliente fazia esse cálculo localmente.
  Future<ApiEligibilityView> getEligibility(
    String academyId,
    String studentId,
  ) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId/graduation-eligibility',
    );
    return ApiEligibilityView.fromJson(json);
  }

  /// `GET /v1/academies/{academyId}/belt-progressions/eligible`
  ///
  /// Lista todos os alunos elegíveis para graduação na academia, calculado
  /// server-side. Retorna alunos com `eligible == true` junto com o snapshot
  /// completo de elegibilidade de cada um (mesma estrutura de
  /// `graduation-eligibility`). Suporta paginação por cursor e filtro de
  /// [limit].
  Future<EligibleStudentsPage> getEligibleStudents(
    String academyId, {
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/belt-progressions/eligible',
      queryParameters: params,
    );
    return EligibleStudentsPage.fromJson(json);
  }

  /// `GET /v1/academies/{academyId}/students/belt-distribution`
  ///
  /// Retorna a contagem de alunos ativos por faixa, calculada server-side.
  /// Substitui a agregação client-side que buscava todos os alunos e
  /// contabilizava localmente.
  Future<List<ApiBeltCount>> getBeltDistribution(String academyId) async {
    final json = await _api.get<dynamic>(
      '/v1/academies/$academyId/students/belt-distribution',
    );
    if (json is List) {
      return json
          .whereType<Map<String, dynamic>>()
          .map(ApiBeltCount.fromJson)
          .toList();
    }
    if (json is Map<String, dynamic>) {
      return (json['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ApiBeltCount.fromJson)
          .toList();
    }
    return const [];
  }

  /// `GET /v1/academies/{academyId}/belt-progressions/recent?limit={N}`
  ///
  /// Retorna as N promoções mais recentes da academia, com dados básicos
  /// do aluno embutidos. Substitui a busca Firestore paginada que requeria
  /// leituras extras para montar o nome/foto de cada aluno.
  Future<List<ApiRecentProgression>> getRecentProgressions(
    String academyId, {
    int limit = 20,
  }) async {
    final json = await _api.get<dynamic>(
      '/v1/academies/$academyId/belt-progressions/recent',
      queryParameters: {'limit': limit},
    );
    if (json is List) {
      return json
          .whereType<Map<String, dynamic>>()
          .map(ApiRecentProgression.fromJson)
          .toList();
    }
    if (json is Map<String, dynamic>) {
      return (json['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ApiRecentProgression.fromJson)
          .toList();
    }
    return const [];
  }

  /// `POST /v1/academies/{academyId}/students/{studentId}/belt-progressions`
  ///
  /// Cria a promoção E atualiza `current_belt/current_stripes` do aluno na
  /// mesma transação — o caller não precisa de duas chamadas separadas.
  /// Idempotente via Idempotency-Key.
  ///
  /// Erros relevantes:
  ///   - 422 → sequência de faixa inválida (ex: pular de branca para roxa)
  ///   - 404 → aluno não encontrado
  Future<ApiBeltProgression> promote(
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
}
