import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/repositories.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../providers/selected_academy_provider.dart' show selectedAcademyIdProvider;

/// Shows the link-code generation dialog.
///
/// Generates a link code via the Go backend and displays a dialog where the
/// admin can copy the code to share with the student.
Future<void> showGenerateLinkCodeFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String studentId,
  required String studentName,
}) async {
  try {
    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null) {
      if (context.mounted) context.showError('Selecione uma academia.');
      return;
    }
    final src = await ref.read(linkCodeRepoProvider).createForStudent(
          academyId,
          studentId: studentId,
        );

    if (context.mounted) {
      _showLinkCodeDialog(context, src.code, studentName);
    }
  } catch (e) {
    if (context.mounted) {
      context.showError('Erro ao gerar codigo: $e');
    }
  }
}

void _showLinkCodeDialog(BuildContext context, String code, String studentName) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.link, color: AppTheme.primary),
          const SizedBox(width: 8),
          const Text('Codigo Gerado'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Compartilhe com $studentName:'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary, width: 2),
            ),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Valido por 24 horas',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            context.showSuccess('Codigo copiado!');
          },
          icon: const Icon(LucideIcons.copy, size: 16),
          label: const Text('Copiar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
