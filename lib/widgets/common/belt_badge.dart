import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../polish/polish.dart';

// ============================================
// Belt Labels
// ============================================
const Map<String, String> _beltLabels = {
  // Adult belts
  'white': 'Branca',
  'blue': 'Azul',
  'purple': 'Roxa',
  'brown': 'Marrom',
  'black': 'Preta',
  // Kids belts
  'grey': 'Cinza',
  'grey-white': 'Cinza/Branca',
  'grey-black': 'Cinza/Preta',
  'yellow': 'Amarela',
  'yellow-white': 'Amarela/Branca',
  'yellow-black': 'Amarela/Preta',
  'orange': 'Laranja',
  'orange-white': 'Laranja/Branca',
  'orange-black': 'Laranja/Preta',
  'green': 'Verde',
  'green-white': 'Verde/Branca',
  'green-black': 'Verde/Preta',
  // Above-black master ranks (coral / red)
  'coral': 'Coral',
  'red-black': 'Coral',
  'red-white': 'Vermelha/Branca',
  'red': 'Vermelha',
};

String getBeltLabel(String belt) => _beltLabels[belt] ?? belt;
// '-white' suffix and judô's 'coral' (kōhaku) draw a white middle stripe;
// '-black' suffix draws a black middle stripe (e.g. BJJ/Luta Livre coral).
bool _hasWhiteStripe(String belt) => belt.endsWith('-white') || belt == 'coral';
bool _hasBlackStripe(String belt) => belt.endsWith('-black');

// ============================================
// Size Configurations (matching webapp exactly)
// ============================================
enum BeltSize { small, medium, large }

class _BeltSizeConfig {
  final double width;
  final double height;
  final double tipWidth;
  final double stripeWidth;
  final double stripeGap;
  final double fontSize;

  const _BeltSizeConfig({
    required this.width,
    required this.height,
    required this.tipWidth,
    required this.stripeWidth,
    required this.stripeGap,
    required this.fontSize,
  });
}

const Map<BeltSize, _BeltSizeConfig> _sizeConfig = {
  BeltSize.small: _BeltSizeConfig(
    width: 70,
    height: 16,
    tipWidth: 20,
    stripeWidth: 2.5,
    stripeGap: 1.5,
    fontSize: 10,
  ),
  BeltSize.medium: _BeltSizeConfig(
    width: 100,
    height: 22,
    tipWidth: 28,
    stripeWidth: 3.5,
    stripeGap: 2,
    fontSize: 11,
  ),
  BeltSize.large: _BeltSizeConfig(
    width: 140,
    height: 28,
    tipWidth: 38,
    stripeWidth: 5,
    stripeGap: 2.5,
    fontSize: 13,
  ),
};

// ============================================
// BeltBadge - Realistic belt display (matching webapp)
// ============================================
class BeltBadge extends StatelessWidget {
  final String belt;
  final int stripes;
  final BeltSize size;
  final bool showLabel;

  /// When provided, the belt color is resolved from this sport's grade ladder
  /// (GradeDefinition), so non-BJJ belts render their true color. When null,
  /// falls back to the legacy BJJ-oriented theme color map.
  final SportId? sportId;

  const BeltBadge({
    super.key,
    required this.belt,
    this.stripes = 0,
    this.size = BeltSize.medium,
    this.showLabel = false,
    this.sportId,
  });

  @override
  Widget build(BuildContext context) {
    final config = _sizeConfig[size]!;
    // Resolve the belt color from the sport's grade ladder when the sport is
    // known (so non-BJJ belts like Luta Livre DAN 'black-red' and the coral
    // ranks render their true color, and the blue/etc. shades match the
    // graduation screen); fall back to the legacy theme map otherwise.
    final beltColor = sportId != null
        ? getGradeColor(sportId!, belt)
        : AppTheme.getBeltColor(belt);
    final beltLabel = getBeltLabel(belt);
    final isWhiteBelt = belt == 'white';
    final isBlackBelt = belt == 'black';
    final showWhiteStripe = _hasWhiteStripe(belt);
    final showBlackStripe = _hasBlackStripe(belt);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Belt container — a restrained scale-in plus a single shimmer pass on
        // first appearance gives the belt a subtle "earned" sheen.
        Container(
          width: config.width,
          height: config.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
            border: isWhiteBelt
                ? Border.all(color: AppTheme.divider, width: 1)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Belt body (colored part)
              Expanded(
                child: Container(
                  color: beltColor,
                  child: Stack(
                    children: [
                      // White stripe in middle (for combo belts like grey-white)
                      if (showWhiteStripe)
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              height: config.height * 0.2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      // Black stripe in middle (for combo belts like grey-black)
                      if (showBlackStripe)
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              height: config.height * 0.2,
                              color: const Color(0xFF171717),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Black tip (ponta preta) - FULL HEIGHT
              Container(
                width: config.tipWidth,
                height: config.height, // Full height
                color: isBlackBelt
                    ? const Color(0xFF2D2D2D)
                    : const Color(0xFF171717),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: stripes > 0
                      ? List.generate(
                          stripes,
                          (index) => Container(
                            width: config.stripeWidth,
                            height: config.height * 0.65, // Stripes at ~65% of belt height
                            margin: EdgeInsets.symmetric(
                              horizontal: config.stripeGap / 2,
                            ),
                            decoration: BoxDecoration(
                              color: isBlackBelt
                                  ? const Color(0xFFDC2626) // Red for black belt
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        )
                      : [],
                ),
              ),
            ],
          ),
        )
            .animate()
            .scale(
              begin: const Offset(0.92, 0.92),
              end: const Offset(1, 1),
              duration: PolishMotion.normal,
              curve: Curves.easeOutBack,
            )
            .shimmer(
              delay: PolishMotion.normal,
              duration: const Duration(milliseconds: 900),
              color: Colors.white.withValues(alpha: 0.35),
            ),

        // Label below
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            stripes > 0 ? '$beltLabel $stripes°' : beltLabel,
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

// ============================================
// BeltDisplay - Large belt with label (for profile)
// ============================================
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
          size: BeltSize.large,
          showLabel: true,
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            label!,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================
// Compact Belt Chip (for lists, tables)
// ============================================
class BeltChip extends StatelessWidget {
  final String belt;
  final int stripes;

  const BeltChip({
    super.key,
    required this.belt,
    this.stripes = 0,
  });

  @override
  Widget build(BuildContext context) {
    final beltColor = AppTheme.getBeltColor(belt);
    final beltLabel = getBeltLabel(belt);
    final isWhiteBelt = belt == 'white';
    final isBlackBelt = belt == 'black';
    final isLightBelt = belt == 'white' || belt == 'yellow';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: beltColor,
        borderRadius: BorderRadius.circular(4),
        border: isWhiteBelt
            ? Border.all(color: AppTheme.divider, width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            beltLabel.length >= 3
                ? beltLabel.substring(0, 3).toUpperCase()
                : beltLabel.toUpperCase(),
            style: TextStyle(
              color: isLightBelt ? const Color(0xFF171717) : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
          if (stripes > 0) ...[
            const SizedBox(width: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                stripes,
                (index) => Container(
                  width: 3,
                  height: 8,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: isBlackBelt
                        ? const Color(0xFFDC2626)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: isWhiteBelt
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 1,
                            ),
                          ]
                        : null,
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

// ============================================
// Belt progress indicator
// ============================================
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
    final attendancesToNextStripe =
        attendancesPerStripe - (attendanceCount % attendancesPerStripe);
    final progress = (attendanceCount % attendancesPerStripe) / attendancesPerStripe;
    final beltLabel = getBeltLabel(currentBelt);

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
                size: BeltSize.large,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Faixa $beltLabel',
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
          Column(
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
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
