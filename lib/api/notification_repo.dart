import 'dto/notification_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Notification.
///
/// Inclui inbox do usuário, FCM tokens (push) e broadcast admin. NÃO inclui
/// SSE stream — esse fica para um PR posterior usando event_source ou
/// HTTP streaming hand-rolled. O caminho intermediário do doc 03 §8 é
/// polling com ETag, que pode ser implementado por cima do list() daqui.
class NotificationRemoteRepo {
  NotificationRemoteRepo(this._api);

  final TatamiClient _api;

  // ---------------------------------------------------------------------------
  // Inbox do usuário (/v1/me/notifications*).
  // ---------------------------------------------------------------------------

  Future<NotificationsPage> list({
    NotificationsFilter filter = const NotificationsFilter(),
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/me/notifications',
      queryParameters: filter.toQueryParameters(),
    );
    return NotificationsPage.fromJson(json);
  }

  /// `GET /v1/me/notifications/unread-count` — endpoint leve dedicado pro
  /// badge da UI. NÃO use list() só pra contar não-lidas.
  Future<int> getUnreadCount({String? academyId}) async {
    final params = <String, dynamic>{};
    if (academyId != null) params['academy_id'] = academyId;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/me/notifications/unread-count',
      queryParameters: params.isEmpty ? null : params,
    );
    return (json['unread_count'] as num?)?.toInt() ?? 0;
  }

  /// `PATCH /v1/me/notifications/{id}` — `{read: bool}`. Default true.
  /// `read: false` permite desfazer ("marcar como não lida").
  Future<ApiNotification> markRead(String notificationId,
      {bool read = true}) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/me/notifications/$notificationId',
      data: {'read': read},
    );
    return ApiNotification.fromJson(json);
  }

  /// `POST /v1/me/notifications/mark-all-read` — bulk. Retorna quantas
  /// linhas foram atualizadas.
  Future<int> markAllRead({String? academyId}) async {
    final body = <String, dynamic>{};
    if (academyId != null) body['academy_id'] = academyId;
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/me/notifications/mark-all-read',
      data: body,
    );
    return (json['updated_count'] as num?)?.toInt() ?? 0;
  }

  Future<void> delete(String notificationId) async {
    await _api.delete('/v1/me/notifications/$notificationId');
  }

  // ---------------------------------------------------------------------------
  // FCM tokens (/v1/me/fcm-tokens*).
  // ---------------------------------------------------------------------------

  /// Idempotente em (uid, token). Reregistrar o mesmo token só bumpa
  /// last_seen_at. App deve chamar isso no launch E sempre que o Firebase
  /// rotacionar o token.
  Future<ApiFCMToken> registerFcmToken(RegisterFcmTokenRequest req) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/me/fcm-tokens',
      data: req.toJson(),
    );
    return ApiFCMToken.fromJson(json);
  }

  Future<void> deregisterFcmToken(String token) async {
    // Sem encode — token é opaco mas pode conter ':' / '/'. Usamos um
    // Uri.encodeComponent pra ser seguro.
    final encoded = Uri.encodeComponent(token);
    await _api.delete('/v1/me/fcm-tokens/$encoded');
  }

  // ---------------------------------------------------------------------------
  // Broadcast (/v1/academies/{id}/notifications/broadcast) — admin-only.
  // ---------------------------------------------------------------------------

  /// Admin envia uma notificação para vários usuários da academia em uma
  /// chamada. Backend resolve recipients via roles/filters e cria N rows
  /// em uma transação. Canais async são enfileirados no outbox.
  ///
  /// USE Idempotency-Key — broadcast é caro e o app pode retentar em flap.
  Future<BroadcastResponse> broadcast(
    String academyId,
    BroadcastRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/notifications/broadcast',
      data: req.toJson(),
      key: key,
    );
    return BroadcastResponse.fromJson(json);
  }
}
