import 'package:cloud_firestore/cloud_firestore.dart';
import 'fns.dart';

import '../core/class_occurrences.dart';
import '../models/class_booking.dart';
import 'firebase_service.dart';

/// Result of a reserve/cancel call.
class BookingActionResult {
  final BookingStatus status;

  /// 1-based position in the waitlist when [status] is waitlist, else 0.
  final int position;

  /// studentId promoted from the waitlist by a cancellation, if any.
  final String? promotedStudentId;

  const BookingActionResult({
    required this.status,
    this.position = 0,
    this.promotedStudentId,
  });
}

/// Client wrapper for the class-booking feature (A1). Capacity/waitlist
/// mutations go through Cloud Function callables (`reserveClassSlot` /
/// `cancelClassReservation`) so the `classOccurrences` counter stays
/// server-authoritative — the client only *reads* occurrences and bookings.
class ClassBookingService {
  final String academyId;
  late final Collections _collections;
  final CallableClient _functions = Fns.functions;

  ClassBookingService(this.academyId) {
    _collections = Collections.forAcademy(academyId);
  }

  // --- Mutations (server-authoritative) ------------------------------------

  /// Reserve a spot. Returns confirmed or waitlist (with [position]). [studentId]
  /// is required for staff/responsible booking on behalf of someone; for the
  /// student's own booking the callable also accepts it explicitly.
  Future<BookingActionResult> reserve({
    required String classId,
    required String date, // yyyyMMdd
    required String startTime, // HH:mm
    required String studentId,
    required int slotStartMillis, // absolute instant (device-local = academy TZ)
  }) async {
    final res = await _functions.httpsCallable('reserveClassSlot').call({
      'academyId': academyId,
      'classId': classId,
      'date': date,
      'startTime': startTime,
      'studentId': studentId,
      'slotStartMillis': slotStartMillis,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return BookingActionResult(
      status: BookingStatusX.fromString(data['status'] as String?),
      position: (data['position'] as num?)?.toInt() ?? 0,
    );
  }

  /// Cancel a reservation. Staff bypass the cancel cutoff. Returns the promoted
  /// student id when a confirmed cancellation freed a spot for the waitlist.
  Future<BookingActionResult> cancel({
    required String classId,
    required String date,
    required String startTime,
    required String studentId,
    required int slotStartMillis,
    String? occId, // exact stored occurrence id (survives schedule edits)
  }) async {
    final res = await _functions.httpsCallable('cancelClassReservation').call({
      'academyId': academyId,
      'classId': classId,
      'date': date,
      'startTime': startTime,
      'studentId': studentId,
      'slotStartMillis': slotStartMillis,
      if (occId != null) 'occId': occId,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return BookingActionResult(
      status: BookingStatus.cancelled,
      promotedStudentId: data['promotedStudentId'] as String?,
    );
  }

  // --- Reads ----------------------------------------------------------------

  /// Loads existing occurrence counters by id (missing ids mean 0/maxStudents).
  /// Chunks into `whereIn` queries of 30 (Firestore limit).
  Future<Map<String, ClassOccurrence>> occurrencesByIds(List<String> ids) async {
    final out = <String, ClassOccurrence>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
      if (chunk.isEmpty) continue;
      final snap = await _collections.classOccurrences
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in snap.docs) {
        out[d.id] = ClassOccurrence.fromFirestore(d);
      }
    }
    return out;
  }

  /// A student's active (confirmed + waitlist) reservations, soonest first.
  Future<List<ClassBooking>> activeBookingsForStudent(String studentId) async {
    final snap = await _collections.classBookings
        .where('studentId', isEqualTo: studentId)
        .where('status', whereIn: [
      BookingStatus.confirmed.value,
      BookingStatus.waitlist.value,
    ]).get();
    final list = snap.docs.map(ClassBooking.fromFirestore).toList()
      ..sort((a, b) => (a.slotStart ?? DateTime(2100))
          .compareTo(b.slotStart ?? DateTime(2100)));
    return list;
  }

  /// All bookings for one occurrence (staff roster view), ordered: confirmed
  /// first, then waitlist by arrival.
  Future<List<ClassBooking>> rosterForOccurrence(String occId) async {
    final snap = await _collections.classBookings
        .where('occId', isEqualTo: occId)
        .where('status', whereIn: [
      BookingStatus.confirmed.value,
      BookingStatus.waitlist.value,
    ]).get();
    final list = snap.docs.map(ClassBooking.fromFirestore).toList()
      ..sort((a, b) {
        if (a.status != b.status) {
          return a.status == BookingStatus.confirmed ? -1 : 1;
        }
        return (a.waitlistSeq ?? 0).compareTo(b.waitlistSeq ?? 0);
      });
    return list;
  }

  /// Convenience: expand a class schedule into bookable occurrences within the
  /// window, pairing each with its current counter (or an empty one).
  List<ScheduleSlot> toScheduleSlots(
    Iterable<({int dayOfWeek, String startTime, String endTime})> schedule,
  ) =>
      schedule
          .map((s) => ScheduleSlot(
                dayOfWeek: s.dayOfWeek,
                startTime: s.startTime,
                endTime: s.endTime,
              ))
          .toList();
}
