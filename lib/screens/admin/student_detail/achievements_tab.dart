import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/achievement_service.dart';

/// Achievements tab content for student detail screen.
///
/// Read-only view — conquistas são criadas automaticamente pelo backend como
/// efeito colateral de graduações, resultados de competição e marcos de
/// presença. Não há escrita local.
class StudentAchievementsTab extends StatelessWidget {
  final Student student;
  final List<Achievement> achievements;
  final VoidCallback onRefresh;

  const StudentAchievementsTab({
    super.key,
    required this.student,
    required this.achievements,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.trophy,
                  size: 64,
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Nenhuma conquista ainda',
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Conquistas são desbloqueadas automaticamente\npelo sistema conforme o aluno evolui',
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: achievements.length,
      itemBuilder: (context, index) {
        final achievement = achievements[index];
        return _AchievementCard(achievement: achievement);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widget
// ---------------------------------------------------------------------------

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;

  const _AchievementCard({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getTypeColor().withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_getTypeIcon(), color: _getTypeColor(), size: 24),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    achievement.title,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (achievement.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      achievement.description!,
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM/yyyy').format(achievement.date),
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getTypeColor().withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _getTypeLabel(),
                          style: AppTheme.labelSmall.copyWith(
                            color: _getTypeColor(),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTypeIcon() {
    switch (achievement.type) {
      case AchievementType.graduation:
        return Icons.military_tech;
      case AchievementType.stripe:
        return LucideIcons.award;
      case AchievementType.competition:
        return Icons.emoji_events;
      case AchievementType.milestone:
        return Icons.star;
    }
  }

  Color _getTypeColor() {
    switch (achievement.type) {
      case AchievementType.graduation:
        return Colors.purple;
      case AchievementType.stripe:
        return Colors.blue;
      case AchievementType.competition:
        return Colors.amber;
      case AchievementType.milestone:
        return Colors.green;
    }
  }

  String _getTypeLabel() {
    switch (achievement.type) {
      case AchievementType.graduation:
        return 'Graduação';
      case AchievementType.stripe:
        return 'Grau';
      case AchievementType.competition:
        return 'Competição';
      case AchievementType.milestone:
        return 'Marco';
    }
  }
}
