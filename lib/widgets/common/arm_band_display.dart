import 'package:flutter/material.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';

// ============================================
// ArmBandDisplay — Muay Thai Prajied (armband)
// Visual: wider-than-tall horizontal band with
// optional "tip" color on each end (stripes = tips shown).
// ============================================

enum ArmBandSize { small, medium, large }

class _ArmBandSizeConfig {
  final double width;
  final double height;
  final double tipWidth;
  final double fontSize;

  const _ArmBandSizeConfig({
    required this.width,
    required this.height,
    required this.tipWidth,
    required this.fontSize,
  });
}

const Map<ArmBandSize, _ArmBandSizeConfig> _sizeConfig = {
  ArmBandSize.small: _ArmBandSizeConfig(
    width: 80,
    height: 14,
    tipWidth: 14,
    fontSize: 10,
  ),
  ArmBandSize.medium: _ArmBandSizeConfig(
    width: 120,
    height: 20,
    tipWidth: 20,
    fontSize: 11,
  ),
  ArmBandSize.large: _ArmBandSizeConfig(
    width: 160,
    height: 26,
    tipWidth: 28,
    fontSize: 13,
  ),
};

class ArmBandDisplay extends StatelessWidget {
  final String grade;
  final int stripes;
  final ArmBandSize size;
  final bool showLabel;

  const ArmBandDisplay({
    super.key,
    required this.grade,
    this.stripes = 0,
    this.size = ArmBandSize.medium,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final config = _sizeConfig[size]!;

    // Look up grade from Muay Thai sport definition
    final gradeDef = getGradeDefinition(SportId.muaythai, grade);
    final bodyColor = gradeDef?.color ?? const Color(0xFFF5F5F5);
    final tipColor = gradeDef?.tipColor ?? const Color(0xFFDC2626);
    final gradeLabel = gradeDef?.label ?? grade;
    // Light bands (white, prata, ouro, "...e branca") need a border to stand
    // out from the page; keyed off luminance so both systems are covered.
    final isWhite = bodyColor.computeLuminance() > 0.7;

    // A grade with its own tipColor IS a "ponta" rank (e.g. "Branca ponta
    // vermelha") — show that tip regardless of stripes. Stripes add the
    // classic 1–2 tips on top for the simpler solid grades.
    final intrinsicTip = gradeDef?.tipColor != null;
    final showLeftTip = stripes >= 1;
    final showRightTip = intrinsicTip || stripes >= 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: config.width,
          height: config.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(config.height / 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
            border: isWhite
                ? Border.all(color: AppTheme.divider, width: 1)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Left tip
              if (showLeftTip)
                Container(
                  width: config.tipWidth,
                  decoration: BoxDecoration(
                    color: tipColor,
                  ),
                ),

              // Body
              Expanded(
                child: Container(
                  color: bodyColor,
                  child: Stack(
                    children: [
                      // Center stitch / fold line
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            height: 1.5,
                            color: isWhite
                                ? Colors.black.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Right tip
              if (showRightTip)
                Container(
                  width: config.tipWidth,
                  decoration: BoxDecoration(
                    color: tipColor,
                  ),
                ),
            ],
          ),
        ),

        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            stripes > 0
                ? '$gradeLabel $stripes ponta${stripes > 1 ? 's' : ''}'
                : gradeLabel,
            style: TextStyle(
              fontSize: config.fontSize,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
