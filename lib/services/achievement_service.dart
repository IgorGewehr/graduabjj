import 'package:flutter/foundation.dart';

import '../api/achievement_repo.dart' as repo_ach;
import '../api/dto/competition_dto.dart' as api;
import '../api/tatami_client.dart';
import 'firebase_service.dart';
import 'notification_dispatcher.dart';
import 'student_service.dart';

// Mirrors the compile-time constant from api_provider.dart.
const _tatamiBaseUrl = String.fromEnvironment(
  'TATAMI_BASE_URL',
  defaultValue: 'https://tatami.tensorroot.com',
);

/// Achievement Type
enum AchievementType { graduation, stripe, competition, milestone }

extension AchievementTypeExtension on AchievementType {
  String get value {
    switch (this) {
      case AchievementType.graduation:
        return 'graduation';
      case AchievementType.stripe:
        return 'stripe';
      case AchievementType.competition:
        return 'competition';
      case AchievementType.milestone:
        return 'milestone';
    }
  }

  static AchievementType fromString(String value) {
    switch (value) {
      case 'graduation':
        return AchievementType.graduation;
      case 'stripe':
        return AchievementType.stripe;
      case 'competition':
        return AchievementType.competition;
      case 'milestone':
        return AchievementType.milestone;
      default:
        return AchievementType.milestone;
    }
  }
}

/// Competition Position
enum CompetitionPosition { gold, silver, bronze, participant }

extension CompetitionPositionExtension on CompetitionPosition {
  String get value {
    switch (this) {
      case CompetitionPosition.gold:
        return 'gold';
      case CompetitionPosition.silver:
        return 'silver';
      case CompetitionPosition.bronze:
        return 'bronze';
      case CompetitionPosition.participant:
        return 'participant';
    }
  }

  String get label {
    switch (this) {
      case CompetitionPosition.gold:
        return 'Ouro';
      case CompetitionPosition.silver:
        return 'Prata';
      case CompetitionPosition.bronze:
        return 'Bronze';
      case CompetitionPosition.participant:
        return 'Participante';
    }
  }

  static CompetitionPosition fromString(String value) {
    switch (value) {
      case 'gold':
        return CompetitionPosition.gold;
      case 'silver':
        return CompetitionPosition.silver;
      case 'bronze':
        return CompetitionPosition.bronze;
      default:
        return CompetitionPosition.participant;
    }
  }
}

/// Achievement Model
class Achievement {
  final String id;
  final String studentId;
  final String studentName;
  final AchievementType type;
  final String title;
  final String? description;
  final DateTime date;

  // Graduation fields
  final String? fromBelt;
  final String? toBelt;
  final int? fromStripes;
  final int? toStripes;

  // Competition fields
  final String? competitionId;
  final String? competitionName;
  final CompetitionPosition? position;

  // Milestone fields
  final String? milestone;

  final String? photoUrl;
  final bool isPublic;
  final DateTime createdAt;
  final String? createdBy;

  Achievement({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.type,
    required this.title,
    this.description,
    required this.date,
    this.fromBelt,
    this.toBelt,
    this.fromStripes,
    this.toStripes,
    this.competitionId,
    this.competitionName,
    this.position,
    this.milestone,
    this.photoUrl,
    this.isPublic = true,
    required this.createdAt,
    this.createdBy,
  });

  /// Sprint 7 wiring — adapter `ApiAchievement` → `Achievement` legacy.
  ///
  /// Diferenças:
  /// - `studentName` não vem na resposta (param opcional).
  /// - `title`/`description` legacy não existem na API — derivamos de
  ///   type quando possível.
  /// - `date` legacy = `unlocked_at` API.
  /// - `photoUrl`/`isPublic`/`createdBy` não existem na API.
  factory Achievement.fromApi(api.ApiAchievement a, {String? studentName}) {
    final type = _typeFromApi(a.type);
    return Achievement(
      id: a.id,
      studentId: a.studentId,
      studentName: studentName ?? '',
      type: type,
      title: _derivedTitle(type, a),
      description: a.payload?['description'] as String?,
      date: a.unlockedAt,
      fromBelt: a.fromBelt,
      toBelt: a.toBelt,
      fromStripes: a.fromStripes,
      toStripes: a.toStripes,
      competitionId: a.competitionId,
      position: a.position == null ? null : _positionFromApi(a.position!),
      milestone: a.milestoneKey,
      isPublic: true,
      createdAt: a.unlockedAt,
    );
  }

  /// Adapter `repo_ach.ApiAchievement` (achievement_repo.dart) → `Achievement`.
  ///
  /// Usa o DTO retornado diretamente por `AchievementRemoteRepo.getByStudent`.
  /// Diferencia-se de `fromApi` porque `position` aqui é `String?` (wire raw)
  /// em vez de `ApiPosition?` (enum do competition_dto).
  factory Achievement.fromApiRepo(
    repo_ach.ApiAchievement a, {
    String? studentName,
  }) {
    final type = _typeFromRepoApi(a.type);
    return Achievement(
      id: a.id,
      studentId: a.studentId,
      studentName: studentName ?? '',
      type: type,
      title: _derivedTitleRepo(type, a),
      description: a.payload?['description'] as String?,
      date: a.unlockedAt,
      fromBelt: a.fromBelt,
      toBelt: a.toBelt,
      fromStripes: a.fromStripes,
      toStripes: a.toStripes,
      competitionId: a.competitionId,
      position: a.position == null
          ? null
          : CompetitionPositionExtension.fromString(a.position!),
      milestone: a.milestoneKey,
      isPublic: true,
      createdAt: a.unlockedAt,
    );
  }

  static AchievementType _typeFromRepoApi(repo_ach.ApiAchievementType t) {
    switch (t) {
      case repo_ach.ApiAchievementType.graduation:
        return AchievementType.graduation;
      case repo_ach.ApiAchievementType.stripe:
        return AchievementType.stripe;
      case repo_ach.ApiAchievementType.competition:
        return AchievementType.competition;
      case repo_ach.ApiAchievementType.milestone:
        return AchievementType.milestone;
    }
  }

  static String _derivedTitleRepo(
    AchievementType type,
    repo_ach.ApiAchievement a,
  ) {
    switch (type) {
      case AchievementType.graduation:
        if (a.fromBelt != null && a.toBelt != null) {
          return 'Graduação: faixa ${a.fromBelt} → ${a.toBelt}';
        }
        return 'Graduação';
      case AchievementType.stripe:
        if (a.toStripes != null) {
          return 'Conquistou ${a.toStripes}ª grau';
        }
        return 'Novo grau';
      case AchievementType.competition:
        return 'Competição: ${a.position ?? 'participação'}';
      case AchievementType.milestone:
        return a.milestoneKey ?? 'Marco';
    }
  }

  static AchievementType _typeFromApi(api.ApiAchievementType t) {
    switch (t) {
      case api.ApiAchievementType.graduation:
        return AchievementType.graduation;
      case api.ApiAchievementType.stripe:
        return AchievementType.stripe;
      case api.ApiAchievementType.competition:
        return AchievementType.competition;
      case api.ApiAchievementType.milestone:
        return AchievementType.milestone;
    }
  }

  static CompetitionPosition _positionFromApi(api.ApiPosition p) {
    switch (p) {
      case api.ApiPosition.gold:
        return CompetitionPosition.gold;
      case api.ApiPosition.silver:
        return CompetitionPosition.silver;
      case api.ApiPosition.bronze:
        return CompetitionPosition.bronze;
      case api.ApiPosition.participant:
        return CompetitionPosition.participant;
    }
  }

  static String _derivedTitle(AchievementType type, api.ApiAchievement a) {
    switch (type) {
      case AchievementType.graduation:
        if (a.fromBelt != null && a.toBelt != null) {
          return 'Graduação: faixa ${a.fromBelt} → ${a.toBelt}';
        }
        return 'Graduação';
      case AchievementType.stripe:
        if (a.toStripes != null) {
          return 'Conquistou ${a.toStripes}ª grau';
        }
        return 'Novo grau';
      case AchievementType.competition:
        return 'Competição: ${a.position?.name ?? 'participação'}';
      case AchievementType.milestone:
        return a.milestoneKey ?? 'Marco';
    }
  }

  // Helper: Get year from date
  int get year => date.year;

  // Convenience getter (for backwards compatibility)
  DateTime get awardedAt => date;
}

/// Belt Name Helper
String getBeltName(String belt) {
  const names = {
    'white': 'Branca',
    'blue': 'Azul',
    'purple': 'Roxa',
    'brown': 'Marrom',
    'black': 'Preta',
    'grey': 'Cinza',
    'grey-white': 'Cinza/Branca',
    'grey-black': 'Cinza/Preta',
    'yellow': 'Amarela',
    'yellow-white': 'Amarela/Branca',
    'yellow-black': 'Amarela/Preta',
    'orange': 'Laranja',
    'orange-white': 'Laranja/Branca',
    'orange-black': 'Laranja/Preta',
    'green': 'Verde',
    'green-white': 'Verde/Branca',
    'green-black': 'Verde/Preta',
  };
  return names[belt] ?? belt;
}

/// Achievement Service - Multi-tenant achievement management
///
/// All Firestore operations have been replaced with HTTP calls via
/// [AchievementRemoteRepo]. Methods without a matching backend endpoint
/// are marked as no-ops with TODO comments.
class AchievementService {
  final String academyId;
  late final repo_ach.AchievementRemoteRepo _repo;
  late final NotificationDispatcher _notificationDispatcher;
  late final StudentService _studentService;

  AchievementService(this.academyId) {
    _repo = repo_ach.AchievementRemoteRepo(TatamiClient(baseUrl: _tatamiBaseUrl));
    _notificationDispatcher = NotificationDispatcher(academyId);
    _studentService = StudentService(academyId);
  }

  // ============================================
  // Get Achievements by Student
  // GET /v1/academies/{academyId}/students/{studentId}/achievements
  // Fetches all pages to return a flat list (mirrors previous Firestore behaviour).
  // ============================================
  Future<List<Achievement>> getByStudent(String studentId) async {
    final all = <Achievement>[];
    String? cursor;

    do {
      final page = await _repo.getByStudent(
        academyId,
        studentId,
        limit: 100,
        cursor: cursor,
      );
      all.addAll(page.items.map(Achievement.fromApiRepo));
      cursor = page.hasMore ? page.nextCursor : null;
    } while (cursor != null);

    all.sort((a, b) => b.date.compareTo(a.date));
    return all;
  }

  // ============================================
  // Get Achievement by ID
  // No individual GET endpoint — filter from the student list.
  // ============================================
  Future<Achievement?> getById(String id) async {
    // TODO(tatami): no GET /v1/.../achievements/{id} endpoint;
    // searching all achievements for a known student is not efficient here.
    // This method is only used internally in this service where studentId is
    // already known — callers should prefer getByStudent().
    debugPrint('[AchievementService] getById($id): no individual endpoint, returning null');
    return null;
  }

  // ============================================
  // Get Achievements by Type
  // ============================================
  Future<List<Achievement>> getByType(String studentId, AchievementType type) async {
    final achievements = await getByStudent(studentId);
    return achievements.where((a) => a.type == type).toList();
  }

  // ============================================
  // Get Graduations (graduation + stripe)
  // ============================================
  Future<List<Achievement>> getGraduations(String studentId) async {
    final achievements = await getByStudent(studentId);
    return achievements
        .where((a) => a.type == AchievementType.graduation || a.type == AchievementType.stripe)
        .toList();
  }

  // ============================================
  // Get Competitions
  // ============================================
  Future<List<Achievement>> getCompetitions(String studentId) async {
    return getByType(studentId, AchievementType.competition);
  }

  // ============================================
  // Get Milestones
  // ============================================
  Future<List<Achievement>> getMilestones(String studentId) async {
    return getByType(studentId, AchievementType.milestone);
  }

  // ============================================
  // Get Medal Count
  // ============================================
  Future<Map<String, int>> getMedalCount(String studentId) async {
    final competitions = await getCompetitions(studentId);

    final counts = {
      'gold': 0,
      'silver': 0,
      'bronze': 0,
      'total': 0,
    };

    for (final c in competitions) {
      if (c.position == CompetitionPosition.gold) counts['gold'] = counts['gold']! + 1;
      if (c.position == CompetitionPosition.silver) counts['silver'] = counts['silver']! + 1;
      if (c.position == CompetitionPosition.bronze) counts['bronze'] = counts['bronze']! + 1;
    }

    counts['total'] = counts['gold']! + counts['silver']! + counts['bronze']!;
    return counts;
  }

  // ============================================
  // Get Timeline (grouped by year)
  // ============================================
  Future<Map<int, List<Achievement>>> getTimeline(String studentId) async {
    final achievements = await getByStudent(studentId);

    final timeline = <int, List<Achievement>>{};
    for (final a in achievements) {
      if (!timeline.containsKey(a.year)) {
        timeline[a.year] = [];
      }
      timeline[a.year]!.add(a);
    }

    return timeline;
  }

  // ============================================
  // Get Recent Achievements (all students)
  // TODO(tatami): no academy-wide achievements endpoint exists.
  // Returns empty list for now.
  // ============================================
  Future<List<Achievement>> getRecent({int limit = 10}) async {
    // TODO(tatami): implement when GET /v1/academies/{id}/achievements is available
    debugPrint('[AchievementService] getRecent: no-op — no academy-wide endpoint');
    return [];
  }

  // ============================================
  // Get Achievements Count by Type
  // ============================================
  Future<Map<AchievementType, int>> getCountByType(String studentId) async {
    final achievements = await getByStudent(studentId);

    final count = {
      AchievementType.graduation: 0,
      AchievementType.stripe: 0,
      AchievementType.competition: 0,
      AchievementType.milestone: 0,
    };

    for (final a in achievements) {
      count[a.type] = count[a.type]! + 1;
    }

    return count;
  }

  // ============================================
  // Get For Student (alias)
  // ============================================
  Future<List<Achievement>> getForStudent(String studentId) async {
    return getByStudent(studentId);
  }

  // ============================================
  // Get Public Achievements
  // ============================================
  Future<List<Achievement>> getPublic(String studentId) async {
    final achievements = await getByStudent(studentId);
    return achievements.where((a) => a.isPublic).toList();
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Create Achievement
  // POST /v1/academies/{academyId}/students/{studentId}/achievements
  // ============================================
  Future<Achievement> create({
    required String studentId,
    required String studentName,
    required AchievementType type,
    required String title,
    String? description,
    DateTime? date,
    String? fromBelt,
    String? toBelt,
    int? fromStripes,
    int? toStripes,
    String? competitionId,
    String? competitionName,
    CompetitionPosition? position,
    String? milestone,
    String? photoUrl,
    bool isPublic = true,
    String? createdBy,
    bool sendNotification = true,
  }) async {
    final body = <String, dynamic>{
      'type': type.value,
      'unlocked_at': (date ?? DateTime.now()).toIso8601String(),
    };

    if (fromBelt != null) body['from_belt'] = fromBelt;
    if (toBelt != null) body['to_belt'] = toBelt;
    if (fromStripes != null) body['from_stripes'] = fromStripes;
    if (toStripes != null) body['to_stripes'] = toStripes;
    if (competitionId != null) body['competition_id'] = competitionId;
    if (position != null) body['position'] = position.value;
    if (milestone != null) body['milestone_key'] = milestone;

    // Pack extra fields that have no direct API mapping into payload.
    final payload = <String, dynamic>{};
    if (description != null) payload['description'] = description;
    if (competitionName != null) payload['competition_name'] = competitionName;
    if (photoUrl != null) payload['photo_url'] = photoUrl;
    if (createdBy != null) payload['created_by'] = createdBy;
    if (payload.isNotEmpty) body['payload'] = payload;

    final apiAchievement = await _repo.create(academyId, studentId, body);
    final achievement = Achievement.fromApiRepo(apiAchievement, studentName: studentName);

    // Send notification to student about new achievement
    if (sendNotification) {
      try {
        final student = await _studentService.getById(studentId);
        if (student != null && student.linkedUserId != null) {
          await _notificationDispatcher.notifyNewAchievement(
            userId: student.linkedUserId!,
            studentName: studentName,
            achievementTitle: title,
            studentId: studentId,
          );
        }
      } catch (e) {
        // ignore notification errors
      }
    }

    return achievement;
  }

  // ============================================
  // Create Graduation Achievement
  // ============================================
  Future<Achievement> createGraduation({
    required String studentId,
    required String studentName,
    required String fromBelt,
    required String toBelt,
    required int fromStripes,
    required int toStripes,
    String? createdBy,
  }) async {
    final title = 'Graduação para Faixa ${getBeltName(toBelt)}';
    return create(
      studentId: studentId,
      studentName: studentName,
      type: AchievementType.graduation,
      title: title,
      fromBelt: fromBelt,
      toBelt: toBelt,
      fromStripes: fromStripes,
      toStripes: toStripes,
      createdBy: createdBy,
    );
  }

  // ============================================
  // Create Competition Achievement
  // ============================================
  Future<Achievement> createCompetitionAchievement({
    required String studentId,
    required String studentName,
    required String competitionId,
    required String competitionName,
    required CompetitionPosition position,
    DateTime? date,
    String? createdBy,
  }) async {
    final title = '${position.label} - $competitionName';
    return create(
      studentId: studentId,
      studentName: studentName,
      type: AchievementType.competition,
      title: title,
      competitionId: competitionId,
      competitionName: competitionName,
      position: position,
      date: date,
      createdBy: createdBy,
    );
  }

  // ============================================
  // Create Milestone Achievement
  // ============================================
  Future<Achievement> createMilestone({
    required String studentId,
    required String studentName,
    required String milestone,
    required String title,
    String? description,
    DateTime? date,
    String? createdBy,
  }) async {
    return create(
      studentId: studentId,
      studentName: studentName,
      type: AchievementType.milestone,
      title: title,
      description: description,
      milestone: milestone,
      date: date,
      createdBy: createdBy,
    );
  }

  // ============================================
  // Create Attendance Milestone (50, 100, 200, 500, 1000)
  // ============================================
  Future<Achievement?> createAttendanceMilestone({
    required String studentId,
    required String studentName,
    required int attendanceCount,
    DateTime? milestoneDate,
    String? createdBy,
  }) async {
    const milestones = [50, 100, 200, 500, 1000];
    if (!milestones.contains(attendanceCount)) return null;

    final title = '$attendanceCount Treinos!';
    final description = 'Parabéns por completar $attendanceCount treinos!';

    return create(
      studentId: studentId,
      studentName: studentName,
      type: AchievementType.milestone,
      title: title,
      description: description,
      milestone: 'attendance_$attendanceCount',
      date: milestoneDate,
      createdBy: createdBy,
    );
  }

  // ============================================
  // Create Anniversary Milestone (1, 2, 3, 5, 10 years)
  // ============================================
  Future<Achievement?> createAnniversaryMilestone({
    required String studentId,
    required String studentName,
    required int years,
    required DateTime anniversaryDate,
    String? createdBy,
  }) async {
    const milestones = [1, 2, 3, 5, 10];
    if (!milestones.contains(years)) return null;

    final title = '$years ${years == 1 ? 'Ano' : 'Anos'} de Academia!';
    final description = 'Parabéns por $years ${years == 1 ? 'ano' : 'anos'} de dedicação!';

    return create(
      studentId: studentId,
      studentName: studentName,
      type: AchievementType.milestone,
      title: title,
      description: description,
      milestone: 'anniversary_$years',
      date: anniversaryDate,
      createdBy: createdBy,
    );
  }

  // ============================================
  // Update Achievement
  // PATCH /v1/academies/{academyId}/students/{studentId}/achievements/{id}
  //
  // The data map is forwarded as-is. Callers using legacy Firestore
  // field names (camelCase) should migrate to snake_case when possible;
  // the server ignores unknown fields.
  // ============================================
  Future<Achievement> update(
    String id,
    Map<String, dynamic> data, {
    required String studentId,
  }) async {
    final apiAchievement = await _repo.update(academyId, studentId, id, data);
    return Achievement.fromApiRepo(apiAchievement);
  }

  // ============================================
  // Delete Achievement
  // DELETE /v1/academies/{academyId}/students/{studentId}/achievements/{id}
  // ============================================
  Future<void> delete(String id, {required String studentId}) async {
    await _repo.delete(academyId, studentId, id);
  }

  // ============================================
  // Toggle Public Visibility
  // PATCH /v1/academies/{academyId}/students/{studentId}/achievements/{id}
  // ============================================
  Future<Achievement> togglePublic(String id, {required String studentId}) async {
    // 'is_public' is the snake_case wire field.
    // We don't know current value without fetching — pass toggle intent.
    // For now we optimistically use true and let the caller manage state.
    // TODO(tatami): add GET /v1/.../achievements/{id} to read current value.
    debugPrint('[AchievementService] togglePublic: fetching list to determine current value');
    final list = await getByStudent(studentId);
    final current = list.where((a) => a.id == id).firstOrNull;
    final newValue = current != null ? !current.isPublic : true;
    return update(id, {'is_public': newValue}, studentId: studentId);
  }
}

// ============================================
// Factory Function
// ============================================
AchievementService createAchievementService(String academyId) {
  return AchievementService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
AchievementService get achievementService => AchievementService(FirebaseService.academyId);
