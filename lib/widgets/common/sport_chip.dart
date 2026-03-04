import 'package:flutter/material.dart';

import '../../core/sports.dart';

// ============================================
// Sport color map — subtle background per sport
// ============================================
const Map<SportId, ({Color bg, Color text})> _sportChipColorMap = {
  SportId.bjj: (bg: Color(0x221E40AF), text: Color(0xFF1E40AF)),
  SportId.muaythai: (bg: Color(0x22DC2626), text: Color(0xFFDC2626)),
  SportId.karate: (bg: Color(0x227C3AED), text: Color(0xFF7C3AED)),
  SportId.judo: (bg: Color(0x22EA580C), text: Color(0xFFEA580C)),
  SportId.kickboxing: (bg: Color(0x2216A34A), text: Color(0xFF16A34A)),
  SportId.boxing: (bg: Color(0x22171717), text: Color(0xFF374151)),
};

// ============================================
// SportChip — small badge showing sport label
// ============================================

enum SportChipVariant { short, full }

enum SportChipSize { xs, sm }

class SportChip extends StatelessWidget {
  final SportId sportId;
  final SportChipVariant variant;
  final SportChipSize size;

  const SportChip({
    super.key,
    required this.sportId,
    this.variant = SportChipVariant.short,
    this.size = SportChipSize.sm,
  });

  @override
  Widget build(BuildContext context) {
    final sport = sports[sportId];
    if (sport == null) return const SizedBox.shrink();

    final colors = _sportChipColorMap[sportId]!;
    final label = variant == SportChipVariant.short
        ? sport.labelShort
        : sport.label;

    final isXs = size == SportChipSize.xs;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isXs ? 4 : 6,
        vertical: isXs ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colors.text.withValues(alpha: 0.27),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.text,
          fontWeight: FontWeight.w700,
          fontSize: isXs ? 9 : 10,
          letterSpacing: 0.5,
          height: 1,
        ),
      ),
    );
  }
}
