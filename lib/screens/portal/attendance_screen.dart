import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';

/// Attendance Screen - Minhas Presencas
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildNoStudentState();
        }

        final attendanceAsync = ref.watch(studentAttendanceProvider(student.id));
        final countAsync = ref.watch(studentAttendanceCountProvider(student.id));

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(studentAttendanceProvider(student.id));
            ref.invalidate(studentAttendanceCountProvider(student.id));
          },
          child: attendanceAsync.when(
            data: (records) {
              final totalCount = countAsync.valueOrNull ?? records.length;
              final thisMonthCount = _getThisMonthCount(records);
              final calendarDays = _getCalendarDays(records);

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats Cards
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            value: totalCount.toString(),
                            label: 'total de presencas',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            value: thisMonthCount.toString(),
                            label: 'este mes',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Calendar View
                    _CalendarView(
                      days: calendarDays,
                      monthLabel: DateFormat('MMMM yyyy', 'pt_BR').format(DateTime.now()),
                    ),
                    const SizedBox(height: 24),

                    // Recent Attendance List
                    Text(
                      'HISTORICO RECENTE',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (records.isEmpty)
                      _buildEmptyState()
                    else
                      ...records.take(15).map((record) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AttendanceListItem(record: record),
                      )),

                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
            loading: () => _buildLoadingState(),
            error: (_, __) => _buildErrorState(),
          ),
        );
      },
      loading: () => _buildLoadingState(),
      error: (_, __) => _buildErrorState(),
    );
  }

  int _getThisMonthCount(List<Attendance> records) {
    final now = DateTime.now();
    return records.where((r) => r.date.month == now.month && r.date.year == now.year).length;
  }

  List<CalendarDay> _getCalendarDays(List<Attendance> records) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);

    final days = <CalendarDay>[];
    for (var day = firstDayOfMonth;
        day.isBefore(lastDayOfMonth.add(const Duration(days: 1)));
        day = day.add(const Duration(days: 1))) {
      final hasAttendance = records.any((r) =>
          r.date.year == day.year && r.date.month == day.month && r.date.day == day.day);
      days.add(CalendarDay(date: day, hasAttendance: hasAttendance));
    }
    return days;
  }

  Widget _buildNoStudentState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.clipboardCheck, size: 64, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Conta nao vinculada',
              style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Vincule sua conta a um aluno para ver as presencas.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
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
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 280,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
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
            Icon(LucideIcons.alertCircle, size: 64, color: AppTheme.error),
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
          'Nenhuma presenca registrada ainda',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String value;
  final String label;

  const _StatCard({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTheme.displaySmall.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Calendar View Widget
class _CalendarView extends StatelessWidget {
  final List<CalendarDay> days;
  final String monthLabel;

  const _CalendarView({
    required this.days,
    required this.monthLabel,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = days.isNotEmpty ? days.first.date : DateTime.now();
    final startPadding = firstDay.weekday % 7; // Sunday = 0

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month label
          Row(
            children: [
              const Icon(LucideIcons.calendar, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                monthLabel,
                style: AppTheme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Week days header
          Row(
            children: ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']
                .map((day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),

          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: startPadding + days.length,
            itemBuilder: (context, index) {
              if (index < startPadding) {
                return const SizedBox();
              }
              final day = days[index - startPadding];
              final isToday = _isSameDay(day.date, DateTime.now());
              final isFuture = day.date.isAfter(DateTime.now());

              return Container(
                decoration: BoxDecoration(
                  color: day.hasAttendance ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: isToday && !day.hasAttendance
                      ? Border.all(color: AppTheme.primary, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    '${day.date.day}',
                    style: AppTheme.labelSmall.copyWith(
                      color: day.hasAttendance
                          ? Colors.white
                          : isFuture
                              ? AppTheme.textDisabled
                              : AppTheme.textPrimary,
                      fontWeight:
                          day.hasAttendance || isToday ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// Attendance List Item
class _AttendanceListItem extends StatelessWidget {
  final Attendance record;

  const _AttendanceListItem({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.successLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              LucideIcons.checkCircle,
              size: 18,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat("d 'de' MMMM", 'pt_BR').format(record.date),
                  style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  record.className.isNotEmpty ? record.className : 'Treino',
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Data Models
class CalendarDay {
  final DateTime date;
  final bool hasAttendance;

  CalendarDay({required this.date, required this.hasAttendance});
}
