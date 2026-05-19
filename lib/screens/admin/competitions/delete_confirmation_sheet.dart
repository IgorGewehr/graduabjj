import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/competition_repo.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../services/services.dart';

/// Exibe o bottom sheet de confirmação para excluir um campeonato.
/// [repo] é o repositório Tatami para a operação de deleção.
/// [onDeleted] é chamado após exclusão bem-sucedida.
///
/// Quando [repo] é fornecido, usa Tatami. Caso contrário mantém
/// comportamento legado via [CompetitionService].
void showDeleteCompetitionConfirmation({
  required BuildContext context,
  required String academyId,
  required Competition competition,
  CompetitionRemoteRepo? repo,
  required VoidCallback onDeleted,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
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
            'Excluir Campeonato',
            style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Deseja excluir "${competition.name}"? Esta acao tambem removera todas as inscricoes.',
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
                  onPressed: () => Navigator.pop(sheetContext),
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
                      if (repo != null) {
                        await repo.delete(academyId, competition.id);
                      } else {
                        // Fallback legado — remove quando todos os callers
                        // passarem o repo Tatami.
                        await CompetitionService(academyId).delete(competition.id);
                      }

                      if (!sheetContext.mounted) return;
                      Navigator.pop(sheetContext);
                      sheetContext.showSuccess('Campeonato excluido!');
                      onDeleted();
                    } catch (e) {
                      if (!sheetContext.mounted) return;
                      sheetContext.showError('Erro: $e');
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
