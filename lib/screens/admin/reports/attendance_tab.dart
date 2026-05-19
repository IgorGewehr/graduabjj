import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import 'shared_widgets.dart';

class AttendanceTab extends StatelessWidget {
  final Map<String, int> attendanceByDay;
  final int totalAttendanceThisMonth;
  final int totalAttendanceLastMonth;
  final double averageAttendancePerDay;
  final int peakDay;
  final String peakDayName;

  const AttendanceTab({
    super.key,
    required this.attendanceByDay,
    required this.totalAttendanceThisMonth,
    required this.totalAttendanceLastMonth,
    required this.averageAttendancePerDay,
    required this.peakDay,
    required this.peakDayName,
  });

  String _shortDayName(String fullName) {
    const shortNames = {
      'segunda-feira': 'Seg',
      'terca-feira': 'Ter',
      'quarta-feira': 'Qua',
      'quinta-feira': 'Qui',
      'sexta-feira': 'Sex',
      'sabado': 'Sab',
      'domingo': 'Dom',
    };
    return shortNames[fullName] ?? fullName;
  }

  @override
  Widget build(BuildContext context) {
    final change = totalAttendanceLastMonth > 0
        ? ((totalAttendanceThisMonth - totalAttendanceLastMonth) /
              totalAttendanceLastMonth *
              100)
        : 0.0;
    final isPositive = change >= 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main stat card
          MainStatCard(
            title: 'Total de Presencas',
            value: totalAttendanceThisMonth.toString(),
            subtitle: 'neste mes',
            icon: LucideIcons.checkCircle,
            color: AppTheme.success,
            change: change,
            isPositive: isPositive,
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.trendingUp,
                  label: 'Media/Dia',
                  value: averageAttendancePerDay.toStringAsFixed(1),
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.flame,
                  label: 'Pico',
                  value: '$peakDay',
                  subtitle: _shortDayName(peakDayName),
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Chart
          ReportCard(
            title: 'Presencas por Dia',
            icon: LucideIcons.barChart3,
            child: Column(
              children: [
                'segunda-feira',
                'terca-feira',
                'quarta-feira',
                'quinta-feira',
                'sexta-feira',
                'sabado',
              ].map((day) {
                final value = attendanceByDay[day] ?? 0;
                final maxValue = attendanceByDay.values.fold(
                  1,
                  (a, b) => a > b ? a : b,
                );
                final percentage = value / maxValue;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          _shortDayName(day),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: percentage,
                              child: Container(
                                height: 28,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.primary,
                                      AppTheme.primary.withValues(alpha: 0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 32,
                        child: Text(
                          value.toString(),
                          style: AppTheme.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
