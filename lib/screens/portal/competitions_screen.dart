import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/competitions/team_gallery_view.dart';
import '../../widgets/skeletons/skeletons.dart';

/// Competitions Screen - Competicoes (with Tabs)
class CompetitionsScreen extends ConsumerStatefulWidget {
  const CompetitionsScreen({super.key});

  @override
  ConsumerState<CompetitionsScreen> createState() => _CompetitionsScreenState();
}

class _CompetitionsScreenState extends ConsumerState<CompetitionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentAsync = ref.watch(currentStudentProvider);
    final competitionsAsync = ref.watch(competitionsProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildEmptyState('Perfil nao encontrado');
        }

        return competitionsAsync.when(
          data: (competitions) {
            // Separate competitions by status
            final upcomingCompetitions = competitions
                .where((c) => c.status == CompetitionStatus.upcoming)
                .toList();

            final pastCompetitions = competitions
                .where(
                  (c) =>
                      c.status == CompetitionStatus.completed ||
                      c.status == CompetitionStatus.cancelled,
                )
                .toList();

            // Get student enrollments
            final enrollmentsAsync = ref.watch(
              studentEnrollmentsProvider(student.id),
            );
            final enrollments = enrollmentsAsync.valueOrNull ?? [];

            // Filter for enrolled upcoming competitions
            final enrolledUpcoming = upcomingCompetitions.where((c) {
              return enrollments.any((e) => e.competitionId == c.id);
            }).toList();

            return RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: () async {
                HapticFeedback.mediumImpact();
                ref.invalidate(competitionsProvider);
                ref.invalidate(currentStudentProvider);
                ref.invalidate(studentEnrollmentsProvider(student.id));
                ref.invalidate(studentMedalCountProvider(student.id));
              },
              child: Column(
                children: [
                  // Academy indicator for multi-academy users
                  const _AcademyIndicator(),

                  // Trophy Showcase (before Conquistas)
                  _TrophyShowcase(competitions: competitions),

                  // Conquistas Card
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _ConquistasCard(studentId: student.id),
                  ),

                  // Tab Bar
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppTheme.divider, width: 1),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: AppTheme.textPrimary,
                      unselectedLabelColor: AppTheme.textSecondary,
                      labelStyle: AppTheme.labelMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: AppTheme.labelMedium,
                      indicatorColor: AppTheme.primary,
                      indicatorWeight: 2,
                      tabs: [
                        Tab(text: 'Proximas (${upcomingCompetitions.length})'),
                        Tab(text: 'Inscricoes (${enrolledUpcoming.length})'),
                        Tab(text: 'Historico (${pastCompetitions.length})'),
                      ],
                    ),
                  ),

                  // Tab Views
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Proximas Tab
                        _CompetitionsList(
                          competitions: upcomingCompetitions,
                          student: student,
                          isUpcoming: true,
                          emptyMessage: 'Nenhuma competicao programada',
                        ),

                        // Inscricoes Tab
                        _CompetitionsList(
                          competitions: enrolledUpcoming,
                          student: student,
                          isUpcoming: true,
                          showEnrolledBadge: true,
                          emptyMessage:
                              'Voce nao esta inscrito em nenhuma competicao',
                        ),

                        // Historico Tab
                        _CompetitionsList(
                          competitions: pastCompetitions,
                          student: student,
                          isUpcoming: false,
                          emptyMessage: 'Nenhuma competicao no historico',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => _buildLoadingState(),
          error: (_, __) => _buildErrorState(),
        );
      },
      loading: () => _buildLoadingState(),
      error: (_, __) => _buildErrorState(),
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonCard(
            height: 100,
            showAvatar: false,
            padding: EdgeInsets.all(16),
          ),
          SizedBox(height: 24),
          SkeletonCard(height: 140, showAvatar: true),
          SizedBox(height: 12),
          SkeletonCard(height: 140, showAvatar: true),
          SizedBox(height: 12),
          SkeletonCard(height: 140, showAvatar: true),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.userX, size: 64, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTheme.titleLarge.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Conquistas Card with 4 columns
class _ConquistasCard extends ConsumerWidget {
  final String studentId;

  const _ConquistasCard({required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medalCountAsync = ref.watch(studentMedalCountProvider(studentId));

    return medalCountAsync.when(
      data: (medals) {
        final gold = medals['gold'] ?? 0;
        final silver = medals['silver'] ?? 0;
        final bronze = medals['bronze'] ?? 0;
        final total = medals['total'] ?? 0;

        return Container(
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
                'MINHAS CONQUISTAS',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MedalColumn(
                      emoji: '🥇',
                      count: gold,
                      label: 'Ouros',
                    ),
                  ),
                  Expanded(
                    child: _MedalColumn(
                      emoji: '🥈',
                      count: silver,
                      label: 'Pratas',
                    ),
                  ),
                  Expanded(
                    child: _MedalColumn(
                      emoji: '🥉',
                      count: bronze,
                      label: 'Bronzes',
                    ),
                  ),
                  Expanded(
                    child: _MedalColumn(
                      emoji: '⭐',
                      count: total,
                      label: 'Participacoes',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SkeletonCard(
        height: 100,
        showAvatar: false,
        padding: EdgeInsets.all(16),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Text(
              'Nenhuma conquista ainda',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Medal column for conquistas card
class _MedalColumn extends StatelessWidget {
  final String emoji;
  final int count;
  final String label;

  const _MedalColumn({
    required this.emoji,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Competitions list for each tab
class _CompetitionsList extends ConsumerWidget {
  final List<Competition> competitions;
  final Student student;
  final bool isUpcoming;
  final bool showEnrolledBadge;
  final String emptyMessage;

  const _CompetitionsList({
    required this.competitions,
    required this.student,
    required this.isUpcoming,
    this.showEnrolledBadge = false,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (competitions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.trophy, size: 48, color: AppTheme.textDisabled),
              const SizedBox(height: 16),
              Text(
                emptyMessage,
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

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: competitions.length,
      itemBuilder: (context, index) {
        final competition = competitions[index];

        // Check enrollment status
        bool isEnrolled = false;
        if (!showEnrolledBadge) {
          final enrolledAsync = ref.watch(
            isStudentEnrolledProvider((
              competitionId: competition.id,
              studentId: student.id,
            )),
          );
          isEnrolled = enrolledAsync.valueOrNull ?? false;
        } else {
          isEnrolled = true;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => context.push('/portal/competicoes/${competition.id}'),
            child: _CompetitionCard(
              competition: competition,
              isEnrolled: isEnrolled,
              isUpcoming: isUpcoming,
              studentId: student.id,
            ),
          ),
        );
      },
    );
  }
}

/// Competition Card
class _CompetitionCard extends ConsumerWidget {
  final Competition competition;
  final bool isEnrolled;
  final bool isUpcoming;
  final String studentId;

  const _CompetitionCard({
    required this.competition,
    required this.isEnrolled,
    required this.isUpcoming,
    required this.studentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysUntil = competition.date.difference(DateTime.now()).inDays;
    final isSoon = daysUntil <= 7 && daysUntil >= 0;

    // Get academy name for past competitions
    final academyInfo = ref.watch(currentAcademyInfoProvider);
    final academyName = academyInfo?.name;

    // Get student results for this competition (history only)
    final allResults = !isUpcoming
        ? (ref.watch(studentAllResultsProvider(studentId)).valueOrNull ?? [])
        : <CompetitionResult>[];
    final competitionResults = allResults
        .where((r) => r.competitionId == competition.id)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSoon && isUpcoming ? AppTheme.warning : AppTheme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Academy badge for past competitions
          if (!isUpcoming && academyName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.building2,
                    size: 12,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Lutou por $academyName',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Header
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isUpcoming
                      ? AppTheme.warningLight
                      : AppTheme.surfaceVariant,
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
                      style: AppTheme.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: AppTheme.textSecondary,
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
                        DateFormat(
                          "d 'de' MMM",
                          'pt_BR',
                        ).format(competition.date),
                        style: AppTheme.bodySmall.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUpcoming && daysUntil >= 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],

          // Description
          if (competition.description != null &&
              competition.description!.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              competition.description!,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Student results (history only)
          if (!isUpcoming && competitionResults.isNotEmpty) ...[
            const Divider(height: 24),
            ...competitionResults.map((result) {
              final positionConfig = {
                'gold': (
                  icon: LucideIcons.medal,
                  label: 'Ouro',
                  color: const Color(0xFFD4AF37),
                ),
                'silver': (
                  icon: LucideIcons.medal,
                  label: 'Prata',
                  color: const Color(0xFF9CA3AF),
                ),
                'bronze': (
                  icon: LucideIcons.medal,
                  label: 'Bronze',
                  color: const Color(0xFFCD7F32),
                ),
              };
              final config = positionConfig[result.position];
              final categoryParts = <String>[
                if (result.ageCategory != null) result.ageCategory!,
                if (result.weightCategory != null) result.weightCategory!,
              ];
              final categoryText = categoryParts.isNotEmpty
                  ? categoryParts.join(' / ')
                  : null;

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    if (config != null) ...[
                      Icon(config.icon, size: 16, color: config.color),
                      const SizedBox(width: 6),
                      Text(
                        config.label,
                        style: AppTheme.labelSmall.copyWith(
                          color: config.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else ...[
                      Icon(
                        LucideIcons.user,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Participante',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (categoryText != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          categoryText,
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
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
          Icon(LucideIcons.trophy, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Competicoes de',
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

/// Trophy Showcase - horizontal carousel of academy team trophies
class _TrophyShowcase extends StatelessWidget {
  final List<Competition> competitions;

  const _TrophyShowcase({required this.competitions});

  @override
  Widget build(BuildContext context) {
    final trophyCompetitions = competitions
        .where((c) => c.teamPosition != null)
        .toList();

    if (trophyCompetitions.isEmpty) return const SizedBox.shrink();

    final config = {
      'gold': {
        'label': 'Campeao',
        'bgColor': const Color(0xFFFEF3C7),
        'borderColor': const Color(0xFFF59E0B),
        'textColor': const Color(0xFF92400E),
      },
      'silver': {
        'label': 'Vice',
        'bgColor': const Color(0xFFF3F4F6),
        'borderColor': const Color(0xFF9CA3AF),
        'textColor': const Color(0xFF374151),
      },
      'bronze': {
        'label': '3o Lugar',
        'bgColor': const Color(0xFFFED7AA),
        'borderColor': const Color(0xFFF97316),
        'textColor': const Color(0xFF7C2D12),
      },
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TROFEUS DA ACADEMIA',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TeamGalleryView()),
                  );
                },
                icon: const Icon(LucideIcons.image, size: 14),
                label: const Text('Galeria'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  textStyle: AppTheme.labelSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: trophyCompetitions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final comp = trophyCompetitions[index];
                final c = config[comp.teamPosition] ?? config['gold']!;
                final bgColor = c['bgColor'] as Color;
                final borderColor = c['borderColor'] as Color;
                final textColor = c['textColor'] as Color;
                final label = c['label'] as String;

                return GestureDetector(
                  onTap: () => context.push('/portal/competicoes/${comp.id}'),
                  child: Container(
                    width: 160,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🏆', style: TextStyle(fontSize: 28)),
                        const SizedBox(height: 8),
                        Text(
                          comp.name,
                          style: AppTheme.bodySmall.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          DateFormat("MMM yyyy", 'pt_BR').format(comp.date),
                          style: AppTheme.labelSmall.copyWith(
                            color: textColor.withValues(alpha: 0.7),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          label,
                          style: AppTheme.labelSmall.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
