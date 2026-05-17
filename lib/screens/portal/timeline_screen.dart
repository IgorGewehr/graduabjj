import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../api/dto/student_dto.dart' as api_student;
import '../../api/feature_flags.dart';
import '../../api/repositories.dart' as tatami_repos;
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../providers/selected_academy_provider.dart';
import '../../services/services.dart';

/// Timeline event types
enum TimelineEventType { graduation, stripe, competition, milestone, start }

/// Timeline event model
class _TimelineEvent {
  final String id;
  final DateTime date;
  final TimelineEventType type;
  final String title;
  final String? description;
  final String? position;
  final String? belt;
  final int? stripes;
  final String? academyName;

  _TimelineEvent({
    required this.id,
    required this.date,
    required this.type,
    required this.title,
    this.description,
    this.position,
    this.belt,
    this.stripes,
    this.academyName,
  });
}

/// Adapter inline: ApiBeltProgression → BeltProgression legacy. Reside
/// na tela porque a model legacy não tem `BeltProgression.fromApi` (gap
/// para Sprint 3). Mapping é 1:1 com a única peculiaridade de
/// `promotedByName` ser nulo (BE só expõe uid).
BeltProgression _beltProgressionFromApi(api_student.ApiBeltProgression p) =>
    BeltProgression(
      id: p.id,
      studentId: p.studentId,
      previousBelt: p.previousBelt.wire,
      previousStripes: p.previousStripes,
      newBelt: p.newBelt.wire,
      newStripes: p.newStripes,
      promotionDate: p.promotionDate,
      totalClasses: p.totalClasses,
      effectiveCountAtPromotion: p.effectiveCountAtPromotion,
      promotedBy: p.promotedByUid,
      promotedByName: null,
      notes: p.notes,
      sport: p.sport.wire,
      createdAt: p.createdAt ?? p.promotionDate,
    );

/// Belt progressions provider for timeline
final studentBeltProgressionsProvider =
    FutureProvider.family<List<BeltProgression>, String>((
      ref,
      studentId,
    ) async {
      final currentUser = await ref.watch(currentUserProvider.future);
      if (currentUser?.academyId == null) return [];

      final academyId = currentUser!.academyId!;
      final flags = ref.watch(tatamiFlagsProvider);

      if (flags.useTatamiReads) {
        try {
          // Lê direto via studentRepo — não há domain provider equivalente
          // (gap registrado pra Sprint 3 — domain_providers ainda não
          // expõe beltProgressions).
          final page = await ref
              .watch(tatami_repos.studentRepoProvider)
              .listBeltProgressions(academyId, studentId, limit: 100);
          return page.items.map(_beltProgressionFromApi).toList();
        } catch (_) {
          // Fallback transparente para Firestore legacy.
        }
      }

      final service = BeltProgressionService(academyId);
      return await service.getByStudent(studentId);
    });

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
                    attendanceCountAsync: attendanceCountAsync,
                    medalCountAsync: medalCountAsync,
                    competitionsAsync: competitionsAsync,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Timeline
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildTimeline(
                    student,
                    achievementsAsync,
                    progressionsAsync,
                    academyInfo?.name,
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
      error: (_, __) => _buildEmptyState(
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
  ) {
    final achievements = achievementsAsync.valueOrNull ?? [];
    final progressions = progressionsAsync.valueOrNull ?? [];

    // Build unified timeline events
    final events = <_TimelineEvent>[];

    // Add start event
    events.add(
      _TimelineEvent(
        id: 'start',
        date: student.jiujitsuStartDate ?? student.startDate,
        type: TimelineEventType.start,
        title: 'Inicio da Jornada',
        description: 'Primeiro treino na academia',
        belt: 'white',
        academyName: academyName,
      ),
    );

    // Add belt progressions
    for (final p in progressions) {
      events.add(
        _TimelineEvent(
          id: 'progression_${p.id}',
          date: p.promotionDate,
          type: p.isBeltChange
              ? TimelineEventType.graduation
              : TimelineEventType.stripe,
          title: p.isBeltChange
              ? 'Faixa ${getGradeLabel(p.getSport(), p.newBelt)}'
              : '${p.newStripes}o Grau',
          description: p.notes,
          belt: p.newBelt,
          stripes: p.newStripes,
          academyName: academyName,
        ),
      );
    }

    // Add achievements (only competitions and milestones, since graduations come from progressions)
    for (final a in achievements) {
      if (a.type == AchievementType.competition ||
          a.type == AchievementType.milestone) {
        events.add(
          _TimelineEvent(
            id: 'achievement_${a.id}',
            date: a.date,
            type: a.type == AchievementType.competition
                ? TimelineEventType.competition
                : TimelineEventType.milestone,
            title: a.title,
            description: a.description,
            position: a.position?.value,
            academyName: academyName,
          ),
        );
      }
    }

    // Sort by date ascending (oldest first)
    events.sort((a, b) => a.date.compareTo(b.date));

    if (events.isEmpty) {
      return _buildTimelineEmptyState();
    }

    // Reverse for display (newest at top, oldest at bottom)
    final reversedEvents = events.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Sua Jornada',
          style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        ...reversedEvents.asMap().entries.map((entry) {
          final index = entry.key;
          final event = entry.value;
          final isLast = index == reversedEvents.length - 1;
          return _TimelineItem(event: event, isLast: isLast);
        }),
      ],
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
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
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.clock, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Sua linha do tempo esta vazia',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Suas conquistas aparecerao aqui conforme voce progride',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Journey Card with Stats Carousel
class _JourneyCard extends StatefulWidget {
  final Student student;
  final AsyncValue<int> attendanceCountAsync;
  final AsyncValue<Map<String, int>> medalCountAsync;
  final AsyncValue<List<Competition>> competitionsAsync;

  const _JourneyCard({
    required this.student,
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

  Color _getBeltDisplayColor(String belt) {
    const colors = {
      'white': Color(0xFF6B7280),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
      'grey': Color(0xFF6B7280),
      'yellow': Color(0xFFF59E0B),
      'orange': Color(0xFFF97316),
      'green': Color(0xFF22C55E),
    };
    final baseBelt = belt.split('-').first;
    return colors[baseBelt] ?? const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) {
    final attendanceCount = widget.attendanceCountAsync.valueOrNull ?? 0;
    final medalStats =
        widget.medalCountAsync.valueOrNull ??
        {'gold': 0, 'silver': 0, 'bronze': 0, 'total': 0};
    final competitions = widget.competitionsAsync.valueOrNull ?? [];
    final beltColor = _getBeltDisplayColor(widget.student.currentBelt);

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
                value: getGradeLabel(
                  widget.student.getPrimarySport(),
                  widget.student.currentBelt,
                ),
                label: widget.student.currentStripes > 0
                    ? '${widget.student.currentStripes} grau${widget.student.currentStripes > 1 ? 's' : ''}'
                    : 'Faixa Atual',
              ),
              _JourneyCarouselCard(
                icon: LucideIcons.dumbbell,
                iconColor: AppTheme.success,
                iconBgColor: AppTheme.successLight,
                value: attendanceCount.toString(),
                label: 'Treinos',
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
                        emoji: '🥇',
                        count: medalStats['gold']!,
                        label: 'Ouro',
                      ),
                    if ((medalStats['silver'] ?? 0) > 0)
                      _MedalBadge(
                        emoji: '🥈',
                        count: medalStats['silver']!,
                        label: 'Prata',
                      ),
                    if ((medalStats['bronze'] ?? 0) > 0)
                      _MedalBadge(
                        emoji: '🥉',
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

/// Medal Badge
class _MedalBadge extends StatelessWidget {
  final String emoji;
  final int count;
  final String label;

  const _MedalBadge({
    required this.emoji,
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
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count.toString(),
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
  final _TimelineEvent event;
  final bool isLast;

  const _TimelineItem({required this.event, required this.isLast});

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFF6B7280),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
      'grey': Color(0xFF6B7280),
      'yellow': Color(0xFFF59E0B),
      'orange': Color(0xFFF97316),
      'green': Color(0xFF22C55E),
    };
    final baseBelt = belt.split('-').first;
    return colors[baseBelt] ?? const Color(0xFF6B7280);
  }

  _EventConfig _getEventConfig(TimelineEventType type, String? belt) {
    switch (type) {
      case TimelineEventType.graduation:
        final beltColor = _getBeltColor(belt ?? 'white');
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
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _TypeChip(type: event.type),
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
                    _BeltIndicator(belt: event.belt!),
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

/// Belt Indicator
class _BeltIndicator extends StatelessWidget {
  final String belt;

  const _BeltIndicator({required this.belt});

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFF9CA3AF),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
      'grey': Color(0xFF6B7280),
      'yellow': Color(0xFFF59E0B),
      'orange': Color(0xFFF97316),
      'green': Color(0xFF22C55E),
    };
    final baseBelt = belt.split('-').first;
    return colors[baseBelt] ?? const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) {
    final beltColor = _getBeltColor(belt);
    final beltLabel = getGradeLabel(SportId.bjj, belt);

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

/// Position Badge
class _PositionBadge extends StatelessWidget {
  final String position;

  const _PositionBadge({required this.position});

  @override
  Widget build(BuildContext context) {
    String emoji;
    String label;
    Color color;

    switch (position) {
      case 'gold':
        emoji = '🥇';
        label = 'Ouro';
        color = const Color(0xFFD97706);
        break;
      case 'silver':
        emoji = '🥈';
        label = 'Prata';
        color = const Color(0xFF6B7280);
        break;
      case 'bronze':
        emoji = '🥉';
        label = 'Bronze';
        color = const Color(0xFFB45309);
        break;
      default:
        emoji = '🎖️';
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
          Text(emoji, style: const TextStyle(fontSize: 18)),
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
