import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../services/store_service.dart';

/// Shared status timeline for a [StoreOrder], used by both the student portal
/// order sheet and the admin order-management board so the two stay in sync.
///
/// Renders the linear progression pendingPayment -> paid -> preparing -> ready
/// -> delivered, or a "cancelled" banner when the order was cancelled.
class OrderStatusTimeline extends StatelessWidget {
  final StoreOrder order;

  const OrderStatusTimeline({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final steps = [
      _TimelineStep(
        label: 'Criado',
        isCompleted: true,
        isActive: order.status == StoreOrderStatus.pendingPayment,
      ),
      _TimelineStep(
        label: 'Pago',
        isCompleted: order.isPaid,
        isActive: order.status == StoreOrderStatus.paid,
      ),
      _TimelineStep(
        label: 'Preparando',
        isCompleted:
            order.status == StoreOrderStatus.preparing ||
            order.status == StoreOrderStatus.ready ||
            order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.preparing,
      ),
      _TimelineStep(
        label: 'Pronto',
        isCompleted:
            order.status == StoreOrderStatus.ready ||
            order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.ready,
      ),
      _TimelineStep(
        label: 'Entregue',
        isCompleted: order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.delivered,
      ),
    ];

    if (order.status == StoreOrderStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.errorLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.xCircle, color: AppTheme.error),
            const SizedBox(width: 12),
            Text(
              'Pedido cancelado',
              style: AppTheme.titleSmall.copyWith(color: AppTheme.error),
            ),
          ],
        ),
      );
    }

    return Row(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isLast = index == steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: step.isCompleted || step.isActive
                            ? AppTheme.primary
                            : AppTheme.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: step.isCompleted
                          ? const Icon(
                              LucideIcons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : step.isActive
                          ? Container(
                              margin: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.label,
                      style: AppTheme.labelSmall.copyWith(
                        color: step.isCompleted || step.isActive
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontWeight: step.isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        fontSize: 9,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Container(
                  width: 16,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 20),
                  color: step.isCompleted
                      ? AppTheme.primary
                      : AppTheme.surfaceVariant,
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TimelineStep {
  final String label;
  final bool isCompleted;
  final bool isActive;

  _TimelineStep({
    required this.label,
    required this.isCompleted,
    required this.isActive,
  });
}
