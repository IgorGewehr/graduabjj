import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';

/// Minhas Modalidades — read-only list of every sport the student trains.
///
/// The portal shell (portal_shell.dart) already provides the Scaffold, AppBar
/// and bottom nav, so this screen returns body content directly (mirroring
/// evolution_screen.dart). The "Minhas Modalidades" title is rendered as an
/// in-body header to avoid stacking a second app bar.
class MySportsScreen extends ConsumerWidget {
  const MySportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) return _buildNoStudentState();
        final sports = student.getSports();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text('Minhas Modalidades', style: AppTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              sports.length == 1
                  ? '1 modalidade'
                  : '${sports.length} modalidades',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            for (final sport in sports)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SportEnrollmentCard(student: student, sport: sport),
              ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
      error: (error, stack) => _buildNoStudentState(),
    );
  }

  Widget _buildNoStudentState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.dumbbell, size: 64,
                color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Conta nao vinculada',
              style: AppTheme.titleLarge.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vincule sua conta a um aluno para ver suas modalidades.',
              style: AppTheme.bodyMedium.copyWith(
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

/// A single read-only enrollment card for one sport the student trains.
class _SportEnrollmentCard extends StatelessWidget {
  const _SportEnrollmentCard({required this.student, required this.sport});

  final Student student;
  final SportId sport;

  @override
  Widget build(BuildContext context) {
    final def = getSport(sport);
    final accent = sportChipColors[sport] ?? AppTheme.primary;
    final grade = student.getGrade(sport);

    final String gradeLabel;
    if (grade == null) {
      gradeLabel = 'Sem graduacao';
    } else {
      final label = getGradeLabel(sport, grade.currentGrade);
      final stripes = grade.currentStripes;
      gradeLabel = stripes > 0
          ? '$label · ${stripes == 1 ? '1 grau' : '$stripes graus'}'
          : label;
    }

    final startLabel = _startDateLabel();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(def.icon, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.label,
                  style: AppTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _GradeBadge(label: gradeLabel, accent: accent),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.calendar,
                            size: 13, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Desde $startLabel',
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Reads sportData[sport.value]["startDate"] defensively. Returns "—" when
  /// absent or of an unexpected type — never throws.
  String _startDateLabel() {
    final raw = student.sportData?[sport.value];
    if (raw is! Map) return '—';
    final value = raw['startDate'];
    DateTime? date;
    if (value is DateTime) {
      date = value;
    } else if (value is String && value.isNotEmpty) {
      date = DateTime.tryParse(value);
    } else {
      // Firestore Timestamp exposes a toDate() — call it reflectively-safely.
      try {
        final dynamic dyn = value;
        if (dyn != null) {
          final maybe = dyn.toDate();
          if (maybe is DateTime) date = maybe;
        }
      } catch (_) {
        date = null;
      }
    }
    if (date == null) return '—';
    return DateFormat('MMM yyyy', 'pt_BR').format(date);
  }
}

class _GradeBadge extends StatelessWidget {
  const _GradeBadge({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTheme.bodySmall.copyWith(
          color: accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
