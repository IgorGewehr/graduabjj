import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/ranking_entry.dart';
import '../../providers/portal_providers.dart';
import '../../providers/ranking_providers.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

/// Student-facing attendance leaderboard. Pick an audience (Geral / Adulto /
/// Kids) + period and see who trained the most. Each row links to that
/// student's public profile.
class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen> {
  RankingCategory _category = RankingCategory.general;
  RankingPeriod _period = RankingPeriod.week;

  @override
  Widget build(BuildContext context) {
    // Defense in depth: even reached via deep link / stale nav, the ranking
    // stays hidden when the academy disabled student visibility. Loading/null
    // resolves to true so it shows by default for legacy academies.
    final rankingVisible = ref.watch(
      academySettingsProvider.select(
        (s) => s.valueOrNull?.rankingVisibleToStudents ?? true,
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Ranking de Turmas')),
      body: !rankingVisible
          ? const _RankingUnavailableState()
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _RankingHeader(
          category: _category,
          period: _period,
          onCategoryChanged: (c) => setState(() => _category = c),
          onPeriodChanged: (p) => setState(() => _period = p),
        ),
        Expanded(child: _buildLeaderboard()),
      ],
    );
  }

  Widget _buildLeaderboard() {
    final key = (category: _category, period: _period);
    final rankingAsync = ref.watch(classRankingProvider(key));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(classRankingProvider(key)),
      child: rankingAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: PolishSkeleton.list(count: 6, itemHeight: 68),
        ),
        error: (_, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            _RankingMessageState(
              icon: LucideIcons.alertCircle,
              message: 'Nao foi possivel carregar o ranking.\nPuxe para atualizar.',
            ),
          ],
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 100),
                PolishedEmptyState(
                  icon: LucideIcons.trophy,
                  title: 'Nenhuma presença registrada',
                  subtitle: 'Treine no período para aparecer no ranking.',
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final entry = entries[i];
              return _RankingTile(
                entry: entry,
                onTap: () =>
                    context.push('/portal/profile/${entry.studentId}'),
              ).entrance(index: i);
            },
          );
        },
      ),
    );
  }
}

/// Sticky header: audience (Geral / Adulto / Kids) + period segmented controls.
class _RankingHeader extends StatelessWidget {
  final RankingCategory category;
  final RankingPeriod period;
  final ValueChanged<RankingCategory> onCategoryChanged;
  final ValueChanged<RankingPeriod> onPeriodChanged;

  const _RankingHeader({
    required this.category,
    required this.period,
    required this.onCategoryChanged,
    required this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Audience segmented control
          SegmentedButton<RankingCategory>(
            segments: const [
              ButtonSegment(
                value: RankingCategory.general,
                label: Text('Geral'),
              ),
              ButtonSegment(
                value: RankingCategory.adult,
                label: Text('Adulto'),
              ),
              ButtonSegment(
                value: RankingCategory.kids,
                label: Text('Kids'),
              ),
            ],
            selected: {category},
            showSelectedIcon: false,
            onSelectionChanged: (set) => onCategoryChanged(set.first),
          ),
          const SizedBox(height: 12),
          // Period segmented control
          SegmentedButton<RankingPeriod>(
            segments: const [
              ButtonSegment(
                value: RankingPeriod.week,
                label: Text('Esta Semana'),
              ),
              ButtonSegment(
                value: RankingPeriod.month,
                label: Text('Este Mes'),
              ),
            ],
            selected: {period},
            showSelectedIcon: false,
            onSelectionChanged: (set) => onPeriodChanged(set.first),
          ),
        ],
      ),
    );
  }
}

/// One leaderboard row: medal/rank badge, avatar, name, training count.
class _RankingTile extends StatelessWidget {
  final RankingEntry entry;
  final VoidCallback onTap;

  const _RankingTile({required this.entry, required this.onTap});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            _RankBadge(rank: entry.rank),
            const SizedBox(width: 12),
            Hero(
              tag: 'profile-avatar-${entry.studentId}',
              child: AppCachedAvatar(
                imageUrl: entry.photoUrl,
                radius: 22,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                foregroundColor: AppTheme.primary,
                child: Text(
                  _initials(entry.studentName),
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.studentName,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.attendanceCount} treinos',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppTheme.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rank indicator: amber/silver/bronze medal disc for the top 3, plain numbered
/// circle otherwise.
class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    Color? medal;
    switch (rank) {
      case 1:
        medal = const Color(0xFFF59E0B); // amber/gold
        break;
      case 2:
        medal = const Color(0xFF9CA3AF); // silver
        break;
      case 3:
        medal = const Color(0xFFEA580C); // bronze/orange
        break;
    }

    final bg = medal?.withValues(alpha: 0.15) ?? AppTheme.surface;
    final fg = medal ?? AppTheme.textSecondary;
    final isTopThree = medal != null;

    final badge = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: medal ?? AppTheme.divider,
          width: medal != null ? 2 : 1,
        ),
        boxShadow: medal != null
            ? [
                BoxShadow(
                  color: medal.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        '$rank',
        style: AppTheme.bodyMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );

    // Top-3 medals get a restrained scale-in pop (easeOutBack) so the podium
    // reads instantly; plain ranks stay static.
    if (!isTopThree) return badge;
    return badge.animate().scale(
          begin: const Offset(0.7, 0.7),
          end: const Offset(1, 1),
          duration: PolishMotion.normal,
          curve: Curves.easeOutBack,
        );
  }
}

/// Shown when the academy turned off the student-facing ranking. Guards against
/// deep links or stale navigation reaching a leaderboard that should be hidden.
class _RankingUnavailableState extends StatelessWidget {
  const _RankingUnavailableState();

  @override
  Widget build(BuildContext context) {
    return const PolishedEmptyState(
      icon: LucideIcons.trophy,
      title: 'Ranking indisponível',
      subtitle: 'O ranking não está disponível no momento.',
    );
  }
}

/// Centered icon + message used for empty / error / unavailable states.
class _RankingMessageState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _RankingMessageState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTheme.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
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
