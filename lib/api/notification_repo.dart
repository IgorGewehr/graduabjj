import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'dto/notification_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Notification.
///
/// Inclui inbox do usuário, FCM tokens (push), broadcast admin e SSE stream.
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

  /// `GET /v1/me/notifications/stream` — SSE (Server-Sent Events).
  ///
  /// O servidor emite eventos do tipo `data: <json>\n\n`. Cada evento pode
  /// ser um objeto `ApiNotification` único ou uma lista deles. O stream
  /// permanece aberto enquanto houver um listener; descarte o subscription
  /// para fechar a conexão HTTP.
  Stream<List<ApiNotification>> streamNotifications() async* {
    final uri = Uri.parse('${_api.baseUrl}/v1/me/notifications/stream');

    // Usa FirebaseAuth diretamente — TatamiClient não expõe getAuthToken().
    final token =
        await FirebaseAuth.instance.currentUser?.getIdToken();

    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';

      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final response = await client.send(request);

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;

        final raw = line.substring(6).trim();
        if (raw.isEmpty || raw == '[DONE]') continue;

        final dynamic decoded = jsonDecode(raw);
        if (decoded is List) {
          yield decoded
              .whereType<Map<String, dynamic>>()
              .map(ApiNotification.fromJson)
              .toList();
        } else if (decoded is Map<String, dynamic>) {
          yield [ApiNotification.fromJson(decoded)];
        }
      }
    } finally {
      client.close();
    }
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
