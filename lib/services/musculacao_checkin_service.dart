import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';

import 'fns.dart';

import 'firebase_service.dart';

/// Payload written to the fixed musculação QR shown at the reception desk.
/// Unlike the rotating class QR, it carries no classId/timestamp — all
/// validation (mode, hours, dedup) happens server-side in `selfCheckin`, so a
/// static code is safe to print. Format: `{"v":1,"a":<academyId>,"k":"musculacao"}`.
String encodeMusculacaoQr(String academyId) =>
    jsonEncode({'v': 1, 'a': academyId, 'k': 'musculacao'});

/// Returns the academyId from a musculação QR payload, or null if [raw] is not
/// a valid musculação QR (so the scanner can ignore class QRs and garbage).
String? parseMusculacaoQrAcademy(String raw) {
  try {
    final decoded = jsonDecode(raw.trim());
    if (decoded is Map &&
        decoded['k'] == 'musculacao' &&
        decoded['a'] is String &&
        (decoded['a'] as String).isNotEmpty) {
      return decoded['a'] as String;
    }
  } catch (_) {
    // Not JSON / not ours — ignore.
  }
  return null;
}

/// Friendly error surfaced to the UI when a musculação self check-in fails.
/// Carries the human-readable message returned by the Cloud Function.
class MusculacaoCheckinException implements Exception {
  final String message;
  const MusculacaoCheckinException(this.message);

  @override
  String toString() => message;
}

/// Client wrapper around the `selfCheckin` Cloud Function. Musculação has no
/// class schedule, so the student records their own attendance through this
/// function (the attendance subcollection is not writable by students under
/// Firestore rules). All validation — membership, mode, operating hours,
/// active status and one-per-day dedup — happens server-side.
class MusculacaoCheckinService {
  final CallableClient _functions;

  MusculacaoCheckinService({CallableClient? functions})
      : _functions = functions ?? Fns.functions;

  /// Records a self check-in for the current student in [academyId] (defaults
  /// to the active academy), for [sport] (defaults server-side to
  /// 'musculacao' when omitted — total backward compat with every existing
  /// caller). Since jul/2026 the `selfCheckin` function also accepts the
  /// other schedule-less modalities (boxing/mma — see SELF_CHECKIN_SPORTS in
  /// functions/index.js), so a caller can pass e.g. `sport: 'boxing'` to
  /// check the student into that modality instead. Throws
  /// [MusculacaoCheckinException] with a user-facing message on any rejection.
  Future<void> checkIn({String? academyId, String? sport}) async {
    final id = academyId ?? FirebaseService.academyId;
    try {
      await _functions.httpsCallable('selfCheckin').call({
        'academyId': id,
        if (sport != null) 'sport': sport,
      });
    } on FirebaseFunctionsException catch (e) {
      throw MusculacaoCheckinException(
        e.message ?? 'Não foi possível registrar o check-in.',
      );
    }
  }
}
