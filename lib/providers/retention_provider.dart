import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/student.dart';
import '../services/firebase_service.dart';
import '../services/retention_service.dart';
import '../services/student_service.dart';

/// Data class holding all retention analysis results
class RetentionData {
  final List<StudentRiskScore> atRiskStudents;
  final RetentionMetrics metrics;
  final int totalStudents;

  RetentionData({
    required this.atRiskStudents,
    required this.metrics,
    required this.totalStudents,
  });
}

/// Retention service provider (pure computation, no academyId needed)
final retentionServiceProvider = Provider<RetentionService>((ref) {
  return RetentionService();
});

/// Combined retention data provider - fetches students, attendance, financials and computes risk
final retentionDataProvider = FutureProvider<RetentionData>((ref) async {
  final academyId = FirebaseService.academyId;
  final retentionService = ref.watch(retentionServiceProvider);
  final collections = Collections(academyId);

  // Fetch active students
  final studentService = StudentService(academyId);
  final students = await studentService.getActive();

  // Fetch attendance from last 30 days
  final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
  final attendanceSnapshot = await collections.attendance
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
      .get();
  final attendanceRecords = attendanceSnapshot.docs.map((doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }).toList();

  // Fetch overdue financials
  final financialsSnapshot = await collections.payments
      .where('status', isEqualTo: 'overdue')
      .get();
  final overduePayments = financialsSnapshot.docs.map((doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }).toList();

  // Build attendance map grouped by studentId
  final attendanceMap = <String, List<Map<String, dynamic>>>{};
  for (final record in attendanceRecords) {
    final studentId = record['studentId'] as String;
    attendanceMap.putIfAbsent(studentId, () => []).add(record);
  }

  // Build financials map grouped by studentId
  final financialsMap = <String, List<Map<String, dynamic>>>{};
  for (final payment in overduePayments) {
    final studentId = payment['studentId'] as String;
    financialsMap.putIfAbsent(studentId, () => []).add(payment);
  }

  // Compute risk scores
  final atRiskStudents = retentionService.getAtRiskStudents(
    students,
    attendanceMap,
    financialsMap,
  );
  final metrics = retentionService.getRetentionMetrics(students, atRiskStudents);

  return RetentionData(
    atRiskStudents: atRiskStudents,
    metrics: metrics,
    totalStudents: students.length,
  );
});
