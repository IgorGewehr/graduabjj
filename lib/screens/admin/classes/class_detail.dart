// Bottom-sheet that shows the details of a single BJJClass.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/repositories.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/services.dart';
import 'class_helpers.dart';
import 'class_widgets.dart';

/// Shows the class detail sheet.
///
/// [onEdit], [onDelete] and [onManageStudents] are forwarded to the parent so
/// the parent can open the relevant sub-sheets.
void showClassDetails(
  BuildContext context,
  WidgetRef ref,
  BJJClass cls, {
  required VoidCallback onEdit,
  required VoidCallback onManageStudents,
  required VoidCallback onDeleteDone,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _ClassDetailSheet(
      bjjClass: cls,
      ref: ref,
      screenContext: context,
      onEdit: onEdit,
      onManageStudents: onManageStudents,
      onDeleteDone: onDeleteDone,
    ),
  );
}

/// Shows a standalone delete-confirmation sheet (used from the card's popup menu).
void showDeleteConfirmation(
  BuildContext context,
  WidgetRef ref,
  BJJClass cls, {
  required VoidCallback onDeleteDone,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _DeleteConfirmSheet(
      bjjClass: cls,
      ref: ref,
      screenContext: context,
      onDeleteDone: onDeleteDone,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _DeleteConfirmSheet extends StatelessWidget {
  final BJJClass bjjClass;
  final WidgetRef ref;
  final BuildContext screenContext;
  final VoidCallback onDeleteDone;

  const _DeleteConfirmSheet({
    required this.bjjClass,
    required this.ref,
    required this.screenContext,
    required this.onDeleteDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              LucideIcons.alertTriangle,
              color: AppTheme.error,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Excluir Turma',
            style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Deseja excluir a turma "${bjjClass.name}"? Esta acao nao pode ser desfeita.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppTheme.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      final currentUser =
                          ref.read(currentUserProvider).valueOrNull;
                      if (currentUser?.academyId == null) return;

                      final academyId = currentUser!.academyId!;
                      await ref
                          .read(classRepoProvider)
                          .delete(academyId, bjjClass.id);

                      if (context.mounted) {
                        Navigator.pop(context);
                        screenContext.showSuccess('Turma excluida!');
                        onDeleteDone();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        screenContext.showError('Erro: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Excluir'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ClassDetailSheet extends StatelessWidget {
  final BJJClass bjjClass;
  final WidgetRef ref;
  final BuildContext screenContext;
  final VoidCallback onEdit;
  final VoidCallback onManageStudents;
  final VoidCallback onDeleteDone;

  const _ClassDetailSheet({
    required this.bjjClass,
    required this.ref,
    required this.screenContext,
    required this.onEdit,
    required this.onManageStudents,
    required this.onDeleteDone,
  });

  Future<void> _deleteClass(BuildContext sheetCtx) async {
    // Inner delete confirmation sheet
    showModalBottomSheet(
      context: sheetCtx,
      backgroundColor: Colors.transparent,
      builder: (confirmCtx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                LucideIcons.alertTriangle,
                color: AppTheme.error,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Excluir Turma',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Deseja excluir a turma "${bjjClass.name}"? Esta acao nao pode ser desfeita.',
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(confirmCtx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: AppTheme.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        final currentUser =
                            ref.read(currentUserProvider).valueOrNull;
                        if (currentUser?.academyId == null) return;

                        final academyId = currentUser!.academyId!;
                        await ref
                            .read(classRepoProvider)
                            .delete(academyId, bjjClass.id);

                        if (confirmCtx.mounted) {
                          Navigator.pop(confirmCtx); // close confirm
                          Navigator.pop(sheetCtx); // close detail
                          screenContext.showSuccess('Turma excluida!');
                          onDeleteDone();
                        }
                      } catch (e) {
                        if (confirmCtx.mounted) {
                          screenContext.showError('Erro: $e');
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Excluir'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cls = bjjClass;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  LucideIcons.users,
                  color: AppTheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cls.name,
                      style: AppTheme.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (cls.category != null)
                      Text(
                        cls.category!.label,
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (cls.description != null) ...[
            const SizedBox(height: 16),
            Text(
              cls.description!,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                DetailRow(
                  icon: LucideIcons.users,
                  label: 'Alunos',
                  value: cls.maxStudents != null
                      ? '${cls.studentIds.length}/${cls.maxStudents}'
                      : '${cls.studentIds.length}',
                ),
                if (cls.maxStudents != null) ...[
                  const SizedBox(height: 12),
                  DetailRow(
                    icon: LucideIcons.userPlus,
                    label: 'Maximo de Alunos',
                    value: '${cls.maxStudents}',
                  ),
                ],
                const SizedBox(height: 12),
                DetailRow(
                  icon: LucideIcons.userCircle,
                  label: 'Instrutor',
                  value: cls.instructorName ?? 'Nao definido',
                ),
                const SizedBox(height: 12),
                DetailRow(
                  icon: LucideIcons.clock,
                  label: 'Horarios',
                  value: '${cls.schedule.length} configurados',
                ),
              ],
            ),
          ),
          if (cls.schedule.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Horarios',
              style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...cls.schedule.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${getDayLabel(s.dayOfWeek)}: ${s.startTime} - ${s.endTime}',
                        style: AppTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onManageStudents();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.userPlus, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Gerenciar Alunos',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onEdit();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppTheme.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.pencil, size: 18),
                      const SizedBox(width: 8),
                      const Text('Editar'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _deleteClass(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: AppTheme.error,
                    side: BorderSide(
                      color: AppTheme.error.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.trash2, size: 18),
                      const SizedBox(width: 8),
                      const Text('Excluir'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
