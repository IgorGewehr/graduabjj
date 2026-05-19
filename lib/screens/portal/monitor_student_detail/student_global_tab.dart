import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/services.dart';
import 'student_detail_helpers.dart';

class StudentGlobalTab extends StatelessWidget {
  const StudentGlobalTab({
    super.key,
    required this.isLoadingGlobal,
    required this.globalHistory,
    required this.currentAcademyId,
  });

  final bool isLoadingGlobal;
  final CrossAcademyStudentHistory? globalHistory;
  final String currentAcademyId;

  @override
  Widget build(BuildContext context) {
    if (isLoadingGlobal) {
      return const Center(child: CircularProgressIndicator());
    }

    if (globalHistory == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.globe, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Nao foi possivel carregar o historico global',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    final history = globalHistory!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy notice
          if (!history.isProfilePublic)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.lock, size: 16, color: AppTheme.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'O perfil deste aluno e privado. Apenas informacoes basicas sao exibidas.',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.info),
                    ),
                  ),
                ],
              ),
            ),

          // Academies Overview
          if (history.academies.length > 1) ...[
            StudentDetailSectionTitle(
              'Academias Vinculadas (${history.academies.length})',
            ),
            const SizedBox(height: 12),
            ...history.academies.map(
              (academy) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: academy.academyId == currentAcademyId
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: academy.academyId == currentAcademyId
                        ? AppTheme.success.withValues(alpha: 0.3)
                        : AppTheme.divider,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: studentBeltColor(academy.currentBelt),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            academy.academyName,
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${CrossAcademyService.beltLabels[academy.currentBelt] ?? academy.currentBelt} - ${academy.currentStripes} grau(s)',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (academy.academyId == currentAcademyId)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Atual',
                          style: AppTheme.labelSmall.copyWith(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Global Attendance Stats
          if (history.attendanceStats.length > 1) ...[
            const StudentDetailSectionTitle('Presencas por Academia'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...history.attendanceStats.map(
                  (stat) => Container(
                    width: (MediaQuery.of(context).size.width - 48) / 2,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: stat.academyId == currentAcademyId
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${stat.totalCount}',
                          style: AppTheme.headlineMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: stat.academyId == currentAcademyId
                                ? AppTheme.success
                                : AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          stat.academyName,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: (MediaQuery.of(context).size.width - 48) / 2,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${history.totalAttendance}',
                        style: AppTheme.headlineMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                      Text(
                        'Total Global',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Belt Progressions from Other Academies
          if (history.beltProgressions.isNotEmpty) ...[
            const StudentDetailSectionTitle('Graduacoes em Outras Academias'),
            const SizedBox(height: 12),
            ...history.beltProgressions.take(10).map(
              (progression) => Container(
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
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        LucideIcons.award,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  progression.newStripes >
                                          (progression.previousStripes ?? 0)
                                      ? '${progression.newStripes}º grau - ${CrossAcademyService.beltLabels[progression.newBelt] ?? progression.newBelt}'
                                      : 'Faixa ${CrossAcademyService.beltLabels[progression.newBelt] ?? progression.newBelt}',
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              AcademyBadge(progression.academyName),
                            ],
                          ),
                          Text(
                            DateFormat('dd/MM/yyyy').format(
                              progression.promotionDate,
                            ),
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textDisabled,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: studentBeltColor(progression.newBelt),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Competition Results
          if (history.competitionResults.isNotEmpty) ...[
            const StudentDetailSectionTitle('Competicoes em Outras Academias'),
            const SizedBox(height: 12),
            ...history.competitionResults.take(10).map((result) {
              const positionIcons = {
                'gold': '🥇',
                'silver': '🥈',
                'bronze': '🥉',
                'participant': '🎖️',
              };
              const positionLabels = {
                'gold': 'Ouro',
                'silver': 'Prata',
                'bronze': 'Bronze',
                'participant': 'Participante',
              };

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
                    Text(
                      positionIcons[result.position] ?? '🎖️',
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  result.competitionName,
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Lutou por ${result.academyName}',
                                  style: AppTheme.labelSmall.copyWith(
                                    color: AppTheme.warning,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat('dd/MM/yyyy').format(result.date)} - ${positionLabels[result.position] ?? result.position}',
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
            }),
            const SizedBox(height: 24),
          ],

          // Global Medal Count
          if (history.medalCount.total > 0) ...[
            const StudentDetailSectionTitle('Total de Medalhas (Todas Academias)'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MedalCard(
                    emoji: '🥇',
                    count: history.medalCount.gold,
                    label: 'Ouros',
                    color: const Color(0xFFFFD700),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MedalCard(
                    emoji: '🥈',
                    count: history.medalCount.silver,
                    label: 'Pratas',
                    color: const Color(0xFFC0C0C0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MedalCard(
                    emoji: '🥉',
                    count: history.medalCount.bronze,
                    label: 'Bronzes',
                    color: const Color(0xFFCD7F32),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MedalCard(
                    emoji: '🏆',
                    count: history.medalCount.total,
                    label: 'Total',
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Empty State
          if (history.beltProgressions.isEmpty &&
              history.competitionResults.isEmpty &&
              history.academies.length <= 1)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(LucideIcons.globe, size: 48, color: AppTheme.textDisabled),
                    const SizedBox(height: 16),
                    Text(
                      'Este aluno nao possui historico em outras academias',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
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
