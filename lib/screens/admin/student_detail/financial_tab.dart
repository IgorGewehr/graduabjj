import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../services/services.dart';

/// Financial tab content for student detail screen.
class StudentFinancialTab extends StatelessWidget {
  final String studentId;
  final List<Payment> payments;
  final List<StoreOrder> storeOrders;
  final List<Plan> studentPlans;
  final VoidCallback onRefresh;

  const StudentFinancialTab({
    super.key,
    required this.studentId,
    required this.payments,
    required this.storeOrders,
    required this.studentPlans,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty && storeOrders.isEmpty && studentPlans.isEmpty) {
      return const Center(child: Text('Nenhum pagamento registrado'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Plan and value section
        if (studentPlans.isNotEmpty) ...[
          Text(
            'PLANO E VALOR',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...studentPlans.map((plan) {
            final studentValue = plan.getStudentValue(studentId);
            final hasCustomValue = plan.customValues.containsKey(studentId);
            final studentDueDay = plan.getStudentDueDay(studentId);
            final hasCustomDueDay = plan.customDueDays.containsKey(studentId);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
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
                        onTap: () =>
                            _showCustomValueDialog(context, plan),
                        child: const Icon(
                          LucideIcons.pencil,
                          size: 18,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Valor padrão: R\$ ${plan.monthlyValue.toStringAsFixed(2)}',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Valor personalizado',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Personalizado',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        // Tuition payments
        if (payments.isNotEmpty) ...[
          Text(
            'MENSALIDADES',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...payments.map((payment) => _PaymentCard(payment: payment)),
        ],
        // Store orders
        if (storeOrders.isNotEmpty) ...[
          if (payments.isNotEmpty) const SizedBox(height: 16),
          Text(
            'PEDIDOS DA LOJA',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...storeOrders.map((order) => _StoreOrderCard(order: order)),
        ],
      ],
    );
  }

  void _showCustomValueDialog(BuildContext context, Plan plan) {
    final studentValue = plan.getStudentValue(studentId);
    final controller = TextEditingController(
      text: studentValue.toStringAsFixed(2),
    );
    final hasCustomValue = plan.customValues.containsKey(studentId);
    final studentDueDay = plan.getStudentDueDay(studentId);
    final dueDayController = TextEditingController(
      text: studentDueDay.toString(),
    );
    final hasCustomDueDay = plan.customDueDays.containsKey(studentId);
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
              controller: controller,
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
                  Navigator.of(dialogContext).pop();
                  final planService = PlanService(FirebaseService.academyId);
                  await planService.removeCustomValue(plan.id, studentId);
                  if (parentContext.mounted)
                    parentContext.showSuccess(
                      'Valor restaurado ao padrão do plano',
                    );
                  onRefresh();
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
                  Navigator.of(dialogContext).pop();
                  final planService = PlanService(FirebaseService.academyId);
                  await planService.removeCustomDueDay(plan.id, studentId);
                  if (parentContext.mounted)
                    parentContext.showSuccess(
                      'Vencimento restaurado ao padrão do plano',
                    );
                  onRefresh();
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
                controller.text.replaceAll(',', '.'),
              );
              if (value == null || value <= 0) return;
              final dueDay = int.tryParse(dueDayController.text);
              if (dueDay == null || dueDay < 1 || dueDay > 31) return;
              Navigator.of(dialogContext).pop();
              final planService = PlanService(FirebaseService.academyId);
              // Save value
              if (value == plan.monthlyValue) {
                await planService.removeCustomValue(plan.id, studentId);
              } else {
                await planService.setCustomValue(plan.id, studentId, value);
              }
              // Save due day
              if (dueDay == plan.defaultDueDay) {
                await planService.removeCustomDueDay(plan.id, studentId);
              } else {
                await planService.setCustomDueDay(plan.id, studentId, dueDay);
              }
              if (parentContext.mounted)
                parentContext.showSuccess('Valor e vencimento atualizados');
              onRefresh();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets
// ---------------------------------------------------------------------------

class _PaymentCard extends StatelessWidget {
  final Payment payment;

  const _PaymentCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    final statusColors = {
      PaymentStatus.pending: Colors.orange,
      PaymentStatus.paid: Colors.green,
      PaymentStatus.overdue: Colors.red,
      PaymentStatus.cancelled: Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColors[payment.status]?.withValues(alpha: 0.2),
          child: Icon(
            payment.status == PaymentStatus.paid ? Icons.check : Icons.receipt,
            color: statusColors[payment.status],
          ),
        ),
        title: Text(payment.description ?? 'Mensalidade'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Venc: ${DateFormat('dd/MM/yyyy').format(payment.dueDate)}'),
            if (payment.paidAt != null)
              Text(
                'Pago em: ${DateFormat('dd/MM/yyyy').format(payment.paidAt!)}',
                style: const TextStyle(color: Colors.green),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'R\$ ${payment.value.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColors[payment.status]?.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                payment.status.label,
                style: TextStyle(
                  fontSize: 9,
                  color: statusColors[payment.status],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreOrderCard extends StatelessWidget {
  final StoreOrder order;

  const _StoreOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final statusColors = {
      StoreOrderStatus.pendingPayment: Colors.orange,
      StoreOrderStatus.paid: Colors.green,
      StoreOrderStatus.preparing: Colors.blue,
      StoreOrderStatus.ready: Colors.purple,
      StoreOrderStatus.delivered: Colors.teal,
      StoreOrderStatus.cancelled: Colors.grey,
    };

    final itemNames = order.items.map((i) => i.productName).join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColors[order.status]?.withValues(alpha: 0.2),
          child: Icon(
            LucideIcons.shoppingBag,
            color: statusColors[order.status],
            size: 20,
          ),
        ),
        title: Text(
          itemNames.isNotEmpty ? itemNames : 'Pedido',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('dd/MM/yyyy').format(order.createdAt)),
            if (order.paidAt != null)
              Text(
                'Pago em: ${DateFormat('dd/MM/yyyy').format(order.paidAt!)}',
                style: const TextStyle(color: Colors.green),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'R\$ ${order.total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColors[order.status]?.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                order.status.label,
                style: TextStyle(
                  fontSize: 9,
                  color: statusColors[order.status],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
