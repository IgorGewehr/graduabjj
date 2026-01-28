import 'package:cloud_firestore/cloud_firestore.dart';

/// Checkin Status
enum CheckinStatus { pending, confirmed, rejected }

extension CheckinStatusExtension on CheckinStatus {
  String get value {
    switch (this) {
      case CheckinStatus.pending:
        return 'pending';
      case CheckinStatus.confirmed:
        return 'confirmed';
      case CheckinStatus.rejected:
        return 'rejected';
    }
  }

  String get label {
    switch (this) {
      case CheckinStatus.pending:
        return 'Pendente';
      case CheckinStatus.confirmed:
        return 'Confirmado';
      case CheckinStatus.rejected:
        return 'Rejeitado';
    }
  }

  static CheckinStatus fromString(String value) {
    switch (value) {
      case 'confirmed':
        return CheckinStatus.confirmed;
      case 'rejected':
        return CheckinStatus.rejected;
      default:
        return CheckinStatus.pending;
    }
  }
}

/// Student Check-in Model
class Checkin {
  final String id;
  final String studentId;
  final String studentName;
  final String classId;
  final String className;
  final DateTime scheduleDate;
  final int scheduleDayOfWeek;
  final String scheduleStartTime;
  final String scheduleEndTime;
  final DateTime checkinTime;
  final CheckinStatus status;

  // Confirmation info
  final String? confirmedBy;
  final String? confirmedByName;
  final DateTime? confirmedAt;

  final DateTime createdAt;

  Checkin({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.classId,
    required this.className,
    required this.scheduleDate,
    required this.scheduleDayOfWeek,
    required this.scheduleStartTime,
    required this.scheduleEndTime,
    required this.checkinTime,
    required this.status,
    this.confirmedBy,
    this.confirmedByName,
    this.confirmedAt,
    required this.createdAt,
  });

  factory Checkin.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Checkin(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      classId: data['classId'] ?? '',
      className: data['className'] ?? '',
      scheduleDate: (data['scheduleDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      scheduleDayOfWeek: data['scheduleDayOfWeek'] ?? 0,
      scheduleStartTime: data['scheduleStartTime'] ?? '',
      scheduleEndTime: data['scheduleEndTime'] ?? '',
      checkinTime: (data['checkinTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: CheckinStatusExtension.fromString(data['status'] ?? 'pending'),
      confirmedBy: data['confirmedBy'],
      confirmedByName: data['confirmedByName'],
      confirmedAt: (data['confirmedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'studentName': studentName,
      'classId': classId,
      'className': className,
      'scheduleDate': Timestamp.fromDate(scheduleDate),
      'scheduleDayOfWeek': scheduleDayOfWeek,
      'scheduleStartTime': scheduleStartTime,
      'scheduleEndTime': scheduleEndTime,
      'checkinTime': Timestamp.fromDate(checkinTime),
      'status': status.value,
      'confirmedBy': confirmedBy,
      'confirmedByName': confirmedByName,
      'confirmedAt': confirmedAt != null ? Timestamp.fromDate(confirmedAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  Checkin copyWith({
    String? id,
    String? studentId,
    String? studentName,
    String? classId,
    String? className,
    DateTime? scheduleDate,
    int? scheduleDayOfWeek,
    String? scheduleStartTime,
    String? scheduleEndTime,
    DateTime? checkinTime,
    CheckinStatus? status,
    String? confirmedBy,
    String? confirmedByName,
    DateTime? confirmedAt,
    DateTime? createdAt,
  }) {
    return Checkin(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      scheduleDate: scheduleDate ?? this.scheduleDate,
      scheduleDayOfWeek: scheduleDayOfWeek ?? this.scheduleDayOfWeek,
      scheduleStartTime: scheduleStartTime ?? this.scheduleStartTime,
      scheduleEndTime: scheduleEndTime ?? this.scheduleEndTime,
      checkinTime: checkinTime ?? this.checkinTime,
      status: status ?? this.status,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      confirmedByName: confirmedByName ?? this.confirmedByName,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'Checkin(id: $id, studentName: $studentName, className: $className, status: ${status.value})';
  }
}
