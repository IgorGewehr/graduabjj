import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme.dart';

/// A row of KPI / stat-card placeholders shown while metrics load.
class SkeletonStats extends StatelessWidget {
  /// Number of stat cards rendered side by side.
  final int count;

  /// Height of each stat card.
  final double height;

  /// Outer padding around the row.
  final EdgeInsetsGeometry padding;

  const SkeletonStats({
    super.key,
    this.count = 2,
    this.height = 80,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: List.generate(count, (index) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: index == 0 ? 0 : 6,
                right: index == count - 1 ? 0 : 6,
              ),
              child: _StatSkeletonCard(height: height),
            ),
          );
        }),
      ),
    );
  }
}

class _StatSkeletonCard extends StatelessWidget {
  final double height;

  const _StatSkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      // vertical 12 (não 16): com altura 72 o conteúdo (20+8+12=40) + 32 de
      // padding estourava a Column por 2px.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: 60,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: 90,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
