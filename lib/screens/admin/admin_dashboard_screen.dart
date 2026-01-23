import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../services/services.dart';

/// Admin Dashboard Screen
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  Map<String, dynamic>? _studentStats;
  List<dynamic>? _overduePayments;
  List<dynamic>? _eligibleStudents;
  Map<String, dynamic>? _monthlySummary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;

      // Load data in parallel
      final results = await Future.wait([
        StudentService(academyId).getDashboardStats(),
        PaymentService(academyId).getOverdue(),
        BeltProgressionService(academyId).getEligibleStudents(),
        PaymentService(academyId).getMonthlySummary(
          DateFormat('yyyy-MM').format(DateTime.now()),
        ),
      ]);

      setState(() {
        _studentStats = results[0] as Map<String, dynamic>;
        _overduePayments = results[1] as List<dynamic>;
        _eligibleStudents = results[2] as List<dynamic>;
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
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              // TODO: Show notifications
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats Cards
                    _buildStatsSection(),
                    const SizedBox(height: 24),

                    // Quick Actions
                    _buildQuickActionsSection(),
                    const SizedBox(height: 24),

                    // Alerts Section
                    if (_overduePayments != null && _overduePayments!.isNotEmpty)
                      _buildAlertsSection(),

                    // Eligible for Promotion
                    if (_eligibleStudents != null && _eligibleStudents!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildEligibleStudentsSection(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatsSection() {
    final stats = _studentStats ?? {};
    final byStatus = stats['byStatus'] as Map<String, dynamic>? ?? {};
    final summary = _monthlySummary ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Visão Geral',
          style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _StatCard(
              title: 'Alunos Ativos',
              value: '${byStatus['active'] ?? 0}',
              icon: Icons.people,
              color: Colors.green,
              onTap: () => context.go('/admin/alunos'),
            ),
            _StatCard(
              title: 'Total de Alunos',
              value: '${stats['total'] ?? 0}',
              icon: Icons.groups,
              color: AppTheme.primary,
              onTap: () => context.go('/admin/alunos'),
            ),
            _StatCard(
              title: 'Receita do Mês',
              value: 'R\$ ${(summary['totalPaid'] ?? 0).toStringAsFixed(0)}',
              icon: Icons.attach_money,
              color: Colors.green,
              onTap: () => context.go('/admin/financeiro'),
            ),
            _StatCard(
              title: 'Pagtos Pendentes',
              value: '${_overduePayments?.length ?? 0}',
              icon: Icons.warning_amber,
              color: Colors.orange,
              onTap: () => context.go('/admin/financeiro'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ações Rápidas',
          style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _QuickActionButton(
              icon: Icons.person_add,
              label: 'Novo Aluno',
              color: AppTheme.primary,
              onTap: () => context.go('/admin/alunos/novo'),
            ),
            _QuickActionButton(
              icon: Icons.check_circle,
              label: 'Fazer Chamada',
              color: Colors.green,
              onTap: () => context.go('/admin/chamada'),
            ),
            _QuickActionButton(
              icon: Icons.receipt_long,
              label: 'Gerar Mensalidades',
              color: Colors.blue,
              onTap: () => _showGenerateTuitionsDialog(),
            ),
            _QuickActionButton(
              icon: Icons.military_tech,
              label: 'Graduar Aluno',
              color: Colors.purple,
              onTap: () => context.go('/admin/graduacao'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Alertas',
              style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => context.go('/admin/financeiro'),
              child: const Text('Ver todos'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          color: Colors.orange.shade50,
          child: ListTile(
            leading: Icon(Icons.warning_amber, color: Colors.orange.shade700),
            title: Text(
              '${_overduePayments!.length} pagamento(s) em atraso',
              style: TextStyle(color: Colors.orange.shade900),
            ),
            subtitle: Text(
              'Clique para ver detalhes',
              style: TextStyle(color: Colors.orange.shade700),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/admin/financeiro'),
          ),
        ),
      ],
    );
  }

  Widget _buildEligibleStudentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Prontos para Graduação',
              style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => context.go('/admin/graduacao'),
              child: const Text('Ver todos'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          color: Colors.green.shade50,
          child: ListTile(
            leading: Icon(Icons.military_tech, color: Colors.green.shade700),
            title: Text(
              '${_eligibleStudents!.length} aluno(s) elegível(is)',
              style: TextStyle(color: Colors.green.shade900),
            ),
            subtitle: Text(
              'Prontos para receber grau ou faixa',
              style: TextStyle(color: Colors.green.shade700),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/admin/graduacao'),
          ),
        ),
      ],
    );
  }

  void _showGenerateTuitionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gerar Mensalidades'),
        content: const Text(
          'Deseja gerar as mensalidades do mês atual para todos os alunos ativos?',
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
                final referenceMonth = DateFormat('yyyy-MM').format(DateTime.now());
                await service.generateMonthlyTuitions(referenceMonth: referenceMonth);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mensalidades geradas com sucesso!')),
                  );
                  _loadDashboardData();
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

/// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick Action Button
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
