import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../services/self_records_service.dart';
import '../../services/services.dart';
import '../../widgets/polish/polish.dart';
import '../../widgets/sport_tab_bar.dart';

/// Belt progressions provider for timeline
final studentBeltProgressionsProvider =
    FutureProvider.family<List<BeltProgression>, String>((
      ref,
      studentId,
    ) async {
      final currentUser = await ref.watch(currentUserProvider.future);
      if (currentUser?.academyId == null) return [];

      final service = BeltProgressionService(currentUser!.academyId!);
      return await service.getByStudent(studentId);
    });

// ── Self-record helpers for the portal timeline ──────────────────────────────

/// Holds the student's auto-declared records needed to merge them into the
/// timeline and resolve edit/delete operations.
class _SelfTimelineRecords {
  final String academyId;
  final String studentId;
  final List<SelfGraduation> grads;
  final List<SelfCompetition> comps;
  const _SelfTimelineRecords({
    required this.academyId,
    required this.studentId,
    required this.grads,
    required this.comps,
  });
}

/// Loads self-declared graduations + competitions for the portal timeline.
/// Invalidated whenever a self record is mutated.
final _selfTimelineRecordsProvider =
    FutureProvider.autoDispose.family<_SelfTimelineRecords?, String>((
  ref,
  studentId,
) async {
  final user = await ref.watch(currentUserProvider.future);
  final academyId = user?.academyId;
  if (academyId == null || academyId.isEmpty) return null;
  final svc = SelfRecordsService(academyId);
  final grads = await svc.listGraduations(studentId);
  final comps = await svc.listCompetitions(studentId);
  return _SelfTimelineRecords(
    academyId: academyId,
    studentId: studentId,
    grads: grads,
    comps: comps,
  );
});

/// Actions available on a self-declared timeline event.
enum _SelfTimelineAction { editDate, delete }

/// Shows the options bottom sheet for a self-declared timeline event and
/// executes the chosen action (edit date or delete) via [SelfRecordsService].
/// Invalidates [_selfTimelineRecordsProvider] and [studentAchievementsProvider]
/// after any successful mutation so the timeline rebuilds.
Future<void> _showSelfTimelineOptions(
  BuildContext context,
  WidgetRef ref,
  TimelineEvent event,
  _SelfTimelineRecords self,
) async {
  final isGrad = event.type == TimelineEventType.graduation ||
      event.type == TimelineEventType.stripe;
  final docId = event.selfDocId;
  if (docId == null) return;

  // Show options sheet.
  final action = await showModalBottomSheet<_SelfTimelineAction>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(LucideIcons.calendar,
                size: 20, color: AppTheme.textPrimary),
            title: Text(
              'Editar data',
              style: AppTheme.bodyMedium
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            onTap: () => Navigator.pop(c, _SelfTimelineAction.editDate),
          ),
          ListTile(
            leading: Icon(LucideIcons.trash2, size: 20, color: Colors.red),
            title: Text(
              'Excluir',
              style: AppTheme.bodyMedium.copyWith(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => Navigator.pop(c, _SelfTimelineAction.delete),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (action == null) return;
  if (!context.mounted) return;

  if (action == _SelfTimelineAction.editDate) {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: event.date.isAfter(now) ? now : event.date,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked == null) return;
    try {
      final svc = SelfRecordsService(self.academyId);
      if (isGrad) {
        await svc.updateGraduation(
            self.studentId, docId, {'date': Timestamp.fromDate(picked)});
      } else {
        await svc.updateCompetition(
            self.studentId, docId, {'date': Timestamp.fromDate(picked)});
      }
      ref.invalidate(_selfTimelineRecordsProvider(self.studentId));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nao foi possivel atualizar a data.')),
        );
      }
    }
  } else if (action == _SelfTimelineAction.delete) {
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          isGrad ? 'Excluir graduacao?' : 'Excluir competicao?',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Este registro auto-declarado sera removido da sua linha do '
          'tempo. Nao da para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child:
                const Text('Excluir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final svc = SelfRecordsService(self.academyId);
      if (isGrad) {
        await svc.deleteGraduation(self.studentId, docId);
      } else {
        await svc.deleteCompetition(self.studentId, docId);
      }
      ref.invalidate(_selfTimelineRecordsProvider(self.studentId));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nao foi possivel excluir agora.')),
        );
      }
    }
  }
}

/// Timeline Screen - Linha do Tempo with enhanced design
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildEmptyState(
            'Perfil nao vinculado',
            'Sua conta nao esta vinculada a um aluno',
          );
        }

        final achievementsAsync = ref.watch(
          studentAchievementsProvider(student.id),
        );
        final progressionsAsync = ref.watch(
          studentBeltProgressionsProvider(student.id),
        );
        final attendanceCountAsync = ref.watch(
          studentAttendanceCountProvider(student.id),
        );
        final medalCountAsync = ref.watch(
          studentMedalCountProvider(student.id),
        );
        final competitionsAsync = ref.watch(
          studentCompetitionResultsProvider(student.id),
        );
        final academyInfo = ref.watch(currentAcademyInfoProvider);
        final selfRecords = ref.watch(
          _selfTimelineRecordsProvider(student.id),
        ).valueOrNull;

        // Multi-sport students can filter the timeline by sport. Single-sport
        // students never see the selector and get the full, unfiltered list.
        final sports = student.getSports();
        final showSportFilter = sports.length > 1;
        final selectedSport =
            ref.watch(selectedSportProvider('timeline')) ??
            student.getPrimarySport();

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            ref.invalidate(currentStudentProvider);
            ref.invalidate(studentAchievementsProvider(student.id));
            ref.invalidate(studentBeltProgressionsProvider(student.id));
            ref.invalidate(studentAttendanceCountProvider(student.id));
            ref.invalidate(studentMedalCountProvider(student.id));
            ref.invalidate(studentCompetitionResultsProvider(student.id));
            ref.invalidate(_selfTimelineRecordsProvider(student.id));
          },
          child: CustomScrollView(
            slivers: [
              // Academy indicator for multi-academy users
              const SliverToBoxAdapter(child: _AcademyIndicator()),

              // Header
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // Journey Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _JourneyCard(
                    student: student,
                    // When a multi-sport student is filtering the timeline, the
                    // belt chip reflects the selected sport so header and list
                    // agree. The training/time/competition counts remain global
                    // (no per-sport provider) and are labelled "no total".
                    selectedSport: showSportFilter ? selectedSport : null,
                    attendanceCountAsync: attendanceCountAsync,
                    medalCountAsync: medalCountAsync,
                    competitionsAsync: competitionsAsync,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Per-sport filter (multi-sport students only). SportTabBar
              // hides itself when sports.length <= 1, but we also gate the
              // padding so single-sport layout is pixel-identical.
              if (showSportFilter)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: SportTabBar(
                      sports: sports,
                      selected: selectedSport,
                      onSelected: (s) => ref
                          .read(selectedSportProvider('timeline').notifier)
                          .state = s,
                    ),
                  ),
                ),

              // Timeline
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildTimeline(
                    student,
                    achievementsAsync,
                    progressionsAsync,
                    academyInfo?.name,
                    showSportFilter ? selectedSport : null,
                    selfRecords: selfRecords,
                    onSelfOptions: selfRecords == null
                        ? null
                        : (event) => _showSelfTimelineOptions(
                              context,
                              ref,
                              event,
                              selfRecords,
                            ),
                  ),
                ),
              ),

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
      loading: () => _buildLoadingState(),
      error: (e, s) => _buildEmptyState(
        'Erro ao carregar',
        'Nao foi possivel carregar sua linha do tempo',
      ),
    );
  }

  Widget _buildTimeline(
    Student student,
    AsyncValue<List<Achievement>> achievementsAsync,
    AsyncValue<List<BeltProgression>> progressionsAsync,
    String? academyName,
    SportId? sportFilter, {
    _SelfTimelineRecords? selfRecords,
    void Function(TimelineEvent)? onSelfOptions,
  }) {
    final achievements = achievementsAsync.valueOrNull ?? [];
    final progressions = progressionsAsync.valueOrNull ?? [];

    // Build the unified, ordered+filtered timeline via the shared motor
    // (lib/services/timeline_builder.dart). Self records are merged inline and
    // tagged isSelf=true so the UI can offer edit/delete affordances.
    final filteredEvents = buildTimelineEvents(
      student: student,
      achievements: achievements,
      progressions: progressions,
      academyName: academyName,
      sportFilter: sportFilter,
      selfGraduations: selfRecords?.grads ?? [],
      selfCompetitions: selfRecords?.comps ?? [],
    );

    if (filteredEvents.isEmpty) {
      return _buildTimelineEmptyState();
    }

    // Reverse for display (newest at top, oldest at bottom)
    final reversedEvents = filteredEvents.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Sua Jornada',
          style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w700),
        ).fadeInQuick(),
        const SizedBox(height: 20),
        ...reversedEvents.asMap().entries.map((entry) {
          final index = entry.key;
          final event = entry.value;
          final isLast = index == reversedEvents.length - 1;
          return _TimelineItem(
            event: event,
            isLast: isLast,
            onOptions: (event.isSelf && onSelfOptions != null)
                ? () => onSelfOptions(event)
                : null,
          ).entrance(index: index);
        }),
      ],
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: PolishSkeleton.shimmer(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 150,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (index < 2)
                        Container(
                          width: 3,
                          height: 60,
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.clock, size: 48, color: AppTheme.textDisabled),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineEmptyState() {
    return const PolishedEmptyState(
      icon: LucideIcons.clock,
      title: 'Sua linha do tempo esta vazia',
      subtitle: 'Suas conquistas aparecerao aqui conforme voce progride',
    );
  }
}

/// Journey Card with Stats Carousel
class _JourneyCard extends StatefulWidget {
  final Student student;
  /// Sport selected in the timeline's SportTabBar, or null for single-sport /
  /// unfiltered. Drives the belt chip so it matches the filtered list below.
  final SportId? selectedSport;
  final AsyncValue<int> attendanceCountAsync;
  final AsyncValue<Map<String, int>> medalCountAsync;
  final AsyncValue<List<Competition>> competitionsAsync;

  const _JourneyCard({
    required this.student,
    this.selectedSport,
    required this.attendanceCountAsync,
    required this.medalCountAsync,
    required this.competitionsAsync,
  });

  @override
  State<_JourneyCard> createState() => _JourneyCardState();
}

class _JourneyCardState extends State<_JourneyCard> {
  final PageController _pageController = PageController(viewportFraction: 0.85);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatTrainingTime(DateTime startDate) {
    final now = DateTime.now();
    final difference = now.difference(startDate);
    final years = difference.inDays ~/ 365;
    final months = (difference.inDays % 365) ~/ 30;

    if (years > 0 && months > 0) {
      return '$years a ${months}m';
    } else if (years > 0) {
      return '$years ano${years > 1 ? 's' : ''}';
    } else if (months > 0) {
      return '$months mes${months > 1 ? 'es' : ''}';
    } else {
      final days = difference.inDays;
      return '$days dia${days > 1 ? 's' : ''}';
    }
  }

  Color _getBeltDisplayColor(String belt, {SportId sportId = SportId.bjj}) {
    final c = getGradeColor(sportId, belt);
    return c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
  }

  @override
  Widget build(BuildContext context) {
    final attendanceCount = widget.attendanceCountAsync.valueOrNull ?? 0;
    final medalStats =
        widget.medalCountAsync.valueOrNull ??
        {'gold': 0, 'silver': 0, 'bronze': 0, 'total': 0};
    final competitions = widget.competitionsAsync.valueOrNull ?? [];

    // Belt chip reflects the selected sport (when filtering) so the header
    // agrees with the sport-filtered timeline below. Falls back to the primary
    // sport's legacy belt for single-sport / unfiltered views.
    final beltSport = widget.selectedSport ?? widget.student.getPrimarySport();
    final beltGrade = widget.student.getGrade(beltSport);
    final beltValue = beltGrade?.currentGrade ?? widget.student.currentBelt;
    final beltStripes =
        beltGrade?.currentStripes ?? widget.student.currentStripes;
    final beltColor = _getBeltDisplayColor(beltValue, sportId: beltSport);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stats Carousel
        SizedBox(
          height: 100,
          child: PageView(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _currentPage = page),
            children: [
              _JourneyCarouselCard(
                icon: LucideIcons.award,
                iconColor: beltColor,
                iconBgColor: beltColor.withValues(alpha: 0.15),
                value: getGradeLabel(beltSport, beltValue),
                label: beltStripes > 0
                    ? '$beltStripes grau${beltStripes > 1 ? 's' : ''}'
                    : 'Faixa Atual',
              ),
              _JourneyCarouselCard(
                icon: LucideIcons.dumbbell,
                iconColor: AppTheme.success,
                iconBgColor: AppTheme.successLight,
                value: attendanceCount.toString(),
                // Count is across all sports — label it so the header doesn't
                // imply it's scoped to the selected sport tab.
                label: widget.selectedSport != null ? 'Treinos (total)' : 'Treinos',
              ),
              _JourneyCarouselCard(
                icon: LucideIcons.clock,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
                value: _formatTrainingTime(
                  widget.student.jiujitsuStartDate ?? widget.student.startDate,
                ),
                label: 'Tempo de Tatame',
              ),
              _JourneyCarouselCard(
                icon: LucideIcons.trophy,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFEF3C7),
                value: competitions.length.toString(),
                label: 'Campeonatos',
              ),
            ],
          ),
        ),

        // Dot indicators
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentPage == index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentPage == index
                    ? AppTheme.textPrimary
                    : AppTheme.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),

        // "Pronto para graduação" badge — transient UI state derived from the
        // existing per-sport eligibility provider (no new query, no achievement
        // created). Mirrors the belt-chip sport so it agrees with the filtered
        // timeline below.
        _GraduationReadyBadge(
          studentId: widget.student.id,
          sport: beltSport,
        ),

        // Medal Display
        if ((medalStats['total'] ?? 0) > 0) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MEDALHAS',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if ((medalStats['gold'] ?? 0) > 0)
                      _MedalBadge(
                        icon: Icons.workspace_premium,
                        count: medalStats['gold']!,
                        label: 'Ouro',
                      ),
                    if ((medalStats['silver'] ?? 0) > 0)
                      _MedalBadge(
                        icon: Icons.workspace_premium,
                        count: medalStats['silver']!,
                        label: 'Prata',
                      ),
                    if ((medalStats['bronze'] ?? 0) > 0)
                      _MedalBadge(
                        icon: Icons.workspace_premium,
                        count: medalStats['bronze']!,
                        label: 'Bronze',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "Apto a graduar" badge for the JourneyCard.
///
/// Consumes [studentSportEligibilityProvider] (the same service the portal
/// progress card already reads — no extra query) and, when the student is
/// eligible for the next graduation, shows a transient "Pronto para graduação"
/// badge. This is purely informational UI state: it does NOT create any
/// achievement/doc and writes nothing to Firestore. Hidden while loading, on
/// error, when there's no configured requirement, or when not eligible.
class _GraduationReadyBadge extends ConsumerWidget {
  final String studentId;
  final SportId sport;

  const _GraduationReadyBadge({
    required this.studentId,
    required this.sport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligibility = ref
        .watch(
          studentSportEligibilityProvider(
            (studentId: studentId, sport: sport),
          ),
        )
        .valueOrNull;

    // No data yet, no configured requirement, or not eligible → render nothing.
    if (eligibility == null ||
        eligibility.requiredClasses <= 0 ||
        !eligibility.eligible) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.successLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.partyPopper,
              size: 18,
              color: AppTheme.success,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Pronto para graduação',
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Journey Carousel Card
class _JourneyCarouselCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String value;
  final String label;

  const _JourneyCarouselCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Medal Badge — uses a Material icon so it renders on all platforms/fonts.
class _MedalBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;

  const _MedalBadge({
    required this.icon,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: AppTheme.textPrimary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedCountUp(
                value: count,
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
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

/// Timeline Item with enhanced vertical line
class _TimelineItem extends StatelessWidget {
  final TimelineEvent event;
  final bool isLast;

  /// When non-null the card shows a "more" button that calls this callback.
  /// Only set for self-declared (auto) events that the student can edit/delete.
  final VoidCallback? onOptions;

  const _TimelineItem({
    required this.event,
    required this.isLast,
    this.onOptions,
  });

  Color _getBeltColor(String belt, {SportId sportId = SportId.bjj}) {
    final c = getGradeColor(sportId, belt);
    // Faixas muito claras (branca em qualquer esporte) somem no timeline claro;
    // usa um cinza visível só no indicador, preservando a cor canônica das demais.
    return c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
  }

  _EventConfig _getEventConfig(TimelineEventType type, String? belt) {
    switch (type) {
      case TimelineEventType.graduation:
        final beltColor = _getBeltColor(belt ?? 'white', sportId: event.sportId);
        return _EventConfig(
          icon: LucideIcons.award,
          color: beltColor,
          bgColor: beltColor.withValues(alpha: 0.15),
        );
      case TimelineEventType.stripe:
        return _EventConfig(
          icon: LucideIcons.star,
          color: const Color(0xFFEAB308),
          bgColor: const Color(0xFFFEF9C3),
        );
      case TimelineEventType.competition:
        return _EventConfig(
          icon: LucideIcons.trophy,
          color: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFEF3C7),
        );
      case TimelineEventType.milestone:
        return _EventConfig(
          icon: LucideIcons.target,
          color: const Color(0xFF10B981),
          bgColor: const Color(0xFFD1FAE5),
        );
      case TimelineEventType.start:
        return _EventConfig(
          icon: LucideIcons.flag,
          color: const Color(0xFF2563EB),
          bgColor: const Color(0xFFEFF6FF),
        );
      case TimelineEventType.attendanceStreak:
        // Streak of attendance — warm orange "flame".
        return _EventConfig(
          icon: LucideIcons.flame,
          color: const Color(0xFFEA580C),
          bgColor: const Color(0xFFFFEDD5),
        );
      case TimelineEventType.rankingPosition:
        // Ranking position — amber "trophy".
        return _EventConfig(
          icon: LucideIcons.trophy,
          color: const Color(0xFFD97706),
          bgColor: const Color(0xFFFEF3C7),
        );
      case TimelineEventType.trainingPr:
        // Training personal record — indigo "trending up".
        return _EventConfig(
          icon: LucideIcons.trendingUp,
          color: const Color(0xFF4F46E5),
          bgColor: const Color(0xFFE0E7FF),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _getEventConfig(event.type, event.belt);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator column
          SizedBox(
            width: 44,
            child: Column(
              children: [
                // Icon circle with shadow
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: config.bgColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: config.color, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: config.color.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(config.icon, size: 20, color: config.color),
                ),
                // Gradient vertical line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            config.color.withValues(alpha: 0.6),
                            AppTheme.divider,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Content card
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (event.isSelf) ...[
                        const SizedBox(width: 6),
                        const _AutoBadge(),
                      ],
                      const SizedBox(width: 6),
                      _TypeChip(type: event.type),
                      if (onOptions != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onOptions,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.more_horiz,
                              size: 18,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Description
                  if (event.description != null &&
                      event.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      event.description!,
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],

                  // Belt indicator for graduations
                  if (event.type == TimelineEventType.graduation &&
                      event.belt != null) ...[
                    const SizedBox(height: 12),
                    _BeltIndicator(belt: event.belt!, sportId: event.sportId),
                  ],

                  // Position badge for competitions
                  if (event.type == TimelineEventType.competition &&
                      event.position != null) ...[
                    const SizedBox(height: 12),
                    _PositionBadge(position: event.position!),
                  ],

                  // Academy badge for competitions (shows which academy they represented)
                  if (event.type == TimelineEventType.competition &&
                      event.academyName != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.building2,
                          size: 12,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Lutou por ${event.academyName}',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Date
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 14,
                        color: AppTheme.textDisabled,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat(
                          "d 'de' MMMM 'de' yyyy",
                          'pt_BR',
                        ).format(event.date),
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Type Chip
class _TypeChip extends StatelessWidget {
  final TimelineEventType type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    String label;
    Color bgColor;
    Color textColor;

    switch (type) {
      case TimelineEventType.graduation:
        label = 'Graduacao';
        bgColor = const Color(0xFFEDE9FE);
        textColor = const Color(0xFF7C3AED);
        break;
      case TimelineEventType.stripe:
        label = 'Grau';
        bgColor = const Color(0xFFFEF9C3);
        textColor = const Color(0xFFEAB308);
        break;
      case TimelineEventType.competition:
        label = 'Competicao';
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFF59E0B);
        break;
      case TimelineEventType.milestone:
        label = 'Marco';
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF10B981);
        break;
      case TimelineEventType.start:
        label = 'Inicio';
        bgColor = const Color(0xFFEFF6FF);
        textColor = const Color(0xFF2563EB);
        break;
      case TimelineEventType.attendanceStreak:
        label = 'Sequencia';
        bgColor = const Color(0xFFFFEDD5);
        textColor = const Color(0xFFEA580C);
        break;
      case TimelineEventType.rankingPosition:
        label = 'Ranking';
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFD97706);
        break;
      case TimelineEventType.trainingPr:
        label = 'Recorde';
        bgColor = const Color(0xFFE0E7FF);
        textColor = const Color(0xFF4F46E5);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Small "AUTO" badge shown on self-declared timeline events.
class _AutoBadge extends StatelessWidget {
  const _AutoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppTheme.textSecondary.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        'AUTO',
        style: AppTheme.labelSmall.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

/// Belt Indicator
class _BeltIndicator extends StatelessWidget {
  final String belt;
  final SportId sportId;

  const _BeltIndicator({required this.belt, this.sportId = SportId.bjj});

  Color _getBeltColor(String belt, {SportId sportId = SportId.bjj}) {
    final c = getGradeColor(sportId, belt);
    // Faixas muito claras (branca em qualquer esporte) somem no timeline claro;
    // usa um cinza visível só no indicador, preservando a cor canônica das demais.
    return c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
  }

  @override
  Widget build(BuildContext context) {
    final beltColor = _getBeltColor(belt, sportId: sportId);
    final beltLabel = getGradeLabel(sportId, belt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: beltColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: beltColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 8,
            decoration: BoxDecoration(
              color: beltColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Faixa $beltLabel',
            style: AppTheme.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: beltColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Position Badge — uses Material icons so it renders reliably on all platforms.
class _PositionBadge extends StatelessWidget {
  final String position;

  const _PositionBadge({required this.position});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String label;
    Color color;

    switch (position) {
      case 'gold':
        icon = Icons.workspace_premium;
        label = 'Ouro';
        color = const Color(0xFFD97706);
        break;
      case 'silver':
        icon = Icons.workspace_premium;
        label = 'Prata';
        color = const Color(0xFF6B7280);
        break;
      case 'bronze':
        icon = Icons.workspace_premium;
        label = 'Bronze';
        color = const Color(0xFFB45309);
        break;
      default:
        icon = Icons.military_tech;
        label = 'Participante';
        color = const Color(0xFF10B981);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.textPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Config class for event types
class _EventConfig {
  final IconData icon;
  final Color color;
  final Color bgColor;

  _EventConfig({
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

/// Academy indicator for multi-academy users
class _AcademyIndicator extends ConsumerWidget {
  const _AcademyIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);
    final academyInfo = ref.watch(currentAcademyInfoProvider);

    // Only show if user has multiple academies
    if (!hasMultiple || academyInfo == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jornada em',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  academyInfo.name,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push('/portal/academias'),
            icon: Icon(LucideIcons.arrowRightLeft, size: 14),
            label: const Text('Trocar'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: AppTheme.labelSmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
