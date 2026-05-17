import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';
import '../../widgets/competitions/competition_gallery.dart';
import '../../widgets/competitions/photo_upload_sheet.dart';
import '../../widgets/competitions/team_gallery_view.dart';
import '../portal/competition_detail_screen.dart';

/// Admin Competitions Screen - Fintech style matching webapp
class AdminCompetitionsScreen extends ConsumerStatefulWidget {
  const AdminCompetitionsScreen({super.key});

  @override
  ConsumerState<AdminCompetitionsScreen> createState() =>
      _AdminCompetitionsScreenState();
}

class _AdminCompetitionsScreenState
    extends ConsumerState<AdminCompetitionsScreen> {
  List<Competition> _upcomingCompetitions = [];
  List<Competition> _pastCompetitions = [];
  bool _isLoading = true;
  int _selectedTabIndex = 0;
  String? _academyId;

  final _tabs = ['Proximos', 'Passados'];

  @override
  void initState() {
    super.initState();
    // Load will be triggered by didChangeDependencies when user is ready
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCompetitionsIfReady();
  }

  void _loadCompetitionsIfReady() {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId != null &&
        _academyId != currentUser!.academyId) {
      _academyId = currentUser.academyId;
      _loadCompetitions();
    }
  }

  Future<void> _loadCompetitions() async {
    final academyId = _academyId;
    if (academyId == null) return;

    setState(() => _isLoading = true);

    try {
      // Tatami direto (fallback Firestore removido na Fase 1).
      // Filtragem upcoming/past é client-side (legacy `getUpcoming` faz a
      // mesma divisão por `date`).
      ref.invalidate(tatami.tatamiCompetitionsLegacyProvider(academyId));
      final all = await ref
          .read(tatami.tatamiCompetitionsLegacyProvider(academyId).future);
      final now = DateTime.now();
      final upcoming =
          all.where((c) => !c.date.isBefore(now)).toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      final past =
          all.where((c) => c.date.isBefore(now)).toList()
            ..sort((a, b) => b.date.compareTo(a.date));

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
    // Watch user provider to trigger loading when user data is available
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    if (currentUser?.academyId != null &&
        _academyId != currentUser!.academyId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _academyId = currentUser.academyId;
          _loadCompetitions();
        }
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadCompetitions,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(child: _buildHeader()),

            // Trophy Showcase
            SliverToBoxAdapter(child: _buildTrophyShowcase()),

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
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final competition = _currentList[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CompetitionCard(
                            competition: competition,
                            onTap: () => _showCompetitionDetails(competition),
                            onEdit: () =>
                                _showEditCompetitionSheet(competition),
                            onDelete: () =>
                                _showDeleteConfirmation(competition),
                            onManageEnrollments: () =>
                                _showEnrollmentsSheet(competition),
                          ),
                        );
                      }, childCount: _currentList.length),
                    ),
                  ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      // Competições não tem perm dedicada — criar/editar requer ser pelo
      // menos instrutor. Sidebar já filtra por isInstructor; redundante mas
      // defensivo para deep-link.
      floatingActionButton: (currentUser?.isInstructor ?? false)
          ? FloatingActionButton.extended(
              onPressed: _showCreateCompetitionSheet,
              backgroundColor: AppTheme.textPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(LucideIcons.plus, size: 20),
              label: const Text('Novo Campeonato'),
            )
          : null,
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

  Widget _buildTrophyShowcase() {
    final allCompetitions = [..._upcomingCompetitions, ..._pastCompetitions];
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
                      onTap: () => _showCompetitionDetails(comp),
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

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.all(20),
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedTabIndex == index;
          final count = index == 0
              ? _upcomingCompetitions.length
              : _pastCompetitions.length;
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
            child: Icon(LucideIcons.trophy, size: 40, color: AppTheme.warning),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedTabIndex == 0
                ? 'Nenhum campeonato agendado'
                : 'Nenhum campeonato passado',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione novos campeonatos para comecar',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
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
    bool isSaving = false;

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
                        child: Icon(
                          LucideIcons.trophy,
                          color: AppTheme.warning,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Novo Campeonato',
                        style: AppTheme.titleLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
                        initialDate: DateTime.now(),
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
                          Icon(
                            LucideIcons.calendar,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
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
                  if (selectedDate != null &&
                      selectedDate!.isBefore(DateTime.now()))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.warning.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.checkCircle,
                              color: AppTheme.warning,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sera criado como concluido. Alunos poderao adicionar seus resultados e fotos.',
                                style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.warning,
                                ),
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
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (nameController.text.isEmpty ||
                                  selectedDate == null) {
                                sheetContext.showWarning(
                                  'Preencha nome e data',
                                );
                                return;
                              }

                              setSheetState(() => isSaving = true);

                              try {
                                if (_academyId == null) {
                                  setSheetState(() => isSaving = false);
                                  sheetContext.showError(
                                    'Academia nao encontrada',
                                  );
                                  return;
                                }
                                final isPast = selectedDate!.isBefore(
                                  DateTime.now(),
                                );
                                final service = CompetitionService(_academyId!);
                                await service.create(
                                  name: nameController.text,
                                  date: selectedDate!,
                                  location: locationController.text.isEmpty
                                      ? null
                                      : locationController.text,
                                  description:
                                      descriptionController.text.isEmpty
                                      ? null
                                      : descriptionController.text,
                                  status: isPast
                                      ? CompetitionStatus.completed
                                      : CompetitionStatus.upcoming,
                                );

                                if (mounted) {
                                  Navigator.pop(sheetContext);
                                  this.context.showSuccess(
                                    isPast
                                        ? 'Campeonato concluido criado!'
                                        : 'Campeonato criado!',
                                  );
                                  _loadCompetitions();
                                }
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                if (mounted) {
                                  this.context.showError('Erro: $e');
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
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  selectedDate != null &&
                                          selectedDate!.isBefore(DateTime.now())
                                      ? LucideIcons.checkCircle
                                      : LucideIcons.plus,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  selectedDate != null &&
                                          selectedDate!.isBefore(DateTime.now())
                                      ? 'Criar como Concluido'
                                      : 'Criar Campeonato',
                                ),
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
    bool isSaving = false;
    final nameController = TextEditingController(text: competition.name);
    final locationController = TextEditingController(
      text: competition.location ?? '',
    );
    final descriptionController = TextEditingController(
      text: competition.description ?? '',
    );
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
                        child: Icon(
                          LucideIcons.pencil,
                          color: AppTheme.warning,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Editar Campeonato',
                        style: AppTheme.titleLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
                          Icon(
                            LucideIcons.calendar,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
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
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (nameController.text.isEmpty) {
                                sheetContext.showWarning('Nome e obrigatorio');
                                return;
                              }

                              setSheetState(() => isSaving = true);

                              try {
                                if (_academyId == null) {
                                  setSheetState(() => isSaving = false);
                                  sheetContext.showError(
                                    'Academia nao encontrada',
                                  );
                                  return;
                                }
                                final service = CompetitionService(_academyId!);
                                await service.update(competition.id, {
                                  'name': nameController.text,
                                  'date': selectedDate,
                                  'location': locationController.text.isEmpty
                                      ? null
                                      : locationController.text,
                                  'description':
                                      descriptionController.text.isEmpty
                                      ? null
                                      : descriptionController.text,
                                });

                                if (mounted) {
                                  Navigator.pop(sheetContext);
                                  this.context.showSuccess(
                                    'Campeonato atualizado!',
                                  );
                                  _loadCompetitions();
                                }
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                if (mounted) {
                                  this.context.showError('Erro: $e');
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
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
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
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => CompetitionDetailScreen(
              competitionId: competition.id,
              isAdmin: true,
            ),
          ),
        )
        .then((_) => _loadCompetitions());
  }

  void _showCompetitionGallery(Competition competition) async {
    if (_academyId == null) return;

    final enrollmentService = CompetitionEnrollmentService(_academyId!);
    final enrollments = await enrollmentService.getByCompetition(
      competition.id,
    );

    if (!mounted) return;

    final enrolledStudents = enrollments
        .map((e) => EnrolledStudent(id: e.studentId, name: e.studentName))
        .toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(competition.name),
            backgroundColor: AppTheme.surface,
          ),
          backgroundColor: AppTheme.background,
          body: CompetitionGallery(
            academyId: _academyId!,
            competitionId: competition.id,
            competitionName: competition.name,
            isAdmin: true,
            enrolledStudents: enrolledStudents,
          ),
        ),
      ),
    );
  }

  void _showEnrollmentsSheet(Competition competition) async {
    if (_academyId == null) return;
    final enrollmentService = CompetitionEnrollmentService(_academyId!);
    final enrollments = await enrollmentService.getByCompetition(
      competition.id,
    );

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
                          child: Icon(
                            LucideIcons.users,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Inscricoes',
                                style: AppTheme.titleLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
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
                          icon: Icon(
                            LucideIcons.userPlus,
                            color: AppTheme.primary,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primary.withValues(
                              alpha: 0.1,
                            ),
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
                                      enrollment.studentName
                                          .substring(0, 1)
                                          .toUpperCase(),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                    color: AppTheme.primary.withValues(
                                      alpha: 0.1,
                                    ),
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
    if (_academyId == null) return;
    final studentService = StudentService(_academyId!);
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
                        child: Icon(
                          LucideIcons.userPlus,
                          color: AppTheme.success,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Nova Inscricao',
                        style: AppTheme.titleLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
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
                          sheetContext.showWarning('Selecione um aluno');
                          return;
                        }

                        try {
                          if (_academyId == null) {
                            sheetContext.showError('Academia nao encontrada');
                            return;
                          }
                          final service = CompetitionEnrollmentService(
                            _academyId!,
                          );
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
                            Navigator.pop(sheetContext);
                            this.context.showSuccess('Inscricao realizada!');
                            _loadCompetitions();
                          }
                        } catch (e) {
                          if (mounted) {
                            this.context.showError('Erro: $e');
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
              child: Icon(
                LucideIcons.alertTriangle,
                color: AppTheme.error,
                size: 28,
              ),
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
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
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
                      try {
                        if (_academyId == null) {
                          this.context.showError('Academia nao encontrada');
                          return;
                        }
                        final service = CompetitionService(_academyId!);
                        await service.delete(competition.id);

                        if (mounted) {
                          Navigator.pop(context);
                          this.context.showSuccess('Campeonato excluido!');
                          _loadCompetitions();
                        }
                      } catch (e) {
                        if (mounted) {
                          this.context.showError('Erro: $e');
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

/// Stats Carousel Card Widget (for horizontal scrolling stats)

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
                  child: Icon(
                    LucideIcons.trophy,
                    color: AppTheme.warning,
                    size: 24,
                  ),
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
                  icon: Icon(
                    LucideIcons.moreVertical,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
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
                          Icon(
                            LucideIcons.users,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Inscricoes'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.pencil,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Editar'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.trash2,
                            size: 18,
                            color: AppTheme.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Excluir',
                            style: TextStyle(color: AppTheme.error),
                          ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
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
