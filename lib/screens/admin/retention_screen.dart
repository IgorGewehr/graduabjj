import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/attendance_dto.dart' as api_att;
import '../../api/dto/financial_dto.dart' as api_fin;
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/firebase_service.dart';
import '../../services/retention_service.dart';

/// Admin Retention Screen
/// Displays student retention analytics, risk scores, and churn indicators
class AdminRetentionScreen extends ConsumerStatefulWidget {
  const AdminRetentionScreen({super.key});

  @override
  ConsumerState<AdminRetentionScreen> createState() =>
      _AdminRetentionScreenState();
}

class _AdminRetentionScreenState
    extends ConsumerState<AdminRetentionScreen> {
  // Data
  List<StudentRiskScore> _atRiskStudents = [];
  RetentionMetrics? _metrics;
  bool _isLoading = true;

  // Filter
  RiskLevel? _selectedFilter; // null = all

  // Carousel
  final PageController _pageController = PageController(viewportFraction: 0.92);
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));

      // Risk-score CÁLCULO ainda é client-side (gap BE Sprint B). Reads
      // agora 100% Tatami; fallback Firestore removido na Fase 1.

      Future<List<Student>> studentsFuture() async {
        final q = tatami.StudentsQuery(academyId: academyId);
        ref.invalidate(tatami.tatamiStudentsLegacyProvider(q));
        return ref.read(tatami.tatamiStudentsLegacyProvider(q).future);
      }

      Future<Map<String, List<Map<String, dynamic>>>>
          attendanceMapFuture() async {
        final q = tatami.AttendanceQuery(
          academyId: academyId,
          filter: api_att.AttendanceFilter(
            dateFrom: thirtyDaysAgo,
            limit: 500,
          ),
        );
        ref.invalidate(tatami.tatamiAttendanceProvider(q));
        final page = await ref.read(tatami.tatamiAttendanceProvider(q).future);
        final m = <String, List<Map<String, dynamic>>>{};
        for (final a in page.items) {
          m.putIfAbsent(a.studentId, () => []).add({
            'studentId': a.studentId,
            'date': Timestamp.fromDate(a.date),
          });
        }
        return m;
      }

      Future<Map<String, List<Map<String, dynamic>>>>
          financialsMapFuture() async {
        final q = tatami.FinancialsQuery(
          academyId: academyId,
          filter: const api_fin.FinancialFilter(limit: 500),
        );
        ref.invalidate(tatami.tatamiFinancialsProvider(q));
        final page = await ref.read(tatami.tatamiFinancialsProvider(q).future);
        final m = <String, List<Map<String, dynamic>>>{};
        for (final f in page.items) {
          m.putIfAbsent(f.studentId, () => []).add({
            'studentId': f.studentId,
            'status': f.status.wire,
            'dueDate': Timestamp.fromDate(f.dueDate),
          });
        }
        return m;
      }

      // Fan-out — students + attendance + financials são independentes
      final results = await Future.wait<dynamic>([
        studentsFuture(),
        attendanceMapFuture(),
        financialsMapFuture(),
      ]);
      final allStudents = results[0] as List<Student>;
      final attendanceMap = results[1] as Map<String, List<Map<String, dynamic>>>;
      final financialsMap = results[2] as Map<String, List<Map<String, dynamic>>>;

      // Compute risk scores
      final retentionService = RetentionService();
      final riskScores = retentionService.getAtRiskStudents(
        allStudents,
        attendanceMap,
        financialsMap,
      );

      // Compute metrics
      final metrics = retentionService.getRetentionMetrics(
        allStudents,
        riskScores,
      );

      // Compute average frequency from attendance data
      final activeStudents = allStudents
          .where((s) => s.status == StudentStatus.active)
          .toList();
      double totalFrequency = 0;
      for (final student in activeStudents) {
        final records = attendanceMap[student.id] ?? [];
        final last30 = records.where((r) {
          final raw = r['date'];
          if (raw == null) return false;
          final date = raw is Timestamp ? raw.toDate() : DateTime.now();
          return now.difference(date).inDays <= 30;
        }).length;
        totalFrequency += last30;
      }
      final avgFrequency = activeStudents.isNotEmpty
          ? totalFrequency / activeStudents.length
          : 0.0;

      setState(() {
        _atRiskStudents = riskScores;
        _metrics = RetentionMetrics(
          totalAtRisk: metrics.totalAtRisk,
          atRiskPercentage: metrics.atRiskPercentage,
          averageFrequency: avgFrequency,
          paymentComplianceRate: metrics.paymentComplianceRate,
          distributionByRisk: metrics.distributionByRisk,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<StudentRiskScore> get _filteredStudents {
    if (_selectedFilter == null) return _atRiskStudents;
    return _atRiskStudents
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Retencao de Alunos'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  // KPI Cards
                  SliverToBoxAdapter(child: _buildKpiCards()),

                  // Risk Distribution
                  SliverToBoxAdapter(child: _buildRiskDistribution()),

                  // Filter Chips
                  SliverToBoxAdapter(child: _buildFilterChips()),

                  // Student List
                  if (_filteredStudents.isEmpty)
                    SliverFillRemaining(child: _buildEmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildStudentItem(_filteredStudents[index]),
                          childCount: _filteredStudents.length,
                        ),
                      ),
                    ),

                  // Bottom spacing
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }

  // ============================================
  // KPI Carousel
  // ============================================
  Widget _buildKpiCards() {
    if (_metrics == null) return const SizedBox.shrink();

    final dist = _metrics!.distributionByRisk;
    final total = _atRiskStudents.length;

    final pages = [
      // Page 1: Overview
      _CarouselPage(
        children: [
          _KpiTile(
            icon: LucideIcons.users,
            label: 'Alunos em Risco',
            value: '${_metrics!.totalAtRisk}',
            subtitle: 'de $total ativos',
          ),
          _KpiTile(
            icon: LucideIcons.trendingDown,
            label: 'Taxa de Evasao',
            value: '${_metrics!.atRiskPercentage.toStringAsFixed(1)}%',
            subtitle: 'score >= 25',
          ),
        ],
      ),
      // Page 2: Attendance & Payment
      _CarouselPage(
        children: [
          _KpiTile(
            icon: LucideIcons.calendarCheck,
            label: 'Frequencia Media',
            value: _metrics!.averageFrequency.toStringAsFixed(1),
            subtitle: 'presencas/mes',
          ),
          _KpiTile(
            icon: LucideIcons.checkCircle,
            label: 'Adimplencia',
            value: '${_metrics!.paymentComplianceRate.toStringAsFixed(0)}%',
            subtitle: 'em dia',
          ),
        ],
      ),
      // Page 3: Risk Distribution
      _CarouselPage(
        children: [
          _DistTile(label: 'Baixo', count: dist[RiskLevel.low] ?? 0),
          _DistTile(label: 'Medio', count: dist[RiskLevel.medium] ?? 0),
          _DistTile(label: 'Alto', count: dist[RiskLevel.high] ?? 0),
          _DistTile(label: 'Critico', count: dist[RiskLevel.critical] ?? 0),
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                    : AppTheme.textDisabled.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ============================================
  // Risk Distribution (no longer separate — merged into carousel)
  // ============================================
  Widget _buildRiskDistribution() {
    return const SizedBox.shrink();
  }

  // ============================================
  // Filter Chips
  // ============================================
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
                color:
                    _selectedFilter == null ? Colors.white : AppTheme.textPrimary,
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
                  onSelected: (_) =>
                      setState(() => _selectedFilter = isSelected ? null : level),
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

  // ============================================
  // Empty State
  // ============================================
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.shieldCheck,
              size: 64, color: AppTheme.success.withOpacity(0.5)),
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
            style:
                AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  // ============================================
  // Student Item
  // ============================================
  Widget _buildStudentItem(StudentRiskScore riskScore) {
    final color = _riskColor(riskScore.level);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => _showDetailBottomSheet(riskScore),
        leading: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
          ),
          child: CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            child: Text(
              riskScore.studentName.isNotEmpty
                  ? riskScore.studentName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        title: Text(
          riskScore.studentName,
          style: AppTheme.titleMedium,
        ),
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
    );
  }

  // ============================================
  // Detail Bottom Sheet
  // ============================================
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
                          backgroundColor: color.withOpacity(0.1),
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
                            Text(riskScore.studentName,
                                style: AppTheme.headlineSmall),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Score: ${riskScore.score}',
                                  style: AppTheme.titleMedium
                                      .copyWith(color: color),
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
                        color: AppTheme.success.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.checkCircle,
                              color: AppTheme.success, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Nenhum fator de risco identificado',
                            style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.success),
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
                          border:
                              Border.all(color: AppTheme.divider),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${factor.score}',
                                  style: AppTheme.titleMedium
                                      .copyWith(color: color),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
                        color: color.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: color.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.arrowRight,
                              size: 16, color: color),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              action,
                              style: AppTheme.bodyMedium,
                            ),
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

  /// Get suggested actions based on risk level
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
}

// ============================================
// Carousel Page: lays children in a Row
// ============================================
class _CarouselPage extends StatelessWidget {
  final List<Widget> children;
  const _CarouselPage({required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: children
          .expand((w) => [Expanded(child: w)])
          .toList(),
    );
  }
}

// ============================================
// KPI Tile (sober, monochrome)
// ============================================
class _KpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;

  const _KpiTile({
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
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textDisabled,
          ),
        ),
      ],
    );
  }
}

// ============================================
// Distribution Tile (compact, for carousel page 3)
// ============================================
class _DistTile extends StatelessWidget {
  final String label;
  final int count;

  const _DistTile({required this.label, required this.count});

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
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
