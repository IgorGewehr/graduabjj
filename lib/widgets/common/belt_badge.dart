import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Belt Badge - Displays a belt with stripes
class BeltBadge extends StatelessWidget {
  final String belt;
  final int stripes;
  final double size;

  const BeltBadge({
    super.key,
    required this.belt,
    this.stripes = 0,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final beltColor = AppTheme.getBeltColor(belt);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: beltColor,
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(
          color: belt == 'white' ? AppTheme.divider : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: beltColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: stripes > 0
          ? Stack(
              alignment: Alignment.center,
              children: [
                // Stripes indicator at the bottom
                Positioned(
                  bottom: size * 0.15,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      stripes,
                      (index) => Container(
                        width: size * 0.12,
                        height: size * 0.35,
                        margin: EdgeInsets.symmetric(horizontal: size * 0.02),
                        decoration: BoxDecoration(
                          color: _getStripeColor(belt),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
    );
  }

  Color _getStripeColor(String belt) {
    // Kids belts have white stripes on solid belts, or black/white stripes on combo belts
    if (belt.contains('-white')) return Colors.white;
    if (belt.contains('-black')) return Colors.black;

    // Adult belts
    switch (belt) {
      case 'white':
      case 'blue':
      case 'purple':
      case 'brown':
        return Colors.white;
      case 'black':
        return const Color(0xFFDC2626); // Red stripes for black belt
      default:
        return Colors.white;
    }
  }
}

/// Large belt display with label
class BeltDisplay extends StatelessWidget {
  final String belt;
  final int stripes;
  final String? label;

  const BeltDisplay({
    super.key,
    required this.belt,
    this.stripes = 0,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BeltBadge(
          belt: belt,
          stripes: stripes,
          size: 64,
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label!,
            style: AppTheme.labelMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (stripes > 0) ...[
          const SizedBox(height: 4),
          Text(
            '$stripes ${stripes == 1 ? 'grau' : 'graus'}',
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Belt progress indicator
class BeltProgressIndicator extends StatelessWidget {
  final String currentBelt;
  final int currentStripes;
  final int attendanceCount;
  final int attendancesPerStripe;

  const BeltProgressIndicator({
    super.key,
    required this.currentBelt,
    required this.currentStripes,
    required this.attendanceCount,
    this.attendancesPerStripe = 50,
  });

  @override
  Widget build(BuildContext context) {
    // stripesFromAttendance can be used in future for auto-graduation calculation
    // final stripesFromAttendance = attendanceCount ~/ attendancesPerStripe;
    final attendancesToNextStripe =
        attendancesPerStripe - (attendanceCount % attendancesPerStripe);
    final progress = (attendanceCount % attendancesPerStripe) / attendancesPerStripe;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BeltBadge(
                belt: currentBelt,
                stripes: currentStripes,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getBeltLabel(currentBelt),
                      style: AppTheme.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$currentStripes ${currentStripes == 1 ? 'grau' : 'graus'} • $attendanceCount presencas',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Proximo grau',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          '${attendanceCount % attendancesPerStripe}/$attendancesPerStripe',
                          style: AppTheme.labelSmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: AppTheme.surfaceVariant,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Faltam $attendancesToNextStripe presencas',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getBeltLabel(String belt) {
    final labels = {
      'white': 'Faixa Branca',
      'blue': 'Faixa Azul',
      'purple': 'Faixa Roxa',
      'brown': 'Faixa Marrom',
      'black': 'Faixa Preta',
      'grey': 'Faixa Cinza',
      'yellow': 'Faixa Amarela',
      'orange': 'Faixa Laranja',
      'green': 'Faixa Verde',
    };

    // Handle combo belts
    final baseBelt = belt.split('-').first;
    return labels[baseBelt] ?? 'Faixa ${belt.capitalize()}';
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
