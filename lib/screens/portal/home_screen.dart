import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/academy_event.dart';
import '../../providers/portal_providers.dart';
import '../../providers/providers.dart';
import '../../providers/selected_academy_provider.dart';
import '../../services/checkin_service.dart';
import '../../services/musculacao_checkin_service.dart';
import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/grade_display.dart';
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
                    userName: currentUser.valueOrNull?.displayName ?? 'Aluno',
                  );
                }
                final primarySport = s.getPrimarySport();
                // Sports without a graduation system (e.g. musculação, boxe)
                // have no belt/grade — show the plain header instead.
                if (sports[primarySport]?.gradeSystem == GradeSystem.none) {
                  return _WelcomeHeader(userName: s.displayName);
                }
                final grade = s.getGrade(primarySport);
                return _WelcomeHeaderWithBelt(
                  userName: s.displayName,
                  sportId: primarySport,
                  belt: grade?.currentGrade ?? 'white',
                  stripes: grade?.currentStripes ?? 0,
                  sports: s.getSports(),
                  primarySport: primarySport,
                );
              },
              loading: () => _WelcomeHeader(
                userName: currentUser.valueOrNull?.displayName ?? 'Aluno',
              ),
              error: (_, __) => _WelcomeHeader(
                userName: currentUser.valueOrNull?.displayName ?? 'Aluno',
              ),
            ),

            // Academy indicator for multi-academy users
            const _AcademyIndicator(),

            const SizedBox(height: 24),

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_greeting,',
          style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
        ),
        Text(
          userName.split(' ').first,
          style: AppTheme.displaySmall.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Welcome header with belt badge inline.
///
/// For multi-sport students it also surfaces a compact "{n} modalidades" pill
/// next to the belt chip; tapping it reveals a [SportTabBar] row below the
/// greeting, bound to `selectedSportProvider("home")`. This is purely an
/// affordance — the rest of the home (graduation cards, etc.) stays all-sports
/// stacked. Single-sport (or zero graded sports) students see neither the pill
/// nor the selector, so the layout is pixel-identical to before.
class _WelcomeHeaderWithBelt extends ConsumerStatefulWidget {
  final String userName;
  final SportId sportId;
  final String belt;
  final int stripes;
  final List<SportId> sports;
  final SportId primarySport;

  const _WelcomeHeaderWithBelt({
    required this.userName,
    required this.sportId,
    required this.belt,
    required this.stripes,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_greeting,',
          style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                widget.userName.split(' ').first,
                style: AppTheme.displaySmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            GradeDisplay(
              sportId: widget.sportId,
              grade: widget.belt,
              stripes: widget.stripes,
              size: GradeDisplaySize.small,
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
        if (multiSport && _selectorOpen) ...[
          const SizedBox(height: 12),
          SportTabBar(
            sports: widget.sports,
            selected: ref.watch(selectedSportProvider('home')) ??
                widget.primarySport,
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
                data: (count) => _StatCarouselCard(
                  emoji: '🔥',
                  value: count.toString(),
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
                loading: () => _StatCarouselCard(
                  emoji: '🔥',
                  value: '...',
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
                error: (_, __) => _StatCarouselCard(
                  emoji: '🔥',
                  value: '-',
                  label: 'Treinos',
                  sublabel: 'Total de presencas',
                  color: AppTheme.warning,
                ),
              ),

              // Months on mat card
              _StatCarouselCard(
                emoji: '📅',
                value: monthsOnMat > 0 ? monthsOnMat.toString() : '0',
                label: 'Meses de Tatame',
                sublabel: 'Tempo de jornada',
                color: AppTheme.info,
              ),

              // Competitions card
              medalCountAsync.when(
                data: (medals) {
                  final total = medals['total'] ?? 0;
                  return _StatCarouselCard(
                    emoji: '🏆',
                    value: total.toString(),
                    label: 'Competicoes',
                    sublabel: 'Participacoes',
                    color: Colors.purple,
                  );
                },
                loading: () => _StatCarouselCard(
                  emoji: '🏆',
                  value: '...',
                  label: 'Competicoes',
                  sublabel: 'Participacoes',
                  color: Colors.purple,
                ),
                error: (_, __) => _StatCarouselCard(
                  emoji: '🏆',
                  value: '0',
                  label: 'Competicoes',
                  sublabel: 'Participacoes',
                  color: Colors.purple,
                ),
              ),
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

/// Individual stat carousel card
class _StatCarouselCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final String sublabel;
  final Color color;

  const _StatCarouselCard({
    required this.emoji,
    required this.value,
    required this.label,
    required this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: AppTheme.displayMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  sublabel,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final nextClassAsync = ref.watch(studentNextClassProvider(studentId));
    final streakAsync = ref.watch(studentStreakProvider(studentId));
    final monthlyAttendanceAsync = ref.watch(
      studentMonthlyAttendanceProvider(studentId),
    );
    final upcomingCompetitionsAsync = ref.watch(upcomingCompetitionsProvider);
    // Only depend on the single boolean we actually consume — avoids
    // rebuilding when other settings fields change.
    final checkinEnabled = ref.watch(
      academySettingsProvider.select(
        (s) => s.valueOrNull?.studentCheckinEnabled ?? false,
      ),
    );
    // Musculação self check-in — shown to students who practice musculação
    // when the academy picked the 'button' or 'qr' mode.
    final musculacaoMode = ref.watch(
      academySettingsProvider.select(
        (s) => s.valueOrNull?.musculacaoCheckinMode ?? 'manual',
      ),
    );
    final practicesMusculacao = ref
            .watch(currentStudentProvider)
            .valueOrNull
            ?.getSports()
            .contains(SportId.musculacao) ??
        false;
    final showMusculacaoCheckin = practicesMusculacao &&
        (musculacaoMode == 'button' || musculacaoMode == 'qr');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showMusculacaoCheckin) ...[
          _MusculacaoCheckinCard(qrMode: musculacaoMode == 'qr'),
          const SizedBox(height: 12),
        ],

        // Next Class Card (Featured)
        nextClassAsync.when(
          data: (data) {
            if (data == null || data.classInfo == null) {
              return _NextClassCard(
                className: null,
                schedule: null,
                nextDate: null,
                checkinEnabled: false,
                canCheckin: false,
                onTap: () => onTap('/portal/horarios'),
              );
            }

            // Check if within check-in window
            final canCheckin =
                checkinEnabled &&
                data.nextDate != null &&
                data.schedule != null &&
                isInCheckinWindow(
                  startTime: data.schedule!.startTime,
                  endTime: data.schedule!.endTime,
                  date: data.nextDate!,
                );

            return _NextClassCard(
              className: data.classInfo!.name,
              schedule: data.schedule,
              nextDate: data.nextDate,
              checkinEnabled: checkinEnabled,
              canCheckin: canCheckin,
              onTap: () => onTap('/portal/horarios'),
            );
          },
          loading: () => _NextClassCard(
            className: null,
            schedule: null,
            nextDate: null,
            isLoading: true,
            checkinEnabled: false,
            canCheckin: false,
            onTap: () => onTap('/portal/horarios'),
          ),
          error: (_, __) => _NextClassCard(
            className: null,
            schedule: null,
            nextDate: null,
            checkinEnabled: false,
            canCheckin: false,
            onTap: () => onTap('/portal/horarios'),
          ),
        ),

        const SizedBox(height: 12),

        // Row with Streak and Monthly Stats
        Row(
          children: [
            Expanded(
              child: streakAsync.when(
                data: (streak) => _StreakCard(
                  streak: streak,
                  onTap: () => onTap('/portal/presencas'),
                ),
                loading: () => _StreakCard(
                  streak: 0,
                  isLoading: true,
                  onTap: () => onTap('/portal/presencas'),
                ),
                error: (_, __) => _StreakCard(
                  streak: 0,
                  onTap: () => onTap('/portal/presencas'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: monthlyAttendanceAsync.when(
                data: (count) => _MonthlyCard(
                  count: count,
                  onTap: () => onTap('/portal/presencas'),
                ),
                loading: () => _MonthlyCard(
                  count: 0,
                  isLoading: true,
                  onTap: () => onTap('/portal/presencas'),
                ),
                error: (_, __) => _MonthlyCard(
                  count: 0,
                  onTap: () => onTap('/portal/presencas'),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

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
        ),

        // Upcoming Events
        _EventsSection(onTap: onTap),
      ],
    );
  }
}

/// Self check-in card for musculação students (button mode). Calls the
/// selfCheckin Cloud Function; the server enforces operating hours, active
/// status and one-per-day dedup. Local state flips to "done" after success or
/// when the server reports today's check-in already exists.
class _MusculacaoCheckinCard extends ConsumerStatefulWidget {
  /// When true the academy uses the fixed-QR mode: tapping opens the scanner
  /// instead of calling the function directly.
  final bool qrMode;

  const _MusculacaoCheckinCard({required this.qrMode});

  @override
  ConsumerState<_MusculacaoCheckinCard> createState() =>
      _MusculacaoCheckinCardState();
}

class _MusculacaoCheckinCardState
    extends ConsumerState<_MusculacaoCheckinCard> {
  bool _loading = false;
  bool _doneToday = false;

  Future<void> _checkin() async {
    if (widget.qrMode) {
      final result = await context.push<bool>('/portal/musculacao-checkin');
      if (result == true && mounted) setState(() => _doneToday = true);
      return;
    }
    setState(() => _loading = true);
    try {
      await MusculacaoCheckinService().checkIn();
      if (!mounted) return;
      setState(() => _doneToday = true);
      context.showSuccess('Presenca registrada!');
    } on MusculacaoCheckinException catch (e) {
      if (!mounted) return;
      if (e.message.toLowerCase().contains('registrou presen')) {
        setState(() => _doneToday = true);
      }
      context.showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _doneToday;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: done
              ? [AppTheme.success, AppTheme.success.withValues(alpha: 0.85)]
              : [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.fitness_center,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                done ? 'Presenca de hoje registrada' : 'Treino de musculacao',
                style: AppTheme.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            done
                ? 'Bom treino! Volte amanha para registrar de novo.'
                : widget.qrMode
                    ? 'Escaneie o QR da recepcao para registrar presenca.'
                    : 'Chegou na academia? Registre sua presenca.',
            style: AppTheme.bodyMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_loading || done) ? null : _checkin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: done ? AppTheme.success : AppTheme.primary,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      done
                          ? Icons.check
                          : widget.qrMode
                              ? Icons.qr_code_scanner
                              : Icons.location_on,
                      size: 18,
                    ),
              label: Text(
                done
                    ? 'Check-in feito'
                    : widget.qrMode
                        ? 'Escanear QR'
                        : 'Cheguei',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Next Class Card (Featured)
class _NextClassCard extends StatelessWidget {
  final String? className;
  final dynamic schedule;
  final DateTime? nextDate;
  final bool isLoading;
  final bool checkinEnabled;
  final bool canCheckin;
  final VoidCallback onTap;

  const _NextClassCard({
    required this.className,
    required this.schedule,
    required this.nextDate,
    this.isLoading = false,
    required this.checkinEnabled,
    required this.canCheckin,
    required this.onTap,
  });

  String _formatNextClass() {
    if (nextDate == null || schedule == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final classDay = DateTime(nextDate!.year, nextDate!.month, nextDate!.day);
    final difference = classDay.difference(today).inDays;

    String dayLabel;
    if (difference == 0) {
      dayLabel = 'Hoje';
    } else if (difference == 1) {
      dayLabel = 'Amanha';
    } else {
      dayLabel = DateFormat('EEEE', 'pt_BR').format(nextDate!);
      dayLabel = dayLabel[0].toUpperCase() + dayLabel.substring(1);
    }

    return '$dayLabel as ${schedule.startTime}';
  }

  @override
  Widget build(BuildContext context) {
    final hasClass = className != null && !isLoading;
    // Use success color when check-in is available
    final cardColor = canCheckin
        ? AppTheme.success
        : (hasClass ? AppTheme.textPrimary : AppTheme.surface);

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: hasClass ? null : Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: hasClass
                      ? Colors.white.withValues(alpha: 0.15)
                      : AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  canCheckin ? LucideIcons.userCheck : LucideIcons.calendar,
                  size: 28,
                  color: hasClass ? Colors.white : AppTheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      canCheckin ? 'CHECK-IN DISPONIVEL' : 'PROXIMA AULA',
                      style: AppTheme.labelSmall.copyWith(
                        color: hasClass
                            ? Colors.white.withValues(alpha: 0.7)
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isLoading)
                      Text(
                        'Carregando...',
                        style: AppTheme.titleMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      )
                    else if (hasClass) ...[
                      Text(
                        className!,
                        style: AppTheme.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _formatNextClass(),
                        style: AppTheme.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ] else
                      Text(
                        'Ver horarios disponiveis',
                        style: AppTheme.titleMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (canCheckin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Fazer Check-in',
                        style: AppTheme.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: Colors.white,
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  LucideIcons.chevronRight,
                  size: 20,
                  color: hasClass
                      ? Colors.white.withValues(alpha: 0.5)
                      : AppTheme.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Streak Card
class _StreakCard extends StatelessWidget {
  final int streak;
  final bool isLoading;
  final VoidCallback onTap;

  const _StreakCard({
    required this.streak,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasStreak = streak > 0;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    hasStreak ? '🔥' : '💪',
                    style: const TextStyle(fontSize: 24),
                  ),
                  const Spacer(),
                  if (hasStreak)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Em alta!',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (isLoading)
                Text(
                  '...',
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Text(
                  hasStreak ? '$streak dias' : 'Comece hoje!',
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                'Sequencia',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Monthly Attendance Card
class _MonthlyCard extends StatelessWidget {
  final int count;
  final bool isLoading;
  final VoidCallback onTap;

  const _MonthlyCard({
    required this.count,
    this.isLoading = false,
    required this.onTap,
  });

  String get _monthName {
    final now = DateTime.now();
    final month = DateFormat('MMMM', 'pt_BR').format(now);
    return month[0].toUpperCase() + month.substring(1);
  }

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('📅', style: TextStyle(fontSize: 24)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _monthName,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (isLoading)
                Text(
                  '...',
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Text(
                  '$count treinos',
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                'Este mes',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
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
class _SportProgressCard extends ConsumerWidget {
  final String studentId;
  final SportId sport;
  final String graduationMode;
  const _SportProgressCard({
    required this.studentId,
    required this.sport,
    required this.graduationMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref
        .watch(studentSportEligibilityProvider(
          (studentId: studentId, sport: sport),
        ))
        .valueOrNull;
    // No configured requirement for this sport → nothing meaningful to show.
    if (e == null || e.requiredClasses <= 0) return const SizedBox.shrink();

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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: eligible
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppTheme.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  eligible ? Colors.white : AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '$total / $threshold $unit',
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
// Events Section
// ============================================

class _EventsSection extends ConsumerWidget {
  final void Function(String path) onTap;

  const _EventsSection({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(upcomingEventsProvider);

    return eventsAsync.when(
      data: (events) {
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
            ...events.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _EventCard(
                    event: e,
                    onTap: () => onTap('/portal/eventos/${e.id}'),
                  ),
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

    return GestureDetector(
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
                  ? AppCachedImage(
                      imageUrl: event.coverUrl!,
                      width: 88,
                      height: 80,
                      fit: BoxFit.cover,
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

