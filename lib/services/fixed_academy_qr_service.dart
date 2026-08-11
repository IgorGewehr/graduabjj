import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';

import 'fns.dart';
import 'qr_attendance_service.dart';

/// Permanent, printable academy QR. It intentionally contains no class or
/// date; both are resolved by Cloud Functions at scan time.
class FixedAcademyQrPayload {
  static const int currentVersion = 2;

  final String academyId;
  final String code;

  const FixedAcademyQrPayload({required this.academyId, required this.code});

  String encode() => jsonEncode({
    'v': currentVersion,
    'k': 'academy_checkin',
    'a': academyId,
    'c': code,
  });

  static FixedAcademyQrPayload? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map ||
          decoded['v'] != currentVersion ||
          decoded['k'] != 'academy_checkin' ||
          decoded['a'] is! String ||
          decoded['c'] is! String) {
        return null;
      }
      final academyId = (decoded['a'] as String).trim();
      final code = (decoded['c'] as String).trim();
      if (academyId.isEmpty || code.length < 16) return null;
      return FixedAcademyQrPayload(academyId: academyId, code: code);
    } catch (_) {
      return null;
    }
  }
}

class FixedAcademyQrData {
  final String academyId;
  final String academyName;
  final FixedAcademyQrPayload payload;

  const FixedAcademyQrData({
    required this.academyId,
    required this.academyName,
    required this.payload,
  });

  factory FixedAcademyQrData.fromMap(Map<String, dynamic> data) {
    final academyId = (data['academyId'] ?? '').toString();
    return FixedAcademyQrData(
      academyId: academyId,
      academyName: (data['academyName'] ?? 'Academia').toString(),
      payload: FixedAcademyQrPayload(
        academyId: academyId,
        code: (data['code'] ?? '').toString(),
      ),
    );
  }
}

class FixedAcademyQrClass {
  final String id;
  final String name;
  final String sport;
  final String startTime;
  final String endTime;

  const FixedAcademyQrClass({
    required this.id,
    required this.name,
    required this.sport,
    required this.startTime,
    required this.endTime,
  });

  factory FixedAcademyQrClass.fromMap(Map<String, dynamic> data) {
    return FixedAcademyQrClass(
      id: (data['id'] ?? '').toString(),
      name: (data['name'] ?? 'Turma').toString(),
      sport: (data['sport'] ?? 'bjj').toString(),
      startTime: (data['startTime'] ?? '').toString(),
      endTime: (data['endTime'] ?? '').toString(),
    );
  }
}

class FixedAcademyQrSession {
  final String academyId;
  final String academyName;
  final List<FixedAcademyQrClass> classes;

  const FixedAcademyQrSession({
    required this.academyId,
    required this.academyName,
    required this.classes,
  });

  factory FixedAcademyQrSession.fromMap(Map<String, dynamic> data) {
    final rawClasses = data['classes'];
    return FixedAcademyQrSession(
      academyId: (data['academyId'] ?? '').toString(),
      academyName: (data['academyName'] ?? 'Academia').toString(),
      classes: rawClasses is List
          ? rawClasses
                .whereType<Map>()
                .map(
                  (item) => FixedAcademyQrClass.fromMap(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class FixedAcademyQrException implements Exception {
  final String message;
  const FixedAcademyQrException(this.message);

  @override
  String toString() => message;
}

class FixedAcademyQrService {
  final CallableClient _functions;

  FixedAcademyQrService({CallableClient? functions})
    : _functions = functions ?? Fns.functions;

  Future<FixedAcademyQrData> getOrCreate(String academyId) async {
    final data = await _call('getOrCreateFixedAcademyQr', {
      'academyId': academyId,
    });
    return FixedAcademyQrData.fromMap(data);
  }

  Future<FixedAcademyQrSession> resolve(FixedAcademyQrPayload payload) async {
    final data = await _call('resolveFixedAcademyQr', {
      'academyId': payload.academyId,
      'code': payload.code,
    });
    return FixedAcademyQrSession.fromMap(data);
  }

  Future<QrAttendanceResult> checkIn({
    required FixedAcademyQrPayload payload,
    required String classId,
  }) async {
    final data = await _call('checkInWithFixedAcademyQr', {
      'academyId': payload.academyId,
      'code': payload.code,
      'classId': classId,
    });
    return QrAttendanceResult(
      classId: (data['classId'] ?? '').toString(),
      className: (data['className'] ?? 'Turma').toString(),
      studentId: (data['studentId'] ?? '').toString(),
      studentName: (data['studentName'] ?? 'Aluno').toString(),
      markedAt: DateTime.parse(data['markedAt'].toString()).toLocal(),
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> parameters,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call(parameters);
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw FixedAcademyQrException(
        error.message ?? 'Nao foi possivel validar o QR.',
      );
    } on FnsException catch (error) {
      throw FixedAcademyQrException(error.message);
    } on FixedAcademyQrException {
      rethrow;
    } catch (_) {
      throw const FixedAcademyQrException(
        'Nao foi possivel validar o QR. Tente novamente.',
      );
    }
  }
}
