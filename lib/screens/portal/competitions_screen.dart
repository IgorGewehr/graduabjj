import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';

/// Competitions Screen - Competicoes
class CompetitionsScreen extends ConsumerWidget {
  const CompetitionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);
    final competitionsAsync = ref.watch(competitionsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(competitionsProvider);
        ref.invalidate(currentStudentProvider);
      },
      child: competitionsAsync.when(
        data: (competitions) {
          final student = studentAsync.valueOrNull;
          final upcomingCompetitions =
              competitions.where((c) => c.status == CompetitionStatus.upcoming).toList();
          final pastCompetitions = competitions
              .where((c) =>
                  c.status == CompetitionStatus.completed ||
                  c.status == CompetitionStatus.cancelled)
              .toList();

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Competicoes',
                  style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Acompanhe as competicoes e inscricoes',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),

                // Student results summary
                if (student != null) ...[
                  _StudentResultsSummary(student: student),
                  const SizedBox(height: 24),
                ],

                // Upcoming Competitions
                if (upcomingCompetitions.isNotEmpty) ...[
                  Text(
                    'PROXIMAS COMPETICOES',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...upcomingCompetitions.map((competition) {
                    // Check if enrolled
                    bool isEnrolled = false;
                    if (student != null) {
                      final enrolledAsync = ref.watch(
                        isStudentEnrolledProvider((
                          competitionId: competition.id,
                          studentId: student.id,
                        )),
                      );
                      isEnrolled = enrolledAsync.valueOrNull ?? false;
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CompetitionCard(
                        competition: competition,
                        isEnrolled: isEnrolled,
                        isUpcoming: true,
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],

                // Past Competitions
                if (pastCompetitions.isNotEmpty) ...[
                  Text(
                    'COMPETICOES ANTERIORES',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...pastCompetitions.map((competition) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CompetitionCard(
                          competition: competition,
                          isEnrolled: false,
                          isUpcoming: false,
                        ),
                      )),
                ],

                // Empty state
                if (competitions.isEmpty) _buildEmptyState(),

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
          const SizedBox(height: 24),
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 140,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.trophy, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Nenhuma competicao cadastrada',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Student Results Summary
class _StudentResultsSummary extends ConsumerWidget {
  final Student student;

  const _StudentResultsSummary({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medalCountAsync = ref.watch(studentMedalCountProvider(student.id));

    return medalCountAsync.when(
      data: (medals) {
        final total = medals['total'] ?? 0;
        if (total == 0) {
          return const SizedBox.shrink();
        }

        final gold = medals['gold'] ?? 0;
        final silver = medals['silver'] ?? 0;
        final bronze = medals['bronze'] ?? 0;

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
              Row(
                children: [
                  const Icon(LucideIcons.trophy, size: 18, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  Text(
                    'Minhas Conquistas',
                    style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MedalCard(
                      icon: LucideIcons.medal,
                      color: const Color(0xFFFFD700), // Gold
                      count: gold,
                      label: 'Ouro',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MedalCard(
                      icon: LucideIcons.medal,
                      color: const Color(0xFFC0C0C0), // Silver
                      count: silver,
                      label: 'Prata',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MedalCard(
                      icon: LucideIcons.medal,
                      color: const Color(0xFFCD7F32), // Bronze
                      count: bronze,
                      label: 'Bronze',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Medal Card
class _MedalCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const _MedalCard({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: AppTheme.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Competition Card
class _CompetitionCard extends StatelessWidget {
  final Competition competition;
  final bool isEnrolled;
  final bool isUpcoming;

  const _CompetitionCard({
    required this.competition,
    required this.isEnrolled,
    required this.isUpcoming,
  });

  @override
  Widget build(BuildContext context) {
    final daysUntil = competition.date.difference(DateTime.now()).inDays;
    final isSoon = daysUntil <= 7 && daysUntil >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSoon && isUpcoming ? AppTheme.warning : AppTheme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isUpcoming ? AppTheme.warningLight : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  LucideIcons.trophy,
                  color: isUpcoming ? AppTheme.warning : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      competition.name,
                      style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (competition.location != null)
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.mapPin,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              competition.location!,
                              style: AppTheme.labelSmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (isEnrolled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.successLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Inscrito',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Info row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.calendar,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat("d 'de' MMM", 'pt_BR').format(competition.date),
                        style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                if (isUpcoming && daysUntil >= 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSoon ? AppTheme.warning : AppTheme.info,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      daysUntil == 0
                          ? 'Hoje!'
                          : daysUntil == 1
                              ? 'Amanha!'
                              : 'Em $daysUntil dias',
                      style: AppTheme.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Deadline info
          if (isUpcoming && competition.registrationDeadline != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  LucideIcons.clock,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Inscricoes ate ${DateFormat("d 'de' MMM", 'pt_BR').format(competition.registrationDeadline!)}',
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],

          // Description
          if (competition.description != null && competition.description!.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              competition.description!,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
