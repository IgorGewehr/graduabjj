import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

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

  factory Achievement.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Achievement(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      type: AchievementTypeExtension.fromString(data['type'] ?? 'milestone'),
      title: data['title'] ?? '',
      description: data['description'],
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fromBelt: data['fromBelt'],
      toBelt: data['toBelt'],
      fromStripes: data['fromStripes'],
      toStripes: data['toStripes'],
      competitionId: data['competitionId'],
      competitionName: data['competitionName'],
      position: data['position'] != null
          ? CompetitionPositionExtension.fromString(data['position'])
          : null,
      milestone: data['milestone'],
      photoUrl: data['photoUrl'],
      isPublic: data['isPublic'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'],
    );
  }

  // Helper: Get year from date
  int get year => date.year;
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
class AchievementService {
  final String academyId;
  late final Collections _collections;

  AchievementService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _achievementsRef => _collections.achievements;

  // ============================================
  // Get Achievements by Student
  // ============================================
  Future<List<Achievement>> getByStudent(String studentId) async {
    final query = await _achievementsRef
        .where('studentId', isEqualTo: studentId)
        .get();

    var achievements = query.docs.map((doc) => Achievement.fromFirestore(doc)).toList();
    achievements.sort((a, b) => b.date.compareTo(a.date));
    return achievements;
  }

  // ============================================
  // Get Achievement by ID
  // ============================================
  Future<Achievement?> getById(String id) async {
    final doc = await _collections.achievement(id).get();
    if (!doc.exists) return null;
    return Achievement.fromFirestore(doc);
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
  // ============================================
  Future<List<Achievement>> getRecent({int limit = 10}) async {
    final snapshot = await _achievementsRef.get();
    var achievements = snapshot.docs.map((doc) => Achievement.fromFirestore(doc)).toList();
    achievements.sort((a, b) => b.date.compareTo(a.date));
    if (achievements.length > limit) {
      achievements = achievements.sublist(0, limit);
    }
    return achievements;
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
  }) async {
    final docRef = await _achievementsRef.add({
      'studentId': studentId,
      'studentName': studentName,
      'type': type.value,
      'title': title,
      'description': description,
      'date': Timestamp.fromDate(date ?? DateTime.now()),
      'fromBelt': fromBelt,
      'toBelt': toBelt,
      'fromStripes': fromStripes,
      'toStripes': toStripes,
      'competitionId': competitionId,
      'competitionName': competitionName,
      'position': position?.value,
      'milestone': milestone,
      'photoUrl': photoUrl,
      'isPublic': isPublic,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    });

    final doc = await docRef.get();
    return Achievement.fromFirestore(doc);
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
  // ============================================
  Future<Achievement> update(String id, Map<String, dynamic> data) async {
    await _collections.achievement(id).update(data);
    final updated = await getById(id);
    return updated!;
  }

  // ============================================
  // Delete Achievement
  // ============================================
  Future<void> delete(String id) async {
    await _collections.achievement(id).delete();
  }

  // ============================================
  // Toggle Public Visibility
  // ============================================
  Future<Achievement> togglePublic(String id) async {
    final achievement = await getById(id);
    if (achievement == null) throw Exception('Conquista não encontrada');

    return update(id, {'isPublic': !achievement.isPublic});
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
