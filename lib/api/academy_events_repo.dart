import 'idempotency.dart';
import 'tatami_client.dart';

// DTOs do contexto AcademyEvent.

enum ApiEventType { regular, seminar, competition, social, other }

extension ApiEventTypeX on ApiEventType {
  String get wire => name;
  static ApiEventType fromWire(String? value) {
    for (final t in ApiEventType.values) {
      if (t.name == value) return t;
    }
    return ApiEventType.regular;
  }
}

class ApiAcademyEvent {
  const ApiAcademyEvent({
    required this.id,
    required this.academyId,
    required this.title,
    required this.startsAt,
    this.description,
    this.location,
    this.type,
    this.endsAt,
    this.imageUrl,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String academyId;
  final String title;
  final String? description;
  final String? location;
  final ApiEventType? type;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? imageUrl;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ApiAcademyEvent.fromJson(Map<String, dynamic> j) => ApiAcademyEvent(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        location: j['location'] as String?,
        type: j['type'] == null
            ? null
            : ApiEventTypeX.fromWire(j['type'] as String?),
        startsAt: _parseDate(j['starts_at']) ?? DateTime.now(),
        endsAt: _parseDate(j['ends_at']),
        imageUrl: j['image_url'] as String?,
        createdByUid: j['created_by_uid'] as String?,
        createdAt: _parseDate(j['created_at']),
        updatedAt: _parseDate(j['updated_at']),
      );
}

class AcademyEventsPage {
  const AcademyEventsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiAcademyEvent> items;
  final String? nextCursor;
  final bool hasMore;

  factory AcademyEventsPage.fromJson(Map<String, dynamic> j) =>
      AcademyEventsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiAcademyEvent.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class CreateEventRequest {
  const CreateEventRequest({
    required this.title,
    required this.startsAt,
    this.description,
    this.location,
    this.type,
    this.endsAt,
    this.imageUrl,
  });

  final String title;
  final DateTime startsAt;
  final String? description;
  final String? location;
  final ApiEventType? type;
  final DateTime? endsAt;
  final String? imageUrl;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'title': title,
      'starts_at': startsAt.toUtc().toIso8601String(),
    };
    if (description != null) m['description'] = description;
    if (location != null) m['location'] = location;
    if (type != null) m['type'] = type!.wire;
    if (endsAt != null) m['ends_at'] = endsAt!.toUtc().toIso8601String();
    if (imageUrl != null) m['image_url'] = imageUrl;
    return m;
  }
}

class UpdateEventRequest {
  const UpdateEventRequest({
    this.title,
    this.description,
    this.location,
    this.type,
    this.startsAt,
    this.endsAt,
    this.imageUrl,
  });

  final String? title;
  final String? description;
  final String? location;
  final ApiEventType? type;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? imageUrl;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (title != null) m['title'] = title;
    if (description != null) m['description'] = description;
    if (location != null) m['location'] = location;
    if (type != null) m['type'] = type!.wire;
    if (startsAt != null) m['starts_at'] = startsAt!.toUtc().toIso8601String();
    if (endsAt != null) m['ends_at'] = endsAt!.toUtc().toIso8601String();
    if (imageUrl != null) m['image_url'] = imageUrl;
    return m;
  }
}

/// Repositório remoto do contexto AcademyEvent.
///
/// Endpoints: `GET/POST /v1/academies/{id}/events` +
/// `PATCH/DELETE /v1/academies/{id}/events/{eventId}`.
/// Eventos de academia são exibidos no calendário do portal do aluno
/// e na seção de avisos do admin.
class AcademyEventsRemoteRepo {
  AcademyEventsRemoteRepo(this._api);

  final TatamiClient _api;

  /// `GET /v1/academies/{academyId}/events`
  ///
  /// Lista eventos da academia, paginados por cursor. Ordenados por
  /// `starts_at` ascendente (próximos primeiro) por padrão.
  Future<AcademyEventsPage> listEvents(
    String academyId, {
    int limit = 50,
    int? offset,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (offset != null) params['offset'] = offset;
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/events',
      queryParameters: params,
    );
    return AcademyEventsPage.fromJson(json);
  }

  /// `POST /v1/academies/{academyId}/events`
  ///
  /// Cria um novo evento. Idempotente via Idempotency-Key.
  Future<ApiAcademyEvent> createEvent(
    String academyId,
    CreateEventRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/events',
      data: req.toJson(),
      key: key,
    );
    return ApiAcademyEvent.fromJson(json);
  }

  /// `PATCH /v1/academies/{academyId}/events/{eventId}`
  ///
  /// Atualização parcial. Campos null em [req] não são enviados.
  Future<ApiAcademyEvent> updateEvent(
    String academyId,
    String eventId,
    UpdateEventRequest req,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/events/$eventId',
      data: req.toJson(),
    );
    return ApiAcademyEvent.fromJson(json);
  }

  /// `DELETE /v1/academies/{academyId}/events/{eventId}`
  ///
  /// Remove o evento permanentemente.
  Future<void> deleteEvent(String academyId, String eventId) async {
    await _api.delete('/v1/academies/$academyId/events/$eventId');
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
