import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../services/services.dart';

/// History tab content for student detail screen.
///
/// Merges belt progressions and achievements into a single chronological list.
class StudentHistoryTab extends StatelessWidget {
  final List<BeltProgression> progressions;
  final List<Achievement> achievements;

  const StudentHistoryTab({
    super.key,
    required this.progressions,
    required this.achievements,
  });

  @override
  Widget build(BuildContext context) {
    final allHistory = <_HistoryItem>[];

    // Add progressions
    for (final p in progressions) {
      allHistory.add(
        _HistoryItem(
          date: p.promotionDate,
          title: p.isBeltChange ? 'Faixa ${p.newBelt}' : 'Grau ${p.newStripes}',
          subtitle: p.notes,
          icon: Icons.military_tech,
          color: getGradeColor(p.getSport(), p.newBelt),
        ),
      );
    }

    // Add achievements
    for (final a in achievements) {
      allHistory.add(
        _HistoryItem(
          date: a.date,
          title: a.title,
          subtitle: a.description,
          icon: Icons.emoji_events,
          color: Colors.amber,
        ),
      );
    }

    // Sort by date descending
    allHistory.sort((a, b) => b.date.compareTo(a.date));

    if (allHistory.isEmpty) {
      return const Center(child: Text('Nenhum histórico'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allHistory.length,
      itemBuilder: (context, index) {
        final item = allHistory[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: item.color.withValues(alpha: 0.2),
              child: Icon(item.icon, color: item.color),
            ),
            title: Text(item.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.subtitle != null) Text(item.subtitle!),
                Text(
                  DateFormat('dd/MM/yyyy').format(item.date),
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryItem {
  final DateTime date;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  _HistoryItem({
    required this.date,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
  });
}
