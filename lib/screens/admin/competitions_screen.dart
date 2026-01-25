import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

/// Admin Competitions Screen - Fintech style matching webapp
class AdminCompetitionsScreen extends ConsumerStatefulWidget {
  const AdminCompetitionsScreen({super.key});

  @override
  ConsumerState<AdminCompetitionsScreen> createState() => _AdminCompetitionsScreenState();
}

class _AdminCompetitionsScreenState extends ConsumerState<AdminCompetitionsScreen> {
  List<Competition> _upcomingCompetitions = [];
  List<Competition> _pastCompetitions = [];
  bool _isLoading = true;
  int _selectedTabIndex = 0;

  final _tabs = ['Proximos', 'Passados'];

  @override
  void initState() {
    super.initState();
    _loadCompetitions();
  }

  Future<void> _loadCompetitions() async {
    setState(() => _isLoading = true);

    try {
      final service = CompetitionService(FirebaseService.academyId);
      final upcoming = await service.getUpcoming();
      final all = await service.list();
      final now = DateTime.now();
      final past = all.where((c) => c.date.isBefore(now)).toList();

      setState(() {
        _upcomingCompetitions = upcoming;
        _pastCompetitions = past;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Competition> get _currentList =>
      _selectedTabIndex == 0 ? _upcomingCompetitions : _pastCompetitions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadCompetitions,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(child: _buildHeader()),

            // Stats Cards
            SliverToBoxAdapter(child: _buildStatsCards()),

            // Tabs
            SliverToBoxAdapter(child: _buildTabs()),

            // Competition List
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _currentList.isEmpty
                    ? SliverFillRemaining(child: _buildEmptyState())
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final competition = _currentList[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _CompetitionCard(
                                  competition: competition,
                                  onTap: () => _showCompetitionDetails(competition),
                                  onEdit: () => _showEditCompetitionSheet(competition),
                                  onDelete: () => _showDeleteConfirmation(competition),
                                  onManageEnrollments: () => _showEnrollmentsSheet(competition),
                                ),
                              );
                            },
                            childCount: _currentList.length,
                          ),
                        ),
                      ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCompetitionSheet,
        backgroundColor: AppTheme.textPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(LucideIcons.plus, size: 20),
        label: const Text('Novo Campeonato'),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_upcomingCompetitions.length + _pastCompetitions.length} campeonatos',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadCompetitions,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
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
    final totalUpcoming = _upcomingCompetitions.length;
    final totalEnrollments = _upcomingCompetitions.fold<int>(
      0,
      (sum, c) => sum + c.enrolledCount,
    );
    final nextCompetition = _upcomingCompetitions.isNotEmpty
        ? _upcomingCompetitions.first.date.difference(DateTime.now()).inDays
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Proximos',
              value: totalUpcoming.toString(),
              icon: LucideIcons.trophy,
              color: AppTheme.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Inscricoes',
              value: totalEnrollments.toString(),
              icon: LucideIcons.users,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Dias',
              value: nextCompetition?.toString() ?? '-',
              icon: LucideIcons.calendar,
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
          final count = index == 0 ? _upcomingCompetitions.length : _pastCompetitions.length;
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
                  '${_tabs[index]} ($count)',
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              LucideIcons.trophy,
              size: 40,
              color: AppTheme.warning,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedTabIndex == 0
                ? 'Nenhum campeonato agendado'
                : 'Nenhum campeonato passado',
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione novos campeonatos para comecar',
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateCompetitionSheet() {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? selectedDate;

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
                        child: Icon(LucideIcons.trophy, color: AppTheme.warning, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Novo Campeonato',
                        style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _ModernTextField(
                    controller: nameController,
                    label: 'Nome do Campeonato',
                    hint: 'Ex: CBJJ Nacional',
                    icon: LucideIcons.trophy,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Data',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setSheetState(() => selectedDate = date);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.calendar, color: AppTheme.textSecondary, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            selectedDate != null
                                ? DateFormat('dd/MM/yyyy').format(selectedDate!)
                                : 'Selecionar data',
                            style: AppTheme.bodyMedium.copyWith(
                              color: selectedDate != null
                                  ? AppTheme.textPrimary
                                  : AppTheme.textDisabled,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ModernTextField(
                    controller: locationController,
                    label: 'Local (opcional)',
                    hint: 'Endereco ou cidade',
                    icon: LucideIcons.mapPin,
                  ),
                  const SizedBox(height: 16),
                  _ModernTextField(
                    controller: descriptionController,
                    label: 'Descricao (opcional)',
                    hint: 'Informacoes adicionais',
                    icon: LucideIcons.fileText,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.isEmpty || selectedDate == null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text('Preencha nome e data'),
                            ),
                          );
                          return;
                        }

                        Navigator.pop(sheetContext);

                        try {
                          final service = CompetitionService(FirebaseService.academyId);
                          await service.create(
                            name: nameController.text,
                            date: selectedDate!,
                            location: locationController.text.isEmpty
                                ? null
                                : locationController.text,
                            description: descriptionController.text.isEmpty
                                ? null
                                : descriptionController.text,
                          );

                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(LucideIcons.check, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Campeonato criado!'),
                                  ],
                                ),
                                backgroundColor: AppTheme.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            _loadCompetitions();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Erro: $e')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.plus, size: 20),
                          const SizedBox(width: 8),
                          const Text('Criar Campeonato'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditCompetitionSheet(Competition competition) {
    final nameController = TextEditingController(text: competition.name);
    final locationController = TextEditingController(text: competition.location ?? '');
    final descriptionController = TextEditingController(text: competition.description ?? '');
    DateTime selectedDate = competition.date;

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
                        child: Icon(LucideIcons.pencil, color: AppTheme.warning, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Editar Campeonato',
                        style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _ModernTextField(
                    controller: nameController,
                    label: 'Nome do Campeonato',
                    hint: 'Ex: CBJJ Nacional',
                    icon: LucideIcons.trophy,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Data',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setSheetState(() => selectedDate = date);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.calendar, color: AppTheme.textSecondary, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            DateFormat('dd/MM/yyyy').format(selectedDate),
                            style: AppTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ModernTextField(
                    controller: locationController,
                    label: 'Local (opcional)',
                    hint: 'Endereco ou cidade',
                    icon: LucideIcons.mapPin,
                  ),
                  const SizedBox(height: 16),
                  _ModernTextField(
                    controller: descriptionController,
                    label: 'Descricao (opcional)',
                    hint: 'Informacoes adicionais',
                    icon: LucideIcons.fileText,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('Nome e obrigatorio')),
                          );
                          return;
                        }

                        Navigator.pop(sheetContext);

                        try {
                          final service = CompetitionService(FirebaseService.academyId);
                          await service.update(competition.id, {
                            'name': nameController.text,
                            'date': selectedDate,
                            'location': locationController.text.isEmpty
                                ? null
                                : locationController.text,
                            'description': descriptionController.text.isEmpty
                                ? null
                                : descriptionController.text,
                          });

                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(LucideIcons.check, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Campeonato atualizado!'),
                                  ],
                                ),
                                backgroundColor: AppTheme.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            _loadCompetitions();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Erro: $e')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.save, size: 20),
                          const SizedBox(width: 8),
                          const Text('Salvar'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCompetitionDetails(Competition competition) {
    final daysUntil = competition.date.difference(DateTime.now()).inDays;
    final isUpcoming = daysUntil >= 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
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
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.trophy, color: AppTheme.warning, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        competition.name,
                        style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (competition.location != null)
                        Text(
                          competition.location!,
                          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (competition.description != null) ...[
              const SizedBox(height: 16),
              Text(
                competition.description!,
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _DetailRow(
                    icon: LucideIcons.calendar,
                    label: 'Data',
                    value: DateFormat('dd/MM/yyyy').format(competition.date),
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(
                    icon: LucideIcons.users,
                    label: 'Inscritos',
                    value: '${competition.enrolledCount}',
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(
                    icon: LucideIcons.checkCircle,
                    label: 'Status',
                    value: competition.status.label,
                  ),
                  if (isUpcoming && daysUntil <= 30) ...[
                    const SizedBox(height: 12),
                    _DetailRow(
                      icon: LucideIcons.clock,
                      label: 'Tempo restante',
                      value: daysUntil == 0
                          ? 'Hoje!'
                          : daysUntil == 1
                              ? 'Amanha'
                              : 'Em $daysUntil dias',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showEnrollmentsSheet(competition);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.users, size: 18),
                    const SizedBox(width: 8),
                    const Text('Ver Inscricoes'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showEditCompetitionSheet(competition);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: AppTheme.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.pencil, size: 18),
                        const SizedBox(width: 8),
                        const Text('Editar'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showDeleteConfirmation(competition);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: AppTheme.error,
                      side: BorderSide(color: AppTheme.error.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.trash2, size: 18),
                        const SizedBox(width: 8),
                        const Text('Excluir'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showEnrollmentsSheet(Competition competition) async {
    final enrollmentService = CompetitionEnrollmentService(FirebaseService.academyId);
    final enrollments = await enrollmentService.getByCompetition(competition.id);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(LucideIcons.users, color: AppTheme.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Inscricoes',
                                style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                competition.name,
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showAddEnrollmentSheet(competition);
                          },
                          icon: Icon(LucideIcons.userPlus, color: AppTheme.primary),
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: enrollments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.userX,
                              size: 48,
                              color: AppTheme.textDisabled,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Nenhuma inscricao',
                              style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20),
                        itemCount: enrollments.length,
                        itemBuilder: (context, index) {
                          final enrollment = enrollments[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      enrollment.studentName.substring(0, 1).toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
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
                                        enrollment.studentName,
                                        style: AppTheme.bodyMedium.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${enrollment.ageCategory ?? 'Sem categoria'} - ${enrollment.weightCategory ?? 'Sem peso'}',
                                        style: AppTheme.bodySmall.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    enrollment.transportPreference.label,
                                    style: AppTheme.labelSmall.copyWith(
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddEnrollmentSheet(Competition competition) async {
    final studentService = StudentService(FirebaseService.academyId);
    final students = await studentService.getActive();

    if (!mounted) return;

    Student? selectedStudent;
    final categoryController = TextEditingController();
    final weightController = TextEditingController();

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
                          color: AppTheme.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(LucideIcons.userPlus, color: AppTheme.success, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Nova Inscricao',
                        style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Aluno',
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
                    child: DropdownButtonFormField<Student>(
                      value: selectedStudent,
                      items: students.map((s) {
                        return DropdownMenuItem(
                          value: s,
                          child: Text(s.fullName),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setSheetState(() => selectedStudent = value);
                      },
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      dropdownColor: AppTheme.surface,
                      hint: const Text('Selecione o aluno'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ModernTextField(
                    controller: categoryController,
                    label: 'Categoria de Idade',
                    hint: 'Ex: Adulto',
                    icon: LucideIcons.users,
                  ),
                  const SizedBox(height: 16),
                  _ModernTextField(
                    controller: weightController,
                    label: 'Categoria de Peso',
                    hint: 'Ex: Leve',
                    icon: LucideIcons.scale,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (selectedStudent == null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('Selecione um aluno')),
                          );
                          return;
                        }

                        Navigator.pop(sheetContext);

                        try {
                          final service = CompetitionEnrollmentService(FirebaseService.academyId);
                          await service.enroll(
                            competitionId: competition.id,
                            competitionName: competition.name,
                            studentId: selectedStudent!.id,
                            studentName: selectedStudent!.fullName,
                            ageCategory: categoryController.text.isEmpty
                                ? null
                                : categoryController.text,
                            weightCategory: weightController.text.isEmpty
                                ? null
                                : weightController.text,
                          );

                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(LucideIcons.check, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Inscricao realizada!'),
                                  ],
                                ),
                                backgroundColor: AppTheme.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            _loadCompetitions();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Erro: $e')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.userPlus, size: 20),
                          const SizedBox(width: 8),
                          const Text('Inscrever'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(Competition competition) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(LucideIcons.alertTriangle, color: AppTheme.error, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'Excluir Campeonato',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Deseja excluir "${competition.name}"? Esta acao tambem removera todas as inscricoes.',
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
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
                      Navigator.pop(context);

                      try {
                        final service = CompetitionService(FirebaseService.academyId);
                        await service.delete(competition.id);

                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  Icon(LucideIcons.check, color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  const Text('Campeonato excluido!'),
                                ],
                              ),
                              backgroundColor: AppTheme.success,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          _loadCompetitions();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text('Erro: $e')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Excluir'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
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

/// Competition Card Widget
class _CompetitionCard extends StatelessWidget {
  final Competition competition;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManageEnrollments;

  const _CompetitionCard({
    required this.competition,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onManageEnrollments,
  });

  @override
  Widget build(BuildContext context) {
    final daysUntil = competition.date.difference(DateTime.now()).inDays;
    final isUpcoming = daysUntil >= 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.trophy, color: AppTheme.warning, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        competition.name,
                        style: AppTheme.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (competition.location != null)
                        Text(
                          competition.location!,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(LucideIcons.moreVertical, color: AppTheme.textSecondary, size: 20),
                  onSelected: (value) {
                    if (value == 'enrollments') onManageEnrollments();
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'enrollments',
                      child: Row(
                        children: [
                          Icon(LucideIcons.users, size: 18, color: AppTheme.textSecondary),
                          const SizedBox(width: 8),
                          const Text('Inscricoes'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(LucideIcons.pencil, size: 18, color: AppTheme.textSecondary),
                          const SizedBox(width: 8),
                          const Text('Editar'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(LucideIcons.trash2, size: 18, color: AppTheme.error),
                          const SizedBox(width: 8),
                          Text('Excluir', style: TextStyle(color: AppTheme.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _InfoBadge(
                  icon: LucideIcons.calendar,
                  label: DateFormat('dd/MM/yyyy').format(competition.date),
                ),
                const SizedBox(width: 8),
                _InfoBadge(
                  icon: LucideIcons.users,
                  label: '${competition.enrolledCount} inscritos',
                ),
                const Spacer(),
                if (isUpcoming && daysUntil <= 30)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: daysUntil <= 7 ? AppTheme.error : AppTheme.warning,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      daysUntil == 0
                          ? 'Hoje!'
                          : daysUntil == 1
                              ? 'Amanha'
                              : 'Em $daysUntil dias',
                      style: AppTheme.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Info Badge Widget
class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Detail Row Widget
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        Text(
          value,
          style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Modern Text Field Widget
class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
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
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textDisabled,
              ),
              prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
