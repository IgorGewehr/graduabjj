import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../services/services.dart';

/// Admin Graduation Screen - Fintech style matching webapp
class AdminGraduationScreen extends ConsumerStatefulWidget {
  const AdminGraduationScreen({super.key});

  @override
  ConsumerState<AdminGraduationScreen> createState() => _AdminGraduationScreenState();
}

class _AdminGraduationScreenState extends ConsumerState<AdminGraduationScreen> {
  List<Map<String, dynamic>> _eligibleStudents = [];
  List<BeltProgression> _recentPromotions = [];
  Map<String, Map<String, int>> _beltDistribution = {};
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
      final service = BeltProgressionService(FirebaseService.academyId);

      final results = await Future.wait([
        service.getEligibleStudents(),
        service.getRecentPromotions(limit: 20),
        service.getBeltDistribution(),
      ]);

      setState(() {
        _eligibleStudents = results[0] as List<Map<String, dynamic>>;
        _recentPromotions = results[1] as List<BeltProgression>;
        _beltDistribution = results[2] as Map<String, Map<String, int>>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(child: _buildHeader()),

            // Stats Cards
            SliverToBoxAdapter(child: _buildStatsCards()),

            // Tabs
            SliverToBoxAdapter(child: _buildTabs()),

            // Content based on tab
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

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

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
    final totalStudents = _beltDistribution.values
        .fold<int>(0, (a, m) => a + m.values.fold<int>(0, (x, y) => x + y));
    final eligibleCount = _eligibleStudents.length;
    final recentCount = _recentPromotions.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Elegiveis',
              value: eligibleCount.toString(),
              icon: LucideIcons.userCheck,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Graduados',
              value: recentCount.toString(),
              icon: LucideIcons.award,
              color: AppTheme.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
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
          String suffix = '';
          if (index == 0) suffix = ' (${_eligibleStudents.length})';
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
            child: _EligibleStudentCard(
              data: data,
              onPromote: () => _showPromotionSheet(data),
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
            child: _PromotionHistoryCard(promotion: promotion),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDistributionTab() {
    final grandTotal = _beltDistribution.values
        .fold<int>(0, (a, m) => a + m.values.fold<int>(0, (x, y) => x + y));
    if (grandTotal == 0) {
      return _buildEmptyState(
        icon: LucideIcons.pieChart,
        title: 'Sem dados de distribuicao',
        subtitle: 'Cadastre alunos ativos para ver a distribuicao de faixas',
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // Uma seção por modalidade — não mistura faixas de esportes diferentes.
      child: Column(
        key: const ValueKey('distribution'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _beltDistribution.entries.map((entry) {
          final sportId = SportId.fromString(entry.key);
          final dist = entry.value;
          final sportTotal = dist.values.fold<int>(0, (a, b) => a + b);
          // Ordem pela escada do esporte. Muay Thai tem dois sistemas (CBMT e
          // CBMTT); concatena as duas escadas pra ordenar alunos de qualquer
          // um. Faixas fora da escada (legado) vão ao fim.
          final orderIds = <String>[
            if (sportId == SportId.muaythai) ...[
              ...getGradesForSport(sportId, muaythaiVariant: muaythaiVariantCbmt)
                  .map((g) => g.id),
              ...getGradesForSport(sportId,
                      muaythaiVariant: muaythaiVariantCbmtt)
                  .map((g) => g.id),
            ] else
              ...getGradesForSport(sportId).map((g) => g.id),
          ];
          final orderedBelts = <String>[
            ...orderIds.where(dist.containsKey),
            ...dist.keys.where((b) => !orderIds.contains(b)),
          ];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
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
                          getSport(sportId).label,
                          style: AppTheme.titleMedium
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Total: $sportTotal alunos ativos',
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ...orderedBelts.map((belt) {
                  final count = dist[belt] ?? 0;
                  final percentage =
                      sportTotal > 0 ? (count / sportTotal * 100) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _BeltDistributionBar(
                      belt: belt,
                      count: count,
                      percentage: percentage,
                      sportId: sportId,
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
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
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  void _showPromotionSheet(Map<String, dynamic> studentData) {
    final eligibility = studentData['eligibility'] as EligibilityResult;
    final currentBelt = studentData['currentBelt'] as String;
    final currentStripes = studentData['currentStripes'] as int;
    final sportId = SportId.fromString(studentData['sportId'] as String? ?? 'bjj');
    final studentId = studentData['id'] as String;
    final studentName = studentData['fullName'] as String;

    bool isStripePromotion = eligibility.nextStripes != null && eligibility.nextStripes! > 0;
    String? selectedBelt = eligibility.nextBelt;
    int selectedStripes = eligibility.nextStripes ?? 0;
    final notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(LucideIcons.award, color: AppTheme.warning, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Confirmar Graduacao',
                        style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Student info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _getBeltColor(currentBelt, sportId: sportId),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              studentName.substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                color: currentBelt == 'white' ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
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
                                studentName,
                                style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Atual: ${_getBeltLabel(currentBelt)} ${currentStripes > 0 ? "• $currentStripes grau(s)" : ""}',
                                style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Promotion type
                  Text(
                    'Tipo de graduacao',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: currentStripes < 4
                              ? () {
                                  setSheetState(() {
                                    isStripePromotion = true;
                                    selectedBelt = currentBelt;
                                    selectedStripes = currentStripes + 1;
                                  });
                                }
                              : null,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isStripePromotion
                                  ? AppTheme.primary.withValues(alpha: 0.1)
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isStripePromotion
                                    ? AppTheme.primary
                                    : AppTheme.divider,
                                width: isStripePromotion ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  LucideIcons.star,
                                  color: isStripePromotion
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Grau',
                                  style: AppTheme.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isStripePromotion
                                        ? AppTheme.primary
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              isStripePromotion = false;
                              selectedBelt = _getNextBelt(currentBelt);
                              selectedStripes = 0;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: !isStripePromotion
                                  ? AppTheme.warning.withValues(alpha: 0.1)
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: !isStripePromotion
                                    ? AppTheme.warning
                                    : AppTheme.divider,
                                width: !isStripePromotion ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  LucideIcons.award,
                                  color: !isStripePromotion
                                      ? AppTheme.warning
                                      : AppTheme.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Faixa',
                                  style: AppTheme.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: !isStripePromotion
                                        ? AppTheme.warning
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // New belt/stripe display
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.arrowRight, color: AppTheme.success, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isStripePromotion
                                ? '$selectedStripes° grau na faixa ${_getBeltLabel(selectedBelt!)}'
                                : 'Faixa ${_getBeltLabel(selectedBelt!)}',
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Notes
                  Text(
                    'Observacoes (opcional)',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Adicione uma observacao...',
                        hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textDisabled),
                        prefixIcon: Icon(LucideIcons.fileText, color: AppTheme.textSecondary, size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: AppTheme.divider),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _promoteStudent(
                              studentId: studentId,
                              studentName: studentName,
                              newBelt: selectedBelt!,
                              newStripes: selectedStripes,
                              notes: notesController.text.isEmpty ? null : notesController.text,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.award, size: 18),
                              const SizedBox(width: 8),
                              const Text('Graduar'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _promoteStudent({
    required String studentId,
    required String studentName,
    required String newBelt,
    required int newStripes,
    String? notes,
  }) async {
    try {
      final service = BeltProgressionService(FirebaseService.academyId);
      // Resolve the student's primary sport so the promotion writes the
      // graduation to the right sportData bucket. Falls back to BJJ for
      // legacy single-sport students.
      final studentSnap = await FirebaseService.firestore
          .collection('academies/${FirebaseService.academyId}/students')
          .doc(studentId)
          .get();
      final studentData = studentSnap.data() ?? const <String, dynamic>{};
      final primarySport = studentData['primarySport'] as String?;
      final sportId = primarySport != null
          ? SportId.fromString(primarySport)
          : SportId.bjj;

      await service.promote(
        studentId: studentId,
        studentName: studentName,
        newBelt: newBelt,
        newStripes: newStripes,
        promotedBy: 'admin',
        promotedByName: 'Administrador',
        notes: notes,
        sportId: sportId,
      );

      if (mounted) {
        context.showSuccess('$studentName foi graduado com sucesso!');
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    }
  }

  String _getNextBelt(String currentBelt, {SportId sportId = SportId.bjj}) {
    final grades = getGradesForSport(
      sportId,
      muaythaiVariant: sportId == SportId.muaythai
          ? resolveMuaythaiVariant(currentBelt)
          : null,
    );
    final gradeIds = grades.map((g) => g.id).toList();
    final index = gradeIds.indexOf(currentBelt);
    if (index >= 0 && index < gradeIds.length - 1) {
      return gradeIds[index + 1];
    }
    return currentBelt;
  }

  String _getBeltLabel(String belt, {SportId sportId = SportId.bjj}) {
    return getGradeLabel(sportId, belt);
  }

  Color _getBeltColor(String belt, {SportId sportId = SportId.bjj}) {
    return getGradeColor(sportId, belt);
  }
}

/// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTheme.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Eligible Student Card
class _EligibleStudentCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onPromote;

  const _EligibleStudentCard({
    required this.data,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    final eligibility = data['eligibility'] as EligibilityResult;
    final currentBelt = data['currentBelt'] as String;
    final currentStripes = data['currentStripes'] as int;
    final totalClasses = data['totalClasses'] as int;
    final sportId = SportId.fromString(data['sportId'] as String? ?? 'bjj');

    return Container(
      padding: const EdgeInsets.all(16),
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
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _getBeltColor(currentBelt, sportId: sportId),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    (data['fullName'] as String).substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: currentBelt == 'white' ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
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
                      data['fullName'] as String,
                      style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildBeltIndicator(currentBelt, currentStripes, sportId),
                        const SizedBox(width: 8),
                        Icon(LucideIcons.clipboardCheck, size: 14, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '$totalClasses treinos',
                          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.checkCircle2, color: AppTheme.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    eligibility.message,
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.success),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPromote,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.award, size: 18),
                  const SizedBox(width: 8),
                  const Text('Graduar'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeltIndicator(String belt, int stripes, SportId sportId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _getBeltColor(belt, sportId: sportId),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getBeltShortLabel(belt, sportId: sportId),
            style: TextStyle(
              fontSize: 10,
              color: belt == 'white' ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (stripes > 0) ...[
            const SizedBox(width: 4),
            Text(
              '• $stripes',
              style: TextStyle(
                fontSize: 10,
                color: belt == 'white' ? Colors.black : Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getBeltColor(String belt, {SportId sportId = SportId.bjj}) {
    return getGradeColor(sportId, belt);
  }

  String _getBeltShortLabel(String belt, {SportId sportId = SportId.bjj}) {
    final label = getGradeLabel(sportId, belt);
    return label.length >= 2 ? label.substring(0, 2).toUpperCase() : label.toUpperCase();
  }
}

/// Promotion History Card
class _PromotionHistoryCard extends StatelessWidget {
  final BeltProgression promotion;

  const _PromotionHistoryCard({required this.promotion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _getBeltColor(promotion.newBelt, sportId: promotion.getSport()),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              promotion.isBeltChange ? LucideIcons.award : LucideIcons.star,
              color: promotion.newBelt == 'white' ? Colors.black : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  promotion.isBeltChange
                      ? 'Faixa ${_getBeltLabel(promotion.newBelt, sportId: promotion.getSport())}'
                      : '${promotion.newStripes}° Grau',
                  style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR').format(promotion.promotionDate),
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${promotion.totalClasses} treinos',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  String _getBeltLabel(String belt, {SportId sportId = SportId.bjj}) {
    return getGradeLabel(sportId, belt);
  }

  Color _getBeltColor(String belt, {SportId sportId = SportId.bjj}) {
    return getGradeColor(sportId, belt);
  }
}

/// Belt Distribution Bar
class _BeltDistributionBar extends StatelessWidget {
  final String belt;
  final int count;
  final double percentage;
  final SportId sportId;

  const _BeltDistributionBar({
    required this.belt,
    required this.count,
    required this.percentage,
    this.sportId = SportId.bjj,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _getBeltColor(belt),
                    borderRadius: BorderRadius.circular(4),
                    border: belt == 'white' ? Border.all(color: AppTheme.divider) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getBeltLabel(belt),
                  style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            Text(
              '$count (${percentage.toStringAsFixed(0)}%)',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: AppTheme.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(_getBeltDisplayColor(belt)),
            minHeight: 10,
          ),
        ),
      ],
    );
  }

  String _getBeltLabel(String belt) {
    return getGradeLabel(sportId, belt);
  }

  Color _getBeltColor(String belt) {
    return getGradeColor(sportId, belt);
  }

  Color _getBeltDisplayColor(String belt) {
    final color = getGradeColor(sportId, belt);
    // Faixas muito claras (branca) somem na barra clara → cinza visível.
    if (color.computeLuminance() > 0.85) return const Color(0xFF9E9E9E);
    return color;
  }
}
