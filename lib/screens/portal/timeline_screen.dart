import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../providers/selected_academy_provider.dart';
import '../../services/services.dart';
import 'timeline/academy_indicator.dart';
import 'timeline/journey_card.dart';
import 'timeline/timeline_item.dart';
import 'timeline/timeline_models.dart';
import 'timeline/timeline_providers.dart';

export 'timeline/timeline_providers.dart' show studentBeltProgressionsProvider;

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
              const SliverToBoxAdapter(
                child: TimelineAcademyIndicator(),
              ),

              // Header
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // Journey Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: JourneyCard(
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

    final events = <TimelineEvent>[];

    // Add start event
    events.add(
      TimelineEvent(
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
        TimelineEvent(
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

    // Add achievements (competitions and milestones only)
    for (final a in achievements) {
      if (a.type == AchievementType.competition ||
          a.type == AchievementType.milestone) {
        events.add(
          TimelineEvent(
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

    // Sort ascending then reverse for display (newest at top)
    events.sort((a, b) => a.date.compareTo(b.date));

    if (events.isEmpty) {
      return _buildTimelineEmptyState();
    }

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
          return TimelineItem(event: event, isLast: isLast);
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
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
