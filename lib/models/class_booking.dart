import 'package:cloud_firestore/cloud_firestore.dart';

/// Reservation status for a single dated class occurrence.
enum BookingStatus { confirmed, waitlist, cancelled }

extension BookingStatusX on BookingStatus {
  String get value => name;

  String get label {
    switch (this) {
      case BookingStatus.confirmed:
        return 'Confirmada';
      case BookingStatus.waitlist:
        return 'Lista de espera';
      case BookingStatus.cancelled:
        return 'Cancelada';
    }
  }

  static BookingStatus fromString(String? v) {
    switch (v) {
      case 'confirmed':
        return BookingStatus.confirmed;
      case 'waitlist':
        return BookingStatus.waitlist;
      case 'cancelled':
        return BookingStatus.cancelled;
      default:
        return BookingStatus.confirmed;
    }
  }
}

/// Who created the reservation. Staff bookings bypass the student-side cancel
/// cutoff and the per-student limit.
enum BookedBy { self, responsible, staff }

extension BookedByX on BookedBy {
  String get value => name;

  static BookedBy fromString(String? v) {
    switch (v) {
      case 'responsible':
        return BookedBy.responsible;
      case 'staff':
        return BookedBy.staff;
      case 'self':
      default:
        return BookedBy.self;
    }
  }
}

/// Server-authoritative capacity counter for one dated occurrence of a class.
/// Written ONLY by the booking Cloud Functions (rules deny client writes); the
/// client reads it to show "X/Y vagas". Lives at
/// `academies/{id}/classOccurrences/{occId}`.
class ClassOccurrence {
  final String id; // occId: {classId}_{yyyyMMdd}[_{HHmm}]
  final String classId;
  final String className;
  final String? sport;
  final String? category;
  final String date; // yyyyMMdd
  final DateTime? slotStart;
  final String startTime;
  final String endTime;
  final int dayOfWeek;
  final int? maxStudents; // null = unlimited (no waitlist)
  final int confirmedCount;
  final int waitlistCount;

  const ClassOccurrence({
    required this.id,
    required this.classId,
    required this.className,
    this.sport,
    this.category,
    required this.date,
    this.slotStart,
    required this.startTime,
    required this.endTime,
    required this.dayOfWeek,
    this.maxStudents,
    this.confirmedCount = 0,
    this.waitlistCount = 0,
  });

  /// True when capacity is set and full (further bookings go to the waitlist).
  bool get isFull => maxStudents != null && confirmedCount >= maxStudents!;

  /// Remaining open spots, or null when capacity is unlimited.
  int? get spotsLeft =>
      maxStudents == null ? null : (maxStudents! - confirmedCount).clamp(0, maxStudents!);

  factory ClassOccurrence.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ClassOccurrence(
      id: doc.id,
      classId: (data['classId'] ?? '').toString(),
      className: (data['className'] ?? '').toString(),
      sport: data['sport'] as String?,
      category: data['category'] as String?,
      date: (data['date'] ?? '').toString(),
      slotStart: (data['slotStart'] as Timestamp?)?.toDate(),
      startTime: (data['startTime'] ?? '').toString(),
      endTime: (data['endTime'] ?? '').toString(),
      dayOfWeek: (data['dayOfWeek'] as num?)?.toInt() ?? 0,
      maxStudents: (data['maxStudents'] as num?)?.toInt(),
      confirmedCount: (data['confirmedCount'] as num?)?.toInt() ?? 0,
      waitlistCount: (data['waitlistCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single student's reservation for a dated class occurrence. Doc id is
/// deterministic (`{occId}__{studentId}`) so re-reserving upserts cleanly.
/// Lives at `academies/{id}/classBookings/{bookingId}`. Written ONLY by the
/// booking Cloud Functions.
class ClassBooking {
  final String id;
  final String occId;
  final String classId;
  final String className;
  final String? sport;
  final String studentId;
  final String studentName;
  final String date; // yyyyMMdd
  final DateTime? slotStart;
  final String startTime;
  final String endTime;
  final BookingStatus status;
  final int? waitlistSeq; // arrival order within the waitlist (millis)
  final BookedBy bookedBy;
  final String? bookedByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? cancelledAt;

  const ClassBooking({
    required this.id,
    required this.occId,
    required this.classId,
    required this.className,
    this.sport,
    required this.studentId,
    required this.studentName,
    required this.date,
    this.slotStart,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.waitlistSeq,
    this.bookedBy = BookedBy.self,
    this.bookedByUid,
    this.createdAt,
    this.updatedAt,
    this.cancelledAt,
  });

  bool get isActive => status != BookingStatus.cancelled;

  factory ClassBooking.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ClassBooking(
      id: doc.id,
      occId: (data['occId'] ?? '').toString(),
      classId: (data['classId'] ?? '').toString(),
      className: (data['className'] ?? '').toString(),
      sport: data['sport'] as String?,
      studentId: (data['studentId'] ?? '').toString(),
      studentName: (data['studentName'] ?? '').toString(),
      date: (data['date'] ?? '').toString(),
      slotStart: (data['slotStart'] as Timestamp?)?.toDate(),
      startTime: (data['startTime'] ?? '').toString(),
      endTime: (data['endTime'] ?? '').toString(),
      status: BookingStatusX.fromString(data['status'] as String?),
      waitlistSeq: (data['waitlistSeq'] as num?)?.toInt(),
      bookedBy: BookedByX.fromString(data['bookedBy'] as String?),
      bookedByUid: data['bookedByUid'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
    );
  }
}
