import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../providers/portal_providers.dart';
import '../../providers/student_provider.dart';
import '../../services/checkin_service.dart';
import '../../widgets/polish/polish.dart';
import 'musculacao_checkin_card.dart';

/// "Hero do Dia" — a single, prioritized call-to-action that anchors the top of
/// the portal home, just below the academy indicator.
///
/// It is purely ADDITIVE and VISUAL: it only reads providers the home already
/// observes (next class, streak, academy settings, current student), so there
/// is ZERO new query/Cloud Function/collection/gating. It NEVER triggers an
/// aula check-in directly — when check-in is available it only NAVIGATES to
/// `/portal/horarios`, where the real (server-authoritative) check-in happens.
///
/// Priority resolution (first match wins):
///   1. canCheckin  → green CTA + subtle shimmer, routes to Horários
///   2. next class  → live countdown until it starts, routes to Horários
///   3. musculação  → reuses [MusculacaoCheckinCard] (its own CF logic)
///   4. streak      → motivational fallback, routes to Presenças
class HomeHeroCard extends ConsumerWidget {
  final String studentId;

  const HomeHeroCard({super.key, required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextClassAsync = ref.watch(studentNextClassProvider(studentId));

    // Single boolean — avoids rebuilding on unrelated settings changes.
    final checkinEnabled = ref.watch(
      academySettingsProvider.select(
        (s) => s.valueOrNull?.studentCheckinEnabled ?? false,
      ),
    );

    // Musculação self check-in availability (same gate the dynamic section
    // uses). Read here so it can act as a fallback action below. Gated first by
    // the academy-level musculacaoEnabled master switch.
    final musculacaoEnabled = ref.watch(
      academySettingsProvider.select(
        (s) => s.valueOrNull?.musculacaoEnabled ?? true,
      ),
    );
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
    final showMusculacao = musculacaoEnabled &&
        practicesMusculacao &&
        (musculacaoMode == 'button' || musculacaoMode == 'qr');

    return nextClassAsync.when(
      data: (data) {
        final classInfo = data?.classInfo;
        final schedule = data?.schedule;
        final nextDate = data?.nextDate;

        // 1) Check-in disponível → highest-priority hero.
        // Only offer check-in for a class the student can actually check into
        // (enrolled, or a genuinely open class) — never for a class they are
        // not matriculated in. Reuses the domain rule [acceptsCheckinFrom].
        final canCheckin = checkinEnabled &&
            classInfo != null &&
            classInfo.acceptsCheckinFrom(studentId) &&
            nextDate != null &&
            schedule != null &&
            isInCheckinWindow(
              startTime: schedule.startTime,
              endTime: schedule.endTime,
              date: nextDate,
            );
        if (canCheckin) {
          return _CheckinHero(
            className: classInfo.name,
            startTime: schedule.startTime,
            onTap: () => context.go('/portal/horarios'),
          ).fadeInQuick();
        }

        // 2) Próxima aula com contagem regressiva.
        if (classInfo != null && schedule != null && nextDate != null) {
          return _NextClassHero(
            className: classInfo.name,
            startTime: schedule.startTime,
            nextDate: nextDate,
            onTap: () => context.go('/portal/horarios'),
          ).fadeInQuick();
        }

        // 3) Musculação check-in (reuses the existing CF-backed card).
        if (showMusculacao) {
          return MusculacaoCheckinCard(qrMode: musculacaoMode == 'qr');
        }

        // 4) Streak fallback.
        return _StreakHero(studentId: studentId).fadeInQuick();
      },
      // While the next class loads, prefer the musculação card / streak so the
      // hero never flashes empty.
      loading: () => showMusculacao
          ? MusculacaoCheckinCard(qrMode: musculacaoMode == 'qr')
          : _StreakHero(studentId: studentId).fadeInQuick(),
      error: (e, st) => showMusculacao
          ? MusculacaoCheckinCard(qrMode: musculacaoMode == 'qr')
          : _StreakHero(studentId: studentId).fadeInQuick(),
    );
  }
}

/// Sober black, shimmering hero shown when the student is inside a class
/// check-in window. Navigates to Horários — never marks attendance directly.
class _CheckinHero extends StatelessWidget {
  final String className;
  final String startTime;
  final VoidCallback onTap;

  const _CheckinHero({
    required this.className,
    required this.startTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hero = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppTheme.primaryLight,
            AppTheme.primaryDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              LucideIcons.userCheck,
              size: 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHECK-IN DISPONIVEL',
                  style: AppTheme.labelSmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  className,
                  style: AppTheme.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Comeca as $startTime — registre sua presenca',
                  style: AppTheme.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Fazer check-in',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 4),
                Icon(LucideIcons.chevronRight, size: 16, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );

    // Subtle, looping shimmer to draw the eye — only on this top-priority state.
    return Pressable(
      onTap: onTap,
      child: hero
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: 1800.ms,
            delay: 1200.ms,
            color: Colors.white.withValues(alpha: 0.22),
          ),
    );
  }
}

/// Neutral hero for the next upcoming class, with a live countdown that ticks
/// down to the class start. Navigates to Horários.
class _NextClassHero extends StatefulWidget {
  final String className;
  final String startTime;
  final DateTime nextDate;
  final VoidCallback onTap;

  const _NextClassHero({
    required this.className,
    required this.startTime,
    required this.nextDate,
    required this.onTap,
  });

  @override
  State<_NextClassHero> createState() => _NextClassHeroState();
}

class _NextClassHeroState extends State<_NextClassHero> {
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
  }

  /// Human countdown / day label until the class starts.
  String get _countdown {
    final diff = widget.nextDate.difference(_now);
    if (diff.isNegative) return 'Comecando agora';

    final today = DateTime(_now.year, _now.month, _now.day);
    final classDay = DateTime(
      widget.nextDate.year,
      widget.nextDate.month,
      widget.nextDate.day,
    );
    final dayGap = classDay.difference(today).inDays;

    // Same-day: show a precise hh/mm countdown so it feels alive.
    if (dayGap == 0) {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      if (h > 0) return 'Em ${h}h${m.toString().padLeft(2, '0')}';
      if (diff.inMinutes > 0) return 'Em ${diff.inMinutes} min';
      return 'Comecando agora';
    }
    if (dayGap == 1) return 'Amanha as ${widget.startTime}';
    final dayLabel = DateFormat('EEEE', 'pt_BR').format(widget.nextDate);
    final cap = dayLabel[0].toUpperCase() + dayLabel.substring(1);
    return '$cap as ${widget.startTime}';
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryLight, AppTheme.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryDark.withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                LucideIcons.calendarClock,
                size: 28,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PROXIMA AULA',
                    style: AppTheme.labelSmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.className,
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _countdown,
                      style: AppTheme.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// Motivational streak hero — the gentlest fallback. Navigates to Presenças.
class _StreakHero extends ConsumerWidget {
  final String studentId;

  const _StreakHero({required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(studentStreakProvider(studentId)).valueOrNull ?? 0;
    final hasStreak = streak > 0;

    return Pressable(
      onTap: () => context.go('/portal/presencas'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasStreak
                ? [
                    AppTheme.warning.withValues(alpha: 0.16),
                    AppTheme.surface,
                  ]
                : [
                    AppTheme.primary.withValues(alpha: 0.10),
                    AppTheme.surface,
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasStreak
                ? AppTheme.warning.withValues(alpha: 0.28)
                : AppTheme.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (hasStreak ? AppTheme.warning : AppTheme.primary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  hasStreak ? '🔥' : '💪',
                  style: const TextStyle(fontSize: 26),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasStreak ? 'SUA SEQUENCIA' : 'COMECE HOJE',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (hasStreak)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        AnimatedCountUp(
                          value: streak,
                          style: AppTheme.headlineSmall.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          streak == 1 ? 'dia em alta' : 'dias em alta',
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Marque presenca e inicie sua sequencia',
                      style: AppTheme.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
