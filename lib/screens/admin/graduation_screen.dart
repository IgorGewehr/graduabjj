import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/dto/student_dto.dart' as api_student;
import '../../api/repositories.dart' as tatami_repos;
import '../../core/theme.dart';
import '../../providers/selected_academy_provider.dart';
import '../../services/services.dart';
import 'graduation/graduation_cards.dart';
import 'graduation/promotion_sheet.dart';

/// Admin Graduation Screen - Fintech style matching webapp
class AdminGraduationScreen extends ConsumerStatefulWidget {
  const AdminGraduationScreen({super.key});

  @override
  ConsumerState<AdminGraduationScreen> createState() =>
      _AdminGraduationScreenState();
}

class _AdminGraduationScreenState
    extends ConsumerState<AdminGraduationScreen> {
  List<Map<String, dynamic>> _eligibleStudents = [];
  List<BeltProgression> _recentPromotions = [];
  Map<String, int> _beltDistribution = {};
  bool _isLoading = true;
  int _selectedTabIndex = 0;

  final _tabs = ['Elegiveis', 'Historico', 'Distribuicao'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = ref.read(selectedAcademyIdProvider) ?? '';
      final beltRepo = ref.read(tatami_repos.beltProgressionRepoProvider);

      final results = await Future.wait([
        beltRepo
            .getEligibleStudents(academyId, limit: 100)
            .then(_adaptEligibleStudents),
        beltRepo
            .getRecentProgressions(academyId, limit: 20)
            .then(_adaptRecentProgressions),
        beltRepo
            .getBeltDistribution(academyId)
            .then(_adaptBeltDistribution),
      ]);

      setState(() {
        _eligibleStudents = results[0] as List<Map<String, dynamic>>;
        _recentPromotions = results[1] as List<BeltProgression>;
        _beltDistribution = results[2] as Map<String, int>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// Adapta [List<ApiRecentProgression>] para [List<BeltProgression>]
  /// para compatibilidade com [PromotionHistoryCard].
  List<BeltProgression> _adaptRecentProgressions(
    List<api_student.ApiRecentProgression> items,
  ) {
    return items.map((p) {
      return BeltProgression(
        id: p.progressionId,
        studentId: p.studentId,
        previousBelt: p.previousBelt.wire,
        previousStripes: p.previousStripes,
        newBelt: p.newBelt.wire,
        newStripes: p.newStripes,
        promotionDate: p.promotionDate,
        totalClasses: 0, // não retornado neste endpoint
        notes: p.notes,
        createdAt: p.promotionDate,
      );
    }).toList();
  }

  /// Adapta [List<ApiBeltCount>] para [Map<String, int>] (wire-name → count).
  Map<String, int> _adaptBeltDistribution(
    List<api_student.ApiBeltCount> items,
  ) {
    return {for (final b in items) b.belt.wire: b.count};
  }

  /// Adapta [EligibleStudentsPage] para a estrutura Map que os widgets
  /// [EligibleStudentCard] e [showPromotionSheet] esperam.
  List<Map<String, dynamic>> _adaptEligibleStudents(
    api_student.EligibleStudentsPage page,
  ) {
    return page.items.map((s) {
      final el = s.eligibility;
      final eligibility = EligibilityResult(
        eligible: el.eligible,
        nextBelt: el.nextBelt?.wire,
        nextStripes: el.nextStripes,
        currentClasses: el.currentCount,
        requiredClasses: el.requiredCount,
        missingClasses: el.attendancesNeeded,
        message: el.eligible
            ? (el.nextStripes != null && el.nextStripes! > 0
                ? 'Elegível para ${el.nextStripes}º grau!'
                : 'Elegível para faixa!')
            : 'Faltam ${el.attendancesNeeded} aulas',
      );
      return <String, dynamic>{
        'id': s.studentId,
        'fullName': s.fullName,
        'currentBelt': s.currentBelt.wire,
        'currentStripes': s.currentStripes,
        'totalClasses': el.currentCount,
        'eligibility': eligibility,
        'photoUrl': s.photoUrl,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildStatsCards()),
            SliverToBoxAdapter(child: _buildTabs()),
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SliverToBoxAdapter(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _buildTabContent(),
                    ),
                  ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-widgets locais
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Graduacao',
                style: AppTheme.headlineMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Promova alunos e acompanhe progressos',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(LucideIcons.refreshCw),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surface,
              foregroundColor: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalStudents =
        _beltDistribution.values.fold<int>(0, (a, b) => a + b);
    final eligibleCount = _eligibleStudents.length;
    final recentCount = _recentPromotions.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: GraduationStatCard(
              label: 'Elegiveis',
              value: eligibleCount.toString(),
              icon: LucideIcons.userCheck,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GraduationStatCard(
              label: 'Graduados',
              value: recentCount.toString(),
              icon: LucideIcons.award,
              color: AppTheme.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GraduationStatCard(
              label: 'Alunos',
              value: totalStudents.toString(),
              icon: LucideIcons.users,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.all(20),
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedTabIndex == index;
          final suffix = index == 0 ? ' (${_eligibleStudents.length})' : '';
          return GestureDetector(
            onTap: () => setState(() => _selectedTabIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
                ),
              ),
              child: Center(
                child: Text(
                  '${_tabs[index]}$suffix',
                  style: AppTheme.bodySmall.copyWith(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildEligibleTab();
      case 1:
        return _buildHistoryTab();
      case 2:
        return _buildDistributionTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEligibleTab() {
    if (_eligibleStudents.isEmpty) {
      return _buildEmptyState(
        icon: LucideIcons.checkCircle,
        title: 'Nenhum aluno elegivel',
        subtitle: 'Todos os alunos estao em dia com suas graduacoes',
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('eligible'),
        children: _eligibleStudents.map((data) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: EligibleStudentCard(
              data: data,
              onPromote: () => _openPromotionSheet(data),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_recentPromotions.isEmpty) {
      return _buildEmptyState(
        icon: LucideIcons.history,
        title: 'Nenhuma graduacao registrada',
        subtitle: 'As graduacoes aparecerão aqui',
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('history'),
        children: _recentPromotions.map((promotion) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PromotionHistoryCard(promotion: promotion),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDistributionTab() {
    final total = _beltDistribution.values.fold<int>(0, (a, b) => a + b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('distribution'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(LucideIcons.pieChart,
                          color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Distribuicao de Faixas',
                          style: AppTheme.titleMedium
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Total: $total alunos ativos',
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ..._beltDistribution.keys.map((belt) {
                  final count = _beltDistribution[belt] ?? 0;
                  final percentage =
                      total > 0 ? (count / total * 100) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: BeltDistributionBar(
                      belt: belt,
                      count: count,
                      percentage: percentage,
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 40, color: AppTheme.success),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style:
                  AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style:
                  AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sheet delegates
  // ---------------------------------------------------------------------------

  void _openPromotionSheet(Map<String, dynamic> studentData) {
    showPromotionSheet(
      context: context,
      ref: ref,
      studentData: studentData,
      onPromoted: _loadData,
    );
  }
}
