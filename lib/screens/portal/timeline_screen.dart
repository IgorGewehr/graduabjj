import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/brand_tokens.dart';
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
enum _SelfTimelineAction { editDate, matches, delete }

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

  // Competition self events can also carry the aluno's key matches (RIVAIS
  // R0 — "confrontos da chave"). Resolve the backing doc up-front so the
  // options sheet can offer the editor with the current match count.
  SelfCompetition? found;
  if (!isGrad) {
    for (final c in self.comps) {
      if (c.id == docId) {
        found = c;
        break;
      }
    }
  }
  final comp = found;

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
          if (comp != null)
            ListTile(
              leading: Icon(LucideIcons.swords,
                  size: 20, color: AppTheme.textPrimary),
              title: Text(
                'Confrontos da chave',
                style: AppTheme.bodyMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              trailing: comp.matches.isEmpty
                  ? null
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Brand.ink.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${comp.matches.length}',
                        style: AppTheme.labelSmall.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: Brand.tabular,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
              onTap: () => Navigator.pop(c, _SelfTimelineAction.matches),
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
  } else if (action == _SelfTimelineAction.matches) {
    if (comp == null) return;
    final edited = await showModalBottomSheet<List<SelfMatch>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _SelfMatchesSheet(comp: comp),
    );
    if (edited == null) return;
    try {
      await SelfRecordsService(self.academyId)
          .setCompetitionMatches(self.studentId, docId, edited);
      ref.invalidate(_selfTimelineRecordsProvider(self.studentId));
      if (context.mounted && edited.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confrontos salvos no seu cartel.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Não foi possível salvar os confrontos.')),
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

              // RIVAIS R0 — "Adversários de chave" (§6.1): head-to-head
              // PRIVADO agregado dos confrontos que o aluno registrou nas
              // próprias competições. Invisível sem >=1 confronto (regra
              // anti-poluição) — o widget colapsa para zero altura.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _RivalsCard(comps: selfRecords?.comps ?? const []),
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

    // Nº de confrontos de chave por competição self (RIVAIS R0) — alimenta a
    // linha discreta "N confrontos na chave" do card. Ausência = zero UI.
    final matchCounts = <String, int>{
      for (final c in selfRecords?.comps ?? const <SelfCompetition>[])
        if (c.matches.isNotEmpty) c.id: c.matches.length,
    };

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
            matchCount: event.selfDocId == null
                ? 0
                : (matchCounts[event.selfDocId] ?? 0),
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

  /// Nº de confrontos de chave registrados nesta competição self (RIVAIS R0).
  /// Zero (o caso de quem não registra) não renderiza NADA.
  final int matchCount;

  const _TimelineItem({
    required this.event,
    required this.isLast,
    this.onOptions,
    this.matchCount = 0,
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

                  // Confrontos da chave (RIVAIS R0) — linha discreta, só
                  // quando o aluno registrou lutas nesta competição.
                  if (event.type == TimelineEventType.competition &&
                      matchCount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.swords,
                          size: 12,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          matchCount == 1
                              ? '1 confronto na chave'
                              : '$matchCount confrontos na chave',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontFeatures: Brand.tabular,
                          ),
                        ),
                      ],
                    ),
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

// ═════════════════════════════════════════════════════════════════════════════
// RIVAIS R0 — "Adversários de chave" (§6.1 da pesquisa de retenção)
//
// O rival NÃO precisa estar no app: o aluno registra os confrontos dos SEUS
// campeonatos (selfCompetitions.matches) e o app agrega um head-to-head
// PRIVADO. Nada do adversário é exposto — é o diário de lutas do próprio
// aluno (esta tela sempre renderiza currentStudentProvider, e todos os
// widgets abaixo são privados do arquivo; a Jornada de visitante em
// public_profile_screen não passa por aqui). Zero backend novo.
// ═════════════════════════════════════════════════════════════════════════════

/// Remove acentos comuns de pt-BR — "João" e "Joao" viram o mesmo adversário
/// na chave de agrupamento do head-to-head.
String _foldDiacritics(String input) {
  const map = <String, String>{
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  final sb = StringBuffer();
  for (final ch in input.split('')) {
    sb.write(map[ch] ?? ch);
  }
  return sb.toString();
}

/// Normalização de nome/equipe para agrupamento: trim, lowercase, espaços
/// colapsados e acentos removidos.
String _normalizeH2H(String s) =>
    _foldDiacritics(s.trim().toLowerCase()).replaceAll(RegExp(r'\s+'), ' ');

/// Um confronto individual + a competição em que aconteceu.
class _H2HBout {
  final SelfCompetition comp;
  final SelfMatch match;
  const _H2HBout(this.comp, this.match);
}

/// Cartel agregado contra um adversário (nome + equipe normalizados).
class _H2HEntry {
  /// Grafia mais recente do nome/equipe (a que o aluno digitou por último).
  final String name;
  final String? team;

  /// Confrontos, mais recente primeiro.
  final List<_H2HBout> bouts;

  const _H2HEntry({required this.name, this.team, required this.bouts});

  int get wins => bouts.where((b) => b.match.result == 'win').length;
  int get losses => bouts.where((b) => b.match.result == 'loss').length;
  int get draws => bouts.where((b) => b.match.result == 'draw').length;
  _H2HBout get last => bouts.first;

  /// Verde à frente, blood atrás, ash empatado — a cor do placar.
  Color get scoreColor => wins > losses
      ? AppTheme.success
      : losses > wins
          ? Brand.blood
          : Brand.ash;
}

/// Agrega os confrontos de todas as competições self num cartel por
/// adversário, ordenado por nº de confrontos (rivalidade nasce de confronto
/// REPETIDO — Kilduff, §4.2) e, no empate, pelo reencontro mais recente.
List<_H2HEntry> _aggregateH2H(List<SelfCompetition> comps) {
  final byKey = <String, List<_H2HBout>>{};
  for (final c in comps) {
    for (final m in c.matches) {
      if (m.opponentName.trim().isEmpty) continue;
      final key =
          '${_normalizeH2H(m.opponentName)}|${_normalizeH2H(m.opponentTeam ?? '')}';
      byKey.putIfAbsent(key, () => []).add(_H2HBout(c, m));
    }
  }
  if (byKey.isEmpty) return const [];

  final entries = <_H2HEntry>[];
  for (final bouts in byKey.values) {
    bouts.sort((a, b) => b.comp.date.compareTo(a.comp.date));
    final latest = bouts.first.match;
    entries.add(_H2HEntry(
      name: latest.opponentName.trim(),
      team: (latest.opponentTeam?.trim().isNotEmpty ?? false)
          ? latest.opponentTeam!.trim()
          : null,
      bouts: bouts,
    ));
  }
  entries.sort((a, b) {
    final byTotal = b.bouts.length.compareTo(a.bouts.length);
    if (byTotal != 0) return byTotal;
    return b.last.comp.date.compareTo(a.last.comp.date);
  });
  return entries;
}

String _resultLabel(String r) =>
    r == 'win' ? 'Vitória' : (r == 'loss' ? 'Derrota' : 'Empate');

Color _resultColor(String r) => r == 'win'
    ? AppTheme.success
    : (r == 'loss' ? Brand.blood : Brand.ash);

/// Card "ADVERSÁRIOS DE CHAVE" da Jornada.
///
/// Regra anti-poluição: sem nenhum confronto registrado o widget colapsa para
/// zero altura — quem não compete nunca vê esta seção. Mostra até 5
/// adversários; tap numa linha abre o histórico de confrontos.
class _RivalsCard extends StatelessWidget {
  final List<SelfCompetition> comps;

  const _RivalsCard({required this.comps});

  @override
  Widget build(BuildContext context) {
    final entries = _aggregateH2H(comps);
    if (entries.isEmpty) return const SizedBox.shrink();

    final totalBouts = entries.fold<int>(0, (s, e) => s + e.bouts.length);
    final visible = entries.take(5).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Row(
                children: [
                  Icon(LucideIcons.swords, size: 14, color: Brand.ink),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ADVERSÁRIOS DE CHAVE',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  Text(
                    totalBouts == 1 ? '1 CONFRONTO' : '$totalBouts CONFRONTOS',
                    style: AppTheme.labelSmall.copyWith(
                      color: Brand.ash,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      fontFeatures: Brand.tabular,
                    ),
                  ),
                ],
              ),
            ),
            ...visible.map((e) => _RivalRow(entry: e)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Linha de um adversário no card: nome · equipe + placar "VOCÊ W × L" +
/// microtexto do último confronto. Tap → histórico completo.
class _RivalRow extends StatelessWidget {
  final _H2HEntry entry;

  const _RivalRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final last = entry.last;
    final subtitle =
        'Último: ${last.comp.name} · ${last.comp.date.year} · '
        '${_resultLabel(last.match.result)}';

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _showRivalBoutsSheet(context, entry);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.team == null
                        ? entry.name
                        : '${entry.name} · ${entry.team}',
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _H2HScoreline(entry: entry),
          ],
        ),
      ),
    );
  }
}

/// Placar "VOCÊ 2 × 1" — números w900 tabulares na cor do estado (verde à
/// frente, blood atrás, ash empate). Empates aparecem como sufixo discreto.
class _H2HScoreline extends StatelessWidget {
  final _H2HEntry entry;

  /// Tamanho dos números (permite reuso no sheet de histórico em escala maior).
  final double scale;

  const _H2HScoreline({required this.entry, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    final color = entry.scoreColor;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'VOCÊ ',
            style: AppTheme.labelSmall.copyWith(
              color: Brand.ash,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              fontSize: (AppTheme.labelSmall.fontSize ?? 11) * scale,
            ),
          ),
          TextSpan(
            text: '${entry.wins}',
            style: AppTheme.titleMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontFeatures: Brand.tabular,
              fontSize: (AppTheme.titleMedium.fontSize ?? 16) * scale,
            ),
          ),
          TextSpan(
            text: ' × ',
            style: AppTheme.bodySmall.copyWith(
              color: Brand.ash,
              fontWeight: FontWeight.w700,
              fontSize: (AppTheme.bodySmall.fontSize ?? 12) * scale,
            ),
          ),
          TextSpan(
            text: '${entry.losses}',
            style: AppTheme.titleMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontFeatures: Brand.tabular,
              fontSize: (AppTheme.titleMedium.fontSize ?? 16) * scale,
            ),
          ),
          if (entry.draws > 0)
            TextSpan(
              text: ' · ${entry.draws}E',
              style: AppTheme.labelSmall.copyWith(
                color: Brand.ash,
                fontWeight: FontWeight.w700,
                fontFeatures: Brand.tabular,
                fontSize: (AppTheme.labelSmall.fontSize ?? 11) * scale,
              ),
            ),
        ],
      ),
    );
  }
}

/// Histórico de confrontos contra UM adversário: evento, ano e resultado de
/// cada luta (leitura pura — a edição vive no sheet da própria competição).
void _showRivalBoutsSheet(BuildContext context, _H2HEntry entry) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(c).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name.toUpperCase(),
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.team != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.team!,
                      style: AppTheme.labelSmall.copyWith(
                        color: Brand.ash,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  _H2HScoreline(entry: entry, scale: 1.4),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            const Divider(height: 17, thickness: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: entry.bouts.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  thickness: 1,
                  indent: 20,
                  endIndent: 20,
                  color: AppTheme.divider,
                ),
                itemBuilder: (_, i) {
                  final bout = entry.bouts[i];
                  final color = _resultColor(bout.match.result);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              _resultLabel(bout.match.result)[0],
                              style: AppTheme.labelSmall.copyWith(
                                color: color,
                                fontWeight: FontWeight.w900,
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
                                bout.comp.name.isNotEmpty
                                    ? bout.comp.name
                                    : 'Competição',
                                style: AppTheme.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${bout.comp.date.year}',
                                style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontFeatures: Brand.tabular,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _resultLabel(bout.match.result),
                          style: AppTheme.labelSmall.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Rascunho editável de um confronto no sheet de captura.
class _MatchDraft {
  final TextEditingController name;
  final TextEditingController team;

  /// `'win' | 'loss' | 'draw'` — null enquanto o aluno não escolher.
  String? result;

  _MatchDraft({String name = '', String team = '', this.result})
      : name = TextEditingController(text: name),
        team = TextEditingController(text: team);

  void dispose() {
    name.dispose();
    team.dispose();
  }
}

/// Sheet de captura "CONFRONTOS DA CHAVE" de uma competição self-declarada.
///
/// Aberto pelas opções (…) do evento na Jornada. Devolve a lista editada via
/// `Navigator.pop` (null = cancelou); o caller persiste. Máximo de 8
/// confrontos por competição. Linhas totalmente em branco são ignoradas.
class _SelfMatchesSheet extends StatefulWidget {
  final SelfCompetition comp;

  const _SelfMatchesSheet({required this.comp});

  @override
  State<_SelfMatchesSheet> createState() => _SelfMatchesSheetState();
}

class _SelfMatchesSheetState extends State<_SelfMatchesSheet> {
  static const int _maxMatches = 8;

  late final List<_MatchDraft> _drafts = widget.comp.matches
      .map((m) => _MatchDraft(
            name: m.opponentName,
            team: m.opponentTeam ?? '',
            result: m.result,
          ))
      .toList();

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  /// Mensagem de validação exibida INLINE (um sheet modal cobre o SnackBar
  /// do Scaffold raiz). Limpa em qualquer interação.
  String? _error;

  void _addDraft() {
    if (_drafts.length >= _maxMatches) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _drafts.add(_MatchDraft());
    });
  }

  void _removeDraft(int index) {
    final removed = _drafts[index];
    setState(() {
      _error = null;
      _drafts.removeAt(index);
    });
    // Dispose after the frame so the fields aren't torn down mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  void _save() {
    final matches = <SelfMatch>[];
    for (final d in _drafts) {
      final name = d.name.text.trim();
      final team = d.team.text.trim();
      if (name.isEmpty && team.isEmpty) continue; // linha em branco: ignora
      if (name.isEmpty) {
        setState(
            () => _error = 'Cada confronto precisa do nome do adversário.');
        return;
      }
      if (d.result == null) {
        setState(() =>
            _error = 'Marca o resultado (V, E ou D) de cada confronto.');
        return;
      }
      matches.add(SelfMatch(
        opponentName: name,
        opponentTeam: team.isEmpty ? null : team,
        result: d.result!,
      ));
    }
    Navigator.pop(context, matches);
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textDisabled),
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: AppTheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Brand.ink, width: 1.4),
        ),
      );

  Widget _draftCard(int index) {
    final draft = _drafts[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.bone,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'CONFRONTO ${index + 1}',
                  style: AppTheme.labelSmall.copyWith(
                    color: Brand.ash,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _removeDraft(index),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(LucideIcons.x, size: 16, color: Brand.ash),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: draft.name,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            style: AppTheme.bodyMedium,
            decoration: _fieldDecoration('Nome do adversário'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.team,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            style: AppTheme.bodyMedium,
            decoration: _fieldDecoration('Equipe (opcional)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ResultChoiceChip(
                  label: 'VITÓRIA',
                  color: AppTheme.success,
                  selected: draft.result == 'win',
                  onTap: () => setState(() {
                    _error = null;
                    draft.result = 'win';
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ResultChoiceChip(
                  label: 'EMPATE',
                  color: Brand.ash,
                  selected: draft.result == 'draw',
                  onTap: () => setState(() {
                    _error = null;
                    draft.result = 'draw';
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ResultChoiceChip(
                  label: 'DERROTA',
                  color: Brand.blood,
                  selected: draft.result == 'loss',
                  onTap: () => setState(() {
                    _error = null;
                    draft.result = 'loss';
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
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
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.swords, size: 16, color: Brand.ink),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'CONFRONTOS DA CHAVE',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.comp.name} · ${widget.comp.date.year}',
                      style: AppTheme.labelSmall.copyWith(
                        color: Brand.ash,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_drafts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Registre seus confrontos e monte seu cartel '
                            'de lutas.',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ...List.generate(_drafts.length, _draftCard),
                      if (_drafts.length < _maxMatches)
                        OutlinedButton.icon(
                          onPressed: _addDraft,
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: Text(
                            'ADICIONAR CONFRONTO',
                            style: AppTheme.labelSmall.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Brand.ink,
                            side: BorderSide(color: AppTheme.divider),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Máximo de 8 confrontos por competição.',
                            style: AppTheme.labelSmall.copyWith(
                              color: Brand.ash,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    _error!,
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Brand.ink,
                      foregroundColor: Brand.bone,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'SALVAR CONFRONTOS',
                      style: AppTheme.labelMedium.copyWith(
                        color: Brand.bone,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip de resultado V/E/D do sheet de captura.
class _ResultChoiceChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ResultChoiceChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 38,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : AppTheme.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTheme.labelSmall.copyWith(
              color: selected ? color : Brand.ash,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
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
