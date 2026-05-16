import 'dto/identity_dto.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Identity.
///
/// Encapsula as chamadas REST para `/v1/me*` e `/v1/users/*`. Stateless —
/// recebe o [TatamiClient] por injeção, sem cache local. O cache, quando
/// fizer sentido, fica no provider Riverpod que consome este repo.
class IdentityRemoteRepo {
  IdentityRemoteRepo(this._api);

  final TatamiClient _api;

  /// `GET /v1/me` — perfil + memberships do caller numa única round-trip.
  /// Substitui as 3+ leituras Firestore (users + userAcademyMapping + N
  /// academies) do fluxo legacy.
  Future<CurrentUserResponse> getMe() async {
    final json = await _api.get<Map<String, dynamic>>('/v1/me');
    return CurrentUserResponse.fromJson(json);
  }

  /// `PATCH /v1/me` — atualiza o perfil global do caller. Apenas os campos
  /// presentes em [req] são alterados; os demais ficam intactos.
  Future<ApiGlobalUser> updateMe(UpdateUserRequest req) async {
    final json =
        await _api.patch<Map<String, dynamic>>('/v1/me', data: req.toJson());
    return ApiGlobalUser.fromJson(json);
  }

  /// `GET /v1/academies/{academyId}/memberships` paginado por cursor.
  ///
  /// [role] filtra por papel quando passado. [limit] é hint — o backend
  /// clampa em [1, 100]. O `nextCursor` retornado é opaco e deve ser
  /// repassado verbatim na próxima chamada.
  Future<MembershipsPage> listMemberships(
    String academyId, {
    String? role,
    String? status,
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (role != null) params['role'] = role;
    if (status != null) params['status'] = status;
    if (cursor != null) params['cursor'] = cursor;

    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/memberships',
      queryParameters: params,
    );
    final items = (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ApiMembership.fromJson)
        .toList();
    return MembershipsPage(
      items: items,
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  /// `GET /v1/users/{uid}` — perfil global de outro usuário (admin only).
  Future<ApiGlobalUser> getUserByUid(String uid) async {
    final json = await _api.get<Map<String, dynamic>>('/v1/users/$uid');
    return ApiGlobalUser.fromJson(json);
  }
}

class MembershipsPage {
  const MembershipsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiMembership> items;
  final String? nextCursor;
  final bool hasMore;
}
