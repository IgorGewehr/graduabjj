import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/checkin.dart';

/// Action buttons row shown when a class is selected:
/// - Check-ins button (if enabled and pending check-ins exist)
/// - Mark All Present
/// - Clear All
class AttendanceActionButtons extends StatelessWidget {
  final bool checkinEnabled;
  final List<Checkin> pendingCheckins;
  final bool isSaving;
  final int presentCount;
  final VoidCallback onShowCheckinDialog;
  final VoidCallback onMarkAllPresent;
  final VoidCallback onUnmarkAllPresent;

  const AttendanceActionButtons({
    super.key,
    required this.checkinEnabled,
    required this.pendingCheckins,
    required this.isSaving,
    required this.presentCount,
    required this.onShowCheckinDialog,
    required this.onMarkAllPresent,
    required this.onUnmarkAllPresent,
  });

  bool get _hasCheckins => checkinEnabled && pendingCheckins.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Check-ins button
        if (_hasCheckins) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onShowCheckinDialog,
              icon: const Icon(LucideIcons.userCheck, size: 18),
              label: Text('Check-ins (${pendingCheckins.length})'),
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
            // Adicionar (green) — only if no check-ins button
            if (!_hasCheckins)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Add student to class
                  },
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: const Text('Adicionar'),
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
            if (!_hasCheckins) const SizedBox(width: 8),

            // Todos (outlined)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isSaving ? null : onMarkAllPresent,
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
              ),
            ),
            const SizedBox(width: 8),

            // Limpar (outlined)
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    isSaving || presentCount == 0 ? null : onUnmarkAllPresent,
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
