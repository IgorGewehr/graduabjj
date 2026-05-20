import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/plan_dto.dart';
import '../../../api/plan_repo.dart';
import '../../../api/repositories.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../providers/selected_academy_provider.dart';
import '../../../services/services.dart';
import 'financial_widgets.dart';

// ============================================
// Plans Tab
// ============================================

class PlansTab extends ConsumerWidget {
  final List<Plan> plans;
  final List<Student> students;
  final String Function(double) formatCurrency;
  final double expectedRevenue;
  final VoidCallback onRefresh;

  const PlansTab({
    super.key,
    required this.plans,
    required this.students,
    required this.formatCurrency,
    required this.expectedRevenue,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plans header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Planos de Mensalidade',
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Receita esperada: ${formatCurrency(expectedRevenue)}/mes',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: () => _showCreatePlanDialog(context, ref),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.textPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Novo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Plan Cards
          ...plans.map((plan) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PlanCard(
                  plan: plan,
                  formatCurrency: formatCurrency,
                  onEdit: () => _showEditPlanDialog(context, ref, plan),
                  onDelete: () => _showDeletePlanDialog(context, ref, plan),
                  onManageStudents: () =>
                      _showManageStudentsDialog(context, ref, plan),
                ),
              )),

          if (plans.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.package,
                      size: 48,
                      color: AppTheme.textDisabled,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum plano cadastrado',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ============================================
  // Create Plan Dialog
  // ============================================

  void _showCreatePlanDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    final dueDayController = TextEditingController(text: '10');
    int? classesPerWeek;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandleBar(),
                const SizedBox(height: 20),
                Text(
                  'Novo Plano',
                  style: AppTheme.titleLarge
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),

                buildFinancialFormField(
                    'Nome do Plano', nameController, 'Ex: Mensal'),
                buildFinancialFormField(
                    'Valor Mensal (R\$)', valueController, 'Ex: 150',
                    keyboardType: TextInputType.number),
                buildFinancialFormField(
                    'Dia de Vencimento', dueDayController, '1-31',
                    keyboardType: TextInputType.number),

                // Classes per week
                Text(
                  'Aulas por Semana',
                  style: AppTheme.labelMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FinancialClassesChip(
                      label: 'Ilimitado',
                      isSelected: classesPerWeek == null,
                      onTap: () =>
                          setDialogState(() => classesPerWeek = null),
                    ),
                    ...List.generate(5, (i) {
                      final count = i + 1;
                      return FinancialClassesChip(
                        label: '$count',
                        isSelected: classesPerWeek == count,
                        onTap: () =>
                            setDialogState(() => classesPerWeek = count),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 24),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: AppTheme.divider),
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
                          if (nameController.text.isEmpty ||
                              valueController.text.isEmpty) {
                            return;
                          }
                          try {
                            final academyId = ref.read(safeAcademyIdProvider) ?? '';
                            final planRepo = ref.read(planRepoProvider);
                            await planRepo.create(
                              academyId,
                              CreatePlanRequest(
                                name: nameController.text,
                                monthlyValue:
                                    (double.tryParse(valueController.text) ?? 0)
                                        .toStringAsFixed(2),
                                defaultDueDay:
                                    int.tryParse(dueDayController.text) ?? 10,
                                classesPerWeek: classesPerWeek,
                              ),
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              context.showSuccess('Plano criado!');
                              onRefresh();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              context.showError('Erro: $e');
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Criar Plano'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // Edit Plan Dialog
  // ============================================

  void _showEditPlanDialog(BuildContext context, WidgetRef ref, Plan plan) {
    final nameController = TextEditingController(text: plan.name);
    final valueController =
        TextEditingController(text: plan.monthlyValue.toString());
    final dueDayController =
        TextEditingController(text: plan.defaultDueDay.toString());
    int? classesPerWeek = plan.classesPerWeek;
    bool isActive = plan.isActive;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandleBar(),
                const SizedBox(height: 20),
                Text(
                  'Editar Plano',
                  style: AppTheme.titleLarge
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),

                buildFinancialFormField(
                    'Nome do Plano', nameController, ''),
                buildFinancialFormField(
                    'Valor Mensal (R\$)', valueController, '',
                    keyboardType: TextInputType.number),
                buildFinancialFormField(
                    'Dia de Vencimento', dueDayController, '',
                    keyboardType: TextInputType.number),

                // Status toggle
                Row(
                  children: [
                    Text(
                      'Status:',
                      style: AppTheme.labelMedium
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: isActive,
                      onChanged: (v) =>
                          setDialogState(() => isActive = v),
                      activeTrackColor: AppTheme.success,
                    ),
                    Text(
                      isActive ? 'Ativo' : 'Inativo',
                      style: AppTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: AppTheme.divider),
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
                            final academyId = ref.read(safeAcademyIdProvider) ?? '';
                            final planRepo = ref.read(planRepoProvider);
                            await planRepo.update(
                              academyId,
                              plan.id,
                              UpdatePlanRequest(
                                name: nameController.text,
                                monthlyValue:
                                    (double.tryParse(valueController.text) ?? 0)
                                        .toStringAsFixed(2),
                                defaultDueDay:
                                    int.tryParse(dueDayController.text) ?? 10,
                                classesPerWeek: classesPerWeek,
                                isActive: isActive,
                              ),
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              context.showSuccess('Plano atualizado!');
                              onRefresh();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              context.showError('Erro: $e');
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Salvar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // Delete Plan Dialog
  // ============================================

  void _showDeletePlanDialog(BuildContext context, WidgetRef ref, Plan plan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Plano'),
        content: Text('Deseja excluir o plano "${plan.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final academyId = ref.read(safeAcademyIdProvider) ?? '';
                final planRepo = ref.read(planRepoProvider);
                await planRepo.delete(academyId, plan.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  context.showSuccess('Plano excluido!');
                  onRefresh();
                }
              } catch (e) {
                if (context.mounted) {
                  context.showError('Erro: $e');
                }
              }
            },
            child: const Text('Excluir',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  // ============================================
  // Manage Students Dialog
  // ============================================

  void _showManageStudentsDialog(BuildContext context, WidgetRef ref, Plan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ManageStudentsSheet(
        plan: plan,
        students: students,
        onClose: () {
          Navigator.pop(context);
          onRefresh();
        },
        planRepo: ref.read(planRepoProvider),
        academyId: ref.read(safeAcademyIdProvider) ?? '',
      ),
    );
  }
}

// ============================================
// Manage Students Sheet
// ============================================

class ManageStudentsSheet extends StatefulWidget {
  final Plan plan;
  final List<Student> students;
  final VoidCallback onClose;
  final PlanRemoteRepo planRepo;
  final String academyId;

  const ManageStudentsSheet({
    super.key,
    required this.plan,
    required this.students,
    required this.onClose,
    required this.planRepo,
    required this.academyId,
  });

  @override
  State<ManageStudentsSheet> createState() => _ManageStudentsSheetState();
}

class _ManageStudentsSheetState extends State<ManageStudentsSheet> {
  late Set<String> _enrolledIds;
  String _searchQuery = '';
  bool _isSaving = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _enrolledIds = Set.from(widget.plan.studentIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Student> get _filteredStudents {
    var result = widget.students.toList();

    if (_searchQuery.isNotEmpty) {
      result = result
          .where((s) =>
              s.fullName.toLowerCase().contains(_searchQuery) ||
              (s.nickname?.toLowerCase().contains(_searchQuery) ?? false))
          .toList();
    }

    result.sort((a, b) {
      final aInPlan = _enrolledIds.contains(a.id);
      final bInPlan = _enrolledIds.contains(b.id);
      if (aInPlan && !bInPlan) return -1;
      if (!aInPlan && bInPlan) return 1;
      return a.fullName.compareTo(b.fullName);
    });

    return result;
  }

  Future<void> _toggleStudent(Student student) async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final planRepo = widget.planRepo;
      final academyId = widget.academyId;
      if (_enrolledIds.contains(student.id)) {
        await planRepo.unassignStudent(academyId, widget.plan.id, student.id);
        setState(() => _enrolledIds.remove(student.id));
        if (mounted) context.showSuccess('Aluno removido do plano');
      } else {
        await planRepo.assignStudents(academyId, widget.plan.id, [student.id]);
        setState(() => _enrolledIds.add(student.id));
        if (mounted) context.showSuccess('Aluno adicionado ao plano');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header (fixed)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SheetHandleBar(),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gerenciar Alunos',
                              style: AppTheme.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.plan.name,
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.users,
                                size: 16, color: AppTheme.success),
                            const SizedBox(width: 6),
                            Text(
                              '${_enrolledIds.length}',
                              style: AppTheme.labelMedium.copyWith(
                                color: AppTheme.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar aluno...',
                        hintStyle: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textDisabled,
                        ),
                        prefixIcon: Icon(
                          LucideIcons.search,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  LucideIcons.x,
                                  color: AppTheme.textSecondary,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value.toLowerCase());
                      },
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Student list (scrollable)
            Expanded(
              child: _filteredStudents.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.userX,
                              size: 48, color: AppTheme.textDisabled),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum aluno encontrado',
                            style: AppTheme.bodyMedium
                                .copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: _filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = _filteredStudents[index];
                        final isInPlan =
                            _enrolledIds.contains(student.id);

                        return StudentToggleCard(
                          student: student,
                          isInPlan: isInPlan,
                          isLoading: _isSaving,
                          onTap: () => _toggleStudent(student),
                        );
                      },
                    ),
            ),

            // Bottom action (fixed)
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                12 +
                    bottomPadding +
                    MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border:
                    const Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onClose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Concluir',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
