import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';

/// Schedule Screen - Horarios das Aulas
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  static const List<WeekDay> _weekDays = [
    WeekDay(value: 1, label: 'Segunda', short: 'Seg'),
    WeekDay(value: 2, label: 'Terca', short: 'Ter'),
    WeekDay(value: 3, label: 'Quarta', short: 'Qua'),
    WeekDay(value: 4, label: 'Quinta', short: 'Qui'),
    WeekDay(value: 5, label: 'Sexta', short: 'Sex'),
    WeekDay(value: 6, label: 'Sabado', short: 'Sab'),
    WeekDay(value: 0, label: 'Domingo', short: 'Dom'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeklyScheduleAsync = ref.watch(weeklyScheduleProvider);
    final currentClassAsync = ref.watch(currentClassProvider);

    final today = DateTime.now().weekday;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(weeklyScheduleProvider);
        ref.invalidate(currentClassProvider);
      },
      child: weeklyScheduleAsync.when(
        data: (weeklySchedule) {
          // Convert map to list of class schedules
          final classes = _buildClassSchedules(weeklySchedule);
          final currentClass = currentClassAsync.valueOrNull;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Horarios das Aulas',
                  style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Grade semanal de treinos',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),

                // Schedule Cards
                if (classes.isEmpty)
                  _buildEmptyState()
                else
                  ...classes.map((classSchedule) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ClassCard(
                          classSchedule: classSchedule,
                          weekDays: _weekDays,
                          today: today,
                          currentClassId: currentClass?.id,
                        ),
                      )),

                const SizedBox(height: 24),

                // Legend
                Row(
                  children: [
                    _LegendItem(
                      color: AppTheme.primary,
                      label: 'Agora',
                    ),
                    const SizedBox(width: 24),
                    _LegendItem(
                      color: AppTheme.primary,
                      label: 'Hoje',
                      isOutlined: true,
                    ),
                  ],
                ),

                const SizedBox(height: 80),
              ],
            ),
          );
        },
        loading: () => _buildLoadingState(),
        error: (_, __) => _buildErrorState(),
      ),
    );
  }

  List<ClassScheduleData> _buildClassSchedules(Map<int, List<BJJClass>> weeklySchedule) {
    // Group by class name to create schedule data
    final classMap = <String, ClassScheduleData>{};

    for (final entry in weeklySchedule.entries) {
      final dayOfWeek = entry.key;
      for (final bjjClass in entry.value) {
        if (!classMap.containsKey(bjjClass.id)) {
          classMap[bjjClass.id] = ClassScheduleData(
            id: bjjClass.id,
            name: bjjClass.name,
            instructor: bjjClass.instructorName,
            scheduleByDay: {},
          );
        }
        final scheduleForDay = bjjClass.getScheduleForDay(dayOfWeek);
        if (scheduleForDay != null) {
          classMap[bjjClass.id]!.scheduleByDay[dayOfWeek] = TimeSlot(
            startTime: scheduleForDay.startTime,
            endTime: scheduleForDay.endTime,
          );
        }
      }
    }

    return classMap.values.toList();
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 200,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 150,
            height: 16,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppTheme.error),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar dados',
              style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Center(
        child: Text(
          'Nenhuma aula cadastrada',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// Class Card Widget
class _ClassCard extends StatelessWidget {
  final ClassScheduleData classSchedule;
  final List<WeekDay> weekDays;
  final int today;
  final String? currentClassId;

  const _ClassCard({
    required this.classSchedule,
    required this.weekDays,
    required this.today,
    this.currentClassId,
  });

  bool _isClassNow(String startTime, String endTime, int dayOfWeek) {
    if (dayOfWeek != today) return false;
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentMinutes = now.minute;
    final startParts = startTime.split(':').map(int.parse).toList();
    final endParts = endTime.split(':').map(int.parse).toList();
    final currentTotal = currentHour * 60 + currentMinutes;
    return currentTotal >= startParts[0] * 60 + startParts[1] &&
        currentTotal <= endParts[0] * 60 + endParts[1];
  }

  @override
  Widget build(BuildContext context) {
    final daysWithClass =
        weekDays.where((day) => classSchedule.scheduleByDay.containsKey(day.value)).toList();
    final hasClassNow = currentClassId == classSchedule.id ||
        daysWithClass.any((day) {
          final schedule = classSchedule.scheduleByDay[day.value];
          return schedule != null && _isClassNow(schedule.startTime, schedule.endTime, day.value);
        });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasClassNow ? AppTheme.primary : AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasClassNow ? AppTheme.primary : AppTheme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    classSchedule.name,
                    style: AppTheme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: hasClassNow ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                  if (classSchedule.instructor != null)
                    Text(
                      classSchedule.instructor!,
                      style: AppTheme.labelSmall.copyWith(
                        color: hasClassNow ? Colors.white70 : AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
              if (hasClassNow)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'AGORA',
                    style: AppTheme.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Day chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: daysWithClass.map((day) {
              final schedule = classSchedule.scheduleByDay[day.value]!;
              final isToday = day.value == today;
              final isNow = _isClassNow(schedule.startTime, schedule.endTime, day.value);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: hasClassNow
                      ? isNow
                          ? Colors.white.withOpacity(0.25)
                          : Colors.white.withOpacity(0.1)
                      : isToday
                          ? AppTheme.primary
                          : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      day.short,
                      style: AppTheme.labelSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: hasClassNow
                            ? Colors.white
                            : isToday
                                ? Colors.white
                                : AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      schedule.startTime,
                      style: AppTheme.labelSmall.copyWith(
                        color: hasClassNow
                            ? Colors.white
                            : isToday
                                ? Colors.white
                                : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Legend Item
class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool isOutlined;

  const _LegendItem({
    required this.color,
    required this.label,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: isOutlined ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(2),
            border: isOutlined ? Border.all(color: color, width: 2) : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

/// Data Models
class ClassScheduleData {
  final String id;
  final String name;
  final String? instructor;
  final Map<int, TimeSlot> scheduleByDay;

  ClassScheduleData({
    required this.id,
    required this.name,
    this.instructor,
    required this.scheduleByDay,
  });
}

class TimeSlot {
  final String startTime;
  final String endTime;

  TimeSlot({required this.startTime, required this.endTime});
}

class WeekDay {
  final int value;
  final String label;
  final String short;

  const WeekDay({required this.value, required this.label, required this.short});
}
