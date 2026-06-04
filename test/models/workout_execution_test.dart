import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/workout_execution.dart';

void main() {
  group('WorkoutExecution.docId', () {
    test('determinístico por aluno/plano/dia/exercício/data', () {
      final d = DateTime(2026, 6, 4);
      expect(WorkoutExecution.docId('s1', 'p1', 0, 2, d), 's1_p1_0_2_20260604');
      // mesmo dia, qualquer hora → mesmo id (idempotente)
      expect(
        WorkoutExecution.docId('s1', 'p1', 0, 2, DateTime(2026, 6, 4, 23, 59)),
        's1_p1_0_2_20260604',
      );
      // exercício diferente → id diferente
      expect(
        WorkoutExecution.docId('s1', 'p1', 0, 3, d) ==
            WorkoutExecution.docId('s1', 'p1', 0, 2, d),
        isFalse,
      );
    });

    test('padding de mês/dia', () {
      expect(WorkoutExecution.docId('s', 'p', 1, 0, DateTime(2026, 1, 9)),
          's_p_1_0_20260109');
    });
  });

  group('derivados', () {
    test('bestLoad / best1RM / volume', () {
      final e = WorkoutExecution(
        id: 'x',
        studentId: 's',
        planId: 'p',
        dayIndex: 0,
        exerciseIndex: 0,
        exerciseName: 'Supino',
        date: DateTime(2026, 6, 4),
        sets: const [
          SetEntry(reps: 12, load: 50),
          SetEntry(reps: 5, load: 80),
        ],
        createdAt: DateTime(2026, 6, 4),
      );
      expect(e.bestLoadKg, 80);
      expect(e.volume, 12 * 50 + 5 * 80); // 1000
      expect(e.best1RMKg, greaterThan(80)); // Epley do 5×80 > 80
    });
  });
}
