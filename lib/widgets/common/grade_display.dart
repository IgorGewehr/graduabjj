import 'package:flutter/material.dart';

import '../../core/sports.dart';
import 'arm_band_display.dart';
import 'belt_badge.dart';

// ============================================
// GradeDisplay — Unified wrapper
// Renders the correct visual for any sport:
//   belt    -> BeltDisplay / BeltBadge
//   armband -> ArmBandDisplay
//   none    -> SizedBox.shrink() (e.g. Boxing)
// ============================================

enum GradeDisplaySize { small, medium, large }

class GradeDisplay extends StatelessWidget {
  final SportId sportId;
  final String grade;
  final int stripes;
  final GradeDisplaySize size;
  final bool showLabel;

  const GradeDisplay({
    super.key,
    required this.sportId,
    required this.grade,
    this.stripes = 0,
    this.size = GradeDisplaySize.medium,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final sport = sports[sportId];
    if (sport == null) return const SizedBox.shrink();

    switch (sport.gradeSystem) {
      case GradeSystem.belt:
        return BeltBadge(
          belt: grade,
          stripes: stripes,
          size: _toBeltSize(size),
          showLabel: showLabel,
        );

      case GradeSystem.armband:
        return ArmBandDisplay(
          grade: grade,
          stripes: stripes,
          size: _toArmBandSize(size),
          showLabel: showLabel,
        );

      case GradeSystem.none:
        return const SizedBox.shrink();
    }
  }

  static BeltSize _toBeltSize(GradeDisplaySize size) {
    switch (size) {
      case GradeDisplaySize.small:
        return BeltSize.small;
      case GradeDisplaySize.medium:
        return BeltSize.medium;
      case GradeDisplaySize.large:
        return BeltSize.large;
    }
  }

  static ArmBandSize _toArmBandSize(GradeDisplaySize size) {
    switch (size) {
      case GradeDisplaySize.small:
        return ArmBandSize.small;
      case GradeDisplaySize.medium:
        return ArmBandSize.medium;
      case GradeDisplaySize.large:
        return ArmBandSize.large;
    }
  }
}

// ============================================
// GradeDisplayLarge — Large grade with label (for profile)
// ============================================
class GradeDisplayLarge extends StatelessWidget {
  final SportId sportId;
  final String grade;
  final int stripes;
  final String? label;

  const GradeDisplayLarge({
    super.key,
    required this.sportId,
    required this.grade,
    this.stripes = 0,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final sport = sports[sportId];
    if (sport == null || sport.gradeSystem == GradeSystem.none) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GradeDisplay(
          sportId: sportId,
          grade: grade,
          stripes: stripes,
          size: GradeDisplaySize.large,
          showLabel: true,
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            label!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF666666),
            ),
          ),
        ],
      ],
    );
  }
}
