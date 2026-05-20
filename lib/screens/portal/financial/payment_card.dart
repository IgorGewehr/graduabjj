import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/services.dart';

String formatCurrency(double value) =>
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);

class PaymentCard extends StatelessWidget {
  final Payment payment;
  final bool showStatus;
  final bool showPayButton;
  final VoidCallback? onPayPix;

  const PaymentCard({
    super.key,
    required this.payment,
    this.showStatus = false,
    this.showPayButton = false,
    this.onPayPix,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = payment.isOverdue;
    final isPaid = payment.status == PaymentStatus.paid;
    final isCancelled = payment.status == PaymentStatus.cancelled;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue
              ? AppTheme.error.withValues(alpha: 0.5)
              : AppTheme.divider,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isOverdue
                      ? AppTheme.errorLight
                      : isPaid
                          ? AppTheme.successLight
                          : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isOverdue
                      ? LucideIcons.alertTriangle
                      : isPaid
                          ? LucideIcons.checkCircle
                          : isCancelled
                              ? LucideIcons.xCircle
                              : LucideIcons.receipt,
                  size: 18,
                  color: isOverdue
                      ? AppTheme.error
                      : isPaid
                          ? AppTheme.success
                          : isCancelled
                              ? AppTheme.textDisabled
                              : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.description ?? 'Mensalidade',
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isCancelled
                            ? AppTheme.textDisabled
                            : AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.calendar,
                          size: 12,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('dd/MM/yyyy').format(payment.dueDate),
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (payment.referenceMonth != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            payment.referenceMonth!,
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(payment.value),
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isOverdue
                          ? AppTheme.error
                          : isCancelled
                              ? AppTheme.textDisabled
                              : AppTheme.textPrimary,
                      decoration:
                          isCancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (showStatus) ...[
                    const SizedBox(height: 4),
                    PaymentStatusChip(status: payment.status),
                  ],
                ],
              ),
            ],
          ),
          if (showPayButton && !isPaid && !isCancelled && onPayPix != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPayPix,
                icon: const Icon(LucideIcons.qrCode, size: 18),
                label: const Text('Pagar com PIX'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PaymentStatusChip extends StatelessWidget {
  final PaymentStatus status;

  const PaymentStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;
    final String label;

    switch (status) {
      case PaymentStatus.paid:
        bgColor = AppTheme.successLight;
        textColor = AppTheme.success;
        label = 'Pago';
      case PaymentStatus.pending:
        bgColor = AppTheme.warningLight;
        textColor = AppTheme.warning;
        label = 'Pendente';
      case PaymentStatus.overdue:
        bgColor = AppTheme.errorLight;
        textColor = AppTheme.error;
        label = 'Atrasado';
      case PaymentStatus.cancelled:
        bgColor = AppTheme.surfaceVariant;
        textColor = AppTheme.textSecondary;
        label = 'Cancelado';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Container(
        key: ValueKey(status),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: AppTheme.labelSmall.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}
