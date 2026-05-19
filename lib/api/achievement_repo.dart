import 'tatami_client.dart';

// ignore_for_file: constant_identifier_names

/// Tipo de conquista — discriminador wire, casado 1:1 com o backend.
enum ApiAchievementType {
  graduation,
  stripe,
  competition,
  milestone,
}

extension ApiAchievementTypeX on ApiAchievementType {
  String get wire => name;
  static ApiAchievementType fromWire(String? value) {
    if (value == null) return ApiAchievementType.milestone;
    for (final t in ApiAchievementType.values) {
      if (t.name == value) return t;
    }
    return ApiAchievementType.milestone;
  }
}

/// Conquista desbloqueada de um aluno.
///
/// Campos opcionais dependem do tipo:
///   - graduation/stripe → fromBelt/toBelt/fromStripes/toStripes
///   - competition → competitionId, position
///   - milestone → milestoneKey
class ApiAchievement {
  const ApiAchievement({
    required this.id,
    required this.studentId,
    required this.type,
    required this.unlockedAt,
    this.fromBelt,
    this.toBelt,
    this.fromStripes,
    this.toStripes,
    this.competitionId,
    this.position,
    this.milestoneKey,
    this.payload,
  });

  final String id;
  final String studentId;
  final ApiAchievementType type;
  final DateTime unlockedAt;
  final String? fromBelt;
  final String? toBelt;
  final int? fromStripes;
  final int? toStripes;
  final String? competitionId;
  final String? position;
  final String? milestoneKey;
  final Map<String, dynamic>? payload;

  factory ApiAchievement.fromJson(Map<String, dynamic> j) => ApiAchievement(
        id: j['id'] as String,
        studentId: j['student_id'] as String,
        type: ApiAchievementTypeX.fromWire(j['type'] as String?),
        unlockedAt: _parseDate(j['unlocked_at']) ?? DateTime.now(),
        fromBelt: j['from_belt'] as String?,
        toBelt: j['to_belt'] as String?,
        fromStripes: (j['from_stripes'] as num?)?.toInt(),
        toStripes: (j['to_stripes'] as num?)?.toInt(),
        competitionId: j['competition_id'] as String?,
        position: j['position'] as String?,
        milestoneKey: j['milestone_key'] as String?,
        payload: j['payload'] is Map<String, dynamic>
            ? j['payload'] as Map<String, dynamic>
            : null,
      );
}

class AchievementsPage {
  const AchievementsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiAchievement> items;
  final String? nextCursor;
  final bool hasMore;

  factory AchievementsPage.fromJson(Map<String, dynamic> j) => AchievementsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiAchievement.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

/// Repositório remoto do contexto Achievement.
///
/// As conquistas vivem no bounded context de Competition (os handlers Go
/// estão em `internal/competition/interfaces/`), mas são consultadas
/// pela rota de estudante:
///   `GET /v1/academies/{academyId}/students/{studentId}/achievements`
///
/// Somente leitura — conquistas são criadas server-side como efeito
/// colateral de graduações, resultados de competição e marcos de presença.
class AchievementRemoteRepo {
  AchievementRemoteRepo(this._api);

  final TatamiClient _api;

  /// `GET /v1/academies/{academyId}/students/{studentId}/achievements`
  ///
  /// Retorna a timeline de conquistas paginada por cursor.
  /// Passar [limit] e [cursor] para navegar páginas subsequentes.
  Future<AchievementsPage> getByStudent(
    String academyId,
    String studentId, {
    int limit = 20,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId/achievements',
      queryParameters: params,
    );
    return AchievementsPage.fromJson(json);
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
