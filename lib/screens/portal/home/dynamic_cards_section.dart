import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/checkin_service.dart';
import 'monthly_card.dart';
import 'next_class_card.dart';
import 'next_competition_card.dart';
import 'streak_card.dart';

/// Dynamic Cards Section with real data — orchestrates the home dashboard cards
class DynamicCardsSection extends ConsumerWidget {
  final String studentId;
  final void Function(String path) onTap;

  const DynamicCardsSection({
    super.key,
    required this.studentId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextClassAsync = ref.watch(studentNextClassProvider(studentId));
    final streakAsync = ref.watch(studentStreakProvider(studentId));
    final monthlyAttendanceAsync = ref.watch(
      studentMonthlyAttendanceProvider(studentId),
    );
    final upcomingCompetitionsAsync = ref.watch(upcomingCompetitionsProvider);
    final checkinEnabled = ref.watch(
      academySettingsProvider.select(
        (s) => s.valueOrNull?.studentCheckinEnabled ?? false,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Next Class Card (Featured)
        nextClassAsync.when(
          data: (data) {
            if (data == null || data.classInfo == null) {
              return NextClassCard(
                className: null,
                schedule: null,
                nextDate: null,
                checkinEnabled: false,
                canCheckin: false,
                onTap: () => onTap('/portal/horarios'),
              );
            }

            final canCheckin =
                checkinEnabled &&
                data.nextDate != null &&
                data.schedule != null &&
                isInCheckinWindow(
                  startTime: data.schedule!.startTime,
                  endTime: data.schedule!.endTime,
                  date: data.nextDate!,
                );

            return NextClassCard(
              className: data.classInfo!.name,
              schedule: data.schedule,
              nextDate: data.nextDate,
              checkinEnabled: checkinEnabled,
              canCheckin: canCheckin,
              onTap: () => onTap('/portal/horarios'),
            );
          },
          loading: () => NextClassCard(
            className: null,
            schedule: null,
            nextDate: null,
            isLoading: true,
            checkinEnabled: false,
            canCheckin: false,
            onTap: () => onTap('/portal/horarios'),
          ),
          error: (_, __) => NextClassCard(
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
                data: (streak) => StreakCard(
                  streak: streak,
                  onTap: () => onTap('/portal/presencas'),
                ),
                loading: () => StreakCard(
                  streak: 0,
                  isLoading: true,
                  onTap: () => onTap('/portal/presencas'),
                ),
                error: (_, __) => StreakCard(
                  streak: 0,
                  onTap: () => onTap('/portal/presencas'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: monthlyAttendanceAsync.when(
                data: (count) => MonthlyCard(
                  count: count,
                  onTap: () => onTap('/portal/presencas'),
                ),
                loading: () => MonthlyCard(
                  count: 0,
                  isLoading: true,
                  onTap: () => onTap('/portal/presencas'),
                ),
                error: (_, __) => MonthlyCard(
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
            return NextCompetitionCard(
              competition: next,
              onTap: () => onTap('/portal/competicoes'),
            );
          },
          loading: () => NextCompetitionCard(
            competition: null,
            isLoading: true,
            onTap: () => onTap('/portal/competicoes'),
          ),
          error: (_, __) => NextCompetitionCard(
            competition: null,
            onTap: () => onTap('/portal/competicoes'),
          ),
        ),
      ],
    );
  }
}
