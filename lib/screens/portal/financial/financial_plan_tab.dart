import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../providers/providers.dart';
import '../../../services/services.dart';
import 'payment_card.dart';

class FinancialPlanTab extends ConsumerWidget {
  const FinancialPlanTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) return const SizedBox.shrink();

        final planAsync = ref.watch(studentPlanProvider(student.id));

        return planAsync.when(
          data: (plan) => plan == null
              ? const _NoPlan()
              : _PlanDetails(plan: plan, studentId: student.id),
          loading: () => const _PlanSkeleton(),
          error: (_, e) => Center(
            child: Text(
              'Erro ao carregar plano.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
            ),
          ),
        );
      },
      loading: () => const _PlanSkeleton(),
      error: (_, e) => const SizedBox.shrink(),
    );
  }
}

class _PlanDetails extends StatelessWidget {
  final Plan plan;
  final String studentId;

  const _PlanDetails({required this.plan, required this.studentId});

  @override
  Widget build(BuildContext context) {
    final studentValue = plan.getStudentValue(studentId);
    final dueDay = plan.getStudentDueDay(studentId);

    return ListView(
      padding: const EdgeInsets.all(20),
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.badgeCheck,
                      size: 22,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (plan.description != null)
                          Text(
                            plan.description!,
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              _InfoRow(
                icon: LucideIcons.dollarSign,
                label: 'Mensalidade',
                value: formatCurrency(studentValue),
              ),
              const SizedBox(height: 12),
              _InfoRow(
                icon: LucideIcons.calendar,
                label: 'Vencimento',
                value: 'Dia $dueDay de cada mes',
              ),
              if (plan.classesPerWeek != null) ...[
                const SizedBox(height: 12),
                _InfoRow(
                  icon: LucideIcons.dumbbell,
                  label: 'Aulas por semana',
                  value: '${plan.classesPerWeek}x',
                ),
              ],
              if (studentValue != plan.monthlyValue) ...[
                const SizedBox(height: 12),
                _InfoRow(
                  icon: LucideIcons.tag,
                  label: 'Valor padrao do plano',
                  value: formatCurrency(plan.monthlyValue),
                  valueColor: AppTheme.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        Text(
          value,
          style: AppTheme.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.fileQuestion,
              size: 40,
              color: AppTheme.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum plano vinculado',
              style: AppTheme.bodyMedium
                  .copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSkeleton extends StatelessWidget {
  const _PlanSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
