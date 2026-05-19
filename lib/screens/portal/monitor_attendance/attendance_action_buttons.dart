import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';

class AttendanceActionButtons extends StatelessWidget {
  const AttendanceActionButtons({
    super.key,
    required this.checkinEnabled,
    required this.pendingCheckinsCount,
    required this.isSaving,
    required this.presentCount,
    required this.onShowCheckins,
    required this.onMarkAll,
    required this.onClearAll,
  });

  final bool checkinEnabled;
  final int pendingCheckinsCount;
  final bool isSaving;
  final int presentCount;
  final VoidCallback onShowCheckins;
  final VoidCallback onMarkAll;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final hasPendingCheckins = checkinEnabled && pendingCheckinsCount > 0;

    return Column(
      children: [
        if (hasPendingCheckins) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onShowCheckins,
              icon: const Icon(LucideIcons.userCheck, size: 18),
              label: Text('Check-ins ($pendingCheckinsCount)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: hasPendingCheckins
                  ? OutlinedButton.icon(
                      onPressed: isSaving ? null : onMarkAll,
                      icon: const Icon(LucideIcons.checkCheck, size: 18),
                      label: const Text('Todos'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: BorderSide(color: AppTheme.divider),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: isSaving ? null : onMarkAll,
                      icon: const Icon(LucideIcons.checkCheck, size: 18),
                      label: const Text('Todos'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isSaving || presentCount == 0 ? null : onClearAll,
                icon: const Icon(LucideIcons.x, size: 18),
                label: const Text('Limpar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: BorderSide(color: AppTheme.divider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
