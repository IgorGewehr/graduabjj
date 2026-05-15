import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/checkin.dart';
import '../../providers/providers.dart';
import '../../providers/portal_providers.dart';
import '../../providers/selected_academy_provider.dart';
import '../../services/services.dart';
import '../../services/checkin_service.dart';

/// Schedule Screen - Horarios das Aulas / Meus Treinos
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  bool _isCreatingCheckin = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final settingsAsync = ref.watch(academySettingsProvider);
    final currentStudent = ref.watch(currentStudentProvider).valueOrNull;

    final studentId = currentStudent?.id ?? currentUser?.studentId;
    final academyId = currentUser?.academyId;

    if (studentId == null || academyId == null) {
      return _buildEmptyState('Aluno nao encontrado');
    }

    final checkinEnabled =
        settingsAsync.valueOrNull?.studentCheckinEnabled ?? false;

    // Fetch classes where student is enrolled
    final classesAsync = ref.watch(
      _enrolledClassesProvider(
        _EnrolledClassesParams(academyId: academyId, studentId: studentId),
      ),
    );

    // Fetch student's pending check-ins
    final studentCheckinsAsync = checkinEnabled
        ? ref.watch(studentPendingCheckinsProvider(studentId))
        : const AsyncValue<List<Checkin>>.data([]);

    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        ref.invalidate(
          _enrolledClassesProvider(
            _EnrolledClassesParams(academyId: academyId, studentId: studentId),
          ),
        );
        if (checkinEnabled) {
          ref.invalidate(studentPendingCheckinsProvider(studentId));
        }
      },
      child: classesAsync.when(
        data: (classes) {
          final studentCheckins = studentCheckinsAsync.valueOrNull ?? [];
          final upcomingSchedules = _buildUpcomingSchedules(
            classes,
            studentCheckins,
            checkinEnabled,
          );

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Academy indicator for multi-academy users
                const _AcademyIndicator(),

                // Info banner for check-in
                if (checkinEnabled) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.info.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: AppTheme.info,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Check-in disponivel de 30 min antes do inicio ate 1h apos o fim da aula.',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(LucideIcons.qrCode, size: 16),
                      label: const Text('Escanear QR da aula'),
                      onPressed: () => context.push('/portal/scan'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Schedule Cards
                if (classes.isEmpty)
                  _buildEmptyState('Voce nao esta matriculado em nenhuma turma')
                else if (upcomingSchedules.isEmpty)
                  _buildEmptyState('Nenhuma aula programada')
                else
                  ..._buildSchedulesByDay(
                    upcomingSchedules,
                    studentId,
                    currentStudent?.fullName ?? 'Aluno',
                    checkinEnabled,
                  ),

                const SizedBox(height: 24),

                // Legend
                if (checkinEnabled && classes.isNotEmpty)
                  Row(
                    children: [
                      _LegendItem(
                        color: AppTheme.success,
                        label: 'Check-in disponivel',
                        isOutlined: true,
                      ),
                      const SizedBox(width: 24),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: AppTheme.success,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Check-in realizado',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
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

  List<UpcomingSchedule> _buildUpcomingSchedules(
    List<BJJClass> classes,
    List<Checkin> studentCheckins,
    bool checkinEnabled,
  ) {
    final now = DateTime.now();
    final schedules = <UpcomingSchedule>[];

    // Get next 7 days
    for (int i = 0; i < 7; i++) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: i));
      final dayOfWeek = date.weekday % 7; // Convert to 0-6

      for (final bjjClass in classes) {
        final classSchedules = bjjClass.schedule
            .where((s) => s.dayOfWeek == dayOfWeek)
            .toList();

        for (final schedule in classSchedules) {
          final isToday = i == 0;
          final inWindow =
              isToday &&
              isInCheckinWindow(
                startTime: schedule.startTime,
                endTime: schedule.endTime,
                date: date,
              );
          final timeUntilWindow = isToday
              ? getTimeUntilCheckinOpens(
                  startTime: schedule.startTime,
                  date: date,
                )
              : null;

          final hasCheckin = studentCheckins.any(
            (c) =>
                c.classId == bjjClass.id &&
                c.scheduleDate.year == date.year &&
                c.scheduleDate.month == date.month &&
                c.scheduleDate.day == date.day,
          );

          schedules.add(
            UpcomingSchedule(
              bjjClass: bjjClass,
              date: date,
              dayOfWeek: dayOfWeek,
              startTime: schedule.startTime,
              endTime: schedule.endTime,
              isToday: isToday,
              inWindow: inWindow,
              timeUntilWindow: timeUntilWindow,
              hasCheckin: hasCheckin,
            ),
          );
        }
      }
    }

    // Sort by date, then start time
    schedules.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.startTime.compareTo(b.startTime);
    });

    return schedules;
  }

  List<Widget> _buildSchedulesByDay(
    List<UpcomingSchedule> schedules,
    String studentId,
    String studentName,
    bool checkinEnabled,
  ) {
    final widgets = <Widget>[];
    final groupedByDate = <String, List<UpcomingSchedule>>{};

    for (final schedule in schedules) {
      final key = DateFormat('yyyy-MM-dd').format(schedule.date);
      groupedByDate.putIfAbsent(key, () => []).add(schedule);
    }

    for (final entry in groupedByDate.entries) {
      final dateSchedules = entry.value;
      final isToday = dateSchedules.first.isToday;

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            isToday
                ? 'HOJE'
                : DateFormat(
                    "EEEE, d 'de' MMMM",
                    'pt_BR',
                  ).format(dateSchedules.first.date),
            style: AppTheme.labelSmall.copyWith(
              color: isToday ? AppTheme.success : AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );

      for (final schedule in dateSchedules) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ScheduleCard(
              schedule: schedule,
              studentId: studentId,
              studentName: studentName,
              checkinEnabled: checkinEnabled,
              isCreating: _isCreatingCheckin,
              onCheckin: () => _handleCheckin(schedule, studentId, studentName),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Future<void> _handleCheckin(
    UpcomingSchedule schedule,
    String studentId,
    String studentName,
  ) async {
    if (_isCreatingCheckin) return;

    // Sprint 6 — light tap on press, success haptic after Firestore confirms.
    HapticFeedback.selectionClick();
    setState(() => _isCreatingCheckin = true);

    try {
      final actions = ref.read(checkinActionsProvider.notifier);
      await actions.createCheckin(
        studentId: studentId,
        studentName: studentName,
        classId: schedule.bjjClass.id,
        className: schedule.bjjClass.name,
        scheduleStartTime: schedule.startTime,
        scheduleEndTime: schedule.endTime,
        scheduleDayOfWeek: schedule.dayOfWeek,
      );

      if (mounted) {
        HapticFeedback.heavyImpact();
        context.showSuccess('Check-in realizado com sucesso!');
        ref.invalidate(studentPendingCheckinsProvider(studentId));
      }
    } catch (e) {
      if (mounted) {
        context.showError(e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingCheckin = false);
      }
    }
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(
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
              style: AppTheme.titleLarge.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Center(
        child: Text(
          message,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// Schedule Card Widget
class _ScheduleCard extends StatelessWidget {
  final UpcomingSchedule schedule;
  final String studentId;
  final String studentName;
  final bool checkinEnabled;
  final bool isCreating;
  final VoidCallback onCheckin;

  const _ScheduleCard({
    required this.schedule,
    required this.studentId,
    required this.studentName,
    required this.checkinEnabled,
    required this.isCreating,
    required this.onCheckin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: schedule.inWindow
            ? AppTheme.success.withOpacity(0.05)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: schedule.inWindow
              ? AppTheme.success.withOpacity(0.3)
              : AppTheme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.bjjClass.name,
                      style: AppTheme.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (schedule.bjjClass.instructorName != null)
                      Text(
                        schedule.bjjClass.instructorName!,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${schedule.startTime} - ${schedule.endTime}',
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Check-in section
          if (checkinEnabled && schedule.isToday) ...[
            const SizedBox(height: 12),
            _buildCheckinSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckinSection() {
    if (schedule.hasCheckin) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: AppTheme.success),
            const SizedBox(width: 6),
            Text(
              'Check-in feito',
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (schedule.inWindow) {
      return ElevatedButton.icon(
        onPressed: isCreating ? null : onCheckin,
        icon: isCreating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.how_to_reg, size: 18),
        label: Text(isCreating ? 'Aguarde...' : 'Marcar Presenca'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.success,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    if (schedule.timeUntilWindow != null) {
      final hours = schedule.timeUntilWindow!['hours']!;
      final minutes = schedule.timeUntilWindow!['minutes']!;
      final timeText = hours > 0 ? '${hours}h ${minutes}min' : '${minutes}min';

      return Text(
        'Abre em $timeText',
        style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
      );
    }

    return const SizedBox.shrink();
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
class UpcomingSchedule {
  final BJJClass bjjClass;
  final DateTime date;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final bool isToday;
  final bool inWindow;
  final Map<String, int>? timeUntilWindow;
  final bool hasCheckin;

  UpcomingSchedule({
    required this.bjjClass,
    required this.date,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.isToday,
    required this.inWindow,
    this.timeUntilWindow,
    required this.hasCheckin,
  });
}

class WeekDay {
  final int value;
  final String label;
  final String short;

  const WeekDay({
    required this.value,
    required this.label,
    required this.short,
  });
}

/// Provider for enrolled classes
class _EnrolledClassesParams {
  final String academyId;
  final String studentId;

  _EnrolledClassesParams({required this.academyId, required this.studentId});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _EnrolledClassesParams) return false;
    return academyId == other.academyId && studentId == other.studentId;
  }

  @override
  int get hashCode => Object.hash(academyId, studentId);
}

final _enrolledClassesProvider =
    FutureProvider.family<List<BJJClass>, _EnrolledClassesParams>((
      ref,
      params,
    ) async {
      final classService = ClassService(params.academyId);
      final allClasses = await classService.list();

      // Filter classes where student is enrolled
      return allClasses
          .where((c) => c.studentIds.contains(params.studentId))
          .toList();
    });

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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.calendar, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Horarios de',
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
