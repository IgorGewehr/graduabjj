import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/billing_reminder_service.dart';

class BillingStatsHeader extends StatelessWidget {
  const BillingStatsHeader({
    super.key,
    required this.stats,
    required this.currencyFormat,
  });

  final CollectionStats stats;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _BillingStatCard(
            icon: LucideIcons.alertCircle,
            label: 'Total Vencido',
            value: currencyFormat.format(stats.totalOverdueAmount),
            color: AppTheme.error,
          ),
          const SizedBox(width: 12),
          _BillingStatCard(
            icon: LucideIcons.users,
            label: 'Inadimplentes',
            value: '${stats.totalStudentsOverdue}',
            color: AppTheme.warning,
          ),
          const SizedBox(width: 12),
          _BillingStatCard(
            icon: LucideIcons.trendingUp,
            label: 'Taxa Recuperacao',
            value: '${stats.recoveryRate.toStringAsFixed(1)}%',
            color: AppTheme.success,
          ),
          const SizedBox(width: 12),
          _BillingStatCard(
            icon: LucideIcons.clock,
            label: 'Media Dias Atraso',
            value: '${stats.averageDaysOverdue} dias',
            color: AppTheme.info,
          ),
        ],
      ),
    );
  }
}

class _BillingStatCard extends StatelessWidget {
  const _BillingStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.labelSmall.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTheme.titleLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
