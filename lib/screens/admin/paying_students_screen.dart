import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/plan_service.dart';
import '../../services/firebase_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/belt_badge.dart';

/// Paying Students Screen - List of students enrolled in plans
class PayingStudentsScreen extends ConsumerStatefulWidget {
  final List<Student> students;
  final List<Plan> plans;

  const PayingStudentsScreen({
    super.key,
    required this.students,
    required this.plans,
  });

  @override
  ConsumerState<PayingStudentsScreen> createState() =>
      _PayingStudentsScreenState();
}

class _PayingStudentsScreenState extends ConsumerState<PayingStudentsScreen> {
  String _searchTerm = '';
  String _planFilter = '';
  String _sortBy = 'name'; // name | belt | planCount
  List<Plan> _plans = [];

  @override
  void initState() {
    super.initState();
    _plans = List.from(widget.plans);
  }

  Future<void> _refreshPlans() async {
    final academyId = FirebaseService.academyId;
    ref.invalidate(tatami.tatamiPlansLegacyProvider(academyId));
    final plans =
        await ref.read(tatami.tatamiPlansLegacyProvider(academyId).future);

    if (mounted) {
      setState(() => _plans = plans);
    }
  }

  /// Get students that are enrolled in at least one plan
  List<Student> get _payingStudents {
    final studentIdsWithPlans = <String>{};
    for (final plan in _plans) {
      for (final id in plan.studentIds) {
        studentIdsWithPlans.add(id);
      }
    }
    return widget.students
        .where((s) => studentIdsWithPlans.contains(s.id))
        .toList();
  }

  /// Get plans for a specific student
  List<Plan> _getPlansForStudent(String studentId) {
    return _plans.where((p) => p.studentIds.contains(studentId)).toList();
  }

  /// Calculate total monthly value for a student
  double _getTotalMonthlyValue(String studentId) {
    final studentPlans = _getPlansForStudent(studentId);
    return studentPlans.fold(
      0.0,
      (sum, plan) => sum + plan.getStudentValue(studentId),
    );
  }

  /// Belt order for sorting
  int _getBeltOrderValue(String belt) {
    const beltOrder = {
      'white': 0,
      'grey-white': 1,
      'grey': 2,
      'grey-black': 3,
      'yellow-white': 4,
      'yellow': 5,
      'yellow-black': 6,
      'orange-white': 7,
      'orange': 8,
      'orange-black': 9,
      'green-white': 10,
      'green': 11,
      'green-black': 12,
      'blue': 13,
      'purple': 14,
      'brown': 15,
      'black': 16,
    };
    return beltOrder[belt] ?? 0;
  }

  /// Filtered and sorted students
  List<Student> get _filteredStudents {
    var result = _payingStudents;

    // Search filter
    if (_searchTerm.isNotEmpty) {
      final term = _searchTerm.toLowerCase();
      result = result
          .where(
            (s) =>
                s.fullName.toLowerCase().contains(term) ||
                (s.nickname?.toLowerCase().contains(term) ?? false),
          )
          .toList();
    }

    // Plan filter
    if (_planFilter.isNotEmpty) {
      final selectedPlan = _plans.firstWhere(
        (p) => p.id == _planFilter,
        orElse: () => _plans.first,
      );
      result = result
          .where((s) => selectedPlan.studentIds.contains(s.id))
          .toList();
    }

    // Sort
    result = List.from(result);
    switch (_sortBy) {
      case 'name':
        result.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case 'belt':
        result.sort((a, b) {
          final aOrder =
              _getBeltOrderValue(a.currentBelt) * 10 + a.currentStripes;
          final bOrder =
              _getBeltOrderValue(b.currentBelt) * 10 + b.currentStripes;
          return bOrder.compareTo(aOrder);
        });
        break;
      case 'planCount':
        result.sort((a, b) {
          final aCount = _getPlansForStudent(a.id).length;
          final bCount = _getPlansForStudent(b.id).length;
          return bCount.compareTo(aCount);
        });
        break;
    }

    return result;
  }

  int get _activePlansCount => _plans.where((p) => p.isActive).length;

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStudents;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alunos Pagantes'),
            Text(
              '${filtered.length} alunos em $_activePlansCount planos',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (value) => setState(() => _searchTerm = value),
              decoration: InputDecoration(
                hintText: 'Buscar aluno...',
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.divider),
                ),
              ),
            ),
          ),

          // Filters row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                // Plan filter
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _planFilter,
                        isExpanded: true,
                        hint: const Text('Todos os Planos'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todos os Planos'),
                          ),
                          ..._plans.map(
                            (plan) => DropdownMenuItem(
                              value: plan.id,
                              child: Text(
                                plan.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _planFilter = value ?? ''),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Sort dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      items: const [
                        DropdownMenuItem(value: 'name', child: Text('Nome')),
                        DropdownMenuItem(
                          value: 'belt',
                          child: Text('Graduação'),
                        ),
                        DropdownMenuItem(
                          value: 'planCount',
                          child: Text('Planos'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _sortBy = value ?? 'name'),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Students list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _searchTerm.isNotEmpty || _planFilter.isNotEmpty
                          ? 'Nenhum aluno encontrado com os filtros aplicados'
                          : 'Nenhum aluno pagante cadastrado',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final student = filtered[index];
                      final studentPlans = _getPlansForStudent(student.id);
                      final totalMonthly = _getTotalMonthlyValue(student.id);
                      final hasCustomValue = studentPlans.any(
                        (plan) => plan.customValues.containsKey(student.id),
                      );
                      final beltColor = AppTheme.getBeltColor(
                        student.currentBelt,
                      );

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showStudentPlansSheet(student),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Avatar
                                AppCachedAvatar(
                                  imageUrl: student.photoUrl,
                                  radius: 24,
                                  backgroundColor: beltColor.withValues(
                                    alpha: 0.15,
                                  ),
                                  child:
                                      (student.photoUrl == null ||
                                          student.photoUrl!.isEmpty)
                                      ? Text(
                                          _getInitials(student.fullName),
                                          style: TextStyle(
                                            color: beltColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                // Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              student.nickname ??
                                                  student.fullName
                                                      .split(' ')
                                                      .first,
                                              style: AppTheme.bodyMedium
                                                  .copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          BeltBadge(
                                            belt: student.currentBelt,
                                            stripes: student.currentStripes,
                                            size: BeltSize.small,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          _buildChip(
                                            '${studentPlans.length} ${studentPlans.length == 1 ? 'plano' : 'planos'}',
                                          ),
                                          if (hasCustomValue)
                                            _buildChip(
                                              'Personalizado',
                                              isSuccess: true,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Value
                                Text(
                                  'R\$ ${totalMonthly.toStringAsFixed(2)}',
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, {bool isSuccess = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSuccess ? AppTheme.successLight : AppTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSuccess
              ? AppTheme.success.withValues(alpha: 0.3)
              : AppTheme.divider,
        ),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(
          color: isSuccess ? AppTheme.success : AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }

  void _showStudentPlansSheet(Student student) {
    final studentPlans = _getPlansForStudent(student.id);
    final totalMonthly = _getTotalMonthlyValue(student.id);
    final beltColor = AppTheme.getBeltColor(student.currentBelt);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header: avatar + name + belt
              Row(
                children: [
                  AppCachedAvatar(
                    imageUrl: student.photoUrl,
                    radius: 28,
                    backgroundColor: beltColor.withValues(alpha: 0.15),
                    child:
                        (student.photoUrl == null || student.photoUrl!.isEmpty)
                        ? Text(
                            _getInitials(student.fullName),
                            style: TextStyle(
                              color: beltColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.fullName,
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        BeltBadge(
                          belt: student.currentBelt,
                          stripes: student.currentStripes,
                          size: BeltSize.small,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Total monthly card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Mensal',
                      style: AppTheme.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'R\$ ${totalMonthly.toStringAsFixed(2)}',
                      style: AppTheme.headlineSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Plans list
              ...studentPlans.map((plan) {
                final studentValue = plan.getStudentValue(student.id);
                final hasCustomValue = plan.customValues.containsKey(
                  student.id,
                );
                final studentDueDay = plan.getStudentDueDay(student.id);
                final hasCustomDueDay = plan.customDueDays.containsKey(
                  student.id,
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
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
                        children: [
                          Expanded(
                            child: Text(
                              plan.name,
                              style: AppTheme.titleSmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              _showEditPlanOverridesDialog(student, plan);
                            },
                            child: const Icon(
                              LucideIcons.pencil,
                              size: 18,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Valor padrão: R\$ ${plan.monthlyValue.toStringAsFixed(2)}',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Valor do aluno: R\$ ${studentValue.toStringAsFixed(2)}',
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: hasCustomValue
                                  ? AppTheme.success
                                  : AppTheme.textPrimary,
                            ),
                          ),
                          if (hasCustomValue) ...[
                            const SizedBox(width: 8),
                            _buildChip('Personalizado', isSuccess: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Vencimento: dia $studentDueDay',
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: hasCustomDueDay
                                  ? AppTheme.success
                                  : AppTheme.textPrimary,
                            ),
                          ),
                          if (hasCustomDueDay) ...[
                            const SizedBox(width: 8),
                            _buildChip('Personalizado', isSuccess: true),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditPlanOverridesDialog(Student student, Plan plan) {
    final studentValue = plan.getStudentValue(student.id);
    final valueController = TextEditingController(
      text: studentValue.toStringAsFixed(2),
    );
    final hasCustomValue = plan.customValues.containsKey(student.id);
    final studentDueDay = plan.getStudentDueDay(student.id);
    final dueDayController = TextEditingController(
      text: studentDueDay.toString(),
    );
    final hasCustomDueDay = plan.customDueDays.containsKey(student.id);
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Valor e Vencimento - ${plan.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Valor padrão do plano: R\$ ${plan.monthlyValue.toStringAsFixed(2)}',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: valueController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor do aluno',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            if (hasCustomValue) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  final planService = PlanService(FirebaseService.academyId);
                  await planService.removeCustomValue(plan.id, student.id);
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  parentContext.showSuccess(
                    'Valor restaurado ao padrão do plano',
                  );
                  _refreshPlans();
                },
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: const Text('Restaurar valor do plano'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Vencimento padrão do plano: dia ${plan.defaultDueDay}',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dueDayController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dia de vencimento',
                hintText: '1-31',
                border: OutlineInputBorder(),
              ),
            ),
            if (hasCustomDueDay) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  final planService = PlanService(FirebaseService.academyId);
                  await planService.removeCustomDueDay(plan.id, student.id);
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  parentContext.showSuccess(
                    'Vencimento restaurado ao padrão do plano',
                  );
                  _refreshPlans();
                },
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: const Text('Restaurar vencimento do plano'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final value = double.tryParse(
                valueController.text.replaceAll(',', '.'),
              );
              if (value == null || value <= 0) return;
              final dueDay = int.tryParse(dueDayController.text);
              if (dueDay == null || dueDay < 1 || dueDay > 31) return;
              final planService = PlanService(FirebaseService.academyId);
              // Save value
              if (value == plan.monthlyValue) {
                await planService.removeCustomValue(plan.id, student.id);
              } else {
                await planService.setCustomValue(plan.id, student.id, value);
              }
              // Save due day
              if (dueDay == plan.defaultDueDay) {
                await planService.removeCustomDueDay(plan.id, student.id);
              } else {
                await planService.setCustomDueDay(plan.id, student.id, dueDay);
              }
              if (!mounted || !dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              parentContext.showSuccess('Valor e vencimento atualizados');
              _refreshPlans();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
