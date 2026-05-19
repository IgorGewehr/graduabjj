import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/services.dart';
import 'student_detail_helpers.dart';

class StudentHistoryTab extends StatelessWidget {
  const StudentHistoryTab({
    super.key,
    required this.progressions,
    required this.achievements,
  });

  final List<BeltProgression> progressions;
  final List<Achievement> achievements;

  @override
  Widget build(BuildContext context) {
    final allItems = <HistoryItem>[];

    for (final p in progressions) {
      allItems.add(
        HistoryItem(
          date: p.date,
          title:
              'Graduacao: ${studentBeltDisplayName(p.belt)} ${p.stripes > 0 ? "(${p.stripes} grau)" : ""}',
          icon: LucideIcons.award,
          color: AppTheme.primary,
        ),
      );
    }

    for (final a in achievements) {
      allItems.add(
        HistoryItem(
          date: a.awardedAt,
          title: a.title,
          subtitle: a.description,
          icon: LucideIcons.trophy,
          color: AppTheme.warning,
        ),
      );
    }

    allItems.sort((a, b) => b.date.compareTo(a.date));

    if (allItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.history, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Nenhum historico registrado',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    Text(
                      DateFormat('dd/MM/yyyy').format(item.date),
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
