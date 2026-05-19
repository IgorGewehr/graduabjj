import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/student.dart';
import '../../../services/services.dart';

/// Enrolls [student] in [competition] and calls [onSuccess] with the new
/// enrollment so the caller can update its state.
///
/// All UI feedback is shown through [context].  [onSetLoading] should update
/// the isEnrolling flag in the parent widget.
Future<void> selfEnroll({
  required BuildContext context,
  required String academyId,
  required Competition competition,
  required Student student,
  required void Function(bool) onSetLoading,
  required void Function(CompetitionEnrollment) onSuccess,
}) async {
  HapticFeedback.selectionClick();
  onSetLoading(true);
  try {
    final enrollmentService = CompetitionEnrollmentService(academyId);
    final enrollment = await enrollmentService.enroll(
      competitionId: competition.id,
      competitionName: competition.name,
      studentId: student.id,
      studentName: student.fullName,
      ageCategory: 'adult',
      weightCategory: '',
      transportPreference: TransportPreference.undecided,
    );

    // Also update legacy enrolledStudentIds
    try {
      final competitionService = CompetitionService(academyId);
      await competitionService.enrollStudent(competition.id, student.id);
    } catch (_) {}

    onSuccess(enrollment);

    if (context.mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inscrito com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      final msg = e is Exception ? e.toString() : 'Erro ao se inscrever';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  } finally {
    onSetLoading(false);
  }
}

/// Cancels the enrollment of [studentId] in [competition] and calls
/// [onSuccess] with the deleted enrollment's id so the caller can update its
/// state list.
Future<void> cancelEnrollment({
  required BuildContext context,
  required String academyId,
  required Competition competition,
  required String studentId,
  required List<CompetitionEnrollment> enrollments,
  required void Function(bool) onSetLoading,
  required void Function(String deletedEnrollmentId) onSuccess,
}) async {
  final myEnrollment =
      enrollments.where((e) => e.studentId == studentId).firstOrNull;
  if (myEnrollment == null) return;

  onSetLoading(true);
  try {
    final enrollmentService = CompetitionEnrollmentService(academyId);
    await enrollmentService.delete(myEnrollment.id);

    // Also remove from legacy array
    try {
      final competitionService = CompetitionService(academyId);
      await competitionService.unenrollStudent(competition.id, studentId);
    } catch (_) {}

    onSuccess(myEnrollment.id);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inscricao cancelada'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao cancelar inscricao'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    onSetLoading(false);
  }
}
