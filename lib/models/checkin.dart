import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/dto/attendance_dto.dart' as api;

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

  /// Constrói um [Checkin] a partir do DTO [api.ApiAttendance] —
  /// resposta do `POST /v1/academies/{id}/attendance/self-checkin` do Tatami.
  ///
  /// Sprint 1B adapter (FE-only). No Tatami NÃO existe entidade `Checkin`
  /// separada: o self-checkin via QR PRODUZ uma row de `attendance` direto
  /// (sem fluxo de aprovação intermediário — o backend valida o token HMAC
  /// e grava atomic). Portanto qualquer `Checkin` materializado a partir
  /// de `ApiAttendance` é por definição [CheckinStatus.confirmed].
  ///
  /// Pontos de atenção:
  /// - `studentName` / `className` NÃO vêm em `ApiAttendance` (Tatami só
  ///   devolve IDs). Caller passa via parâmetro quando souber — fallback
  ///   é string vazia (legacy non-null).
  /// - `schedule_*` (dayOfWeek, startTime, endTime) é metadata da CLASS,
  ///   não da attendance. Caller passa via parâmetro se renderizar listas
  ///   por horário; fallback é zero / empty string.
  /// - `confirmedBy*` é populado com `verified_by_uid` da attendance —
  ///   no Tatami SEMPRE há um verifier (mesmo no self-checkin, o backend
  ///   marca o próprio aluno como `verified_by_uid`).
  /// - `checkinTime` = `created_at` da attendance (momento do POST).
  /// - `scheduleDate` = `date` (dia da aula, formato YYYY-MM-DD).
  factory Checkin.fromApi(
    api.ApiAttendance a, {
    String? studentName,
    String? className,
    int? scheduleDayOfWeek,
    String? scheduleStartTime,
    String? scheduleEndTime,
    String? confirmedByName,
  }) {
    final createdAt = a.createdAt ?? DateTime.now();
    return Checkin(
      id: a.id,
      studentId: a.studentId,
      studentName: studentName ?? '',
      classId: a.classId,
      className: className ?? '',
      scheduleDate: a.date,
      scheduleDayOfWeek: scheduleDayOfWeek ?? 0,
      scheduleStartTime: scheduleStartTime ?? '',
      scheduleEndTime: scheduleEndTime ?? '',
      checkinTime: createdAt,
      status: CheckinStatus.confirmed,
      confirmedBy: a.verifiedByUid,
      confirmedByName: confirmedByName,
      confirmedAt: createdAt,
      createdAt: createdAt,
    );
  }

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
