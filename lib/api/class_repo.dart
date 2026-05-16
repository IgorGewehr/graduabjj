import 'dto/class_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Class.
///
/// Endpoints: `/v1/academies/{academyId}/classes*`. CRUD de turmas +
/// gerenciamento de roster (alunos da turma).
class ClassRemoteRepo {
  ClassRemoteRepo(this._api);

  final TatamiClient _api;

  Future<ClassesPage> list(
    String academyId, {
    int limit = 50,
    String? cursor,
    bool? isActive,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    if (isActive != null) params['is_active'] = isActive;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/classes',
      queryParameters: params,
    );
    return ClassesPage.fromJson(json);
  }

  Future<ApiClass> getById(String academyId, String classId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/classes/$classId',
    );
    return ApiClass.fromJson(json);
  }

  Future<ApiClass> create(
    String academyId,
    CreateClassRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/classes',
      data: req.toJson(),
      key: key,
    );
    return ApiClass.fromJson(json);
  }

  Future<ApiClass> update(
    String academyId,
    String classId,
    UpdateClassRequest req,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/classes/$classId',
      data: req.toJson(),
    );
    return ApiClass.fromJson(json);
  }

  Future<void> delete(String academyId, String classId) async {
    await _api.delete('/v1/academies/$academyId/classes/$classId');
  }

  /// Adiciona um aluno ao roster da turma.
  Future<void> addStudent(
    String academyId,
    String classId,
    String studentId,
  ) async {
    await _api.post<dynamic>(
      '/v1/academies/$academyId/classes/$classId/students',
      data: {'student_id': studentId},
    );
  }

  /// Remove um aluno do roster da turma (não deleta o aluno).
  Future<void> removeStudent(
    String academyId,
    String classId,
    String studentId,
  ) async {
    await _api.delete(
      '/v1/academies/$academyId/classes/$classId/students/$studentId',
    );
  }
}
