import 'dto/academy_dto.dart';
import 'tatami_client.dart';

/// Repositório remoto para settings de academia.
///
/// Endpoints: `/v1/academies/{academyId}/settings*`. Settings são key/value
/// arbitrário — value é `dynamic`, o consumidor sabe o tipo de cada chave.
/// Tipos esperados ficam documentados no doc 09 (glossário).
class SettingsRemoteRepo {
  SettingsRemoteRepo(this._api);

  final TatamiClient _api;

  /// GET retorna o mapa key→value de TODAS as configurações da academia.
  /// O backend formata como `{ items: [ {academy_id, key, value, updated_at} ] }`.
  /// Convertemos para `Map<String, ApiAcademySetting>` indexado por key.
  Future<Map<String, ApiAcademySetting>> getAll(String academyId) async {
    final json = await _api.get<dynamic>(
      '/v1/academies/$academyId/settings',
    );
    final list = json is List
        ? json
        : (json is Map<String, dynamic> ? (json['items'] as List? ?? []) : []);
    final result = <String, ApiAcademySetting>{};
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final s = ApiAcademySetting.fromJson(item);
        result[s.key] = s;
      }
    }
    return result;
  }

  /// PUT /v1/academies/{academyId}/settings/{key} — upsert idempotente.
  /// [value] aceita qualquer JSON-serializable (string, num, bool, Map, List).
  /// O backend devolve o ApiAcademySetting atualizado.
  Future<ApiAcademySetting> set(
    String academyId,
    String key,
    dynamic value,
  ) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/v1/academies/$academyId/settings/$key',
      data: {'value': value},
    );
    return ApiAcademySetting.fromJson(json);
  }
}
