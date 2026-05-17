import 'dart:convert';

/// How long a rotating QR token stays valid after it was issued.
///
/// O admin (lib/screens/admin/qr_session_screen.dart) regenera o payload em
/// torno da metade desse intervalo para que os alunos sempre tenham um token
/// fresco. Pós-Fase 1, o token Tatami signed (`<b64>.<sig>`) é o único formato
/// real consumido pelo scanner; o legacy `QrPayload` (JSON cru) sobrevive
/// apenas para testes e como placeholder UI antes do primeiro token Tatami
/// chegar.
const Duration kQrTokenTtl = Duration(seconds: 60);

/// Parsed payload from a QR code legacy (JSON cru `{v,a,c,t}`).
///
/// Formato (JSON):
/// ```
/// { "v": 1, "a": "<academyId>", "c": "<classId>", "t": <issuedAt seconds> }
/// ```
/// `t` é o Unix timestamp em segundos. Mantido só para o teste de
/// round-trip e como placeholder do widget QR enquanto o token Tatami
/// signed não chegou. Não é mais consumido pelo scanner real
/// (lib/screens/portal/qr_scan_screen.dart só aceita o formato
/// `<b64>.<sig>` da Tatami).
class QrPayload {
  final int version;
  final String academyId;
  final String classId;
  final int issuedAtSeconds;

  const QrPayload({
    required this.version,
    required this.academyId,
    required this.classId,
    required this.issuedAtSeconds,
  });

  /// Convenience constructor that stamps the payload with the current time.
  factory QrPayload.now({
    required String academyId,
    required String classId,
  }) {
    return QrPayload(
      version: 1,
      academyId: academyId,
      classId: classId,
      issuedAtSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Encodes the payload as the compact JSON string written to the QR.
  String encode() => jsonEncode({
        'v': version,
        'a': academyId,
        'c': classId,
        't': issuedAtSeconds,
      });

  /// Parses the payload from the QR string. Throws [FormatException] on bad input.
  factory QrPayload.parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('QR vazio');
    }

    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        throw const FormatException('QR invalido');
      }
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const FormatException('QR invalido');
    }

    final version = data['v'];
    final academyId = data['a'];
    final classId = data['c'];
    final issuedAt = data['t'];

    if (version is! int || version != 1) {
      throw const FormatException('Versao do QR nao suportada');
    }
    if (academyId is! String || academyId.isEmpty) {
      throw const FormatException('QR sem academia');
    }
    if (classId is! String || classId.isEmpty) {
      throw const FormatException('QR sem turma');
    }
    if (issuedAt is! int || issuedAt <= 0) {
      throw const FormatException('QR sem timestamp');
    }

    return QrPayload(
      version: version,
      academyId: academyId,
      classId: classId,
      issuedAtSeconds: issuedAt,
    );
  }
}

/// Resultado de um scan QR — usado pelo widget de confirmação do scanner
/// (lib/screens/portal/qr_scan_screen.dart) e construído a partir do retorno
/// de `attendanceRepo.selfCheckin` (Tatami).
class QrAttendanceResult {
  final String classId;
  final String className;
  final String studentId;
  final String studentName;
  final DateTime markedAt;

  const QrAttendanceResult({
    required this.classId,
    required this.className,
    required this.studentId,
    required this.studentName,
    required this.markedAt,
  });
}

/// Erro friendly emitido pelo scanner quando o QR não passa por validação
/// local (formato inválido) ou pelo BE (assinatura, TTL, turma, roster).
/// A UI exibe `.message` direto, mantenha humano-legível.
class QrAttendanceException implements Exception {
  final String message;
  const QrAttendanceException(this.message);

  @override
  String toString() => message;
}
