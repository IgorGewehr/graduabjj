import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/dto/student_dto.dart' as api_student;
import '../../../api/repositories.dart' as tatami_repos;
import '../../../core/feedback_utils.dart';
import '../../../core/sports.dart';
import '../../../models/student.dart';
import '../../../providers/selected_academy_provider.dart';
import '../../../services/services.dart';

/// Shows the "Graduar Aluno" dialog.
///
/// Call [showPromoteDialog] as a free function — it handles sport selection,
/// stripe vs belt toggle, and commits the belt progression via Tatami.
Future<void> showPromoteDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Student student,
  required VoidCallback onSuccess,
}) async {
  final sports = student.getSports();
  SportId selectedSport = student.getPrimarySport();
  bool isStripe = true;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final grade = student.getGrade(selectedSport);
        final currentGrade = grade?.currentGrade ?? 'white';
        final currentStripes = grade?.currentStripes ?? 0;
        final sportDef = getSport(selectedSport);
        final hasStripes = sportDef.supportsStripes;
        final hasGrades = sportDef.gradeSystem != GradeSystem.none;

        return AlertDialog(
          title: const Text('Graduar Aluno'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Aluno: ${student.fullName}'),
              if (sports.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<SportId>(
                  value: selectedSport,
                  items: sports.map((s) {
                    final sport = getSport(s);
                    return DropdownMenuItem(
                      value: s,
                      child: Text(sport.label),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null)
                      setDialogState(() => selectedSport = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Esporte',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (hasGrades) ...[
                const SizedBox(height: 8),
                Text(
                  'Graduação atual: ${getGradeLabel(selectedSport, currentGrade)} - $currentStripes grau(s)',
                ),
              ],
              if (hasGrades && hasStripes) ...[
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Grau')),
                    ButtonSegment(value: false, label: Text('Faixa')),
                  ],
                  selected: {isStripe},
                  onSelectionChanged: (value) {
                    setDialogState(() => isStripe = value.first);
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final academyId = ref.read(selectedAcademyIdProvider) ?? '';
                  final beltRepo =
                      ref.read(tatami_repos.beltProgressionRepoProvider);

                  final String newBelt;
                  final int newStripes;

                  if (isStripe && hasStripes) {
                    // Stripe promotion: same belt, increment stripes.
                    newBelt = currentGrade;
                    newStripes = currentStripes + 1;
                  } else if (hasGrades) {
                    // Belt promotion: advance to next grade, reset stripes.
                    newBelt = _getNextGrade(selectedSport, currentGrade);
                    newStripes = 0;
                  } else {
                    return; // nothing to do
                  }

                  await beltRepo.promote(
                    academyId,
                    student.id,
                    api_student.CreateBeltProgressionRequest(
                      newBelt: api_student.ApiBeltX.fromWire(newBelt),
                      newStripes: newStripes,
                      promotionDate: DateTime.now(),
                      sport: api_student.ApiSportX.fromWire(
                        selectedSport.value,
                      ),
                    ),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    context.showSuccess('Graduação realizada com sucesso!');
                    onSuccess();
                  }
                } catch (e) {
                  if (context.mounted) {
                    context.showError('Erro: $e');
                  }
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    ),
  );
}

String _getNextGrade(SportId sportId, String current) {
  final grades = getGradesForSport(sportId);
  final index = grades.indexWhere((g) => g.id == current);
  if (index >= 0 && index < grades.length - 1) {
    return grades[index + 1].id;
  }
  return current;
}
