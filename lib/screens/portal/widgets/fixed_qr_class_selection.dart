import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/fixed_academy_qr_service.dart';
import '../../../widgets/polish/polish.dart';

class FixedQrClassSelection extends StatelessWidget {
  final FixedAcademyQrSession session;
  final String? selectedClassId;
  final String? errorMessage;
  final bool isSubmitting;
  final ValueChanged<FixedAcademyQrClass> onSelected;
  final VoidCallback onScanAgain;

  const FixedQrClassSelection({
    super.key,
    required this.session,
    required this.selectedClassId,
    required this.errorMessage,
    required this.isSubmitting,
    required this.onSelected,
    required this.onScanAgain,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            const Icon(LucideIcons.qrCode, size: 48, color: AppTheme.primary),
            const SizedBox(height: 12),
            Text(
              session.academyName,
              style: AppTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Selecione a turma em que voce vai treinar agora.',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      color: AppTheme.error,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(errorMessage!, style: AppTheme.bodySmall),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (session.classes.isEmpty)
              PolishedEmptyState(
                icon: LucideIcons.clock,
                title: 'Nenhuma turma disponivel agora',
                subtitle:
                    'As turmas aparecem somente dentro da janela de check-in e quando sua matricula permite a entrada.',
                actionLabel: 'Ler novamente',
                onAction: onScanAgain,
              )
            else
              ...session.classes.map((cls) {
                final selected = selectedClassId == cls.id;
                return Container(
                  key: ValueKey(cls.id),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? AppTheme.primary : AppTheme.border,
                    ),
                  ),
                  child: ListTile(
                    enabled: !isSubmitting,
                    onTap: () => onSelected(cls),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        LucideIcons.users,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(cls.name, style: AppTheme.titleMedium),
                    subtitle: Text('${cls.startTime} - ${cls.endTime}'),
                    trailing: selected && isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.chevronRight, size: 18),
                  ),
                );
              }),
            if (session.classes.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: isSubmitting ? null : onScanAgain,
                icon: const Icon(LucideIcons.scanLine, size: 17),
                label: const Text('Ler outro QR'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
