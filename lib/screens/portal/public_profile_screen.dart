import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/competition_photo.dart';
import '../../models/public_student_profile.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ranking_providers.dart';
import '../../services/achievement_service.dart' show Achievement, AchievementType;
import '../../services/competition_service.dart' show CompetitionResult;
import '../../widgets/cached_image.dart';
import '../../widgets/common/grade_badge.dart';
import '../../widgets/competitions/photo_card.dart';
import '../../widgets/competitions/photo_fullscreen_viewer.dart';
import '../../widgets/polish/polish.dart';

/// Read-only public profile of a student, viewed from inside the portal.
///
/// Resolves the academy from the current user, then composes the student's
/// timeline, competition results and photos via [publicStudentProfileProvider].
/// Strictly read-only: no edit/mutation affordances are exposed here.
class PublicProfileScreen extends ConsumerStatefulWidget {
  final String studentId;

  const PublicProfileScreen({super.key, required this.studentId});

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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
    final academyId =
        ref.watch(currentUserProvider).valueOrNull?.academyId;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Perfil'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: academyId == null
          ? _buildMessage(
              icon: LucideIcons.userX,
              title: 'Perfil nao disponivel',
            )
          : _buildBody(academyId),
    );
  }

  Widget _buildBody(String academyId) {
    final profileAsync = ref.watch(
      publicStudentProfileProvider(
        (academyId: academyId, studentId: widget.studentId),
      ),
    );

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _buildMessage(
        icon: LucideIcons.alertTriangle,
        title: 'Erro ao carregar',
        subtitle: 'Nao foi possivel carregar este perfil',
      ),
      data: (profile) {
        if (profile == null) {
          return _buildMessage(
            icon: LucideIcons.userX,
            title: 'Perfil nao disponivel',
          );
        }
        return _buildProfile(profile);
      },
    );
  }

  Widget _buildProfile(PublicStudentProfile profile) {
    final Student student = profile.student;
    final List<Achievement> achievements = profile.achievements;
    final List<CompetitionResult> results = profile.competitionResults;
    final List<CompetitionPhoto> photos = profile.photos;

    return Column(
      children: [
        _ProfileHeader(student: student, medalCount: results.length)
            .fadeInQuick(),
        Material(
          color: AppTheme.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            labelStyle: AppTheme.labelMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            tabs: const [
              Tab(text: 'Linha do Tempo'),
              Tab(text: 'Competicoes'),
              Tab(text: 'Fotos'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _TimelineTab(achievements: achievements),
              _CompetitionsTab(results: results),
              _PhotosTab(photos: photos),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppTheme.textDisabled),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================
// Header
// ============================================
class _ProfileHeader extends StatelessWidget {
  final Student student;
  final int medalCount;

  const _ProfileHeader({required this.student, required this.medalCount});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final sport = student.getPrimarySport();
    final grade = student.getGrade(sport);
    final age = student.age;

    return Container(
      width: double.infinity,
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          Hero(
            tag: 'profile-avatar-${student.id}',
            child: AppCachedAvatar(
              imageUrl: student.photoUrl,
              radius: 44,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              foregroundColor: AppTheme.primary,
              child: Text(
                _initials(student.fullName),
                style: AppTheme.headlineSmall.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  student.displayName,
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!student.isProfilePublic) ...[
                const SizedBox(width: 6),
                Icon(
                  LucideIcons.lock,
                  size: 16,
                  color: AppTheme.textDisabled,
                ),
              ],
            ],
          ),
          if (age != null) ...[
            const SizedBox(height: 2),
            Text(
              '$age anos',
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          if (grade != null) ...[
            const SizedBox(height: 12),
            GradeBadge(
              sportId: sport,
              grade: grade.currentGrade,
              stripes: grade.currentStripes,
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(
                icon: LucideIcons.dumbbell,
                value: student.totalAttendanceCount,
                label: 'Treinos',
              ),
              _StatDivider(),
              _StatItem(
                icon: LucideIcons.medal,
                value: medalCount,
                label: 'Medalhas',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final num value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.primary),
        const SizedBox(height: 6),
        AnimatedCountUp(
          value: value,
          style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: AppTheme.divider);
  }
}

// ============================================
// Timeline tab — achievements grouped by year (newest first)
// ============================================
class _TimelineTab extends StatelessWidget {
  final List<Achievement> achievements;

  const _TimelineTab({required this.achievements});

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) {
      return const _EmptyState(
        icon: LucideIcons.clock,
        message: 'Sem registros ainda',
      );
    }

    // Group by year, newest year first.
    final byYear = <int, List<Achievement>>{};
    for (final a in achievements) {
      byYear.putIfAbsent(a.year, () => []).add(a);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: years.length,
      itemBuilder: (context, index) {
        final year = years[index];
        final items = byYear[year]!
          ..sort((a, b) => b.date.compareTo(a.date));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 8, bottom: 12),
              child: Text(
                year.toString(),
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...items.map((a) => _AchievementTile(achievement: a)),
          ],
        ).entrance(index: index);
      },
    );
  }
}

/// Achievement tile reproducing the timeline_screen.dart visual language:
/// a coloured icon circle, title, optional description, a belt indicator on
/// graduations (with sport badge) or a position badge on competitions.
class _AchievementTile extends StatelessWidget {
  final Achievement achievement;

  const _AchievementTile({required this.achievement});

  SportId get _sport => achievement.sport != null
      ? SportId.fromString(achievement.sport!)
      : SportId.bjj;

  Color _beltColor(String belt) {
    final c = getGradeColor(_sport, belt);
    return c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
  }

  ({IconData icon, Color color, Color bg}) get _config {
    switch (achievement.type) {
      case AchievementType.graduation:
        final c = _beltColor(achievement.toBelt ?? 'white');
        return (icon: LucideIcons.award, color: c, bg: c.withValues(alpha: 0.15));
      case AchievementType.stripe:
        return (
          icon: LucideIcons.star,
          color: const Color(0xFFEAB308),
          bg: const Color(0xFFFEF9C3),
        );
      case AchievementType.competition:
        return (
          icon: LucideIcons.trophy,
          color: const Color(0xFFF59E0B),
          bg: const Color(0xFFFEF3C7),
        );
      case AchievementType.milestone:
        return (
          icon: LucideIcons.target,
          color: const Color(0xFF10B981),
          bg: const Color(0xFFD1FAE5),
        );
      case AchievementType.attendanceStreak:
        // Streak of attendance — warm orange "flame" (matches timeline).
        return (
          icon: LucideIcons.flame,
          color: const Color(0xFFEA580C),
          bg: const Color(0xFFFFEDD5),
        );
      case AchievementType.rankingPosition:
        // Ranking position — amber "trophy" (matches timeline).
        return (
          icon: LucideIcons.trophy,
          color: const Color(0xFFD97706),
          bg: const Color(0xFFFEF3C7),
        );
      case AchievementType.trainingPr:
        // Training personal record — indigo "trending up" (matches timeline).
        return (
          icon: LucideIcons.trendingUp,
          color: const Color(0xFF4F46E5),
          bg: const Color(0xFFE0E7FF),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final isGraduation = achievement.type == AchievementType.graduation;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: config.bg,
              shape: BoxShape.circle,
              border: Border.all(color: config.color, width: 3),
            ),
            child: Icon(config.icon, size: 20, color: config.color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          achievement.title,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Sport badge on graduation entries (when the
                      // achievement exposes a sport).
                      if (isGraduation && achievement.sport != null)
                        _SportChip(sport: _sport),
                    ],
                  ),
                  if (achievement.description != null &&
                      achievement.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      achievement.description!,
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                  if (isGraduation && achievement.toBelt != null) ...[
                    const SizedBox(height: 12),
                    _BeltIndicator(
                      belt: achievement.toBelt!,
                      sport: _sport,
                    ),
                  ],
                  if (achievement.type == AchievementType.competition &&
                      achievement.position != null) ...[
                    const SizedBox(height: 12),
                    _PositionBadge(position: achievement.position!.name),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 14,
                        color: AppTheme.textDisabled,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR')
                            .format(achievement.date),
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SportChip extends StatelessWidget {
  final SportId sport;

  const _SportChip({required this.sport});

  @override
  Widget build(BuildContext context) {
    final label = sports[sport]?.labelShort ?? sport.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(
          color: AppTheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BeltIndicator extends StatelessWidget {
  final String belt;
  final SportId sport;

  const _BeltIndicator({required this.belt, required this.sport});

  @override
  Widget build(BuildContext context) {
    final c = getGradeColor(sport, belt);
    final beltColor =
        c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
    final label = getGradeLabel(sport, belt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: beltColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: beltColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 8,
            decoration: BoxDecoration(
              color: beltColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Faixa $label',
            style: AppTheme.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: beltColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionBadge extends StatelessWidget {
  final String position;

  const _PositionBadge({required this.position});

  @override
  Widget build(BuildContext context) {
    String emoji;
    String label;
    Color color;

    switch (position) {
      case 'gold':
        emoji = '🥇';
        label = 'Ouro';
        color = const Color(0xFFD97706);
        break;
      case 'silver':
        emoji = '🥈';
        label = 'Prata';
        color = const Color(0xFF6B7280);
        break;
      case 'bronze':
        emoji = '🥉';
        label = 'Bronze';
        color = const Color(0xFFB45309);
        break;
      default:
        emoji = '🎖️';
        label = 'Participante';
        color = const Color(0xFF10B981);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Competicoes tab
// ============================================
class _CompetitionsTab extends StatelessWidget {
  final List<CompetitionResult> results;

  const _CompetitionsTab({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const _EmptyState(
        icon: LucideIcons.trophy,
        message: 'Sem competicoes registradas',
      );
    }

    final sorted = [...results]..sort((a, b) => b.date.compareTo(a.date));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: sorted.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _ResultTile(result: sorted[index]).entrance(index: index),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final CompetitionResult result;

  const _ResultTile({required this.result});

  ({String emoji, Color color}) get _medal {
    switch (result.position) {
      case 'gold':
        return (emoji: '🥇', color: const Color(0xFFD97706));
      case 'silver':
        return (emoji: '🥈', color: const Color(0xFF6B7280));
      case 'bronze':
        return (emoji: '🥉', color: const Color(0xFFB45309));
      default:
        return (emoji: '🎖️', color: const Color(0xFF10B981));
    }
  }

  @override
  Widget build(BuildContext context) {
    final medal = _medal;
    final details = [
      result.beltCategory,
      result.weightCategory,
      result.modality,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' • ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Text(medal.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.competitionName,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  DateFormat("d 'de' MMM 'de' yyyy", 'pt_BR')
                      .format(result.date),
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

// ============================================
// Fotos tab — 2-column grid, reuses PhotoCard + fullscreen viewer
// ============================================
class _PhotosTab extends StatelessWidget {
  final List<CompetitionPhoto> photos;

  const _PhotosTab({required this.photos});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const _EmptyState(
        icon: LucideIcons.image,
        message: 'Nenhuma foto',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return PhotoCard(
          photo: photo,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PhotoFullscreenViewer(
                  photos: photos,
                  initialIndex: index,
                ),
              ),
            );
          },
        ).entrance(index: index);
      },
    );
  }
}

// ============================================
// Shared empty state
// ============================================
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return PolishedEmptyState(icon: icon, title: message);
  }
}
