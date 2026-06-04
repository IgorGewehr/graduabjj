import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../screens/portal/timeline_screen.dart'
    show studentBeltProgressionsProvider;
import '../../services/timeline_builder.dart';
import '../polish/polish.dart';

/// "Ultimos Marcos" — a compact, horizontal strip of the student's three most
/// recent journey milestones, surfaced on the portal home right below the
/// graduation progress card.
///
/// PURELY ADDITIVE / VISUAL. It only reads academy-scoped providers the portal
/// already observes ([studentAchievementsProvider],
/// [studentBeltProgressionsProvider], [currentAcademyInfoProvider],
/// [selectedSportProvider]) — zero new query, Cloud Function, collection or
/// gating. It reuses the shared timeline motor ([buildTimelineEvents]) so the
/// ordering/synthesis matches the full timeline screen exactly, then takes the
/// newest three. Tapping any chip (or the header) navigates to the full
/// timeline — it never performs an action.
///
/// Renders [SizedBox.shrink] while data is loading or when there are no
/// milestones, so the home layout stays pixel-identical for students with an
/// empty journey.
class RecentMilestonesStrip extends ConsumerWidget {
  const RecentMilestonesStrip({super.key});

  static const int _maxChips = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(currentStudentProvider).valueOrNull;
    if (student == null) return const SizedBox.shrink();

    final achievements =
        ref.watch(studentAchievementsProvider(student.id)).valueOrNull;
    final progressions =
        ref.watch(studentBeltProgressionsProvider(student.id)).valueOrNull;

    // Wait for both sources before deciding — avoids flashing a partial strip
    // (e.g. only the synthetic "start" event) before achievements resolve.
    if (achievements == null || progressions == null) {
      return const SizedBox.shrink();
    }

    final academyName =
        ref.watch(currentAcademyInfoProvider.select((info) => info?.name));

    // Mirror the home/timeline sport filter for multi-sport students so the
    // strip shows marcos of the currently selected modality.
    final sports = student.getSports();
    final sportFilter = sports.length > 1
        ? (ref.watch(selectedSportProvider('home')) ?? student.getPrimarySport())
        : null;

    final events = buildTimelineEvents(
      student: student,
      achievements: achievements,
      progressions: progressions,
      academyName: academyName,
      sportFilter: sportFilter,
    );

    // The builder always synthesizes a "Inicio da Jornada" start marker. On its
    // own that is not a meaningful "milestone", so we only surface the strip
    // when the student has earned at least one real event beyond the start.
    final hasRealMilestone =
        events.any((e) => e.type != TimelineEventType.start);
    if (!hasRealMilestone) return const SizedBox.shrink();

    // Newest first, capped at three.
    final recent = events.reversed.take(_maxChips).toList(growable: false);
    if (recent.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — tappable shortcut to the full timeline.
          Pressable(
            onTap: () => context.go('/portal/linha-do-tempo'),
            haptic: false,
            child: Row(
              children: [
                const Icon(
                  LucideIcons.sparkles,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Ultimos marcos',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.1,
                  ),
                ),
                const Spacer(),
                Text(
                  'Ver tudo',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: 14,
                  color: AppTheme.primary,
                ),
              ],
            ),
          ).fadeInQuick(),
          const SizedBox(height: 12),
          // Horizontal strip of milestone chips with staggered entrance.
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: recent.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return _MilestoneChip(
                  event: recent[index],
                  onTap: () => context.go('/portal/linha-do-tempo'),
                ).entrance(index: index);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A single milestone chip: an icon badge, the event title and its formatted
/// date, wrapped in the standard [PolishCard] press feedback.
class _MilestoneChip extends StatelessWidget {
  final TimelineEvent event;
  final VoidCallback onTap;

  const _MilestoneChip({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(event);

    return SizedBox(
      width: 168,
      child: PolishCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: visual.bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(visual.icon, size: 18, color: visual.color),
            ),
            const SizedBox(height: 10),
            Text(
              event.title,
              style: AppTheme.labelMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat("d MMM yyyy", 'pt_BR').format(event.date),
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Icon + color mapping for each timeline event type. Mirrors the full
  /// timeline screen's `_getEventConfig` so a marco looks consistent wherever
  /// it appears.
  _ChipVisual _visualFor(TimelineEvent e) {
    switch (e.type) {
      case TimelineEventType.graduation:
        final c = _beltColor(e.belt ?? 'white', e.sportId);
        return _ChipVisual(
          LucideIcons.award,
          c,
          c.withValues(alpha: 0.15),
        );
      case TimelineEventType.stripe:
        return const _ChipVisual(
          LucideIcons.star,
          Color(0xFFEAB308),
          Color(0xFFFEF9C3),
        );
      case TimelineEventType.competition:
        return const _ChipVisual(
          LucideIcons.trophy,
          Color(0xFFF59E0B),
          Color(0xFFFEF3C7),
        );
      case TimelineEventType.milestone:
        return const _ChipVisual(
          LucideIcons.target,
          Color(0xFF10B981),
          Color(0xFFD1FAE5),
        );
      case TimelineEventType.start:
        return const _ChipVisual(
          LucideIcons.flag,
          Color(0xFF2563EB),
          Color(0xFFEFF6FF),
        );
      case TimelineEventType.attendanceStreak:
        return const _ChipVisual(
          LucideIcons.flame,
          Color(0xFFEA580C),
          Color(0xFFFFEDD5),
        );
      case TimelineEventType.rankingPosition:
        return const _ChipVisual(
          LucideIcons.trophy,
          Color(0xFFD97706),
          Color(0xFFFEF3C7),
        );
      case TimelineEventType.trainingPr:
        return const _ChipVisual(
          LucideIcons.trendingUp,
          Color(0xFF4F46E5),
          Color(0xFFE0E7FF),
        );
    }
  }

  Color _beltColor(String belt, SportId sportId) {
    final c = getGradeColor(sportId, belt);
    // Very light belts (white) wash out on a light chip; clamp to a visible
    // grey, matching the timeline screen.
    return c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
  }
}

class _ChipVisual {
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _ChipVisual(this.icon, this.color, this.bgColor);
}
