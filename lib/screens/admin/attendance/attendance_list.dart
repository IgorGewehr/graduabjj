import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import 'attendance_student_card.dart';

// ---------------------------------------------------------------------------
// Confirmation dialog helpers
// ---------------------------------------------------------------------------

/// Asks the user to confirm marking [count] students as present.
/// Returns true if confirmed, false/null otherwise.
Future<bool?> showMarkAllPresentDialog(
    BuildContext context, int count) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Marcar Todos Presentes'),
      content: Text(
        'Deseja marcar todos os $count alunos como presentes?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
          ),
          child: const Text('Marcar Todos'),
        ),
      ],
    ),
  );
}

/// Asks the user to confirm removing all presences.
/// Returns true if confirmed, false/null otherwise.
Future<bool?> showUnmarkAllPresentDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remover Todas Presencas'),
      content: const Text('Deseja remover todas as presencas registradas?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.error,
            foregroundColor: Colors.white,
          ),
          child: const Text('Remover Todas'),
        ),
      ],
    ),
  );
}

/// The student sliver list (or empty states) for the attendance screen.
/// Renders as a SliverFillRemaining (empty/no-class) or a SliverList.
class AttendanceStudentSliverList extends StatelessWidget {
  final List<Student> filteredStudents;
  final Set<String> presentStudentIds;
  final String searchQuery;
  final Future<void> Function(Student) onToggleAttendance;

  const AttendanceStudentSliverList({
    super.key,
    required this.filteredStudents,
    required this.presentStudentIds,
    required this.searchQuery,
    required this.onToggleAttendance,
  });

  @override
  Widget build(BuildContext context) {
    if (filteredStudents.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.userX, size: 48, color: AppTheme.textDisabled),
              const SizedBox(height: 16),
              Text(
                searchQuery.isNotEmpty
                    ? 'Nenhum aluno encontrado'
                    : 'Nenhum aluno nesta turma',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final student = filteredStudents[index];
            final isPresent = presentStudentIds.contains(student.id);
            return AttendanceStudentCard(
              student: student,
              isPresent: isPresent,
              onTap: () => onToggleAttendance(student),
            );
          },
          childCount: filteredStudents.length,
        ),
      ),
    );
  }
}

/// Full-screen "select a class first" placeholder.
class AttendanceSelectClassState extends StatelessWidget {
  const AttendanceSelectClassState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.users,
                size: 36,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Selecione uma turma',
              style: AppTheme.titleMedium.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Escolha uma turma acima para\nregistrar as presencas',
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Overlay shown while a bulk save operation is in progress.
class AttendanceSavingOverlay extends StatelessWidget {
  const AttendanceSavingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.black.withValues(alpha: 0.35),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 14),
                Text(
                  'Processando presencas...',
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
