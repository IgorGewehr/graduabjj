import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

/// Shared account-deletion flow used by every account type
/// (student, monitor, professor, admin) so the option stays
/// consistent and meets the App Store / Play Store requirement.
class DeleteAccountHelper {
  static Future<void> showConfirmation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir conta'),
        content: const Text(
          'Tem certeza que deseja excluir sua conta? Esta acao nao pode ser desfeita.\n\n'
          'Todos os seus dados serao removidos permanentemente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (firstConfirm != true || !context.mounted) return;

    final finalConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmacao final'),
        content: const Text(
          'Esta e sua ultima chance. Todos os dados serao perdidos:\n\n'
          '- Historico de treinos e presencas\n'
          '- Graduacoes e progresso\n'
          '- Resultados de competicoes\n'
          '- Dados pessoais\n'
          '- Acesso a academias vinculadas\n\n'
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Excluir permanentemente'),
          ),
        ],
      ),
    );

    if (finalConfirm != true || !context.mounted) return;

    await _runDeletion(context, ref);
  }

  static Future<void> _runDeletion(
    BuildContext context,
    WidgetRef ref,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final authService = ref.read(authServiceProvider);
      await authService.deleteAccount();
      // auth state listener redirects to login automatically
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }
}
