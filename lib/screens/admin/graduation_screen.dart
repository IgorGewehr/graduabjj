import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../services/services.dart';
import '../../widgets/polish/polish.dart';

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
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: PolishSkeleton.list(count: 4, itemHeight: 140),
                    ),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Currículo de técnicas',
                onPressed: () => context.push('/admin/graduacao/curriculo'),
                icon: const Icon(LucideIcons.bookOpen),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.surface,
                  foregroundColor: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
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

    final notifiableCount = _eligibleStudents
        .where((d) => ((d['linkedUserId'] as String?) ?? '').isNotEmpty)
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('eligible'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notifiableCount > 1) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _notifyAllEligible,
                icon: const Icon(LucideIcons.bell, size: 16),
                label: Text('Avisar todos ($notifiableCount)'),
              ),
            ),
            const SizedBox(height: 4),
          ],
          ..._eligibleStudents.asMap().entries.map((e) {
            final data = e.value;
            final uid = (data['linkedUserId'] as String?) ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EligibleStudentCard(
                data: data,
                onPromote: () => _showPromotionSheet(data),
                onNotify: uid.isEmpty ? null : () => _notifyEligible(data),
              ).entrance(index: e.key),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _notifyEligible(Map<String, dynamic> data) async {
    final uid = (data['linkedUserId'] as String?) ?? '';
    if (uid.isEmpty) return;
    try {
      await NotificationDispatcher(FirebaseService.academyId)
          .notifyGraduationEligible(
        userId: uid,
        studentName: (data['fullName'] as String?) ?? '',
        attendanceCount: (data['totalClasses'] as int?) ?? 0,
        studentId: data['id'] as String?,
      );
      if (mounted) context.showSuccess('Aluno avisado: apto a graduar!');
    } catch (e) {
      if (mounted) context.showError('Nao foi possivel avisar: $e');
    }
  }

  Future<void> _notifyAllEligible() async {
    final list = _eligibleStudents
        .where((d) => ((d['linkedUserId'] as String?) ?? '').isNotEmpty)
        .toList();
    if (list.isEmpty) return;
    final dispatcher = NotificationDispatcher(FirebaseService.academyId);
    var ok = 0;
    for (final data in list) {
      try {
        await dispatcher.notifyGraduationEligible(
          userId: data['linkedUserId'] as String,
          studentName: (data['fullName'] as String?) ?? '',
          attendanceCount: (data['totalClasses'] as int?) ?? 0,
          studentId: data['id'] as String?,
        );
        ok++;
      } catch (_) {/* best-effort */}
    }
    if (mounted) context.showSuccess('$ok aluno(s) avisado(s).');
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
        children: _recentPromotions.asMap().entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PromotionHistoryCard(promotion: e.value).entrance(index: e.key),
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
    return PolishedEmptyState(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accent: AppTheme.success,
    );
  }

  void _showPromotionSheet(Map<String, dynamic> studentData) {
    final eligibility = studentData['eligibility'] as EligibilityResult;
    final currentBelt = studentData['currentBelt'] as String;
    final currentStripes = studentData['currentStripes'] as int;
    final sportId = SportId.fromString(studentData['sportId'] as String? ?? 'bjj');
    final studentId = studentData['id'] as String;
    final studentName = studentData['fullName'] as String;
    // Auditoria (graduation-ui): categoria (kids/adult) e variante do Muay Thai
    // precisam acompanhar a promoção, senão a escada usada vira sempre a do BJJ
    // adulto. category pode não vir no mapa (legado) → cai em 'adult' (mesmo
    // default do service).
    final category = (studentData['category'] as String?) ?? 'adult';
    final muaythaiVariant = sportId == SportId.muaythai
        ? resolveMuaythaiVariant(currentBelt)
        : null;
    // Esportes sem faixa (boxe, MMA, musculação = GradeSystem.none) não têm
    // escada — não há promoção de faixa/grau a oferecer.
    final hasGradeSystem = getSport(sportId).gradeSystem != GradeSystem.none;
    // Teto de graus REAL da faixa atual neste esporte (era hardcoded em 4, o que
    // quebrava Muay Thai/Judô = 0 graus e a faixa preta de BJJ/Karatê = 6/10).
    final maxStripesForCurrent =
        getGradeDefinition(sportId, currentBelt)?.maxStripes ?? 0;

    // Promoção de grau só é válida se a faixa atual aceita graus; senão a sheet
    // já abre no modo "faixa" (evita default inconsistente p/ Muay Thai/Judô).
    bool isStripePromotion = maxStripesForCurrent > 0 &&
        eligibility.nextStripes != null &&
        eligibility.nextStripes! > 0;
    String? selectedBelt = isStripePromotion
        ? (eligibility.nextBelt ?? currentBelt)
        : (eligibility.nextBelt ??
            _getNextBelt(
              currentBelt,
              sportId: sportId,
              category: category,
              muaythaiVariant: muaythaiVariant,
            ));
    int selectedStripes = isStripePromotion ? (eligibility.nextStripes ?? 0) : 0;
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
                                'Atual: ${_getBeltLabel(currentBelt, sportId: sportId)} ${currentStripes > 0 ? "• $currentStripes grau(s)" : ""}',
                                style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Auditoria: esportes sem faixa (boxe/MMA/musculação) não têm
                  // escada de graduação — não oferece promoção de faixa/grau.
                  if (hasGradeSystem) ...[
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
                      // Auditoria: só mostra o seletor de "Grau" quando a faixa
                      // atual realmente suporta graus (maxStripes > 0). Muay Thai
                      // e Judô (maxStripes:0) progridem só por faixa/cor.
                      if (maxStripesForCurrent > 0) ...[
                      Expanded(
                        child: GestureDetector(
                          // Teto de graus derivado da definição da faixa, não mais
                          // hardcoded em 4.
                          onTap: currentStripes < maxStripesForCurrent
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
                      ],
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              isStripePromotion = false;
                              // Auditoria: próxima faixa pela escada DO ESPORTE
                              // (sportId/category/variante), não mais a do BJJ.
                              selectedBelt = _getNextBelt(
                                currentBelt,
                                sportId: sportId,
                                category: category,
                                muaythaiVariant: muaythaiVariant,
                              );
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
                                ? '$selectedStripes° grau na faixa ${_getBeltLabel(selectedBelt!, sportId: sportId)}'
                                : 'Faixa ${_getBeltLabel(selectedBelt!, sportId: sportId)}',
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
                  ] else ...[
                    // Modalidade sem graduação por faixa.
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.info,
                              color: AppTheme.textSecondary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Esta modalidade não possui graduação por faixa.',
                              style: AppTheme.bodySmall
                                  .copyWith(color: AppTheme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Notes
                  Text(
                    'Observacoes / banca / exame (opcional)',
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
                        hintText: 'Ex.: banca, resultado do exame, observacao...',
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
                        child: Builder(builder: (context) {
                          // Auditoria: bloqueia promoção no-op. Para "faixa",
                          // a nova faixa precisa ser diferente da atual (escada
                          // pode não ter próxima). Para "grau", precisa subir.
                          // Sem sistema de faixa, nada a graduar.
                          final isNoBeltChange = selectedBelt == currentBelt;
                          final canPromote = hasGradeSystem &&
                              selectedBelt != null &&
                              (isStripePromotion
                                  ? selectedStripes > currentStripes
                                  : !isNoBeltChange);
                          return ElevatedButton(
                          onPressed: !canPromote
                              ? null
                              : () async {
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
                        );
                        }),
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
        // Genuine win: a student was promoted.
        Celebration.confetti(context);
        context.showSuccess('$studentName foi graduado com sucesso!');
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    }
  }

  String _getNextBelt(
    String currentBelt, {
    SportId sportId = SportId.bjj,
    String category = 'adult',
    String? muaythaiVariant,
  }) {
    // Auditoria: respeita a escada do esporte + categoria (kids/adult) e a
    // variante do Muay Thai; antes ignorava tudo e usava a do BJJ adulto.
    final grades = getGradesForSport(
      sportId,
      category: category,
      muaythaiVariant: muaythaiVariant ??
          (sportId == SportId.muaythai
              ? resolveMuaythaiVariant(currentBelt)
              : null),
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
          int.tryParse(value) != null
              ? AnimatedCountUp(
                  value: int.parse(value),
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Text(
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
  final VoidCallback? onNotify;

  const _EligibleStudentCard({
    required this.data,
    required this.onPromote,
    this.onNotify,
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
          Row(
            children: [
              if (onNotify != null) ...[
                OutlinedButton.icon(
                  onPressed: onNotify,
                  icon: const Icon(LucideIcons.bell, size: 16),
                  label: const Text('Avisar'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
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
