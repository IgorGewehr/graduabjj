import 'dto/attendance_dto.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Attendance.
///
/// Cobre o fluxo completo de presença: bulk staff check-in, self check-in
/// QR-driven (com token assinado pelo backend desde o PR 5), delete e
/// emissão de QR pelo terminal da academia.
///
/// O auto-graduação é SERVER-side via worker do outbox — o FE só recebe a
/// notificação. RecordAttendanceResponse.promotionEligibleStudentIds dá
/// uma sinalização imediata pós-bulk para feedback visual ("aluno X cruzou
/// o limiar e foi promovido"), mas a fonte de verdade é o backend.
class AttendanceRemoteRepo {
  AttendanceRemoteRepo(this._api);

  final TatamiClient _api;

  /// `GET /v1/academies/{id}/attendance` — lista com filtros.
  /// IMPORTANTE: o backend usa camelCase nos query params (studentId,
  /// classId, dateFrom, dateTo) — diferente do resto dos endpoints. Isso
  /// está modelado em AttendanceFilter.toQueryParameters().
  Future<AttendancePage> list(
    String academyId, {
    AttendanceFilter filter = const AttendanceFilter(),
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/attendance',
      queryParameters: filter.toQueryParameters(),
    );
    return AttendancePage.fromJson(json);
  }

  /// `POST /v1/academies/{id}/attendance` — bulk staff check-in.
  ///
  /// O backend valida por item (turma na academia, aluno no roster, sem
  /// duplicata) e retorna um resultado por item. Duplicatas NÃO falham o
  /// batch — vêm com status='duplicate' no resultado individual.
  Future<RecordAttendanceResponse> recordBulk(
    String academyId,
    RecordAttendanceRequest req,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/attendance',
      data: req.toJson(),
    );
    return RecordAttendanceResponse.fromJson(json);
  }

  /// `POST /v1/academies/{id}/students/{sid}/attendance` — marca presença
  /// individual de um aluno em uma turma. Duplicatas retornam 409 (já
  /// presente). Admin/instructor only.
  Future<ApiAttendance> markPresent(
    String academyId,
    String studentId,
    AttendanceSingleRequest req,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/students/$studentId/attendance',
      data: req.toJson(),
    );
    return ApiAttendance.fromJson(json);
  }

  /// `DELETE /v1/academies/{id}/students/{sid}/attendance` — desmarca presença
  /// individual. Passa class_id + date como query params (o backend aceita
  /// body OU query — usamos query para compatibilidade máxima com Dio).
  /// Admin/instructor only.
  Future<void> unmarkPresent(
    String academyId,
    String studentId,
    AttendanceSingleRequest req,
  ) async {
    await _api.delete(
      '/v1/academies/$academyId/students/$studentId/attendance',
      queryParameters: req.toJson(),
    );
  }

  /// `POST /v1/academies/{id}/attendance/bulk` — bulk staff check-in with a
  /// single class + list of student IDs. Simpler contract than [recordBulk]:
  /// one class, many students, one timestamp. Duplicates are silently ignored
  /// by the backend (status='duplicate' in results).
  Future<void> bulkRecord(
    String academyId,
    String classId,
    List<String> studentIds,
  ) async {
    await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/attendance/bulk',
      data: {
        'class_id': classId,
        'student_ids': studentIds,
        'attended_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  /// `POST /v1/academies/{id}/attendance/self-checkin`.
  ///
  /// Se [SelfCheckinRequest.qrToken] estiver presente, o backend verifica
  /// a assinatura HMAC + expiry (60s). Sem o token, cai no legacy path
  /// (roster-only, sem QR) — mantido para builds antigos do app.
  ///
  /// Erros relevantes:
  ///   - 400 → QR malformado (base64 ruim, sem separador `.`)
  ///   - 401 → assinatura QR inválida OU token bound em academy/class
  ///           diferente do request
  ///   - 403 → caller não é student linked desta turma
  ///   - 409 → já tem presença pra hoje
  ///   - 410 → token expirado (TTL 60s)
  Future<ApiAttendance> selfCheckin(
    String academyId,
    SelfCheckinRequest req,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/attendance/self-checkin',
      data: req.toJson(),
    );
    return ApiAttendance.fromJson(json);
  }

  /// `DELETE /v1/academies/{id}/attendance/{attendanceId}` — remove uma
  /// linha de presença. Admin/instructor only.
  Future<void> delete(String academyId, String attendanceId) async {
    await _api.delete('/v1/academies/$academyId/attendance/$attendanceId');
  }

  /// `POST /v1/academies/{id}/classes/{cid}/qr-tokens` — emite um QR
  /// assinado para self check-in. Chamado pelo terminal da academia
  /// (admin/instructor/monitor); o token tem TTL 60s.
  ///
  /// O FE renderiza o `token` retornado em um QR. O aluno escaneia e POSTa
  /// para /attendance/self-checkin com `qr_token` no body. NUNCA gere o
  /// token client-side — toda a segurança depende do BE ser o único
  /// signer.
  Future<ApiClassQrToken> issueQrToken(
    String academyId,
    String classId,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/classes/$classId/qr-tokens',
    );
    return ApiClassQrToken.fromJson(json);
  }
}
