import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/polish/polish.dart';

/// Behavior Screen - Meu Comportamento
class BehaviorScreen extends ConsumerWidget {
  const BehaviorScreen({super.key});

  // Assessment categories
  static const List<_AssessmentCategoryData> _categories = [
    _AssessmentCategoryData(
      key: AssessmentCategory.respeito,
      label: 'Respeito',
    ),
    _AssessmentCategoryData(
      key: AssessmentCategory.disciplina,
      label: 'Disciplina',
    ),
    _AssessmentCategoryData(
      key: AssessmentCategory.pontualidade,
      label: 'Pontualidade',
    ),
    _AssessmentCategoryData(key: AssessmentCategory.tecnica, label: 'Tecnica'),
    _AssessmentCategoryData(key: AssessmentCategory.esforco, label: 'Esforco'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildNoStudentState();
        }

        final assessmentsAsync = ref.watch(
          studentAssessmentsProvider(student.id),
        );
        final averagesAsync = ref.watch(assessmentAveragesProvider(student.id));
        final latestAsync = ref.watch(latestAssessmentProvider(student.id));

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            ref.invalidate(studentAssessmentsProvider(student.id));
            ref.invalidate(assessmentAveragesProvider(student.id));
            ref.invalidate(latestAssessmentProvider(student.id));
          },
          child: assessmentsAsync.when(
            data: (assessments) {
              print(
                '[BEHAVIOR] Loaded ${assessments.length} assessments for student ${student.id}',
              );
              final averages = averagesAsync.valueOrNull ?? {};
              final latest = latestAsync.valueOrNull;

              // Calculate overall average
              double? overallAverage;
              if (averages.isNotEmpty) {
                final total = averages.values.fold<double>(
                  0.0,
                  (sum, v) => sum + v,
                );
                overallAverage = total / averages.length;
              }

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A managed kid's own behavior lives in the responsible's
                    // login; show a notice here instead of their assessments.
                    if (student.hasResponsible)
                      _ManagedBehaviorNotice(
                        responsibleName: student.responsibleName,
                      )
                    else ...[
                      // Latest Assessment Card
                      if (latest != null)
                        _LatestAssessmentCard(
                          assessment: latest,
                          categories: _categories,
                        ).entrance(index: 0)
                      else
                        _buildNoAssessmentCard(),
                      const SizedBox(height: 24),

                      // Stats
                      if (overallAverage != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                icon: LucideIcons.trendingUp,
                                iconColor: AppTheme.info,
                                iconBgColor: AppTheme.infoLight,
                                label: 'Media Geral',
                                value: overallAverage.toStringAsFixed(1),
                                animatedValue: overallAverage,
                                animatedDecimals: 1,
                                valueColor: _getPerformanceLevel(
                                  overallAverage,
                                ).color,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                icon: LucideIcons.star,
                                iconColor: AppTheme.warning,
                                iconBgColor: AppTheme.warningLight,
                                label: 'Avaliacoes',
                                value: assessments.length.toString(),
                                animatedValue: assessments.length.toDouble(),
                              ),
                            ),
                          ],
                        ).entrance(index: 1),
                        const SizedBox(height: 24),
                      ],

                      // History
                      if (assessments.isNotEmpty) ...[
                        Text(
                          'HISTORICO DE AVALIACOES',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ).fadeInQuick(),
                        const SizedBox(height: 12),
                        for (var i = 0; i < assessments.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _AssessmentHistoryCard(
                              assessment: assessments[i],
                              categories: _categories,
                            ).entrance(index: i + 2),
                          ),
                      ],
                    ],

                    // Dependents' behavior — surfaced to the responsible adult.
                    _DependentsBehaviorList(
                      currentStudentId: student.id,
                      categories: _categories,
                    ),

                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
            loading: () => _buildLoadingState(),
            error: (error, stack) {
              print('[BEHAVIOR] Error loading assessments: $error');
              return _buildErrorState();
            },
          ),
        );
      },
      loading: () => _buildLoadingState(),
      error: (error, stack) {
        print('[BEHAVIOR] Error loading student: $error');
        return _buildErrorState();
      },
    );
  }

  _PerformanceLevel _getPerformanceLevel(double score) {
    if (score >= 4.5)
      return _PerformanceLevel(label: 'Excelente', color: AppTheme.success);
    if (score >= 4.0)
      return _PerformanceLevel(label: 'Muito Bom', color: AppTheme.success);
    if (score >= 3.0)
      return _PerformanceLevel(label: 'Bom', color: AppTheme.warning);
    if (score >= 2.0)
      return _PerformanceLevel(label: 'Regular', color: AppTheme.warning);
    return _PerformanceLevel(label: 'Precisa Melhorar', color: AppTheme.error);
  }

  Widget _buildNoStudentState() {
    return const PolishedEmptyState(
      icon: LucideIcons.star,
      title: 'Conta nao vinculada',
      subtitle: 'Vincule sua conta a um aluno para ver as avaliacoes.',
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: PolishSkeleton.shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 200,
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
            ...List.generate(
              2,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return const PolishedEmptyState(
      icon: LucideIcons.alertCircle,
      title: 'Erro ao carregar dados',
      accent: AppTheme.error,
    );
  }

  Widget _buildNoAssessmentCard() {
    return const PolishedEmptyState(
      icon: LucideIcons.star,
      title: 'Nenhuma avaliacao registrada ainda',
    );
  }
}

/// Latest Assessment Card
class _LatestAssessmentCard extends StatelessWidget {
  final Assessment assessment;
  final List<_AssessmentCategoryData> categories;

  const _LatestAssessmentCard({
    required this.assessment,
    required this.categories,
  });

  double _calculateOverallScore() {
    return assessment.averageScore;
  }

  _PerformanceLevel _getPerformanceLevel(double score) {
    if (score >= 4.5)
      return _PerformanceLevel(label: 'Excelente', color: AppTheme.success);
    if (score >= 4.0)
      return _PerformanceLevel(label: 'Muito Bom', color: AppTheme.success);
    if (score >= 3.0)
      return _PerformanceLevel(label: 'Bom', color: AppTheme.warning);
    if (score >= 2.0)
      return _PerformanceLevel(label: 'Regular', color: AppTheme.warning);
    return _PerformanceLevel(label: 'Precisa Melhorar', color: AppTheme.error);
  }

  @override
  Widget build(BuildContext context) {
    final score = _calculateOverallScore();
    final performance = _getPerformanceLevel(score);

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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.star,
                    size: 20,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ultima Avaliacao',
                    style: AppTheme.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: performance.color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  performance.label,
                  style: AppTheme.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Date
          Row(
            children: [
              const Icon(
                LucideIcons.calendar,
                size: 14,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat(
                  "d 'de' MMMM 'de' yyyy",
                  'pt_BR',
                ).format(assessment.date),
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Scores Grid
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: categories.map((cat) {
                final catScore = assessment.getScoreForCategory(cat.key) ?? 0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              LucideIcons.star,
                              size: 14,
                              color: AppTheme.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              catScore.toString(),
                              style: AppTheme.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cat.label,
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Notes
          if (assessment.notes != null && assessment.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"${assessment.notes}"',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stat Card
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String label;
  final String value;
  final Color? valueColor;

  /// When set, the value counts up to this number instead of rendering [value]
  /// statically. [animatedDecimals] controls the displayed precision.
  final double? animatedValue;
  final int animatedDecimals;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.label,
    required this.value,
    this.valueColor,
    this.animatedValue,
    this.animatedDecimals = 0,
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
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (animatedValue != null)
            AnimatedCountUp(
              value: animatedValue!,
              decimals: animatedDecimals,
              style: AppTheme.displaySmall.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppTheme.textPrimary,
              ),
            )
          else
            Text(
              value,
              style: AppTheme.displaySmall.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppTheme.textPrimary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Assessment History Card
class _AssessmentHistoryCard extends StatelessWidget {
  final Assessment assessment;
  final List<_AssessmentCategoryData> categories;

  const _AssessmentHistoryCard({
    required this.assessment,
    required this.categories,
  });

  double _calculateOverallScore() {
    return assessment.averageScore;
  }

  _PerformanceLevel _getPerformanceLevel(double score) {
    if (score >= 4.5)
      return _PerformanceLevel(label: 'Excelente', color: AppTheme.success);
    if (score >= 4.0)
      return _PerformanceLevel(label: 'Muito Bom', color: AppTheme.success);
    if (score >= 3.0)
      return _PerformanceLevel(label: 'Bom', color: AppTheme.warning);
    if (score >= 2.0)
      return _PerformanceLevel(label: 'Regular', color: AppTheme.warning);
    return _PerformanceLevel(label: 'Precisa Melhorar', color: AppTheme.error);
  }

  @override
  Widget build(BuildContext context) {
    final score = _calculateOverallScore();
    final performance = _getPerformanceLevel(score);

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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.calendar,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat("d 'de' MMMM", 'pt_BR').format(assessment.date),
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(
                    LucideIcons.star,
                    size: 14,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    score.toStringAsFixed(1),
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: performance.color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      performance.label,
                      style: AppTheme.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Mini scores
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: categories.map((cat) {
              final catScore = assessment.getScoreForCategory(cat.key) ?? 0;
              return Text(
                '${cat.label}: $catScore',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              );
            }).toList(),
          ),

          // Notes
          if (assessment.notes != null && assessment.notes!.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              '"${assessment.notes}"',
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown in a managed kid's own login: their behavior is visible to the
/// responsible, not here.
class _ManagedBehaviorNotice extends StatelessWidget {
  final String? responsibleName;
  const _ManagedBehaviorNotice({this.responsibleName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.users, size: 24, color: AppTheme.info),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              responsibleName != null && responsibleName!.isNotEmpty
                  ? 'Seu acompanhamento de comportamento fica no app de $responsibleName.'
                  : 'Seu acompanhamento de comportamento fica no app do seu responsavel.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists the behavior of each dependent (kids) the logged-in adult is
/// responsible for. Empty (renders nothing) when there are no dependents.
class _DependentsBehaviorList extends ConsumerWidget {
  final String currentStudentId;
  final List<_AssessmentCategoryData> categories;
  const _DependentsBehaviorList({
    required this.currentStudentId,
    required this.categories,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deps = ref.watch(dependentsProvider).valueOrNull ?? const [];
    final others = deps.where((d) => d.id != currentStudentId).toList();
    if (others.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'COMPORTAMENTO DOS DEPENDENTES',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...others.map(
          (dep) => _DependentBehaviorSection(
            dependent: dep,
            categories: categories,
          ),
        ),
      ],
    );
  }
}

/// One dependent's behavior: name header + latest assessment + history.
class _DependentBehaviorSection extends ConsumerWidget {
  final Student dependent;
  final List<_AssessmentCategoryData> categories;
  const _DependentBehaviorSection({
    required this.dependent,
    required this.categories,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assessments =
        ref.watch(studentAssessmentsProvider(dependent.id)).valueOrNull ??
            const [];
    final latest =
        ref.watch(latestAssessmentProvider(dependent.id)).valueOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.user, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dependent.fullName,
                  style: AppTheme.titleSmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (latest != null)
            _LatestAssessmentCard(assessment: latest, categories: categories)
          else
            Text(
              'Nenhuma avaliacao registrada ainda.',
              style:
                  AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          if (assessments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...assessments.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AssessmentHistoryCard(
                  assessment: a,
                  categories: categories,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Data Models
class _AssessmentCategoryData {
  final AssessmentCategory key;
  final String label;

  const _AssessmentCategoryData({required this.key, required this.label});
}

class _PerformanceLevel {
  final String label;
  final Color color;

  _PerformanceLevel({required this.label, required this.color});
}
