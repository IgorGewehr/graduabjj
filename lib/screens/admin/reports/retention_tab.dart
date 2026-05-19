import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/services.dart';

class RetentionTab extends StatefulWidget {
  final bool isLoading;
  final List<StudentRiskScore> atRiskStudents;
  final RetentionMetrics? retentionMetrics;

  const RetentionTab({
    super.key,
    required this.isLoading,
    required this.atRiskStudents,
    required this.retentionMetrics,
  });

  @override
  State<RetentionTab> createState() => _RetentionTabState();
}

class _RetentionTabState extends State<RetentionTab> {
  RiskLevel? _selectedFilter;
  final PageController _pageController = PageController(viewportFraction: 0.92);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<StudentRiskScore> get _filteredStudents {
    if (_selectedFilter == null) return widget.atRiskStudents;
    return widget.atRiskStudents
        .where((s) => s.level == _selectedFilter)
        .toList();
  }

  Color _riskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return Colors.green;
      case RiskLevel.medium:
        return Colors.amber;
      case RiskLevel.high:
        return Colors.orange;
      case RiskLevel.critical:
        return Colors.red;
    }
  }

  List<String> _getSuggestedActions(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return [
          'Manter acompanhamento regular',
          'Incentivar participacao em eventos',
        ];
      case RiskLevel.medium:
        return [
          'Enviar mensagem de acompanhamento',
          'Verificar satisfacao com as aulas',
          'Oferecer aula experimental em outro horario',
        ];
      case RiskLevel.high:
        return [
          'Contato direto por telefone ou WhatsApp',
          'Agendar conversa presencial',
          'Oferecer flexibilidade no pagamento',
          'Avaliar mudanca de plano/horario',
        ];
      case RiskLevel.critical:
        return [
          'Contato urgente com o aluno',
          'Reuniao presencial com professor',
          'Oferecer condicoes especiais de retorno',
          'Avaliar renegociacao financeira',
          'Envolver lideranca da academia',
        ];
    }
  }

  void _showDetailBottomSheet(StudentRiskScore riskScore) {
    final color = _riskColor(riskScore.level);
    final actions = _getSuggestedActions(riskScore.level);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 3),
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: color.withValues(alpha: 0.1),
                          child: Text(
                            riskScore.studentName.isNotEmpty
                                ? riskScore.studentName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: color,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              riskScore.studentName,
                              style: AppTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Score: ${riskScore.score}',
                                  style: AppTheme.titleMedium.copyWith(
                                    color: color,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Chip(
                                  label: Text(
                                    riskScore.level.label,
                                    style: AppTheme.labelSmall.copyWith(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                  backgroundColor: color,
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Risk Factors
                  Text('Fatores de Risco', style: AppTheme.headlineSmall),
                  const SizedBox(height: 12),

                  if (riskScore.factors.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.checkCircle,
                            color: AppTheme.success,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Nenhum fator de risco identificado',
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.success,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...riskScore.factors.map((factor) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${factor.score}',
                                  style: AppTheme.titleMedium.copyWith(
                                    color: color,
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
                                    factor.name,
                                    style: AppTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    factor.details,
                                    style: AppTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Peso: ${factor.weight}',
                              style: AppTheme.labelSmall,
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 24),

                  // Suggested Actions
                  Text('Acoes Sugeridas', style: AppTheme.headlineSmall),
                  const SizedBox(height: 12),

                  ...actions.map((action) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.arrowRight,
                            size: 16,
                            color: color,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(action, style: AppTheme.bodyMedium),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 24),

                  // Close button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fechar'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildKpiCards() {
    if (widget.retentionMetrics == null) return const SizedBox.shrink();

    final metrics = widget.retentionMetrics!;
    final dist = metrics.distributionByRisk;
    final total = widget.atRiskStudents.length;

    final pages = [
      // Page 1: Overview
      _RetentionCarouselPage(
        children: [
          _RetentionKpiTile(
            icon: LucideIcons.users,
            label: 'Alunos em Risco',
            value: '${metrics.totalAtRisk}',
            subtitle: 'de $total ativos',
          ),
          _RetentionKpiTile(
            icon: LucideIcons.trendingDown,
            label: 'Taxa de Evasao',
            value: '${metrics.atRiskPercentage.toStringAsFixed(1)}%',
            subtitle: 'score >= 25',
          ),
        ],
      ),
      // Page 2: Attendance & Payment
      _RetentionCarouselPage(
        children: [
          _RetentionKpiTile(
            icon: LucideIcons.calendarCheck,
            label: 'Frequencia Media',
            value: metrics.averageFrequency.toStringAsFixed(1),
            subtitle: 'presencas/mes',
          ),
          _RetentionKpiTile(
            icon: LucideIcons.checkCircle,
            label: 'Adimplencia',
            value: '${metrics.paymentComplianceRate.toStringAsFixed(0)}%',
            subtitle: 'em dia',
          ),
        ],
      ),
      // Page 3: Risk Distribution
      _RetentionCarouselPage(
        children: [
          _RetentionDistTile(label: 'Baixo', count: dist[RiskLevel.low] ?? 0),
          _RetentionDistTile(
            label: 'Medio',
            count: dist[RiskLevel.medium] ?? 0,
          ),
          _RetentionDistTile(label: 'Alto', count: dist[RiskLevel.high] ?? 0),
          _RetentionDistTile(
            label: 'Critico',
            count: dist[RiskLevel.critical] ?? 0,
          ),
        ],
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 120,
          child: PageView.builder(
            controller: _pageController,
            itemCount: pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: pages[index],
                ),
              );
            },
          ),
        ),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pages.length, (i) {
            final isActive = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.textPrimary
                    : AppTheme.textDisabled.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: _selectedFilter == null,
              onSelected: (_) => setState(() => _selectedFilter = null),
              selectedColor: AppTheme.primary,
              labelStyle: TextStyle(
                color: _selectedFilter == null
                    ? Colors.white
                    : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            ...RiskLevel.values.map((level) {
              final isSelected = _selectedFilter == level;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(level.label),
                  selected: isSelected,
                  onSelected: (_) => setState(
                    () => _selectedFilter = isSelected ? null : level,
                  ),
                  selectedColor: _riskColor(level),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentItem(StudentRiskScore riskScore) {
    final color = _riskColor(riskScore.level);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          onTap: () => _showDetailBottomSheet(riskScore),
          leading: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
            ),
            child: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Text(
                riskScore.studentName.isNotEmpty
                    ? riskScore.studentName[0].toUpperCase()
                    : '?',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          title: Text(riskScore.studentName, style: AppTheme.titleMedium),
          subtitle: Text(
            'Score: ${riskScore.score} | '
            'Ultima presenca: ${riskScore.daysSinceLastAttendance} dias atras | '
            '${riskScore.overduePayments} pagamentos vencidos',
            style: AppTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Chip(
            label: Text(
              riskScore.level.label,
              style: AppTheme.labelSmall.copyWith(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
            backgroundColor: color,
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredStudents;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Carousel
          _buildKpiCards(),

          // Filter Chips
          _buildFilterChips(),

          // Student List
          if (filtered.isEmpty)
            SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.shieldCheck,
                      size: 64,
                      color: AppTheme.success.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _selectedFilter != null
                          ? 'Nenhum aluno neste nivel de risco'
                          : 'Nenhum aluno em risco!',
                      style: AppTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedFilter != null
                          ? 'Tente outro filtro'
                          : 'Otimo trabalho!',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filtered.map((riskScore) => _buildStudentItem(riskScore)),
        ],
      ),
    );
  }
}

// ============================================================
// Internal helper widgets (private to retention_tab.dart)
// ============================================================

/// Carousel Page for retention KPI cards
class _RetentionCarouselPage extends StatelessWidget {
  final List<Widget> children;
  const _RetentionCarouselPage({required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(children: children.expand((w) => [Expanded(child: w)]).toList());
  }
}

/// KPI Tile for retention carousel
class _RetentionKpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;

  const _RetentionKpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTheme.headlineSmall.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textDisabled),
        ),
      ],
    );
  }
}

/// Distribution Tile for retention carousel
class _RetentionDistTile extends StatelessWidget {
  final String label;
  final int count;

  const _RetentionDistTile({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$count',
          style: AppTheme.headlineSmall.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
