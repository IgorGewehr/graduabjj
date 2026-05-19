import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../services/services.dart';

/// Stat Card Widget
class GraduationStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const GraduationStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTheme.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Eligible Student Card
class EligibleStudentCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onPromote;

  const EligibleStudentCard({
    super.key,
    required this.data,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    final eligibility = data['eligibility'] as EligibilityResult;
    final currentBelt = data['currentBelt'] as String;
    final currentStripes = data['currentStripes'] as int;
    final totalClasses = data['totalClasses'] as int;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _getBeltColor(currentBelt),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    (data['fullName'] as String).substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: currentBelt == 'white' ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['fullName'] as String,
                      style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildBeltIndicator(currentBelt, currentStripes),
                        const SizedBox(width: 8),
                        Icon(LucideIcons.clipboardCheck, size: 14, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '$totalClasses treinos',
                          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.checkCircle2, color: AppTheme.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    eligibility.message,
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.success),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPromote,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.award, size: 18),
                  const SizedBox(width: 8),
                  const Text('Graduar'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeltIndicator(String belt, int stripes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _getBeltColor(belt),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getBeltShortLabel(belt),
            style: TextStyle(
              fontSize: 10,
              color: belt == 'white' ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (stripes > 0) ...[
            const SizedBox(width: 4),
            Text(
              '• $stripes',
              style: TextStyle(
                fontSize: 10,
                color: belt == 'white' ? Colors.black : Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getBeltColor(String belt) {
    return getGradeColor(SportId.bjj, belt);
  }

  String _getBeltShortLabel(String belt) {
    final label = getGradeLabel(SportId.bjj, belt);
    return label.length >= 2 ? label.substring(0, 2).toUpperCase() : label.toUpperCase();
  }
}

/// Promotion History Card
class PromotionHistoryCard extends StatelessWidget {
  final BeltProgression promotion;

  const PromotionHistoryCard({super.key, required this.promotion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _getBeltColor(promotion.newBelt),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              promotion.isBeltChange ? LucideIcons.award : LucideIcons.star,
              color: promotion.newBelt == 'white' ? Colors.black : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  promotion.isBeltChange
                      ? 'Faixa ${_getBeltLabel(promotion.newBelt)}'
                      : '${promotion.newStripes}° Grau',
                  style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR').format(promotion.promotionDate),
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${promotion.totalClasses} treinos',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  String _getBeltLabel(String belt) {
    return getGradeLabel(SportId.bjj, belt);
  }

  Color _getBeltColor(String belt) {
    return getGradeColor(SportId.bjj, belt);
  }
}

/// Belt Distribution Bar
class BeltDistributionBar extends StatelessWidget {
  final String belt;
  final int count;
  final double percentage;

  const BeltDistributionBar({
    super.key,
    required this.belt,
    required this.count,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _getBeltColor(belt),
                    borderRadius: BorderRadius.circular(4),
                    border: belt == 'white'
                        ? Border.all(color: AppTheme.divider)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getBeltLabel(belt),
                  style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            Text(
              '$count (${percentage.toStringAsFixed(0)}%)',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: AppTheme.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(_getBeltDisplayColor(belt)),
            minHeight: 10,
          ),
        ),
      ],
    );
  }

  String _getBeltLabel(String belt) {
    return getGradeLabel(SportId.bjj, belt);
  }

  Color _getBeltColor(String belt) {
    return getGradeColor(SportId.bjj, belt);
  }

  Color _getBeltDisplayColor(String belt) {
    final color = getGradeColor(SportId.bjj, belt);
    if (belt == 'white') return const Color(0xFF9E9E9E);
    return color;
  }
}
