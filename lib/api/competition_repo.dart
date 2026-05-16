import 'dto/competition_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Competition.
///
/// Cobre: competitions CRUD, enrollments (inscrições), results, photos com
/// upload 2-step (POST upload-url + HTTP PUT direto no storage + POST
/// /photos pra confirmar), achievements timeline por aluno.
///
/// NÃO inclui upload do byte em si — esse é um HTTP PUT direto na
/// signed URL retornada por createPhotoUploadUrl. Use Dio.put com onSendProgress
/// para barra de progresso.
class CompetitionRemoteRepo {
  CompetitionRemoteRepo(this._api);

  final TatamiClient _api;

  // ---------------------------------------------------------------------------
  // Competitions
  // ---------------------------------------------------------------------------

  Future<CompetitionsPage> list(
    String academyId, {
    ApiCompetitionStatus? status,
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (status != null) params['status'] = status.wire;
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions',
      queryParameters: params,
    );
    return CompetitionsPage.fromJson(json);
  }

  Future<ApiCompetition> getById(String academyId, String competitionId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions/$competitionId',
    );
    return ApiCompetition.fromJson(json);
  }

  Future<ApiCompetition> create(
    String academyId,
    CreateCompetitionRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions',
      data: req.toJson(),
      key: key,
    );
    return ApiCompetition.fromJson(json);
  }

  Future<ApiCompetition> update(
    String academyId,
    String competitionId,
    UpdateCompetitionRequest req,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions/$competitionId',
      data: req.toJson(),
    );
    return ApiCompetition.fromJson(json);
  }

  Future<void> delete(String academyId, String competitionId) async {
    await _api.delete('/v1/academies/$academyId/competitions/$competitionId');
  }

  // ---------------------------------------------------------------------------
  // Enrollments
  // ---------------------------------------------------------------------------

  Future<EnrollmentsPage> listEnrollments(
    String academyId,
    String competitionId, {
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions/$competitionId/enrollments',
      queryParameters: params,
    );
    return EnrollmentsPage.fromJson(json);
  }

  /// Inscreve aluno na competição. Backend valida transport_capacity gate
  /// quando o request preference é need_transport e capacidade já foi
  /// atingida (409 transport-capacity-reached).
  Future<ApiEnrollment> enroll(
    String academyId,
    String competitionId,
    CreateEnrollmentRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions/$competitionId/enrollments',
      data: req.toJson(),
      key: key,
    );
    return ApiEnrollment.fromJson(json);
  }

  Future<void> unenroll(
    String academyId,
    String competitionId,
    String enrollmentId,
  ) async {
    await _api.delete(
      '/v1/academies/$academyId/competitions/$competitionId/enrollments/$enrollmentId',
    );
  }

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------

  Future<ResultsPage> listResults(
    String academyId,
    String competitionId, {
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions/$competitionId/results',
      queryParameters: params,
    );
    return ResultsPage.fromJson(json);
  }

  Future<ApiResult> recordResult(
    String academyId,
    String competitionId,
    CreateResultRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions/$competitionId/results',
      data: req.toJson(),
      key: key,
    );
    return ApiResult.fromJson(json);
  }

  Future<void> deleteResult(
    String academyId,
    String competitionId,
    String resultId,
  ) async {
    await _api.delete(
      '/v1/academies/$academyId/competitions/$competitionId/results/$resultId',
    );
  }

  // ---------------------------------------------------------------------------
  // Photos (2-step upload).
  // ---------------------------------------------------------------------------

  /// Passo 1: pede uma signed URL. Caller depois faz HTTP PUT direto pra
  /// `uploadUrl` com `Content-Type` = o que mandou + o body binário.
  /// Passo 2: chame `createPhoto` echoing `storage_path` retornado aqui.
  Future<ApiPhotoUploadUrl> createPhotoUploadUrl(
    String academyId,
    String competitionId,
    CreatePhotoUploadUrlRequest req,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions/$competitionId/photos/upload-url',
      data: req.toJson(),
    );
    return ApiPhotoUploadUrl.fromJson(json);
  }

  /// Passo 2: confirma o upload chamando POST /photos com url + storage_path
  /// vindos da signed URL. Backend valida que o objeto existe no storage.
  Future<ApiPhoto> createPhoto(
    String academyId,
    String competitionId,
    CreatePhotoRequest req,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions/$competitionId/photos',
      data: req.toJson(),
    );
    return ApiPhoto.fromJson(json);
  }

  Future<PhotosPage> listPhotos(
    String academyId,
    String competitionId, {
    String? studentId,
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (studentId != null) params['student_id'] = studentId;
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/competitions/$competitionId/photos',
      queryParameters: params,
    );
    return PhotosPage.fromJson(json);
  }

  // ---------------------------------------------------------------------------
  // Achievements (vivem no contexto Competition por proximidade).
  // ---------------------------------------------------------------------------

  Future<AchievementsPage> listAchievements(
    String academyId,
    String studentId, {
    int limit = 50,
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
