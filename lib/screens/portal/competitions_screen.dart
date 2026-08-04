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
import '../../widgets/polish/polish.dart';
import '../../widgets/skeletons/skeletons.dart';

// ===========================================================================
// Fighter palette — local to this screen (do NOT touch shared theme.dart).
// Bone canvas, white cards, ink I, one red accent. No gold/orange/purple.
// ===========================================================================
const Color _kBone = Color(0xFFF4F3EF); // canvas
const Color _kCard = Color(0xFFFFFFFF); // cards
const Color _kInk = Color(0xFF0A0A0A); // primary ink
const Color _kInk2 = Color(0xFF6E6E68); // secondary text
const Color _kAccent = Color(0xFFE0301E); // the one red accent
const Color _kHair = Color(0xFFE6E4DD); // hairline border on bone

const List<FontFeature> _kTab = [FontFeature.tabularFigures()];

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

            // INSCRITAS = TODAS as competições em que o aluno se inscreveu
            // (próximas E passadas) — é o registro da participação dele, não
            // só o que vem a seguir. Ordena: próximas primeiro (data asc),
            // depois as passadas (mais recente primeiro).
            final enrolledAll = competitions.where((c) {
              return enrollments.any((e) => e.competitionId == c.id);
            }).toList()
              ..sort((a, b) {
                final aUp = a.status == CompetitionStatus.upcoming;
                final bUp = b.status == CompetitionStatus.upcoming;
                if (aUp != bUp) return aUp ? -1 : 1;
                return aUp
                    ? a.date.compareTo(b.date)
                    : b.date.compareTo(a.date);
              });

            return RefreshIndicator(
              color: _kAccent,
              backgroundColor: _kCard,
              onRefresh: () async {
                HapticFeedback.mediumImpact();
                ref.invalidate(competitionsProvider);
                ref.invalidate(currentStudentProvider);
                ref.invalidate(studentEnrollmentsProvider(student.id));
                ref.invalidate(studentMedalCountProvider(student.id));
              },
              child: Container(
                color: _kBone,
                child: Column(
                  children: [
                    const SizedBox(height: 8),

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
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: _kHair, width: 1),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: false,
                        labelColor: _kInk,
                        unselectedLabelColor: _kInk2,
                        labelPadding: EdgeInsets.zero,
                        labelStyle: AppTheme.labelMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          fontFeatures: _kTab,
                        ),
                        unselectedLabelStyle: AppTheme.labelMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          fontFeatures: _kTab,
                        ),
                        indicatorColor: _kAccent,
                        indicatorWeight: 2.5,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        tabs: [
                          Tab(text: 'PRÓXIMAS ${upcomingCompetitions.length}'),
                          Tab(text: 'INSCRITAS ${enrolledAll.length}'),
                          Tab(text: 'HISTÓRICO ${pastCompetitions.length}'),
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

                          // Inscricoes Tab — todas em que o aluno se
                          // inscreveu, incluindo as já realizadas.
                          _CompetitionsList(
                            competitions: enrolledAll,
                            student: student,
                            isUpcoming: false,
                            showEnrolledBadge: true,
                            emptyMessage:
                                'Voce ainda nao se inscreveu em nenhuma competicao',
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
    return Container(
      color: _kBone,
      child: SingleChildScrollView(
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
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      color: _kBone,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.alertTriangle, size: 56, color: _kAccent),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar dados',
              style: AppTheme.titleLarge.copyWith(color: _kInk),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      color: _kBone,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.userX, size: 56, color: _kInk2),
            const SizedBox(height: 16),
            Text(message, style: AppTheme.titleLarge.copyWith(color: _kInk)),
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
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kHair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MINHAS CONQUISTAS',
                style: AppTheme.labelSmall.copyWith(
                  color: _kInk,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MedalColumn(
                      icon: LucideIcons.medal,
                      count: gold,
                      label: 'Ouros',
                      accent: true,
                    ),
                  ),
                  Expanded(
                    child: _MedalColumn(
                      icon: LucideIcons.medal,
                      count: silver,
                      label: 'Pratas',
                    ),
                  ),
                  Expanded(
                    child: _MedalColumn(
                      icon: LucideIcons.medal,
                      count: bronze,
                      label: 'Bronzes',
                    ),
                  ),
                  Expanded(
                    child: _MedalColumn(
                      icon: LucideIcons.activity,
                      count: total,
                      label: 'Lutas',
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
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kHair),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.trophy, size: 20, color: _kInk2),
            const SizedBox(width: 12),
            Text(
              'Nenhuma conquista ainda',
              style: AppTheme.bodyMedium.copyWith(color: _kInk2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Medal column for conquistas card
class _MedalColumn extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;
  final bool accent;

  const _MedalColumn({
    required this.icon,
    required this.count,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? _kAccent : _kInk;
    return Column(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 6),
        AnimatedCountUp(
          value: count,
          style: AppTheme.headlineSmall.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            fontFeatures: _kTab,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: AppTheme.labelSmall.copyWith(
            color: _kInk2,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
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
      return Container(
        color: _kBone,
        child: PolishedEmptyState(
          icon: LucideIcons.trophy,
          title: emptyMessage,
          accent: _kInk2,
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
          child: Pressable(
            onTap: () => context.push('/portal/competicoes/${competition.id}'),
            child: _CompetitionCard(
              competition: competition,
              isEnrolled: isEnrolled,
              // Por competição (não pelo flag da lista): a aba INSCRITAS é
              // MISTA (próximas + já realizadas) — cada card mostra o estado
              // certo (destaque de "em breve" vs resultado do histórico).
              isUpcoming: competition.status == CompetitionStatus.upcoming,
              studentId: student.id,
            ),
          ).entrance(index: index),
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
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSoon && isUpcoming ? _kAccent : _kHair,
          width: isSoon && isUpcoming ? 1.5 : 1,
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
                color: _kBone,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kHair),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.building2, size: 12, color: _kInk2),
                  const SizedBox(width: 4),
                  Text(
                    'Lutou por $academyName',
                    style: AppTheme.labelSmall.copyWith(
                      color: _kInk2,
                      fontWeight: FontWeight.w600,
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
                  color: _kBone,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kHair),
                ),
                child: Icon(
                  LucideIcons.trophy,
                  size: 22,
                  color: isUpcoming ? _kInk : _kInk2,
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
                        color: _kInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (competition.location != null)
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.mapPin,
                            size: 12,
                            color: _kInk2,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              competition.location!,
                              style: AppTheme.labelSmall.copyWith(
                                color: _kInk2,
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
                    color: _kAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'INSCRITO',
                    style: AppTheme.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(LucideIcons.chevronRight, size: 16, color: _kInk2),
            ],
          ),
          const SizedBox(height: 16),

          // Info row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kBone,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(LucideIcons.calendar, size: 14, color: _kInk2),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat(
                          "d 'de' MMM",
                          'pt_BR',
                        ).format(competition.date),
                        style: AppTheme.bodySmall.copyWith(
                          color: _kInk,
                          fontWeight: FontWeight.w700,
                          fontFeatures: _kTab,
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
                      color: isSoon ? _kAccent : _kInk,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      daysUntil == 0
                          ? 'HOJE'
                          : daysUntil == 1
                          ? 'AMANHÃ'
                          : 'EM $daysUntil DIAS',
                      style: AppTheme.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.4,
                        fontFeatures: _kTab,
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
                const Icon(LucideIcons.clock, size: 14, color: _kInk2),
                const SizedBox(width: 8),
                Text(
                  'Inscricoes ate ${DateFormat("d 'de' MMM", 'pt_BR').format(competition.registrationDeadline!)}',
                  style: AppTheme.labelSmall.copyWith(color: _kInk2),
                ),
              ],
            ),
          ],

          // Description
          if (competition.description != null &&
              competition.description!.isNotEmpty) ...[
            const Divider(height: 24, color: _kHair),
            Text(
              competition.description!,
              style: AppTheme.bodySmall.copyWith(color: _kInk2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Student results (history only)
          if (!isUpcoming && competitionResults.isNotEmpty) ...[
            const Divider(height: 24, color: _kHair),
            ...competitionResults.map((result) {
              final positionConfig = {
                'gold': (
                  icon: LucideIcons.medal,
                  label: 'Ouro',
                  color: _kAccent,
                ),
                'silver': (
                  icon: LucideIcons.medal,
                  label: 'Prata',
                  color: _kInk,
                ),
                'bronze': (
                  icon: LucideIcons.medal,
                  label: 'Bronze',
                  color: _kInk2,
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
                      const Icon(LucideIcons.user, size: 16, color: _kInk2),
                      const SizedBox(width: 6),
                      Text(
                        'Participante',
                        style: AppTheme.labelSmall.copyWith(
                          color: _kInk2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (categoryText != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          categoryText,
                          style: AppTheme.labelSmall.copyWith(color: _kInk2),
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
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kHair),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.building2, size: 16, color: _kInk),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COMPETIÇÕES DE',
                  style: AppTheme.labelSmall.copyWith(
                    color: _kInk2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  academyInfo.name,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push('/portal/academias'),
            icon: const Icon(LucideIcons.arrowRightLeft, size: 14),
            label: const Text('Trocar'),
            style: TextButton.styleFrom(
              foregroundColor: _kAccent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: AppTheme.labelSmall.copyWith(
                fontWeight: FontWeight.w800,
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

    // Fighter palette: no gold/silver/bronze metal. Champion = red accent,
    // everything else = ink. The trophy icon carries the meaning.
    const config = {
      'gold': (label: 'CAMPEÃO', accent: _kAccent),
      'silver': (label: 'VICE', accent: _kInk),
      'bronze': (label: '3º LUGAR', accent: _kInk2),
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
                'TROFÉUS DA ACADEMIA',
                style: AppTheme.labelSmall.copyWith(
                  color: _kInk,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
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
                  foregroundColor: _kAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  textStyle: AppTheme.labelSmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: trophyCompetitions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final comp = trophyCompetitions[index];
                final c = config[comp.teamPosition] ?? config['gold']!;
                final accent = c.accent;
                final label = c.label;

                return Pressable(
                  onTap: () => context.push('/portal/competicoes/${comp.id}'),
                  child: Container(
                    width: 168,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kHair),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.trophy, size: 24, color: accent),
                        const SizedBox(height: 8),
                        Text(
                          comp.name,
                          style: AppTheme.bodySmall.copyWith(
                            color: _kInk,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          DateFormat("MMM yyyy", 'pt_BR').format(comp.date),
                          style: AppTheme.labelSmall.copyWith(
                            color: _kInk2,
                            fontFeatures: _kTab,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          label,
                          style: AppTheme.labelSmall.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
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
