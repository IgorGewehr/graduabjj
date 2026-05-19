// DTOs do contexto Attendance, alinhados 1:1 com api/openapi/attendance.yaml
// (incluindo a extensão do PR 5 — backend-signed HMAC QR tokens para
// self check-in, segurança crítica: o FE não gera mais o token).

// Enum value `not_in_class` casa com wire format do OpenAPI.
// ignore_for_file: constant_identifier_names

enum ApiAttendanceItemStatus { recorded, duplicate, not_in_class, error }

extension ApiAttendanceItemStatusX on ApiAttendanceItemStatus {
  String get wire => name;
  static ApiAttendanceItemStatus fromWire(String? value) {
    for (final s in ApiAttendanceItemStatus.values) {
      if (s.name == value) return s;
    }
    return ApiAttendanceItemStatus.error;
  }
}

class ApiAttendance {
  const ApiAttendance({
    required this.id,
    required this.academyId,
    required this.studentId,
    required this.classId,
    required this.date,
    required this.verifiedByUid,
    required this.weight,
    this.createdAt,
  });

  final String id;
  final String academyId;
  final String studentId;
  final String classId;
  final DateTime date;
  final String verifiedByUid;

  /// Snapshot do peso (multiplier) da turma no momento do check-in. Backend
  /// usa esse snapshot — não o weight atual da classe — para evitar que
  /// reweighing retroativo afete contadores históricos.
  final String weight;
  final DateTime? createdAt;

  factory ApiAttendance.fromJson(Map<String, dynamic> j) => ApiAttendance(
        id: j['id'] as String,
        academyId: j['academy_id'] as String,
        studentId: j['student_id'] as String,
        classId: j['class_id'] as String,
        date: _parseDate(j['date']) ?? DateTime.now(),
        verifiedByUid: j['verified_by_uid'] as String,
        weight: j['weight'] as String? ?? '1.000',
        createdAt: _parseDate(j['created_at']),
      );
}

class AttendancePage {
  const AttendancePage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiAttendance> items;
  final String? nextCursor;
  final bool hasMore;

  factory AttendancePage.fromJson(Map<String, dynamic> j) => AttendancePage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiAttendance.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class AttendanceFilter {
  const AttendanceFilter({
    this.studentId,
    this.classId,
    this.dateFrom,
    this.dateTo,
    this.limit = 50,
    this.cursor,
  });

  final String? studentId;
  final String? classId;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int limit;
  final String? cursor;

  Map<String, dynamic> toQueryParameters() {
    final m = <String, dynamic>{'limit': limit};
    // Backend usa camelCase nos query params (studentId, classId, dateFrom,
    // dateTo) — vide handlers.go:267,275,283,291. Não snake como nos bodies.
    if (studentId != null) m['studentId'] = studentId;
    if (classId != null) m['classId'] = classId;
    if (dateFrom != null) m['dateFrom'] = _formatDate(dateFrom!);
    if (dateTo != null) m['dateTo'] = _formatDate(dateTo!);
    if (cursor != null) m['cursor'] = cursor;
    return m;
  }
}

/// Uma linha do bulk staff check-in.
class AttendanceCheckin {
  const AttendanceCheckin({
    required this.studentId,
    required this.classId,
    required this.date,
  });

  final String studentId;
  final String classId;
  final DateTime date;

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'class_id': classId,
        'date': _formatDate(date),
      };
}

class RecordAttendanceRequest {
  const RecordAttendanceRequest({required this.items});

  final List<AttendanceCheckin> items;

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
      };
}

class AttendanceItemResult {
  const AttendanceItemResult({
    required this.status,
    this.attendance,
    this.error,
  });

  final ApiAttendanceItemStatus status;
  final ApiAttendance? attendance;
  final String? error;

  bool get isRecorded => status == ApiAttendanceItemStatus.recorded;
  bool get isDuplicate => status == ApiAttendanceItemStatus.duplicate;

  factory AttendanceItemResult.fromJson(Map<String, dynamic> j) =>
      AttendanceItemResult(
        status: ApiAttendanceItemStatusX.fromWire(j['status'] as String?),
        attendance: j['attendance'] is Map<String, dynamic>
            ? ApiAttendance.fromJson(j['attendance'] as Map<String, dynamic>)
            : null,
        error: j['error'] as String?,
      );
}

class RecordAttendanceResponse {
  const RecordAttendanceResponse({
    required this.results,
    this.promotionEligibleStudentIds = const [],
  });

  final List<AttendanceItemResult> results;

  /// Alunos que cruzaram o threshold de auto-graduação como resultado
  /// deste bulk. Notificações já são enfileiradas via outbox no BE.
  final List<String> promotionEligibleStudentIds;

  int get recordedCount =>
      results.where((r) => r.isRecorded).length;
  int get duplicateCount =>
      results.where((r) => r.isDuplicate).length;

  factory RecordAttendanceResponse.fromJson(Map<String, dynamic> j) =>
      RecordAttendanceResponse(
        results: (j['results'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AttendanceItemResult.fromJson)
            .toList(),
        promotionEligibleStudentIds:
            (j['promotion_eligible_student_ids'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                const [],
      );
}

/// Payload para marcar/desmarcar presença individual de um aluno.
/// Usado nos endpoints:
///   POST   /v1/academies/{id}/students/{sid}/attendance
///   DELETE /v1/academies/{id}/students/{sid}/attendance  (mesmo body)
class AttendanceSingleRequest {
  const AttendanceSingleRequest({
    required this.classId,
    required this.date,
  });

  final String classId;
  final DateTime date;

  Map<String, dynamic> toJson() => {
        'class_id': classId,
        'date': _formatDate(date),
      };
}

/// Self check-in pelo aluno via QR scan.
///
/// Pós PR 5: o [qrToken] é exigido no fluxo correto. Para builds antigos do
/// FE ainda há o legacy path (só class_id), mas o backend manterá esse path
/// só até a transição completa.
class SelfCheckinRequest {
  const SelfCheckinRequest({
    required this.classId,
    this.qrToken,
    this.date,
  });

  final String classId;
  final String? qrToken;
  final DateTime? date;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'class_id': classId};
    if (qrToken != null) m['qr_token'] = qrToken;
    if (date != null) m['date'] = _formatDate(date!);
    return m;
  }
}

/// Token QR assinado pelo backend (HMAC-SHA256, TTL 60s).
///
/// Wire format: `<base64url(payload)>.<base64url(signature)>` onde payload
/// é `{a, c, exp, jti}`. Cliente RENDERIZA o token cru no QR — não tenta
/// parsear. O backend assina e verifica.
class ApiClassQrToken {
  const ApiClassQrToken({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;

  /// True se o token ainda está dentro do TTL. Útil para evitar render de
  /// QR sem efeito caso o request tenha demorado.
  bool get isFresh => DateTime.now().isBefore(expiresAt);

  /// Quantos segundos faltam até expirar (≥0).
  int get secondsRemaining {
    final d = expiresAt.difference(DateTime.now()).inSeconds;
    return d < 0 ? 0 : d;
  }

  factory ApiClassQrToken.fromJson(Map<String, dynamic> j) => ApiClassQrToken(
        token: j['token'] as String,
        expiresAt: _parseDate(j['expires_at']) ?? DateTime.now(),
      );
}

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
