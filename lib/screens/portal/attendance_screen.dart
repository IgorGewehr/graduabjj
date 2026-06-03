import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';
import '../../widgets/skeletons/skeletons.dart';
import '../../widgets/sport_tab_bar.dart';

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

        final attendanceAsync = ref.watch(
          studentAttendanceProvider(student.id),
        );
        final countAsync = ref.watch(
          studentAttendanceCountProvider(student.id),
        );

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            ref.invalidate(studentAttendanceProvider(student.id));
            ref.invalidate(studentAttendanceCountProvider(student.id));
          },
          child: attendanceAsync.when(
            data: (allRecords) {
              // Multi-sport students can filter their attendance by sport.
              // SportTabBar hides itself when sports.length <= 1, so a
              // single-sport student sees the full, unfiltered list and an
              // identical layout. A doc with no sport is legacy data and is
              // grouped under BJJ — matches graduation/admin filter logic.
              //
              // This is a client-side filter over the already-fetched list:
              // no extra Firestore query and no composite index. A
              // server-side sport-filtered query would be a future
              // optimization if a single student ever exceeds ~365 records.
              final sports = student.getSports();
              final showSportFilter = sports.length > 1;
              final selectedSport =
                  ref.watch(selectedSportProvider('attendance')) ??
                  student.getPrimarySport();
              final records = showSportFilter
                  ? allRecords
                      .where(
                        (r) => (r.sport ?? 'bjj') == selectedSport.value,
                      )
                      .toList()
                  : allRecords;

              // When a sport filter is active the total reflects the filtered
              // list; otherwise we trust the server-side aggregate count.
              final totalCount = showSportFilter
                  ? records.length
                  : (countAsync.valueOrNull ?? records.length);
              final thisMonthCount = _getThisMonthCount(records);
              final calendarDays = _getCalendarDays(records);

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Academy indicator for multi-academy users
                    _AcademyIndicator(),

                    // Per-sport filter (multi-sport students only).
                    if (showSportFilter) ...[
                      SportTabBar(
                        sports: sports,
                        selected: selectedSport,
                        onSelected: (s) => ref
                            .read(
                              selectedSportProvider('attendance').notifier,
                            )
                            .state = s,
                      ),
                      const SizedBox(height: 12),
                    ],

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
                      monthLabel: DateFormat(
                        'MMMM yyyy',
                        'pt_BR',
                      ).format(DateTime.now()),
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

                    // Wrap the recent list in an AnimatedSwitcher keyed by
                    // the count so a new check-in slides in instead of
                    // popping. Cheap visual cue with no layout cost.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, -0.1),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: records.isEmpty
                          ? KeyedSubtree(
                              key: const ValueKey('attendance-empty'),
                              child: _buildEmptyState(),
                            )
                          : Column(
                              key: ValueKey('attendance-${records.length}'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var i = 0;
                                    i < records.take(15).length;
                                    i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _AttendanceListItem(
                                      record: records[i],
                                    ).entrance(index: i),
                                  ),
                              ],
                            ),
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
      },
      loading: () => _buildLoadingState(),
      error: (_, __) => _buildErrorState(),
    );
  }

  int _getThisMonthCount(List<Attendance> records) {
    final now = DateTime.now();
    return records
        .where((r) => r.date.month == now.month && r.date.year == now.year)
        .length;
  }

  List<CalendarDay> _getCalendarDays(List<Attendance> records) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);

    final days = <CalendarDay>[];
    for (
      var day = firstDayOfMonth;
      day.isBefore(lastDayOfMonth.add(const Duration(days: 1)));
      day = day.add(const Duration(days: 1))
    ) {
      final hasAttendance = records.any(
        (r) =>
            r.date.year == day.year &&
            r.date.month == day.month &&
            r.date.day == day.day,
      );
      days.add(CalendarDay(date: day, hasAttendance: hasAttendance));
    }
    return days;
  }

  Widget _buildNoStudentState() {
    return const PolishedEmptyState(
      icon: LucideIcons.clipboardCheck,
      title: 'Conta nao vinculada',
      subtitle: 'Vincule sua conta a um aluno para ver as presencas.',
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonStats(count: 2, height: 72),
          SizedBox(height: 24),
          SkeletonCard(
            height: 280,
            showAvatar: false,
            padding: EdgeInsets.zero,
          ),
          SizedBox(height: 24),
          SkeletonList(
            itemCount: 6,
            scrollable: false,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return const PolishedEmptyState(
      icon: LucideIcons.alertCircle,
      title: 'Erro ao carregar dados',
      accent: AppTheme.error,
    );
  }

  Widget _buildEmptyState() {
    return const PolishedEmptyState(
      icon: LucideIcons.clipboardCheck,
      title: 'Nenhuma presenca registrada ainda',
    );
  }
}

/// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String value;
  final String label;

  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final numeric = int.tryParse(value);
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
          if (numeric != null)
            AnimatedCountUp(
              value: numeric,
              style:
                  AppTheme.displaySmall.copyWith(fontWeight: FontWeight.w700),
            )
          else
            Text(
              value,
              style:
                  AppTheme.displaySmall.copyWith(fontWeight: FontWeight.w700),
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

  const _CalendarView({required this.days, required this.monthLabel});

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
              const Icon(
                LucideIcons.calendar,
                size: 16,
                color: AppTheme.textSecondary,
              ),
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
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                )
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
                  color: day.hasAttendance
                      ? AppTheme.primary
                      : Colors.transparent,
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
                      fontWeight: day.hasAttendance || isToday
                          ? FontWeight.w600
                          : FontWeight.w400,
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
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  record.className.isNotEmpty ? record.className : 'Treino',
                  style: AppTheme.labelSmall.copyWith(
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

/// Data Models
class CalendarDay {
  final DateTime date;
  final bool hasAttendance;

  CalendarDay({required this.date, required this.hasAttendance});
}

/// Academy Indicator - Shows current academy for multi-academy users
class _AcademyIndicator extends ConsumerWidget {
  const _AcademyIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);
    if (!hasMultiple) return const SizedBox.shrink();

    final academyInfo = ref.watch(currentAcademyInfoProvider);
    if (academyInfo == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.infoLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: academyInfo.logoUrl == null ? AppTheme.primary : null,
                borderRadius: BorderRadius.circular(6),
              ),
              clipBehavior: Clip.antiAlias,
              child: academyInfo.logoUrl != null
                  ? AppCachedImage(
                      imageUrl: academyInfo.logoUrl,
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                      errorIcon: _buildDefaultLogo(academyInfo.name),
                    )
                  : _buildDefaultLogo(academyInfo.name),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Presencas em ${academyInfo.name}',
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.info,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => _showAcademySwitcher(context, ref),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Trocar',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      LucideIcons.chevronDown,
                      size: 12,
                      color: AppTheme.info,
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

  Widget _buildDefaultLogo(String name) {
    return Container(
      width: 28,
      height: 28,
      color: AppTheme.primary,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'A',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _showAcademySwitcher(BuildContext context, WidgetRef ref) {
    final academiesAsync = ref.read(userAcademiesInfoProvider);
    final selectedId = ref.read(selectedAcademyIdProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Ver presencas de',
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              academiesAsync.when(
                data: (academies) => ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: academies.length,
                  itemBuilder: (context, index) {
                    final academy = academies[index];
                    final isSelected = academy.id == selectedId;
                    return ListTile(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        ref
                            .read(selectedAcademyProvider.notifier)
                            .selectAcademy(academy.id);
                      },
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: academy.logoUrl == null
                              ? AppTheme.primary
                              : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: academy.logoUrl != null
                            ? AppCachedImage(
                                imageUrl: academy.logoUrl,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                errorIcon: _buildDefaultLogo(academy.name),
                              )
                            : _buildDefaultLogo(academy.name),
                      ),
                      title: Text(
                        academy.name,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              LucideIcons.check,
                              color: AppTheme.success,
                              size: 20,
                            )
                          : null,
                    );
                  },
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
                error: (_, __) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Erro ao carregar academias'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
