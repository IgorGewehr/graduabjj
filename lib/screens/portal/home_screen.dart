import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/navigation/nav_catalog.dart';
import '../../core/navigation/nav_resolver.dart';
import '../../core/theme.dart';
import '../../models/academy_event.dart';
import '../../models/student.dart';
import '../../providers/portal_providers.dart';
import '../../providers/providers.dart';
import '../../providers/selected_academy_provider.dart';
import '../../core/sports.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/animated_belt.dart';
import '../../widgets/common/belt_badge.dart' show BeltSize;
import '../../widgets/polish/polish.dart';
import '../../widgets/portal/home_hero_card.dart';
import '../../widgets/portal/gamification_section.dart';
import '../../widgets/skeletons/skeletons.dart';
import '../../widgets/sport_tab_bar.dart';

/// Home Screen - Portal do Aluno (New Layout)
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final PageController _statsPageController = PageController(
    viewportFraction: 0.85,
  );
  int _currentStatsPage = 0;

  @override
  void dispose() {
    _statsPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final student = ref.watch(currentStudentProvider);

    final studentId = student.valueOrNull?.id;

    final effectiveDisplayName =
        (currentUser.valueOrNull?.displayName.isNotEmpty == true)
            ? currentUser.valueOrNull!.displayName
            : (FirebaseAuth.instance.currentUser?.displayName?.isNotEmpty ==
                    true
                ? FirebaseAuth.instance.currentUser!.displayName!
                : 'Aluno');

    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () async {
        // Sprint 6 — tactile pulse so the user feels the pull-to-refresh
        // before async work begins.
        HapticFeedback.mediumImpact();
        ref.invalidate(currentUserProvider);
        ref.invalidate(currentStudentProvider);
        ref.invalidate(upcomingCompetitionsProvider);
        if (studentId != null) {
          ref.invalidate(studentAttendanceCountProvider(studentId));
          ref.invalidate(studentMedalCountProvider(studentId));
          ref.invalidate(studentStreakProvider(studentId));
          ref.invalidate(studentMonthlyAttendanceProvider(studentId));
          ref.invalidate(studentNextClassProvider(studentId));
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header with belt badge
            student.when(
              data: (s) {
                if (s == null) {
                  return _WelcomeHeader(
                    userName: effectiveDisplayName,
                  );
                }
                final primarySport = s.getPrimarySport();
                // Sports without a graduation system (e.g. musculação, boxe)
                // have no belt/grade — show the plain header instead.
                if (sports[primarySport]?.gradeSystem == GradeSystem.none) {
                  return _WelcomeHeader(userName: s.displayName.isNotEmpty ? s.displayName : effectiveDisplayName);
                }
                return _WelcomeHeaderWithBelt(
                  student: s,
                  userName: s.displayName.isNotEmpty ? s.displayName : effectiveDisplayName,
                  sports: s.getSports(),
                  primarySport: primarySport,
                );
              },
              loading: () => _WelcomeHeader(
                userName: effectiveDisplayName,
              ),
              error: (_, __) => _WelcomeHeader(
                userName: effectiveDisplayName,
              ),
            ),

            // Academy indicator for multi-academy users
            const _AcademyIndicator(),

            const SizedBox(height: 24),

            // Hero do Dia — one prioritized, additive CTA (check-in window →
            // next class countdown → musculação → streak). Purely visual: only
            // reads providers the home already observes and never triggers an
            // aula check-in directly (it only navigates).
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: HomeHeroCard(studentId: s.id),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // Stats Carousel
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                return _StatsCarousel(
                  student: s,
                  pageController: _statsPageController,
                  currentPage: _currentStatsPage,
                  onPageChanged: (page) {
                    setState(() => _currentStatsPage = page);
                  },
                );
              },
              loading: () => _buildStatsLoading(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // Graduation progress (only when academy opted-in + visibility on)
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                return _GraduationProgressCard(student: s);
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // Gamificação (A4): meta do mês + ranking + conquistas recentes.
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                return GamificationSection(student: s);
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            // Dynamic Cards Section
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                return _DynamicCardsSection(
                  studentId: s.id,
                  onTap: (path) => context.go(path),
                );
              },
              loading: () => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonCard(height: 96, showAvatar: true),
                  SizedBox(height: 12),
                  SkeletonStats(count: 2, height: 96),
                  SizedBox(height: 12),
                  SkeletonCard(height: 80, showAvatar: true),
                ],
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            // Quick-access grid — the LAST thing on the home. Surfaces the
            // features actually enabled for this academy/student, reusing the
            // exact portal catalog gating (no duplicated gate logic).
            const _QuickAccessSection(),

            const SizedBox(height: 80), // Bottom padding for nav bar
          ],
        ),
      ),
    );
  }

  Widget _buildStatsLoading() {
    return const SkeletonStats(count: 2, height: 140);
  }
}

/// Welcome header with greeting
class _WelcomeHeader extends StatelessWidget {
  final String userName;

  const _WelcomeHeader({required this.userName});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    // Greeting + first name on a SINGLE line ("Boa noite, Igor").
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: AppTheme.headlineSmall.copyWith(color: AppTheme.textPrimary),
        children: [
          TextSpan(
            text: '$_greeting, ',
            style: AppTheme.headlineSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: userName.split(' ').first,
            style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ).fadeInQuick();
  }
}

/// Welcome header with belt badge inline.
///
/// For multi-sport students it also surfaces a compact "{n} modalidades" pill
/// next to the belt chip; tapping it reveals a [SportTabBar] row below the
/// greeting, bound to `selectedSportProvider("home")`. The belt chip is
/// reactive: it follows the selected sport, recomputing the grade from
/// [student] so picking a modality actually updates the belt/stripes shown.
/// Single-sport (or zero graded sports) students see neither the pill nor the
/// selector, so the layout is pixel-identical to before.
class _WelcomeHeaderWithBelt extends ConsumerStatefulWidget {
  final dynamic student;
  final String userName;
  final List<SportId> sports;
  final SportId primarySport;

  const _WelcomeHeaderWithBelt({
    required this.student,
    required this.userName,
    required this.sports,
    required this.primarySport,
  });

  @override
  ConsumerState<_WelcomeHeaderWithBelt> createState() =>
      _WelcomeHeaderWithBeltState();
}

class _WelcomeHeaderWithBeltState
    extends ConsumerState<_WelcomeHeaderWithBelt> {
  bool _selectorOpen = false;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    final multiSport = widget.sports.length > 1;

    // The belt chip follows the sport selected in the tab bar (defaulting to
    // the primary sport), so picking a modality recomputes the grade shown.
    final selectedSport =
        ref.watch(selectedSportProvider('home')) ?? widget.primarySport;
    final grade = widget.student.getGrade(selectedSport);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Greeting + first name on a SINGLE line ("Boa noite, Igor"), with the
        // multi-sport pill (when applicable) trailing on the same row.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: AppTheme.headlineSmall.copyWith(
                    color: AppTheme.textPrimary,
                  ),
                  children: [
                    TextSpan(
                      text: '$_greeting, ',
                      style: AppTheme.headlineSmall.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: widget.userName.split(' ').first,
                      style: AppTheme.headlineSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (multiSport) ...[
              const SizedBox(width: 8),
              _MultiSportPill(
                count: widget.sports.length,
                expanded: _selectorOpen,
                onTap: () => setState(() => _selectorOpen = !_selectorOpen),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // Belt in evidence — the morph animation sweeps from the first grade up
        // to the student's current grade on entering the home, in the sport's
        // own color ladder (BJJ belts, Muay Thai prajied, etc.). Keyed by
        // sport+grade so switching modalidade re-runs the morph for the new
        // grade.
        AnimatedBelt(
          key: ValueKey(
            '${selectedSport.name}-${grade?.currentGrade ?? 'white'}-${grade?.currentStripes ?? 0}',
          ),
          belt: grade?.currentGrade ?? 'white',
          stripes: grade?.currentStripes ?? 0,
          sportId: selectedSport,
          muaythaiVariant:
              ref.watch(academySettingsProvider).valueOrNull?.muaythaiGradeSystem,
          size: BeltSize.large,
          highlight: true,
        ),
        if (selectedSport != SportId.bjj) ...[
          const SizedBox(height: 8),
          Text(
            getGradeLabel(selectedSport, grade?.currentGrade ?? 'white'),
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (multiSport && _selectorOpen) ...[
          const SizedBox(height: 12),
          SportTabBar(
            sports: widget.sports,
            selected: selectedSport,
            onSelected: (s) =>
                ref.read(selectedSportProvider('home').notifier).state = s,
          ),
        ],
      ],
    );
  }
}

/// Compact, minimalist pill announcing how many sports the student trains.
/// Doubles as the toggle for the home sport selector — a chevron flips when
/// the selector is open.
class _MultiSportPill extends StatelessWidget {
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  const _MultiSportPill({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count modalidades',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 14,
                color: AppTheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stats Carousel with 3 cards + dot indicators
class _StatsCarousel extends ConsumerWidget {
  final dynamic student;
  final PageController pageController;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  const _StatsCarousel({
    required this.student,
    required this.pageController,
    required this.currentPage,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceCountAsync = ref.watch(
      studentAttendanceCountProvider(student.id),
    );
    final medalCountAsync = ref.watch(studentMedalCountProvider(student.id));

    // Calculate months on the mat
    final startDate = student.jiujitsuStartDate ?? student.startDate;
    final now = DateTime.now();
    final monthsOnMat =
        (now.year - startDate.year) * 12 + (now.month - startDate.month);

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PageView(
            controller: pageController,
            onPageChanged: onPageChanged,
            children: [
              // Training count card
              attendanceCountAsync.when(
                data: (count) => StatTile(
                  emoji: '🔥',
                  value: count.toString(),
                  countValue: count,
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
                loading: () => StatTile(
                  emoji: '🔥',
                  value: '...',
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
                error: (_, __) => StatTile(
                  emoji: '🔥',
                  value: '-',
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
              ).entrance(index: 0),

              // Months on mat card
              StatTile(
                emoji: '📅',
                value: monthsOnMat > 0 ? monthsOnMat.toString() : '0',
                countValue: monthsOnMat > 0 ? monthsOnMat : 0,
                label: 'Meses de Tatame',
                sublabel: 'Tempo de jornada',
                color: AppTheme.info,
              ).entrance(index: 1),

              // Medals card — the source counts only podium finishes
              // (gold/silver/bronze), so the label matches the value.
              medalCountAsync.when(
                data: (medals) {
                  final total = medals['total'] ?? 0;
                  return StatTile(
                    emoji: '🏆',
                    value: total.toString(),
                    countValue: total,
                    label: 'Medalhas',
                    sublabel: 'Pódios conquistados',
                    color: Colors.purple,
                  );
                },
                loading: () => StatTile(
                  emoji: '🏆',
                  value: '...',
                  label: 'Medalhas',
                  sublabel: 'Pódios conquistados',
                  color: Colors.purple,
                ),
                error: (_, __) => StatTile(
                  emoji: '🏆',
                  value: '0',
                  label: 'Medalhas',
                  sublabel: 'Pódios conquistados',
                  color: Colors.purple,
                ),
              ).entrance(index: 2),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: currentPage == index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: currentPage == index
                    ? AppTheme.textPrimary
                    : AppTheme.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Dynamic Cards Section with real data
class _DynamicCardsSection extends ConsumerWidget {
  final String studentId;
  final void Function(String path) onTap;

  const _DynamicCardsSection({required this.studentId, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcomingCompetitionsAsync = ref.watch(upcomingCompetitionsProvider);
    // Jornal headline visibility — admins can hide the student feed. Loading/null
    // resolves to true so legacy academies never flicker the tile hidden.
    final journalVisible = ref.watch(
      academySettingsProvider.select(
        (s) => s.valueOrNull?.journalVisibleToStudents ?? true,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Check-in (aula E musculação), "próxima aula" e streak/presenças vivem
        // exclusivamente no HomeHeroCard (fonte única, gateado por matrícula) e
        // no carrossel de stats — nada disso é duplicado aqui.

        // Next Competition Card
        upcomingCompetitionsAsync.when(
          data: (competitions) {
            final next = competitions.isNotEmpty ? competitions.first : null;
            return _NextCompetitionCard(
              competition: next,
              onTap: () => onTap('/portal/competicoes'),
            );
          },
          loading: () => _NextCompetitionCard(
            competition: null,
            isLoading: true,
            onTap: () => onTap('/portal/competicoes'),
          ),
          error: (_, __) => _NextCompetitionCard(
            competition: null,
            onTap: () => onTap('/portal/competicoes'),
          ),
        ).entrance(index: 2),

        // Jornal da Academia — minimalist headline (news/seminars live here).
        // Hidden when the academy turned off student visibility.
        if (journalVisible) const _JornalHeadline(),

        // Upcoming Events (calendar-focused: only postType==event)
        _EventsSection(onTap: onTap),
      ],
    );
  }
}

/// Quick-access grid surfacing the portal features currently enabled for this
/// academy/student. Gating is delegated 1:1 to [resolvePortalCatalog] (the same
/// resolver consumed by [PortalShell]'s "Menu" sheet), so a feature only ever
/// appears here when it would also appear in the menu — no duplicated gate
/// logic. Each tile deep-links to the corresponding portal route.
class _QuickAccessSection extends ConsumerWidget {
  const _QuickAccessSection();

  /// Subset of the portal catalog surfaced as quick-access shortcuts. We only
  /// promote the discovery-worthy destinations (ranking, treinos, vídeos, loja,
  /// financeiro, jornal, evolução, modalidades) — not every menu entry — while
  /// still honoring whatever gate the catalog applies to each.
  static const Set<String> _quickKeys = {
    'portal_ranking',
    'portal_treinos',
    'portal_videos',
    'portal_loja',
    'portal_financeiro',
    'portal_evolucao',
    'portal_modalidades',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final student = ref.watch(currentStudentProvider).valueOrNull;
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    // Same context construction as PortalShell._showMoreMenu — kept in sync so
    // the quick-access grid mirrors the menu's visibility decisions exactly.
    final isKids = student?.category == StudentCategory.kids;

    final studentId = currentUser?.studentId;
    final linkedStudentIds = currentUser?.linkedStudentIds ?? const <String>[];
    final allStudentIds = studentId != null
        ? [studentId, ...linkedStudentIds]
        : linkedStudentIds;
    final monitorIds = settings?.monitorIds ?? const <String>[];
    final isMonitor = allStudentIds.any(monitorIds.contains);
    final hasAttendancePerm =
        currentUser?.hasPermission('attendance:take') == true;

    final studentDocId = student?.id;
    final hasPlan = studentDocId != null &&
        ref.watch(studentPlanProvider(studentDocId)).valueOrNull != null;

    final graduationVisible =
        settings?.graduationProgressVisibleToStudents ?? false;

    final ctx = PortalNavContext(
      isKids: isKids,
      isMonitorOrAttendance: isMonitor || hasAttendancePerm,
      hasPlan: hasPlan,
      storePublished: settings?.storePublished ?? false,
      graduationProgressVisible: graduationVisible,
      multiSport: (student?.getSports().length ?? 0) > 1,
      hasMultipleAcademies: ref.watch(hasMultipleAcademiesProvider),
    );

    final resolved = resolvePortalCatalog(
      catalog: kPortalNavCatalog,
      settings: settings,
      ctx: ctx,
    );

    final entries = resolved
        .where((r) => r.isVisible && _quickKeys.contains(r.entry.key))
        .map((r) => r.entry)
        .toList(growable: false);

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              LucideIcons.zap,
              size: 16,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            const Text(
              'Acessos rapidos',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
          children: [
            for (final (i, entry) in entries.indexed)
              _QuickAccessTile(
                icon: entry.icon,
                label: entry.label,
                onTap: () => context.go(entry.route),
              ).entrance(index: i),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Single quick-access tile: a Lucide icon chip over a short label, wrapped in
/// the standard PolishCard press feedback.
class _QuickAccessTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAccessTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PolishCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppTheme.primary),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Next Competition Card
class _NextCompetitionCard extends StatelessWidget {
  final dynamic competition;
  final bool isLoading;
  final VoidCallback onTap;

  const _NextCompetitionCard({
    required this.competition,
    this.isLoading = false,
    required this.onTap,
  });

  String _formatDate(DateTime date) {
    return DateFormat("d 'de' MMMM", 'pt_BR').format(date);
  }

  int _daysUntil(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    return eventDay.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final hasCompetition = competition != null && !isLoading;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('🏆', style: TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLoading) ...[
                      Text(
                        'Carregando...',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ] else if (hasCompetition) ...[
                      Text(
                        competition.name,
                        style: AppTheme.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _formatDate(competition.date),
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Proximo Campeonato',
                        style: AppTheme.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Nenhum evento proximo',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasCompetition)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_daysUntil(competition.date)} dias',
                    style: AppTheme.labelSmall.copyWith(
                      color: Colors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Academy indicator for multi-academy users - compact version for home screen
class _AcademyIndicator extends ConsumerWidget {
  const _AcademyIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);
    // Only watch the academy name (not the whole AcademyInfo object) so this
    // widget rebuilds solely when the displayed name actually changes.
    final academyName = ref.watch(
      currentAcademyInfoProvider.select((info) => info?.name),
    );

    // Only show if user has multiple academies
    if (!hasMultiple || academyName == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: InkWell(
        onTap: () => context.push('/portal/academias'),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.building2,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  academyName,
                  style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.arrowRightLeft,
                size: 14,
                color: AppTheme.primary.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card showing the student's progress towards the next graduation.
/// Visible only when the academy enabled `autoGraduationEnabled` AND
/// `graduationProgressVisibleToStudents`. Threshold falls back to 70
/// matching the historical default if the academy hasn't set one.
class _GraduationProgressCard extends ConsumerWidget {
  final dynamic student;
  const _GraduationProgressCard({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    if (settings == null) return const SizedBox.shrink();
    if (!settings.autoGraduationEnabled) return const SizedBox.shrink();
    if (!settings.graduationProgressVisibleToStudents) {
      return const SizedBox.shrink();
    }

    // One progress per sport the student trains (skip sports with no
    // graduation system, e.g. musculação/boxe).
    final gradedSports = (student.getSports() as List<SportId>)
        .where((s) => sports[s]?.gradeSystem != GradeSystem.none)
        .toList();
    if (gradedSports.isEmpty) return const SizedBox.shrink();

    return Column(
      children: gradedSports
          .map(
            (sport) => _SportProgressCard(
              studentId: student.id as String,
              sport: sport,
              graduationMode: settings.graduationMode,
            ),
          )
          .toList(),
    );
  }
}

/// Progress card for a single sport, fed by the sport-filtered eligibility.
class _SportProgressCard extends ConsumerStatefulWidget {
  final String studentId;
  final SportId sport;
  final String graduationMode;
  const _SportProgressCard({
    required this.studentId,
    required this.sport,
    required this.graduationMode,
  });

  @override
  ConsumerState<_SportProgressCard> createState() => _SportProgressCardState();
}

class _SportProgressCardState extends ConsumerState<_SportProgressCard> {
  /// Ephemeral, session-only guard: did we already celebrate this card's
  /// graduation eligibility? Never persisted, never written to a CF/Firestore.
  /// Prevents the confetti from re-firing on rebuilds or while staying
  /// eligible.
  bool _celebrated = false;

  @override
  Widget build(BuildContext context) {
    // React to eligibility transitions WITHOUT firing inside build (which would
    // loop/re-fire on every rebuild). [ref.listen] only runs on actual changes.
    ref.listen(
      studentSportEligibilityProvider(
        (studentId: widget.studentId, sport: widget.sport),
      ),
      (prev, next) {
        final wasEligible = prev?.valueOrNull?.eligible ?? false;
        final isEligible = next.valueOrNull?.eligible ?? false;
        // Fire once, only on the false → true transition, only the first time
        // this session.
        if (!wasEligible && isEligible && !_celebrated) {
          _celebrated = true;
          if (mounted) Celebration.confetti(context);
        }
      },
    );

    final e = ref
        .watch(studentSportEligibilityProvider(
          (studentId: widget.studentId, sport: widget.sport),
        ))
        .valueOrNull;
    // No configured requirement for this sport → nothing meaningful to show.
    if (e == null || e.requiredClasses <= 0) return const SizedBox.shrink();

    final graduationMode = widget.graduationMode;
    final sport = widget.sport;

    final eligible = e.eligible;
    final total = e.currentClasses;
    final threshold = e.requiredClasses;
    final remaining = e.missingClasses;
    final progress =
        threshold == 0 ? 1.0 : (total / threshold).clamp(0.0, 1.0);
    final sportLabel = getSport(sport).label;
    final unit = e.weighted ? 'pts' : 'aulas';

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: eligible
                ? [AppTheme.success, AppTheme.success.withValues(alpha: 0.85)]
                : [
                    AppTheme.primary.withValues(alpha: 0.12),
                    AppTheme.surface,
                  ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: eligible
                ? AppTheme.success
                : AppTheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  eligible ? LucideIcons.trophy : LucideIcons.award,
                  color: eligible ? Colors.white : AppTheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    eligible
                        ? 'Meta atingida — $sportLabel!'
                        : 'Próxima graduação — $sportLabel',
                    style: AppTheme.titleMedium.copyWith(
                      color: eligible ? Colors.white : AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedProgressBar(
              value: progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              color: eligible ? Colors.white : AppTheme.primary,
              backgroundColor: eligible
                  ? Colors.white.withValues(alpha: 0.25)
                  : AppTheme.divider,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                AnimatedCountUp(
                  value: total,
                  suffix: ' / $threshold $unit',
                  style: AppTheme.bodyMedium.copyWith(
                    color: eligible ? Colors.white : AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  eligible
                      ? graduationMode == 'auto'
                          ? 'Graduação automática'
                          : 'Aguarde aprovação do mestre'
                      : 'Faltam $remaining',
                  style: AppTheme.labelSmall.copyWith(
                    color: eligible
                        ? Colors.white.withValues(alpha: 0.9)
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Jornal Headline
// ============================================

/// Minimalist single-row entry point to the "Jornal da Academia" feed.
class _JornalHeadline extends StatelessWidget {
  const _JornalHeadline();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Pressable(
        onTap: () => context.push('/portal/jornal'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.newspaper,
                  size: 20, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Jornal da Academia',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Notícias, seminários e novidades',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight,
                  size: 16, color: AppTheme.textDisabled),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// Events Section
// ============================================

class _EventsSection extends ConsumerWidget {
  final void Function(String path) onTap;

  const _EventsSection({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(upcomingEventsProvider);

    return eventsAsync.when(
      data: (allEvents) {
        // The home stays calendar-focused: only actual events. News and
        // seminars live in the Jornal da Academia feed (no duplicate listing).
        final events = allEvents
            .where((e) => e.postType == PostType.event)
            .toList();
        if (events.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(LucideIcons.calendar, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                const Text(
                  'Eventos',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...events.indexed.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _EventCard(
                    event: entry.$2,
                    onTap: () => onTap('/portal/eventos/${entry.$2.id}'),
                  ).entrance(index: entry.$1),
                )),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _EventCard extends StatelessWidget {
  final AcademyEvent event;
  final VoidCallback onTap;

  const _EventCard({required this.event, required this.onTap});

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(d.year, d.month, d.day);
    final diff = eventDay.difference(today).inDays;

    if (diff == 0) return 'Hoje, ${DateFormat('HH:mm').format(d)}';
    if (diff == 1) return 'Amanhã, ${DateFormat('HH:mm').format(d)}';
    if (diff < 7) return DateFormat("EEEE, HH:mm", 'pt_BR').format(d);
    return DateFormat("d 'de' MMM", 'pt_BR').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final hasCover = event.coverUrl != null && event.coverUrl!.isNotEmpty;

    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            // Cover thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(13)),
              child: hasCover
                  ? Hero(
                      tag: 'event-cover-${event.id}',
                      child: AppCachedImage(
                        imageUrl: event.coverUrl!,
                        width: 88,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Container(
                      width: 88,
                      height: 80,
                      color: AppTheme.border,
                      child: const Icon(
                        LucideIcons.calendarDays,
                        size: 28,
                        color: AppTheme.textDisabled,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (event.isOngoing)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.successLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Agora',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.success,
                          ),
                        ),
                      ),
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(event.startDate),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (event.location != null && event.location!.isNotEmpty)
                      Text(
                        event.location!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textDisabled,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(LucideIcons.chevronRight, size: 16, color: AppTheme.textDisabled),
            ),
          ],
        ),
      ),
    );
  }
}

