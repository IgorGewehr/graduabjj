// DTOs do contexto Competition, alinhados 1:1 com api/openapi/competition.yaml.
// Inclui Competition + Enrollment + Result + Photo (com upload 2-step) +
// Achievement (achievements do aluno são por contexto Competition).

// ignore_for_file: constant_identifier_names

enum ApiCompetitionStatus { upcoming, ongoing, completed }

extension ApiCompetitionStatusX on ApiCompetitionStatus {
  String get wire => name;
  static ApiCompetitionStatus fromWire(String? value) {
    for (final s in ApiCompetitionStatus.values) {
      if (s.name == value) return s;
    }
    return ApiCompetitionStatus.upcoming;
  }
}

enum ApiTransportStatus { not_planned, planned, departed, arrived }

extension ApiTransportStatusX on ApiTransportStatus {
  String get wire => name;
  static ApiTransportStatus fromWire(String? value) {
    for (final s in ApiTransportStatus.values) {
      if (s.name == value) return s;
    }
    return ApiTransportStatus.not_planned;
  }
}

enum ApiTransportPreference { need_transport, own_transport, undecided }

extension ApiTransportPreferenceX on ApiTransportPreference {
  String get wire => name;
  static ApiTransportPreference fromWire(String? value) {
    for (final p in ApiTransportPreference.values) {
      if (p.name == value) return p;
    }
    return ApiTransportPreference.undecided;
  }
}

enum ApiModality { gi, nogi }

extension ApiModalityX on ApiModality {
  String get wire => name;
  static ApiModality fromWire(String? value) {
    if (value == 'nogi') return ApiModality.nogi;
    return ApiModality.gi;
  }
}

enum ApiPosition { gold, silver, bronze, participant }

extension ApiPositionX on ApiPosition {
  String get wire => name;
  static ApiPosition fromWire(String? value) {
    for (final p in ApiPosition.values) {
      if (p.name == value) return p;
    }
    return ApiPosition.participant;
  }
}

enum ApiAchievementType { graduation, stripe, competition, milestone }

extension ApiAchievementTypeX on ApiAchievementType {
  String get wire => name;
  static ApiAchievementType fromWire(String? value) {
    for (final t in ApiAchievementType.values) {
      if (t.name == value) return t;
    }
    return ApiAchievementType.milestone;
  }
}

class ApiCompetition {
  const ApiCompetition({
    required this.id,
    required this.academyId,
    required this.name,
    required this.date,
    required this.status,
    this.location,
    this.description,
    this.registrationDeadline,
    this.transportCapacity,
    this.transportStatus,
    this.teamPosition,
    this.teamNotes,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String academyId;
  final String name;
  final DateTime date;
  final ApiCompetitionStatus status;
  final String? location;
  final String? description;
  final DateTime? registrationDeadline;
  final int? transportCapacity;
  final ApiTransportStatus? transportStatus;
  final int? teamPosition;
  final String? teamNotes;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasTransport => transportCapacity != null && transportCapacity! > 0;

  factory ApiCompetition.fromJson(Map<String, dynamic> j) => ApiCompetition(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        name: j['name'] as String,
        date: _parseDate(j['date']) ?? DateTime.now(),
        status: ApiCompetitionStatusX.fromWire(j['status'] as String?),
        location: j['location'] as String?,
        description: j['description'] as String?,
        registrationDeadline: _parseDate(j['registration_deadline']),
        transportCapacity: (j['transport_capacity'] as num?)?.toInt(),
        transportStatus: j['transport_status'] == null
            ? null
            : ApiTransportStatusX.fromWire(j['transport_status'] as String?),
        teamPosition: (j['team_position'] as num?)?.toInt(),
        teamNotes: j['team_notes'] as String?,
        createdByUid: j['created_by_uid'] as String?,
        createdAt: _parseDate(j['created_at']),
        updatedAt: _parseDate(j['updated_at']),
      );
}

class CompetitionsPage {
  const CompetitionsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiCompetition> items;
  final String? nextCursor;
  final bool hasMore;

  factory CompetitionsPage.fromJson(Map<String, dynamic> j) => CompetitionsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiCompetition.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class CreateCompetitionRequest {
  const CreateCompetitionRequest({
    required this.name,
    required this.date,
    this.location,
    this.description,
    this.registrationDeadline,
    this.transportCapacity,
    this.transportStatus,
    this.teamNotes,
  });

  final String name;
  final DateTime date;
  final String? location;
  final String? description;
  final DateTime? registrationDeadline;
  final int? transportCapacity;
  final ApiTransportStatus? transportStatus;
  final String? teamNotes;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'name': name,
      'date': date.toUtc().toIso8601String(),
    };
    if (location != null) m['location'] = location;
    if (description != null) m['description'] = description;
    if (registrationDeadline != null) {
      m['registration_deadline'] = registrationDeadline!.toUtc().toIso8601String();
    }
    if (transportCapacity != null) m['transport_capacity'] = transportCapacity;
    if (transportStatus != null) m['transport_status'] = transportStatus!.wire;
    if (teamNotes != null) m['team_notes'] = teamNotes;
    return m;
  }
}

class UpdateCompetitionRequest {
  const UpdateCompetitionRequest({
    this.name,
    this.date,
    this.location,
    this.description,
    this.status,
    this.registrationDeadline,
    this.transportCapacity,
    this.transportStatus,
    this.teamPosition,
    this.teamNotes,
  });

  final String? name;
  final DateTime? date;
  final String? location;
  final String? description;
  final ApiCompetitionStatus? status;
  final DateTime? registrationDeadline;
  final int? transportCapacity;
  final ApiTransportStatus? transportStatus;
  final int? teamPosition;
  final String? teamNotes;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (name != null) m['name'] = name;
    if (date != null) m['date'] = date!.toUtc().toIso8601String();
    if (location != null) m['location'] = location;
    if (description != null) m['description'] = description;
    if (status != null) m['status'] = status!.wire;
    if (registrationDeadline != null) {
      m['registration_deadline'] = registrationDeadline!.toUtc().toIso8601String();
    }
    if (transportCapacity != null) m['transport_capacity'] = transportCapacity;
    if (transportStatus != null) m['transport_status'] = transportStatus!.wire;
    if (teamPosition != null) m['team_position'] = teamPosition;
    if (teamNotes != null) m['team_notes'] = teamNotes;
    return m;
  }
}

class ApiEnrollment {
  const ApiEnrollment({
    required this.id,
    required this.competitionId,
    required this.studentId,
    required this.modality,
    required this.enrolledAt,
    this.ageCategory,
    this.weightCategory,
    this.transportPreference,
  });

  final String id;
  final String competitionId;
  final String studentId;
  final String? ageCategory;
  final String? weightCategory;
  final ApiModality modality;
  final ApiTransportPreference? transportPreference;
  final DateTime enrolledAt;

  factory ApiEnrollment.fromJson(Map<String, dynamic> j) => ApiEnrollment(
        id: j['id'] as String,
        competitionId: j['competition_id'] as String,
        studentId: j['student_id'] as String,
        ageCategory: j['age_category'] as String?,
        weightCategory: j['weight_category'] as String?,
        modality: ApiModalityX.fromWire(j['modality'] as String?),
        transportPreference: j['transport_preference'] == null
            ? null
            : ApiTransportPreferenceX.fromWire(
                j['transport_preference'] as String?),
        enrolledAt: _parseDate(j['enrolled_at']) ?? DateTime.now(),
      );
}

class CreateEnrollmentRequest {
  const CreateEnrollmentRequest({
    required this.studentId,
    required this.modality,
    this.ageCategory,
    this.weightCategory,
    this.transportPreference,
  });

  final String studentId;
  final ApiModality modality;
  final String? ageCategory;
  final String? weightCategory;
  final ApiTransportPreference? transportPreference;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'student_id': studentId,
      'modality': modality.wire,
    };
    if (ageCategory != null) m['age_category'] = ageCategory;
    if (weightCategory != null) m['weight_category'] = weightCategory;
    if (transportPreference != null) {
      m['transport_preference'] = transportPreference!.wire;
    }
    return m;
  }
}

class EnrollmentsPage {
  const EnrollmentsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiEnrollment> items;
  final String? nextCursor;
  final bool hasMore;

  factory EnrollmentsPage.fromJson(Map<String, dynamic> j) => EnrollmentsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiEnrollment.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class ApiResult {
  const ApiResult({
    required this.id,
    required this.competitionId,
    required this.studentId,
    required this.position,
    required this.modality,
    required this.recordedAt,
    this.beltCategory,
    this.ageCategory,
    this.weightCategory,
    this.recordedByUid,
  });

  final String id;
  final String competitionId;
  final String studentId;
  final ApiPosition position;
  final String? beltCategory;
  final String? ageCategory;
  final String? weightCategory;
  final ApiModality modality;
  final String? recordedByUid;
  final DateTime recordedAt;

  factory ApiResult.fromJson(Map<String, dynamic> j) => ApiResult(
        id: j['id'] as String,
        competitionId: j['competition_id'] as String,
        studentId: j['student_id'] as String,
        position: ApiPositionX.fromWire(j['position'] as String?),
        beltCategory: j['belt_category'] as String?,
        ageCategory: j['age_category'] as String?,
        weightCategory: j['weight_category'] as String?,
        modality: ApiModalityX.fromWire(j['modality'] as String?),
        recordedByUid: j['recorded_by_uid'] as String?,
        recordedAt: _parseDate(j['recorded_at']) ?? DateTime.now(),
      );
}

class CreateResultRequest {
  const CreateResultRequest({
    required this.studentId,
    required this.position,
    required this.modality,
    this.beltCategory,
    this.ageCategory,
    this.weightCategory,
  });

  final String studentId;
  final ApiPosition position;
  final ApiModality modality;
  final String? beltCategory;
  final String? ageCategory;
  final String? weightCategory;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'student_id': studentId,
      'position': position.wire,
      'modality': modality.wire,
    };
    if (beltCategory != null) m['belt_category'] = beltCategory;
    if (ageCategory != null) m['age_category'] = ageCategory;
    if (weightCategory != null) m['weight_category'] = weightCategory;
    return m;
  }
}

class ResultsPage {
  const ResultsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiResult> items;
  final String? nextCursor;
  final bool hasMore;

  factory ResultsPage.fromJson(Map<String, dynamic> j) => ResultsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiResult.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class ApiPhoto {
  const ApiPhoto({
    required this.id,
    required this.competitionId,
    required this.url,
    required this.storagePath,
    required this.uploadedAt,
    this.studentId,
    this.caption,
    this.uploadedByUid,
  });

  final String id;
  final String competitionId;
  final String? studentId;
  final String url;
  final String storagePath;
  final String? caption;
  final String? uploadedByUid;
  final DateTime uploadedAt;

  factory ApiPhoto.fromJson(Map<String, dynamic> j) => ApiPhoto(
        id: j['id'] as String,
        competitionId: j['competition_id'] as String,
        studentId: j['student_id'] as String?,
        url: j['url'] as String,
        storagePath: j['storage_path'] as String,
        caption: j['caption'] as String?,
        uploadedByUid: j['uploaded_by_uid'] as String?,
        uploadedAt: _parseDate(j['uploaded_at']) ?? DateTime.now(),
      );
}

class PhotosPage {
  const PhotosPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiPhoto> items;
  final String? nextCursor;
  final bool hasMore;

  factory PhotosPage.fromJson(Map<String, dynamic> j) => PhotosPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiPhoto.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class CreatePhotoUploadUrlRequest {
  const CreatePhotoUploadUrlRequest({
    required this.filename,
    required this.contentType,
    this.studentId,
  });

  final String filename;
  final String contentType;
  final String? studentId;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'filename': filename,
      'content_type': contentType,
    };
    if (studentId != null) m['student_id'] = studentId;
    return m;
  }
}

class ApiPhotoUploadUrl {
  const ApiPhotoUploadUrl({
    required this.uploadUrl,
    required this.storagePath,
    required this.expiresAt,
  });

  final String uploadUrl;
  final String storagePath;
  final DateTime expiresAt;

  factory ApiPhotoUploadUrl.fromJson(Map<String, dynamic> j) =>
      ApiPhotoUploadUrl(
        uploadUrl: j['upload_url'] as String,
        storagePath: j['storage_path'] as String,
        expiresAt: _parseDate(j['expires_at']) ?? DateTime.now(),
      );
}

class CreatePhotoRequest {
  const CreatePhotoRequest({
    required this.url,
    required this.storagePath,
    this.studentId,
    this.caption,
  });

  final String url;
  final String storagePath;
  final String? studentId;
  final String? caption;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'url': url, 'storage_path': storagePath};
    if (studentId != null) m['student_id'] = studentId;
    if (caption != null) m['caption'] = caption;
    return m;
  }
}

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
  final String? fromBelt;
  final String? toBelt;
  final int? fromStripes;
  final int? toStripes;
  final String? competitionId;
  final ApiPosition? position;
  final String? milestoneKey;
  final Map<String, dynamic>? payload;
  final DateTime unlockedAt;

  factory ApiAchievement.fromJson(Map<String, dynamic> j) => ApiAchievement(
        id: j['id'] as String,
        studentId: j['student_id'] as String,
        type: ApiAchievementTypeX.fromWire(j['type'] as String?),
        fromBelt: j['from_belt'] as String?,
        toBelt: j['to_belt'] as String?,
        fromStripes: (j['from_stripes'] as num?)?.toInt(),
        toStripes: (j['to_stripes'] as num?)?.toInt(),
        competitionId: j['competition_id'] as String?,
        position: j['position'] == null
            ? null
            : ApiPositionX.fromWire(j['position'] as String?),
        milestoneKey: j['milestone_key'] as String?,
        payload: j['payload'] is Map<String, dynamic>
            ? j['payload'] as Map<String, dynamic>
            : null,
        unlockedAt: _parseDate(j['unlocked_at']) ?? DateTime.now(),
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

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
