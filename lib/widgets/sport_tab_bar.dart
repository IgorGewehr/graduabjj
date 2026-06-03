import 'package:flutter/material.dart';

import '../core/sports.dart';
import '../core/theme.dart';

/// A horizontal selector of [ChoiceChip]s, one per sport. Pure presentational:
/// it owns no state and reads nothing from Firestore — the caller passes the
/// [sports] to show, the [selected] sport, and an [onSelected] callback.
///
/// Visuals mirror the per-sport selector in `student_graduation_screen.dart`
/// (rounded ChoiceChip, no checkmark, muted background when unselected) so it
/// feels native across the portal. The selected chip is filled with the sport's
/// color from [sportChipColors].
///
/// When there is one sport or fewer, it renders nothing — a single-sport
/// academy has no use for a selector.
class SportTabBar extends StatelessWidget {
  /// The sports to render, in display order. One chip per entry.
  final List<SportId> sports;

  /// The currently selected sport (its chip is filled/highlighted).
  final SportId selected;

  /// Called with the tapped sport when the user picks a chip.
  final ValueChanged<SportId> onSelected;

  /// When true (default) the row scrolls horizontally if it overflows.
  final bool scrollable;

  const SportTabBar({
    super.key,
    required this.sports,
    required this.selected,
    required this.onSelected,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    if (sports.length <= 1) return const SizedBox.shrink();

    final chips = <Widget>[];
    for (var i = 0; i < sports.length; i++) {
      final s = sports[i];
      final sel = s == selected;
      final color = sportChipColors[s] ?? AppTheme.primary;
      if (i > 0) chips.add(const SizedBox(width: 8));
      chips.add(
        ChoiceChip(
          label: Text(getSport(s).label),
          selected: sel,
          onSelected: (_) {
            if (s != selected) onSelected(s);
          },
          labelStyle: AppTheme.labelSmall.copyWith(
            color: sel ? Colors.white : AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
          selectedColor: color,
          backgroundColor: AppTheme.surfaceVariant,
          showCheckmark: false,
        ),
      );
    }

    final row = Row(mainAxisSize: MainAxisSize.min, children: chips);

    return SizedBox(
      height: 44,
      child: scrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 8),
              child: row,
            )
          : Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: row,
            ),
    );
  }
}
