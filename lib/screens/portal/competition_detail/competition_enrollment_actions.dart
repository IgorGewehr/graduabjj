import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/competition_repo.dart';
import '../../../api/dto/competition_dto.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';

/// Enrolls [student] in [competition] via the Tatami [competitionRepo] and
/// calls [onSuccess] with the new [CompetitionEnrollment] so the caller can
/// update its state.
///
/// All UI feedback is shown through [context].  [onSetLoading] should update
/// the isEnrolling flag in the parent widget.
Future<void> selfEnroll({
  required BuildContext context,
  required String academyId,
  required Competition competition,
  required Student student,
  required CompetitionRemoteRepo competitionRepo,
  required void Function(bool) onSetLoading,
  required void Function(CompetitionEnrollment) onSuccess,
}) async {
  HapticFeedback.selectionClick();
  onSetLoading(true);
  try {
    final apiEnrollment = await competitionRepo.enroll(
      academyId,
      competition.id,
      CreateEnrollmentRequest(
        studentId: student.id,
        modality: ApiModality.gi,
        ageCategory: 'adult',
        transportPreference: ApiTransportPreference.undecided,
      ),
    );

    // Adapta para o modelo legado usado pelo caller.
    final enrollment = CompetitionEnrollment(
      id: apiEnrollment.id,
      competitionId: apiEnrollment.competitionId,
      competitionName: competition.name,
      studentId: apiEnrollment.studentId,
      studentName: student.fullName,
      ageCategory: apiEnrollment.ageCategory,
      weightCategory: apiEnrollment.weightCategory,
      transportPreference: TransportPreference.undecided,
      enrolledAt: apiEnrollment.enrolledAt,
    );

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

/// Cancels the enrollment of [studentId] in [competition] via Tatami and
/// calls [onSuccess] with the deleted enrollment's id so the caller can
/// update its state list.
Future<void> cancelEnrollment({
  required BuildContext context,
  required String academyId,
  required Competition competition,
  required String studentId,
  required List<CompetitionEnrollment> enrollments,
  required CompetitionRemoteRepo competitionRepo,
  required void Function(bool) onSetLoading,
  required void Function(String deletedEnrollmentId) onSuccess,
}) async {
  final myEnrollment =
      enrollments.where((e) => e.studentId == studentId).firstOrNull;
  if (myEnrollment == null) return;

  onSetLoading(true);
  try {
    await competitionRepo.unenroll(academyId, competition.id, myEnrollment.id);

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
