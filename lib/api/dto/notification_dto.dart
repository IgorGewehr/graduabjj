// DTOs do contexto Notification, alinhados 1:1 com api/openapi/notification.yaml.
//
// Cobre inbox + FCM tokens + broadcast admin. SSE stream NÃO está coberto
// aqui — o FE migra de Firestore .snapshots() para POLLING com ETag (doc 03
// §8) como passo intermediário; SSE entra num PR posterior usando package
// event_source ou hand-rolled streaming HTTP.

// Enums casam 1:1 com wire format (snake_case) do OpenAPI.
// ignore_for_file: constant_identifier_names

enum ApiNotificationType {
  payment_due,
  payment_paid,
  payment_overdue,
  graduation_eligible,
  graduation_promoted,
  competition_announcement,
  competition_enrollment,
  store_order_update,
  generic,
}

extension ApiNotificationTypeX on ApiNotificationType {
  String get wire => name;
  static ApiNotificationType fromWire(String? value) {
    for (final t in ApiNotificationType.values) {
      if (t.name == value) return t;
    }
    return ApiNotificationType.generic;
  }
}

enum ApiNotificationChannel { inbox, push, whatsapp, email }

extension ApiNotificationChannelX on ApiNotificationChannel {
  String get wire => name;
  static ApiNotificationChannel fromWire(String? value) {
    for (final c in ApiNotificationChannel.values) {
      if (c.name == value) return c;
    }
    return ApiNotificationChannel.inbox;
  }
}

enum ApiDevicePlatform { ios, android, web }

extension ApiDevicePlatformX on ApiDevicePlatform {
  String get wire => name;
  static ApiDevicePlatform fromWire(String? value) {
    for (final p in ApiDevicePlatform.values) {
      if (p.name == value) return p;
    }
    return ApiDevicePlatform.android;
  }
}

enum ApiDispatchStatus { pending, sent, failed, skipped }

extension ApiDispatchStatusX on ApiDispatchStatus {
  String get wire => name;
  static ApiDispatchStatus fromWire(String? value) {
    for (final s in ApiDispatchStatus.values) {
      if (s.name == value) return s;
    }
    return ApiDispatchStatus.pending;
  }
}

class ApiDispatch {
  const ApiDispatch({
    required this.channel,
    required this.status,
    this.attempt,
    this.error,
    this.deliveredAt,
  });

  final ApiNotificationChannel channel;
  final ApiDispatchStatus status;
  final int? attempt;
  final String? error;
  final DateTime? deliveredAt;

  factory ApiDispatch.fromJson(Map<String, dynamic> j) => ApiDispatch(
        channel: ApiNotificationChannelX.fromWire(j['channel'] as String?),
        status: ApiDispatchStatusX.fromWire(j['status'] as String?),
        attempt: (j['attempt'] as num?)?.toInt(),
        error: j['error'] as String?,
        deliveredAt: _parseDate(j['delivered_at']),
      );
}

class ApiNotification {
  const ApiNotification({
    required this.id,
    required this.recipientUid,
    required this.type,
    required this.title,
    required this.createdAt,
    this.academyId,
    this.body,
    this.actionUrl,
    this.metadata,
    this.channels = const [],
    this.readAt,
    this.dispatches = const [],
  });

  final String id;
  final String? academyId;
  final String recipientUid;
  final ApiNotificationType type;
  final String title;
  final String? body;
  final String? actionUrl;
  final Map<String, dynamic>? metadata;
  final List<ApiNotificationChannel> channels;
  final DateTime? readAt;
  final DateTime createdAt;

  /// Apenas presente em GET por id (não no list).
  final List<ApiDispatch> dispatches;

  bool get isRead => readAt != null;
  bool get isUnread => readAt == null;

  factory ApiNotification.fromJson(Map<String, dynamic> j) => ApiNotification(
        id: j['id'] as String,
        academyId: j['academy_id'] as String?,
        recipientUid: j['recipient_uid'] as String,
        type: ApiNotificationTypeX.fromWire(j['type'] as String?),
        title: j['title'] as String,
        body: j['body'] as String?,
        actionUrl: j['action_url'] as String?,
        metadata: j['metadata'] is Map<String, dynamic>
            ? j['metadata'] as Map<String, dynamic>
            : null,
        channels: (j['channels'] as List? ?? const [])
            .whereType<String>()
            .map(ApiNotificationChannelX.fromWire)
            .toList(),
        readAt: _parseDate(j['read_at']),
        createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
        dispatches: (j['dispatches'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiDispatch.fromJson)
            .toList(),
      );
}

class NotificationsPage {
  const NotificationsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiNotification> items;
  final String? nextCursor;
  final bool hasMore;

  factory NotificationsPage.fromJson(Map<String, dynamic> j) =>
      NotificationsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiNotification.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class NotificationsFilter {
  const NotificationsFilter({
    this.unreadOnly,
    this.type,
    this.academyId,
    this.limit = 50,
    this.cursor,
  });

  final bool? unreadOnly;
  final ApiNotificationType? type;
  final String? academyId;
  final int limit;
  final String? cursor;

  Map<String, dynamic> toQueryParameters() {
    final m = <String, dynamic>{'limit': limit};
    if (unreadOnly != null) m['unread_only'] = unreadOnly;
    if (type != null) m['type'] = type!.wire;
    if (academyId != null) m['academy_id'] = academyId;
    if (cursor != null) m['cursor'] = cursor;
    return m;
  }
}

class ApiFCMToken {
  const ApiFCMToken({
    required this.token,
    required this.platform,
    required this.registeredAt,
    this.appVersion,
    this.locale,
    this.lastSeenAt,
  });

  final String token;
  final ApiDevicePlatform platform;
  final String? appVersion;
  final String? locale;
  final DateTime registeredAt;
  final DateTime? lastSeenAt;

  factory ApiFCMToken.fromJson(Map<String, dynamic> j) => ApiFCMToken(
        token: j['token'] as String,
        platform: ApiDevicePlatformX.fromWire(j['platform'] as String?),
        appVersion: j['app_version'] as String?,
        locale: j['locale'] as String?,
        registeredAt: _parseDate(j['registered_at']) ?? DateTime.now(),
        lastSeenAt: _parseDate(j['last_seen_at']),
      );
}

class RegisterFcmTokenRequest {
  const RegisterFcmTokenRequest({
    required this.token,
    required this.platform,
    this.appVersion,
    this.locale,
  });

  final String token;
  final ApiDevicePlatform platform;
  final String? appVersion;
  final String? locale;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'token': token, 'platform': platform.wire};
    if (appVersion != null) m['app_version'] = appVersion;
    if (locale != null) m['locale'] = locale;
    return m;
  }
}

class BroadcastRecipientsFilter {
  const BroadcastRecipientsFilter({
    this.role,
    this.studentBelt,
    this.includeUids,
    this.excludeUids,
  });

  final List<String>? role;
  final List<String>? studentBelt;
  final List<String>? includeUids;
  final List<String>? excludeUids;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (role != null) m['role'] = role;
    if (studentBelt != null) m['student_belt'] = studentBelt;
    if (includeUids != null) m['include_uids'] = includeUids;
    if (excludeUids != null) m['exclude_uids'] = excludeUids;
    return m;
  }

  bool get isEmpty =>
      (role == null || role!.isEmpty) &&
      (studentBelt == null || studentBelt!.isEmpty) &&
      (includeUids == null || includeUids!.isEmpty) &&
      (excludeUids == null || excludeUids!.isEmpty);
}

class BroadcastRequest {
  const BroadcastRequest({
    required this.type,
    required this.title,
    this.body,
    this.actionUrl,
    this.metadata,
    this.channels,
    this.recipients,
  });

  final ApiNotificationType type;
  final String title;
  final String? body;
  final String? actionUrl;
  final Map<String, dynamic>? metadata;
  final List<ApiNotificationChannel>? channels;
  final BroadcastRecipientsFilter? recipients;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'type': type.wire, 'title': title};
    if (body != null) m['body'] = body;
    if (actionUrl != null) m['action_url'] = actionUrl;
    if (metadata != null) m['metadata'] = metadata;
    if (channels != null) {
      m['channels'] = channels!.map((c) => c.wire).toList();
    }
    if (recipients != null) m['recipients'] = recipients!.toJson();
    return m;
  }
}

class BroadcastResponse {
  const BroadcastResponse({
    required this.broadcastId,
    required this.queuedCount,
  });

  final String broadcastId;
  final int queuedCount;

  factory BroadcastResponse.fromJson(Map<String, dynamic> j) =>
      BroadcastResponse(
        broadcastId: j['broadcast_id'] as String,
        queuedCount: (j['queued_count'] as num?)?.toInt() ?? 0,
      );
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
