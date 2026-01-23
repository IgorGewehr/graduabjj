import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';

/// Belt labels for display
const Map<String, String> _beltLabels = {
  'white': 'Branca',
  'blue': 'Azul',
  'purple': 'Roxa',
  'brown': 'Marrom',
  'black': 'Preta',
  'grey': 'Cinza',
  'grey-white': 'Cinza/Branca',
  'grey-black': 'Cinza/Preta',
  'yellow': 'Amarela',
  'yellow-white': 'Amarela/Branca',
  'yellow-black': 'Amarela/Preta',
  'orange': 'Laranja',
  'orange-white': 'Laranja/Branca',
  'orange-black': 'Laranja/Preta',
  'green': 'Verde',
  'green-white': 'Verde/Branca',
  'green-black': 'Verde/Preta',
};

/// Timeline Screen - Linha do Tempo
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  bool _isLoading = false;

  // Mock data - will be replaced with Firebase data
  final List<Achievement> _achievements = [
    Achievement(
      id: '1',
      type: AchievementType.stripe,
      title: '2º Grau',
      date: DateTime.now().subtract(const Duration(days: 30)),
      toBelt: 'blue',
      toStripes: 2,
    ),
    Achievement(
      id: '2',
      type: AchievementType.competition,
      title: 'Campeonato Municipal',
      date: DateTime.now().subtract(const Duration(days: 60)),
      position: 'gold',
      competitionName: 'Campeonato Municipal',
    ),
    Achievement(
      id: '3',
      type: AchievementType.milestone,
      title: '50 Presencas',
      date: DateTime.now().subtract(const Duration(days: 90)),
      description: 'Voce completou 50 presencas na academia!',
    ),
    Achievement(
      id: '4',
      type: AchievementType.stripe,
      title: '1º Grau',
      date: DateTime.now().subtract(const Duration(days: 180)),
      toBelt: 'blue',
      toStripes: 1,
    ),
    Achievement(
      id: '5',
      type: AchievementType.graduation,
      title: 'Faixa Azul',
      date: DateTime.now().subtract(const Duration(days: 365)),
      fromBelt: 'white',
      toBelt: 'blue',
    ),
    Achievement(
      id: '6',
      type: AchievementType.milestone,
      title: '1 Ano de Treino',
      date: DateTime.now().subtract(const Duration(days: 365)),
      description: 'Completou 1 ano treinando jiu-jitsu!',
    ),
  ];

  // Journey stats
  final _currentBelt = 'blue';
  final _currentStripes = 2;
  final _totalAttendance = 147;
  final _trainingTime = '2 anos e 3 meses';
  final _competitionsCount = 5;
  final _medalStats = MedalStats(gold: 2, silver: 1, bronze: 1);

  Map<int, List<Achievement>> get _groupedByYear {
    final grouped = <int, List<Achievement>>{};
    for (final achievement in _achievements) {
      final year = achievement.date.year;
      grouped.putIfAbsent(year, () => []);
      grouped[year]!.add(achievement);
    }
    return grouped;
  }

  List<int> get _sortedYears {
    final years = _groupedByYear.keys.toList();
    years.sort((a, b) => b.compareTo(a)); // Descending
    return years;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    return RefreshIndicator(
      onRefresh: () async {
        // TODO: Refresh timeline data
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Linha do Tempo',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Sua jornada no jiu-jitsu',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),

            // Journey Card
            _JourneyCard(
              currentBelt: _currentBelt,
              currentStripes: _currentStripes,
              totalAttendance: _totalAttendance,
              trainingTime: _trainingTime,
              competitionsCount: _competitionsCount,
              medalStats: _medalStats,
            ),
            const SizedBox(height: 24),

            // Timeline
            if (_achievements.isEmpty)
              _buildEmptyState()
            else
              ..._sortedYears.map((year) => _YearSection(
                year: year,
                achievements: _groupedByYear[year]!,
              )),

            const SizedBox(height: 80),
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
            width: 150,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(3, (index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
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
            Icon(LucideIcons.clock, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Sua linha do tempo esta vazia',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Suas conquistas aparecerao aqui conforme voce progride',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Journey Card
class _JourneyCard extends StatelessWidget {
  final String currentBelt;
  final int currentStripes;
  final int totalAttendance;
  final String trainingTime;
  final int competitionsCount;
  final MedalStats? medalStats;

  const _JourneyCard({
    required this.currentBelt,
    required this.currentStripes,
    required this.totalAttendance,
    required this.trainingTime,
    required this.competitionsCount,
    this.medalStats,
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
            'SUA JORNADA',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),

          // Stats Grid
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatItem(
                icon: LucideIcons.award,
                iconColor: const Color(0xFF7C3AED),
                iconBgColor: const Color(0xFFEDE9FE),
                value: _beltLabels[currentBelt] ?? currentBelt,
                label: currentStripes > 0 ? '$currentStripes grau${currentStripes > 1 ? 's' : ''}' : 'Faixa Atual',
              ),
              _StatItem(
                icon: LucideIcons.dumbbell,
                iconColor: AppTheme.success,
                iconBgColor: AppTheme.successLight,
                value: totalAttendance.toString(),
                label: 'Treinos',
              ),
              _StatItem(
                icon: LucideIcons.clock,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
                value: trainingTime,
                label: 'Tempo de Tatame',
              ),
              _StatItem(
                icon: LucideIcons.trophy,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFEF3C7),
                value: competitionsCount.toString(),
                label: 'Campeonatos',
              ),
            ],
          ),

          // Medal Display
          if (medalStats != null && medalStats!.total > 0) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'MEDALHAS',
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (medalStats!.gold > 0)
                  _MedalBadge(emoji: '🥇', count: medalStats!.gold, label: 'Ouro'),
                if (medalStats!.silver > 0)
                  _MedalBadge(emoji: '🥈', count: medalStats!.silver, label: 'Prata'),
                if (medalStats!.bronze > 0)
                  _MedalBadge(emoji: '🥉', count: medalStats!.bronze, label: 'Bronze'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Stat Item
class _StatItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

/// Medal Badge
class _MedalBadge extends StatelessWidget {
  final String emoji;
  final int count;
  final String label;

  const _MedalBadge({
    required this.emoji,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count.toString(),
                style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                label,
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Year Section
class _YearSection extends StatelessWidget {
  final int year;
  final List<Achievement> achievements;

  const _YearSection({
    required this.year,
    required this.achievements,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.primary, width: 2),
            ),
          ),
          child: Text(
            year.toString(),
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 16),
        ...achievements.asMap().entries.map((entry) {
          final index = entry.key;
          final achievement = entry.value;
          final isLast = index == achievements.length - 1;
          return _TimelineItem(achievement: achievement, isLast: isLast);
        }),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Timeline Item
class _TimelineItem extends StatelessWidget {
  final Achievement achievement;
  final bool isLast;

  const _TimelineItem({
    required this.achievement,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getAchievementConfig(achievement.type);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline line
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: config.bgColor,
                shape: BoxShape.circle,
                border: Border.all(color: config.color, width: 2),
              ),
              child: Icon(config.icon, size: 20, color: config.color),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 60,
                color: AppTheme.divider,
                margin: const EdgeInsets.only(top: 8),
              ),
          ],
        ),
        const SizedBox(width: 16),

        // Content
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: isLast ? 0 : 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        achievement.title,
                        style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    _TypeChip(type: achievement.type),
                  ],
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  _getDescription(achievement),
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),

                // Date
                Row(
                  children: [
                    const Icon(LucideIcons.calendar, size: 12, color: AppTheme.textDisabled),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR').format(achievement.date),
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),

                // Position badge for competitions
                if (achievement.type == AchievementType.competition && achievement.position != null) ...[
                  const SizedBox(height: 12),
                  _PositionBadge(position: achievement.position!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getDescription(Achievement achievement) {
    if (achievement.description != null) return achievement.description!;

    switch (achievement.type) {
      case AchievementType.graduation:
        return 'Graduacao para Faixa ${_beltLabels[achievement.toBelt] ?? achievement.toBelt}';
      case AchievementType.stripe:
        return '${achievement.toStripes}º grau na Faixa ${_beltLabels[achievement.toBelt ?? achievement.fromBelt] ?? ''}';
      case AchievementType.competition:
        final positionLabels = {'gold': 'Ouro', 'silver': 'Prata', 'bronze': 'Bronze', 'participant': 'Participante'};
        return achievement.competitionName != null
            ? '${positionLabels[achievement.position] ?? 'Participante'} - ${achievement.competitionName}'
            : achievement.title;
      case AchievementType.milestone:
        return achievement.title;
    }
  }

  _AchievementConfig _getAchievementConfig(AchievementType type) {
    switch (type) {
      case AchievementType.graduation:
        return _AchievementConfig(
          icon: LucideIcons.award,
          color: const Color(0xFF7C3AED),
          bgColor: const Color(0xFFEDE9FE),
        );
      case AchievementType.stripe:
        return _AchievementConfig(
          icon: LucideIcons.star,
          color: const Color(0xFFEAB308),
          bgColor: const Color(0xFFFEF9C3),
        );
      case AchievementType.competition:
        return _AchievementConfig(
          icon: LucideIcons.trophy,
          color: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFEF3C7),
        );
      case AchievementType.milestone:
        return _AchievementConfig(
          icon: LucideIcons.target,
          color: const Color(0xFF10B981),
          bgColor: const Color(0xFFD1FAE5),
        );
    }
  }
}

/// Type Chip
class _TypeChip extends StatelessWidget {
  final AchievementType type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    String label;
    Color bgColor;
    Color textColor;

    switch (type) {
      case AchievementType.graduation:
        label = 'Graduacao';
        bgColor = const Color(0xFFEDE9FE);
        textColor = const Color(0xFF7C3AED);
        break;
      case AchievementType.stripe:
        label = 'Grau';
        bgColor = const Color(0xFFFEF9C3);
        textColor = const Color(0xFFEAB308);
        break;
      case AchievementType.competition:
        label = 'Competicao';
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFF59E0B);
        break;
      case AchievementType.milestone:
        label = 'Marco';
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF10B981);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Position Badge
class _PositionBadge extends StatelessWidget {
  final String position;

  const _PositionBadge({required this.position});

  @override
  Widget build(BuildContext context) {
    String emoji;
    String label;

    switch (position) {
      case 'gold':
        emoji = '🥇';
        label = 'Ouro';
        break;
      case 'silver':
        emoji = '🥈';
        label = 'Prata';
        break;
      case 'bronze':
        emoji = '🥉';
        label = 'Bronze';
        break;
      default:
        emoji = '🎖️';
        label = 'Participante';
    }

    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Config class for achievement types
class _AchievementConfig {
  final IconData icon;
  final Color color;
  final Color bgColor;

  _AchievementConfig({
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

/// Data Models
enum AchievementType { graduation, stripe, competition, milestone }

class Achievement {
  final String id;
  final AchievementType type;
  final String title;
  final DateTime date;
  final String? description;
  final String? fromBelt;
  final String? toBelt;
  final int? toStripes;
  final String? position;
  final String? competitionName;

  Achievement({
    required this.id,
    required this.type,
    required this.title,
    required this.date,
    this.description,
    this.fromBelt,
    this.toBelt,
    this.toStripes,
    this.position,
    this.competitionName,
  });
}

class MedalStats {
  final int gold;
  final int silver;
  final int bronze;

  MedalStats({
    required this.gold,
    required this.silver,
    required this.bronze,
  });

  int get total => gold + silver + bronze;
}
