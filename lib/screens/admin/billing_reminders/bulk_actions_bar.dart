import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/billing_reminder_service.dart';

class BulkActionsBar extends StatelessWidget {
  const BulkActionsBar({
    super.key,
    required this.currentStage,
    required this.stageItems,
    required this.isSending,
    required this.hasWhatsApp,
    required this.hasEmail,
    required this.onSendTap,
  });

  final BillingStage currentStage;
  final List<Map<String, dynamic>> stageItems;
  final bool isSending;
  final bool hasWhatsApp;
  final bool hasEmail;
  final VoidCallback onSendTap;

  @override
  Widget build(BuildContext context) {
    if (stageItems.isEmpty) return const SizedBox.shrink();
    if (!hasWhatsApp && !hasEmail) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: isSending
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : ElevatedButton.icon(
                onPressed: onSendTap,
                icon: const Icon(LucideIcons.send, size: 16),
                label: Text(
                  'Cobrar todos (${stageItems.length})',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
      ),
    );
  }
}
