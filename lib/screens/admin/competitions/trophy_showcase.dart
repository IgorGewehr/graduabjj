import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/services.dart';
import '../../../widgets/competitions/team_gallery_view.dart';

/// Trophy Showcase — exibe os trofeus conquistados pela academia
class TrophyShowcase extends StatelessWidget {
  final List<Competition> upcomingCompetitions;
  final List<Competition> pastCompetitions;
  final void Function(Competition) onCompetitionTap;

  const TrophyShowcase({
    super.key,
    required this.upcomingCompetitions,
    required this.pastCompetitions,
    required this.onCompetitionTap,
  });

  @override
  Widget build(BuildContext context) {
    final allCompetitions = [...upcomingCompetitions, ...pastCompetitions];
    final trophyCompetitions = allCompetitions
        .where((c) => c.teamPosition != null)
        .toList();

    const config = {
      'gold': {
        'label': 'Campeao',
        'bgColor': Color(0xFFFEF3C7),
        'borderColor': Color(0xFFF59E0B),
        'textColor': Color(0xFF92400E),
      },
      'silver': {
        'label': 'Vice',
        'bgColor': Color(0xFFF3F4F6),
        'borderColor': Color(0xFF9CA3AF),
        'textColor': Color(0xFF374151),
      },
      'bronze': {
        'label': '3o Lugar',
        'bgColor': Color(0xFFFED7AA),
        'borderColor': Color(0xFFF97316),
        'textColor': Color(0xFF7C2D12),
      },
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TROFEUS DA ACADEMIA ${trophyCompetitions.isNotEmpty ? "(${trophyCompetitions.length})" : ""}',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TeamGalleryView(),
                      ),
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
            if (trophyCompetitions.isNotEmpty) ...[
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
                      onTap: () => onCompetitionTap(comp),
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
            ] else ...[
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.trophy,
                      size: 32,
                      color: AppTheme.textDisabled,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Registre o primeiro trofeu da academia!',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
