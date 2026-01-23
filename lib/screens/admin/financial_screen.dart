import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../services/services.dart';

/// Admin Financial Screen
class AdminFinancialScreen extends ConsumerStatefulWidget {
  const AdminFinancialScreen({super.key});

  @override
  ConsumerState<AdminFinancialScreen> createState() => _AdminFinancialScreenState();
}

class _AdminFinancialScreenState extends ConsumerState<AdminFinancialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Payment> _pendingPayments = [];
  List<Payment> _overduePayments = [];
  List<Payment> _paidPayments = [];
  Map<String, dynamic>? _monthlySummary;
  bool _isLoading = true;
  String _currentMonth = DateFormat('yyyy-MM').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final service = PaymentService(FirebaseService.academyId);

      final results = await Future.wait([
        service.getPending(),
        service.getOverdue(),
        service.getPaidThisMonth(),
        service.getMonthlySummary(_currentMonth),
      ]);

      setState(() {
        _pendingPayments = results[0] as List<Payment>;
        _overduePayments = results[1] as List<Payment>;
        _paidPayments = results[2] as List<Payment>;
        _monthlySummary = results[3] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financeiro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Pendentes (${_pendingPayments.length})'),
            Tab(text: 'Atrasados (${_overduePayments.length})'),
            Tab(text: 'Pagos (${_paidPayments.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Summary Cards
          _buildSummarySection(),

          // Payment Lists
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPaymentList(_pendingPayments, 'pendente'),
                      _buildPaymentList(_overduePayments, 'atrasado'),
                      _buildPaymentList(_paidPayments, 'pago'),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showGenerateTuitionsDialog,
        icon: const Icon(Icons.receipt_long),
        label: const Text('Gerar Mensalidades'),
      ),
    );
  }

  Widget _buildSummarySection() {
    final summary = _monthlySummary ?? {};
    final totalExpected = (summary['totalExpected'] ?? 0.0) as double;
    final totalPaid = (summary['totalPaid'] ?? 0.0) as double;
    final totalPending = (summary['totalPending'] ?? 0.0) as double;

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat("MMMM 'de' yyyy", 'pt_BR').format(DateTime.now()),
                style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () {
                  // TODO: Month selector
                },
                icon: const Icon(Icons.calendar_month, size: 18),
                label: const Text('Alterar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  title: 'Previsto',
                  value: totalExpected,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Recebido',
                  value: totalPaid,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Pendente',
                  value: totalPending,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentList(List<Payment> payments, String type) {
    if (payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'pago' ? Icons.check_circle_outline : Icons.receipt_long_outlined,
              size: 64,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              type == 'pago'
                  ? 'Nenhum pagamento recebido'
                  : 'Nenhum pagamento pendente',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        final payment = payments[index];
        return _PaymentCard(
          payment: payment,
          onMarkPaid: type != 'pago' ? () => _showMarkPaidDialog(payment) : null,
          onSendReminder: type != 'pago' ? () => _sendReminder(payment) : null,
        );
      },
    );
  }

  void _showMarkPaidDialog(Payment payment) {
    PaymentMethod? selectedMethod = PaymentMethod.pix;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Confirmar Pagamento'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aluno: ${payment.studentName}'),
                Text('Valor: R\$ ${payment.value.toStringAsFixed(2)}'),
                const SizedBox(height: 16),
                const Text('Método de pagamento:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: PaymentMethod.values.map((method) {
                    return ChoiceChip(
                      label: Text(method.label),
                      selected: selectedMethod == method,
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() => selectedMethod = method);
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    final service = PaymentService(FirebaseService.academyId);
                    await service.markAsPaid(payment.id, method: selectedMethod!);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pagamento confirmado!')),
                      );
                      _loadData();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e')),
                      );
                    }
                  }
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _sendReminder(Payment payment) async {
    // Need to fetch student phone number
    try {
      final studentService = StudentService(FirebaseService.academyId);
      final student = await studentService.getById(payment.studentId);
      if (student?.phone == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aluno não possui telefone cadastrado')),
          );
        }
        return;
      }

      final paymentService = PaymentService(FirebaseService.academyId);
      final whatsappLink = paymentService.getWhatsAppReminderLink(
        studentName: payment.studentName,
        amount: payment.value,
        dueDate: payment.dueDate,
        phone: student!.phone!,
      );

      // TODO: Open WhatsApp link using url_launcher
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Abrir WhatsApp: $whatsappLink')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  void _showGenerateTuitionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gerar Mensalidades'),
        content: Text(
          'Deseja gerar as mensalidades de ${DateFormat("MMMM 'de' yyyy", 'pt_BR').format(DateTime.now())} para todos os alunos ativos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final service = PaymentService(FirebaseService.academyId);
                final payments = await service.generateMonthlyTuitions(
                  referenceMonth: _currentMonth,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${payments.length} mensalidades geradas!'),
                    ),
                  );
                  _loadData();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e')),
                  );
                }
              }
            },
            child: const Text('Gerar'),
          ),
        ],
      ),
    );
  }
}

/// Summary Card Widget
class _SummaryCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'R\$ ${value.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Payment Card Widget
class _PaymentCard extends StatelessWidget {
  final Payment payment;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onSendReminder;

  const _PaymentCard({
    required this.payment,
    this.onMarkPaid,
    this.onSendReminder,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = payment.status == PaymentStatus.overdue;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isOverdue ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payment.studentName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        payment.description ?? 'Mensalidade',
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'R\$ ${payment.value.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Venc: ${DateFormat('dd/MM').format(payment.dueDate)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isOverdue ? Colors.red : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (onMarkPaid != null || onSendReminder != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onSendReminder != null)
                    TextButton.icon(
                      onPressed: onSendReminder,
                      icon: const Icon(Icons.message, size: 18),
                      label: const Text('Lembrar'),
                    ),
                  if (onMarkPaid != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: onMarkPaid,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Confirmar'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
