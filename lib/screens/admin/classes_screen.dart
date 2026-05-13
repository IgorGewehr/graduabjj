import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import '../../widgets/common/grade_display.dart';
import '../../widgets/common/sport_chip.dart';

// Helper to convert dayOfWeek int to label
String _getDayLabel(int dayOfWeek) {
  const days = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab'];
  return days[dayOfWeek % 7];
}

String _formatTimeOfDay(TimeOfDay t) {
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

TimeOfDay _parseTimeString(String time) {
  final parts = time.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

/// Mutable schedule entry for form state
class _ScheduleEntry {
  int dayOfWeek;
  String startTime;
  String endTime;

  _ScheduleEntry({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toMap() => {
        'dayOfWeek': dayOfWeek,
        'startTime': startTime,
        'endTime': endTime,
      };
}

/// Admin Classes Screen - Fintech style matching webapp
class AdminClassesScreen extends ConsumerStatefulWidget {
  const AdminClassesScreen({super.key});

  @override
  ConsumerState<AdminClassesScreen> createState() => _AdminClassesScreenState();
}

class _AdminClassesScreenState extends ConsumerState<AdminClassesScreen> {
  List<BJJClass> _classes = [];
  bool _isLoading = true;
  String _searchQuery = '';
  StudentCategory? _selectedCategory;

  // Stats carousel
  final PageController _statsPageController = PageController(viewportFraction: 0.85);
  int _currentStatsPage = 0;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _statsPageController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final service = ClassService(currentUser!.academyId!);
      final classes = await service.list();

      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<BJJClass> get _filteredClasses {
    var filtered = _classes;

    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    if (_selectedCategory != null) {
      filtered = filtered.where((c) => c.category == _selectedCategory).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadClasses,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(child: _buildHeader()),

            // Stats Cards
            SliverToBoxAdapter(child: _buildStatsCards()),

            // Search & Filter
            SliverToBoxAdapter(child: _buildSearchAndFilter()),

            // Category Chips
            SliverToBoxAdapter(child: _buildCategoryChips()),

            // Class List
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _filteredClasses.isEmpty
                    ? SliverFillRemaining(child: _buildEmptyState())
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final cls = _filteredClasses[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ClassCard(
                                  bjjClass: cls,
                                  onTap: () => _showClassDetails(cls),
                                  onEdit: () => _showEditClassSheet(cls),
                                  onDelete: () => _showDeleteConfirmation(cls),
                                ),
                              );
                            },
                            childCount: _filteredClasses.length,
                          ),
                        ),
                      ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateClassSheet,
        backgroundColor: AppTheme.textPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(LucideIcons.plus, size: 20),
        label: const Text('Nova Turma'),
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
              '${_classes.length} turmas',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadClasses,
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
    final totalClasses = _classes.length;
    final totalStudents = _classes.fold<int>(0, (sum, c) => sum + c.studentIds.length);
    final withSchedule = _classes.where((c) => c.schedule.isNotEmpty).length;

    return Column(
      children: [
        SizedBox(
          height: 100,
          child: PageView.builder(
            controller: _statsPageController,
            onPageChanged: (page) {
              setState(() => _currentStatsPage = page);
            },
            itemCount: 3,
            itemBuilder: (context, index) {
              final cards = [
                // Turmas
                _StatsCarouselCard(
                  icon: LucideIcons.users,
                  iconBgColor: AppTheme.primary.withValues(alpha: 0.1),
                  iconColor: AppTheme.primary,
                  label: 'Total de Turmas',
                  value: totalClasses.toString(),
                  subtitle: 'turmas cadastradas',
                ),
                // Alunos
                _StatsCarouselCard(
                  icon: LucideIcons.userCheck,
                  iconBgColor: AppTheme.successLight,
                  iconColor: AppTheme.success,
                  label: 'Alunos em Turmas',
                  value: totalStudents.toString(),
                  subtitle: 'alunos matriculados',
                ),
                // Com Horario
                _StatsCarouselCard(
                  icon: LucideIcons.clock,
                  iconBgColor: AppTheme.warning.withValues(alpha: 0.1),
                  iconColor: AppTheme.warning,
                  label: 'Com Horario',
                  value: withSchedule.toString(),
                  subtitle: 'turmas com horario definido',
                ),
              ];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: cards[index],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentStatsPage == index ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentStatsPage == index
                      ? AppTheme.textPrimary
                      : AppTheme.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(LucideIcons.search, color: AppTheme.textSecondary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Buscar turma...',
                  hintStyle: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textDisabled,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: AppTheme.divider,
            ),
            IconButton(
              icon: Icon(
                LucideIcons.slidersHorizontal,
                color: _selectedCategory != null ? AppTheme.primary : AppTheme.textSecondary,
                size: 20,
              ),
              onPressed: _showFilterSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _FilterChip(
            label: 'Todas',
            isSelected: _selectedCategory == null,
            onTap: () => setState(() => _selectedCategory = null),
          ),
          const SizedBox(width: 8),
          ...StudentCategory.values.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: cat.label,
                  isSelected: _selectedCategory == cat,
                  onTap: () => setState(() => _selectedCategory = cat),
                ),
              )),
        ],
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
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              LucideIcons.users,
              size: 40,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma turma encontrada',
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie uma nova turma para comecar',
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
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
            Text(
              'Filtrar por Categoria',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ...StudentCategory.values.map((cat) => ListTile(
                  leading: Icon(
                    _selectedCategory == cat ? LucideIcons.checkCircle2 : LucideIcons.circle,
                    color: _selectedCategory == cat ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                  title: Text(cat.label),
                  onTap: () {
                    setState(() => _selectedCategory = cat);
                    Navigator.pop(context);
                  },
                )),
            ListTile(
              leading: Icon(
                _selectedCategory == null ? LucideIcons.checkCircle2 : LucideIcons.circle,
                color: _selectedCategory == null ? AppTheme.primary : AppTheme.textSecondary,
              ),
              title: const Text('Todas'),
              onTap: () {
                setState(() => _selectedCategory = null);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleEntryRow({
    required _ScheduleEntry schedule,
    required bool canRemove,
    required VoidCallback onChanged,
    required VoidCallback onRemove,
    required BuildContext dialogContext,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButton<int>(
                value: schedule.dayOfWeek,
                isExpanded: true,
                underline: const SizedBox(),
                items: List.generate(7, (i) {
                  return DropdownMenuItem(
                    value: i,
                    child: Text(_getDayLabel(i), style: AppTheme.bodySmall),
                  );
                }),
                onChanged: (value) {
                  schedule.dayOfWeek = value!;
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () async {
                  final time = await showTimePicker(
                    context: dialogContext,
                    initialTime: _parseTimeString(schedule.startTime),
                  );
                  if (time != null) {
                    schedule.startTime = _formatTimeOfDay(time);
                    onChanged();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  child: Text(
                    schedule.startTime,
                    style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            Text(' - ', style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary)),
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () async {
                  final time = await showTimePicker(
                    context: dialogContext,
                    initialTime: _parseTimeString(schedule.endTime),
                  );
                  if (time != null) {
                    schedule.endTime = _formatTimeOfDay(time);
                    onChanged();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  child: Text(
                    schedule.endTime,
                    style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            if (canRemove)
              IconButton(
                icon: Icon(LucideIcons.x, size: 18, color: AppTheme.error),
                onPressed: onRemove,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
          ],
        ),
      ),
    );
  }

  void _showCreateClassSheet() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final instructorController = TextEditingController();
    final maxStudentsController = TextEditingController();
    final weightController = TextEditingController(text: '1');
    StudentCategory? selectedCategory;
    SportId selectedSport = SportId.bjj;
    bool isSaving = false;
    // useClassWeights is observed from the academy settings provider — when
    // the toggle is off in Settings, we never even render the weight field.
    final useClassWeights = ref.read(academySettingsProvider).valueOrNull?.useClassWeights ?? false;
    List<_ScheduleEntry> scheduleEntries = [
      _ScheduleEntry(dayOfWeek: 1, startTime: '19:00', endTime: '20:30'),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
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
            child: Column(
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
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(LucideIcons.users, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Nova Turma',
                      style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ModernTextField(
                          controller: nameController,
                          label: 'Nome da Turma',
                          hint: 'Ex: Turma Iniciante',
                          icon: LucideIcons.users,
                        ),
                        const SizedBox(height: 16),
                        _ModernTextField(
                          controller: descriptionController,
                          label: 'Descricao (opcional)',
                          hint: 'Breve descricao da turma',
                          icon: LucideIcons.fileText,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Categoria',
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
                          child: DropdownButtonFormField<StudentCategory>(
                            value: selectedCategory,
                            items: StudentCategory.values.map((cat) {
                              return DropdownMenuItem(
                                value: cat,
                                child: Text(cat.label),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setSheetState(() => selectedCategory = value);
                            },
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            dropdownColor: AppTheme.surface,
                            hint: const Text('Selecione a categoria'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Esporte',
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
                          child: DropdownButtonFormField<SportId>(
                            value: selectedSport,
                            items: sportOptions.map((sportId) {
                              final sport = getSport(sportId);
                              return DropdownMenuItem(
                                value: sportId,
                                child: Row(
                                  children: [
                                    Icon(sport.icon, size: 18, color: sportChipColors[sportId]),
                                    const SizedBox(width: 8),
                                    Text(sport.label),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) setSheetState(() => selectedSport = value);
                            },
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            dropdownColor: AppTheme.surface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ModernTextField(
                          controller: instructorController,
                          label: 'Instrutor (opcional)',
                          hint: 'Nome do instrutor',
                          icon: LucideIcons.userCircle,
                        ),
                        const SizedBox(height: 16),
                        _ModernTextField(
                          controller: maxStudentsController,
                          label: 'Maximo de Alunos (opcional)',
                          hint: 'Ex: 20',
                          icon: LucideIcons.users,
                          keyboardType: TextInputType.number,
                        ),
                        if (useClassWeights) ...[
                          const SizedBox(height: 16),
                          _ModernTextField(
                            controller: weightController,
                            label: 'Peso da turma',
                            hint: '1 = padrao. Ex: aula particular = 2',
                            icon: LucideIcons.scale,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'Horarios',
                          style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        ...scheduleEntries.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final schedule = entry.value;
                          return _buildScheduleEntryRow(
                            schedule: schedule,
                            canRemove: scheduleEntries.length > 1,
                            onChanged: () => setSheetState(() {}),
                            onRemove: () {
                              setSheetState(() => scheduleEntries.removeAt(idx));
                            },
                            dialogContext: context,
                          );
                        }),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            setSheetState(() {
                              scheduleEntries.add(
                                _ScheduleEntry(dayOfWeek: 1, startTime: '19:00', endTime: '20:30'),
                              );
                            });
                          },
                          icon: Icon(LucideIcons.plus, size: 18),
                          label: const Text('Adicionar Horario'),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSaving ? null : () async {
                      if (nameController.text.isEmpty) {
                        sheetContext.showWarning('Nome e obrigatorio');
                        return;
                      }

                      setSheetState(() => isSaving = true);

                      try {
                        final currentUser = ref.read(currentUserProvider).valueOrNull;
                        if (currentUser?.academyId == null) return;

                        final service = ClassService(currentUser!.academyId!);
                        await service.create(
                          name: nameController.text,
                          description: descriptionController.text.isEmpty
                              ? null
                              : descriptionController.text,
                          category: selectedCategory,
                          sport: selectedSport.value,
                          instructorName: instructorController.text.isEmpty
                              ? null
                              : instructorController.text,
                          maxStudents: maxStudentsController.text.isEmpty
                              ? null
                              : int.tryParse(maxStudentsController.text),
                          weight: useClassWeights
                              ? double.tryParse(weightController.text)
                              : null,
                          schedule: scheduleEntries
                              .map((e) => ClassSchedule(
                                    dayOfWeek: e.dayOfWeek,
                                    startTime: e.startTime,
                                    endTime: e.endTime,
                                  ))
                              .toList(),
                        );

                        if (mounted) {
                          Navigator.pop(sheetContext);
                          this.context.showSuccess('Turma criada com sucesso!');
                          _loadClasses();
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
                              Icon(LucideIcons.plus, size: 20),
                              const SizedBox(width: 8),
                              const Text('Criar Turma'),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditClassSheet(BJJClass cls) {
    final nameController = TextEditingController(text: cls.name);
    final descriptionController = TextEditingController(text: cls.description ?? '');
    final instructorController = TextEditingController(text: cls.instructorName ?? '');
    final maxStudentsController = TextEditingController(text: cls.maxStudents?.toString() ?? '');
    final weightController = TextEditingController(
      text: (cls.weight ?? 1).toString(),
    );
    final useClassWeights = ref.read(academySettingsProvider).valueOrNull?.useClassWeights ?? false;
    StudentCategory? selectedCategory = cls.category;
    SportId selectedSport = cls.getSport();
    bool isSaving = false;
    List<_ScheduleEntry> scheduleEntries = cls.schedule.isNotEmpty
        ? cls.schedule
            .map((s) => _ScheduleEntry(
                  dayOfWeek: s.dayOfWeek,
                  startTime: s.startTime,
                  endTime: s.endTime,
                ))
            .toList()
        : [_ScheduleEntry(dayOfWeek: 1, startTime: '19:00', endTime: '20:30')];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
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
            child: Column(
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
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(LucideIcons.pencil, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Editar Turma',
                      style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ModernTextField(
                          controller: nameController,
                          label: 'Nome da Turma',
                          hint: 'Ex: Turma Iniciante',
                          icon: LucideIcons.users,
                        ),
                        const SizedBox(height: 16),
                        _ModernTextField(
                          controller: descriptionController,
                          label: 'Descricao (opcional)',
                          hint: 'Breve descricao da turma',
                          icon: LucideIcons.fileText,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Categoria',
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
                          child: DropdownButtonFormField<StudentCategory>(
                            value: selectedCategory,
                            items: StudentCategory.values.map((cat) {
                              return DropdownMenuItem(
                                value: cat,
                                child: Text(cat.label),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setSheetState(() => selectedCategory = value);
                            },
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            dropdownColor: AppTheme.surface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Esporte',
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
                          child: DropdownButtonFormField<SportId>(
                            value: selectedSport,
                            items: sportOptions.map((sportId) {
                              final sport = getSport(sportId);
                              return DropdownMenuItem(
                                value: sportId,
                                child: Row(
                                  children: [
                                    Icon(sport.icon, size: 18, color: sportChipColors[sportId]),
                                    const SizedBox(width: 8),
                                    Text(sport.label),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) setSheetState(() => selectedSport = value);
                            },
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            dropdownColor: AppTheme.surface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ModernTextField(
                          controller: instructorController,
                          label: 'Instrutor (opcional)',
                          hint: 'Nome do instrutor',
                          icon: LucideIcons.userCircle,
                        ),
                        const SizedBox(height: 16),
                        _ModernTextField(
                          controller: maxStudentsController,
                          label: 'Maximo de Alunos (opcional)',
                          hint: 'Ex: 20',
                          icon: LucideIcons.users,
                          keyboardType: TextInputType.number,
                        ),
                        if (useClassWeights) ...[
                          const SizedBox(height: 16),
                          _ModernTextField(
                            controller: weightController,
                            label: 'Peso da turma',
                            hint: '1 = padrao. Ex: aula particular = 2',
                            icon: LucideIcons.scale,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'Horarios',
                          style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        ...scheduleEntries.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final schedule = entry.value;
                          return _buildScheduleEntryRow(
                            schedule: schedule,
                            canRemove: scheduleEntries.length > 1,
                            onChanged: () => setSheetState(() {}),
                            onRemove: () {
                              setSheetState(() => scheduleEntries.removeAt(idx));
                            },
                            dialogContext: context,
                          );
                        }),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            setSheetState(() {
                              scheduleEntries.add(
                                _ScheduleEntry(dayOfWeek: 1, startTime: '19:00', endTime: '20:30'),
                              );
                            });
                          },
                          icon: Icon(LucideIcons.plus, size: 18),
                          label: const Text('Adicionar Horario'),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSaving ? null : () async {
                      if (nameController.text.isEmpty) {
                        sheetContext.showWarning('Nome e obrigatorio');
                        return;
                      }

                      setSheetState(() => isSaving = true);

                      try {
                        final currentUser = ref.read(currentUserProvider).valueOrNull;
                        if (currentUser?.academyId == null) return;

                        final service = ClassService(currentUser!.academyId!);
                        await service.update(cls.id, {
                          'name': nameController.text,
                          if (descriptionController.text.isNotEmpty)
                            'description': descriptionController.text,
                          if (selectedCategory != null) 'category': selectedCategory!.value,
                          'sport': selectedSport.value,
                          'instructorName': instructorController.text.isEmpty
                              ? null
                              : instructorController.text,
                          'maxStudents': maxStudentsController.text.isEmpty
                              ? null
                              : int.tryParse(maxStudentsController.text),
                          // Only persist weight when the feature is on (the field
                          // is hidden otherwise). 1.0 means "default" so we strip
                          // it to keep the doc shape consistent with legacy ones.
                          if (useClassWeights)
                            'weight':
                                (double.tryParse(weightController.text) ?? 1.0) == 1.0
                                    ? null
                                    : double.tryParse(weightController.text),
                          'schedule': scheduleEntries.map((s) => s.toMap()).toList(),
                        });

                        if (mounted) {
                          Navigator.pop(sheetContext);
                          this.context.showSuccess('Turma atualizada!');
                          _loadClasses();
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
          );
        },
      ),
    );
  }

  void _showClassDetails(BJJClass cls) {
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
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.users, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cls.name,
                        style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (cls.category != null)
                        Text(
                          cls.category!.label,
                          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (cls.description != null) ...[
              const SizedBox(height: 16),
              Text(
                cls.description!,
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
                    icon: LucideIcons.users,
                    label: 'Alunos',
                    value: cls.maxStudents != null
                        ? '${cls.studentIds.length}/${cls.maxStudents}'
                        : '${cls.studentIds.length}',
                  ),
                  if (cls.maxStudents != null) ...[
                    const SizedBox(height: 12),
                    _DetailRow(
                      icon: LucideIcons.userPlus,
                      label: 'Maximo de Alunos',
                      value: '${cls.maxStudents}',
                    ),
                  ],
                  const SizedBox(height: 12),
                  _DetailRow(
                    icon: LucideIcons.userCircle,
                    label: 'Instrutor',
                    value: cls.instructorName ?? 'Nao definido',
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(
                    icon: LucideIcons.clock,
                    label: 'Horarios',
                    value: '${cls.schedule.length} configurados',
                  ),
                ],
              ),
            ),
            if (cls.schedule.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Horarios',
                style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...cls.schedule.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.calendar, size: 16, color: AppTheme.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            '${_getDayLabel(s.dayOfWeek)}: ${s.startTime} - ${s.endTime}',
                            style: AppTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showManageStudentsSheet(cls);
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
                    Icon(LucideIcons.userPlus, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Gerenciar Alunos',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
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
                      _showEditClassSheet(cls);
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
                      _showDeleteConfirmation(cls);
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

  void _showManageStudentsSheet(BJJClass cls) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _ManageStudentsSheet(
        bjjClass: cls,
        onChanged: _loadClasses,
      ),
    );
  }

  void _showDeleteConfirmation(BJJClass cls) {
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
              'Excluir Turma',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Deseja excluir a turma "${cls.name}"? Esta acao nao pode ser desfeita.',
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
                      try {
                        final currentUser = ref.read(currentUserProvider).valueOrNull;
                        if (currentUser?.academyId == null) return;

                        final service = ClassService(currentUser!.academyId!);
                        await service.delete(cls.id);

                        if (mounted) {
                          Navigator.pop(context);
                          this.context.showSuccess('Turma excluida!');
                          _loadClasses();
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

/// Stats Carousel Card
class _StatsCarouselCard extends StatelessWidget {
  final IconData icon;
  final Color? iconBgColor;
  final Color? iconColor;
  final String label;
  final String value;
  final String subtitle;

  const _StatsCarouselCard({
    required this.icon,
    this.iconBgColor,
    this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              color: iconBgColor ?? AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppTheme.textPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Filter Chip Widget
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.bodySmall.copyWith(
            color: isSelected ? Colors.white : AppTheme.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Class Card Widget
class _ClassCard extends StatelessWidget {
  final BJJClass bjjClass;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClassCard({
    required this.bjjClass,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
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
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.users, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bjjClass.name,
                        style: AppTheme.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          if (bjjClass.category != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4, right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                bjjClass.category!.label,
                                style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: SportChip(sportId: bjjClass.getSport()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(LucideIcons.moreVertical, color: AppTheme.textSecondary, size: 20),
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoBadge(
                  icon: LucideIcons.userCheck,
                  label: bjjClass.maxStudents != null
                      ? '${bjjClass.studentIds.length}/${bjjClass.maxStudents} alunos'
                      : '${bjjClass.studentIds.length} alunos',
                ),
                _InfoBadge(
                  icon: LucideIcons.clock,
                  label: '${bjjClass.schedule.length} horarios',
                ),
                if (bjjClass.instructorName != null && bjjClass.instructorName!.isNotEmpty)
                  _InfoBadge(
                    icon: LucideIcons.userCircle,
                    label: bjjClass.instructorName!,
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
  final TextInputType? keyboardType;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
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
            keyboardType: keyboardType,
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

/// Manage students enrolled in a class.
///
/// Loads every academy student, lets the user toggle membership, and persists
/// each toggle immediately via ClassService (which also enrolls the student in
/// the class's sport on add).
class _ManageStudentsSheet extends ConsumerStatefulWidget {
  final BJJClass bjjClass;
  final VoidCallback onChanged;

  const _ManageStudentsSheet({
    required this.bjjClass,
    required this.onChanged,
  });

  @override
  ConsumerState<_ManageStudentsSheet> createState() =>
      _ManageStudentsSheetState();
}

class _ManageStudentsSheetState extends ConsumerState<_ManageStudentsSheet> {
  bool _isLoading = true;
  bool _hasChanges = false;
  List<Student> _students = [];
  Set<String> _enrolledIds = {};
  final Set<String> _pendingIds = {};
  String _searchQuery = '';
  bool _showOnlyEnrolled = false;

  @override
  void initState() {
    super.initState();
    _enrolledIds = widget.bjjClass.studentIds.toSet();
    _load();
  }

  Future<void> _load() async {
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final service = StudentService(currentUser!.academyId!);
      final students = await service.getAll();
      // Order: enrolled first, then students who already practice this sport,
      // then everyone else — alphabetical inside each group.
      final classSport = widget.bjjClass.getSport();
      students.sort((a, b) {
        final aEnrolled = _enrolledIds.contains(a.id) ? 0 : 1;
        final bEnrolled = _enrolledIds.contains(b.id) ? 0 : 1;
        if (aEnrolled != bEnrolled) return aEnrolled.compareTo(bEnrolled);
        final aMatchesSport = a.getSports().contains(classSport) ? 0 : 1;
        final bMatchesSport = b.getSports().contains(classSport) ? 0 : 1;
        if (aMatchesSport != bMatchesSport) {
          return aMatchesSport.compareTo(bMatchesSport);
        }
        return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });
      setState(() {
        _students = students;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  List<Student> get _visibleStudents {
    Iterable<Student> base = _students;
    if (_showOnlyEnrolled) {
      base = base.where((s) => _enrolledIds.contains(s.id));
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      base = base.where((s) =>
          s.fullName.toLowerCase().contains(q) ||
          (s.nickname?.toLowerCase().contains(q) ?? false));
    }
    return base.toList();
  }

  Future<void> _toggle(Student student) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;
    if (_pendingIds.contains(student.id)) return;

    final wasEnrolled = _enrolledIds.contains(student.id);
    setState(() {
      _pendingIds.add(student.id);
      if (wasEnrolled) {
        _enrolledIds.remove(student.id);
      } else {
        _enrolledIds.add(student.id);
      }
    });

    try {
      final service = ClassService(currentUser!.academyId!);
      if (wasEnrolled) {
        await service.removeStudent(widget.bjjClass.id, student.id);
      } else {
        await service.addStudent(widget.bjjClass.id, student.id);
      }
      _hasChanges = true;
      if (mounted) setState(() => _pendingIds.remove(student.id));
    } catch (e) {
      // Roll back optimistic state on failure.
      if (mounted) {
        setState(() {
          _pendingIds.remove(student.id);
          if (wasEnrolled) {
            _enrolledIds.add(student.id);
          } else {
            _enrolledIds.remove(student.id);
          }
        });
        context.showError('Erro: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cls = widget.bjjClass;
    final classSport = cls.getSport();
    final sportDef = sports[classSport]!;
    final accent = sportChipColors[classSport] ?? AppTheme.primary;
    final maxedOut = cls.maxStudents != null &&
        _enrolledIds.length >= cls.maxStudents!;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
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
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(sportDef.icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cls.name,
                      style: AppTheme.titleMedium
                          .copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        SportChip(sportId: classSport),
                        const SizedBox(width: 8),
                        Text(
                          '${_enrolledIds.length}${cls.maxStudents != null ? '/${cls.maxStudents}' : ''} alunos',
                          style: AppTheme.labelSmall
                              .copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  if (_hasChanges) widget.onChanged();
                  Navigator.pop(context);
                },
                icon: const Icon(LucideIcons.x, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Buscar aluno...',
                hintStyle: AppTheme.bodyMedium
                    .copyWith(color: AppTheme.textDisabled),
                prefixIcon: Icon(LucideIcons.search,
                    color: AppTheme.textSecondary, size: 20),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ToggleChip(
                label: 'Todos (${_students.length})',
                selected: !_showOnlyEnrolled,
                onTap: () => setState(() => _showOnlyEnrolled = false),
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                label: 'Matriculados (${_enrolledIds.length})',
                selected: _showOnlyEnrolled,
                onTap: () => setState(() => _showOnlyEnrolled = true),
              ),
              const Spacer(),
              if (maxedOut)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Lotada',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _visibleStudents.isEmpty
                    ? Center(
                        child: Text(
                          _showOnlyEnrolled
                              ? 'Nenhum aluno matriculado'
                              : 'Nenhum aluno encontrado',
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _visibleStudents.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final s = _visibleStudents[i];
                          final isEnrolled = _enrolledIds.contains(s.id);
                          final isPending = _pendingIds.contains(s.id);
                          final practicesSport =
                              s.getSports().contains(classSport);
                          final blockedByCap = !isEnrolled && maxedOut;
                          return _StudentRow(
                            student: s,
                            classSport: classSport,
                            enrolled: isEnrolled,
                            pending: isPending,
                            practicesSport: practicesSport,
                            disabled: blockedByCap,
                            onTap: blockedByCap ? null : () => _toggle(s),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.textPrimary : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.textPrimary : AppTheme.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.labelSmall.copyWith(
            color: selected ? Colors.white : AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final Student student;
  final SportId classSport;
  final bool enrolled;
  final bool pending;
  final bool practicesSport;
  final bool disabled;
  final VoidCallback? onTap;

  const _StudentRow({
    required this.student,
    required this.classSport,
    required this.enrolled,
    required this.pending,
    required this.practicesSport,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primarySport = student.getPrimarySport();
    final grade = student.getGrade(primarySport);
    final accent = sportChipColors[classSport] ?? AppTheme.primary;

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: enrolled
                ? accent.withValues(alpha: 0.06)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enrolled ? accent : AppTheme.divider,
              width: enrolled ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: student.photoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(student.photoUrl!,
                            fit: BoxFit.cover),
                      )
                    : Center(
                        child: Text(
                          student.displayName[0].toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      student.fullName,
                      style: AppTheme.bodyMedium
                          .copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (grade != null)
                          GradeDisplay(
                            sportId: primarySport,
                            grade: grade.currentGrade,
                            stripes: grade.currentStripes,
                            size: GradeDisplaySize.small,
                          ),
                        SportChip(sportId: primarySport),
                        if (practicesSport && primarySport != classSport)
                          SportChip(sportId: classSport),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                height: 28,
                child: pending
                    ? const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        enrolled
                            ? LucideIcons.checkCircle2
                            : LucideIcons.circle,
                        color: enrolled ? accent : AppTheme.textDisabled,
                        size: 26,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

