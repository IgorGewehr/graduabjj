import 'idempotency.dart';
import 'tatami_client.dart';

// DTOs do contexto News.

class ApiNews {
  const ApiNews({
    required this.id,
    required this.academyId,
    required this.title,
    required this.body,
    this.imageUrl,
    this.isPinned = false,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String academyId;
  final String title;
  final String body;
  final String? imageUrl;
  final bool isPinned;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ApiNews.fromJson(Map<String, dynamic> j) => ApiNews(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        title: j['title'] as String,
        body: j['body'] as String? ?? j['content'] as String? ?? '',
        imageUrl: j['image_url'] as String?,
        isPinned: j['is_pinned'] as bool? ?? false,
        createdByUid: j['created_by_uid'] as String?,
        createdAt: _parseDate(j['created_at']),
        updatedAt: _parseDate(j['updated_at']),
      );
}

class NewsPage {
  const NewsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiNews> items;
  final String? nextCursor;
  final bool hasMore;

  factory NewsPage.fromJson(Map<String, dynamic> j) => NewsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiNews.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class CreateNewsRequest {
  const CreateNewsRequest({
    required this.title,
    required this.body,
    this.imageUrl,
    this.isPinned,
  });

  final String title;
  final String body;
  final String? imageUrl;
  final bool? isPinned;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'title': title, 'body': body};
    if (imageUrl != null) m['image_url'] = imageUrl;
    if (isPinned != null) m['is_pinned'] = isPinned;
    return m;
  }
}

class UpdateNewsRequest {
  const UpdateNewsRequest({
    this.title,
    this.body,
    this.imageUrl,
    this.isPinned,
  });

  final String? title;
  final String? body;
  final String? imageUrl;
  final bool? isPinned;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (title != null) m['title'] = title;
    if (body != null) m['body'] = body;
    if (imageUrl != null) m['image_url'] = imageUrl;
    if (isPinned != null) m['is_pinned'] = isPinned;
    return m;
  }
}

/// Repositório remoto do contexto News.
///
/// Endpoints: `GET/POST /v1/academies/{id}/news` +
/// `PATCH/DELETE /v1/academies/{id}/news/{newsId}`.
/// Notícias são exibidas no feed do portal do aluno e
/// na seção de comunicados do admin.
class NewsRemoteRepo {
  NewsRemoteRepo(this._api);

  final TatamiClient _api;

  /// `GET /v1/academies/{academyId}/news`
  ///
  /// Lista notícias da academia, paginadas por cursor. Ordenadas por
  /// `published_at` descendente (mais recentes primeiro) por padrão.
  Future<NewsPage> listNews(
    String academyId, {
    int limit = 50,
    int? offset,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (offset != null) params['offset'] = offset;
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/news',
      queryParameters: params,
    );
    return NewsPage.fromJson(json);
  }

  /// `POST /v1/academies/{academyId}/news`
  ///
  /// Cria uma nova notícia. Idempotente via Idempotency-Key.
  Future<ApiNews> createNews(
    String academyId,
    CreateNewsRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/news',
      data: req.toJson(),
      key: key,
    );
    return ApiNews.fromJson(json);
  }

  /// `PATCH /v1/academies/{academyId}/news/{newsId}`
  ///
  /// Atualização parcial. Campos null em [req] não são enviados.
  Future<ApiNews> updateNews(
    String academyId,
    String newsId,
    UpdateNewsRequest req,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/news/$newsId',
      data: req.toJson(),
    );
    return ApiNews.fromJson(json);
  }

  /// `DELETE /v1/academies/{academyId}/news/{newsId}`
  ///
  /// Remove a notícia permanentemente.
  Future<void> deleteNews(String academyId, String newsId) async {
    await _api.delete('/v1/academies/$academyId/news/$newsId');
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
