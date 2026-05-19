import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../services/billing_reminder_service.dart';

Color billingStageColor(BillingStage stage) {
  switch (stage) {
    case BillingStage.d0:
      return AppTheme.primary;
    case BillingStage.d1:
      return AppTheme.warning;
    case BillingStage.d3:
      return Colors.orange;
    case BillingStage.d7:
      return Colors.deepOrange;
    case BillingStage.d15:
      return AppTheme.error;
    case BillingStage.d30:
      return Colors.red.shade900;
  }
}

class BillingTabBar extends StatelessWidget {
  const BillingTabBar({
    super.key,
    required this.tabController,
    required this.stageCount,
    required this.onTap,
  });

  final TabController tabController;
  final int Function(BillingStage) stageCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      child: TabBar(
        controller: tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppTheme.textPrimary,
        unselectedLabelColor: AppTheme.textSecondary,
        indicatorColor: AppTheme.primary,
        labelStyle: AppTheme.titleSmall,
        unselectedLabelStyle: AppTheme.bodySmall,
        onTap: (_) => onTap(),
        tabs: BillingStage.values.map((stage) {
          final count = stageCount(stage);
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(stage.label),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: billingStageColor(stage),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: AppTheme.labelSmall.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
