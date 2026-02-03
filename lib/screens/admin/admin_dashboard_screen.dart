import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';

/// Admin Dashboard Screen - Matching webapp design
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  Map<String, dynamic>? _studentStats;
  List<dynamic>? _overduePayments;
  Map<String, dynamic>? _monthlySummary;
  bool _isLoading = true;

  // Stats carousel
  final PageController _statsPageController = PageController(viewportFraction: 0.85);
  int _currentStatsPage = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _statsPageController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;

      final results = await Future.wait([
        StudentService(academyId).getDashboardStats(),
        PaymentService(academyId).getOverdue(),
        PaymentService(academyId).getMonthlySummary(
          DateFormat('yyyy-MM').format(DateTime.now()),
        ),
      ]);

      setState(() {
        _studentStats = results[0] as Map<String, dynamic>;
        _overduePayments = results[1] as List<dynamic>;
        _monthlySummary = results[2] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final weekdays = [
      'Segunda-feira',
      'Terca-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sabado',
      'Domingo'
    ];
    final months = [
      'Janeiro', 'Fevereiro', 'Marco', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];

    final weekday = weekdays[now.weekday - 1];
    final day = now.day;
    final month = months[now.month - 1];

    return '$weekday, $day De $month';
  }

  String _formatCurrency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final userName =
        currentUser.valueOrNull?.displayName.split(' ').first ?? 'Admin';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome Header
                    _buildWelcomeHeader(userName),

                    // Quick Actions
                    _buildQuickActions(),

                    const SizedBox(height: 24),

                    // Stats Carousel
                    _buildStatsCarousel(),

                    const SizedBox(height: 24),

                    // Monthly Financial Card
                    _buildMonthlyFinancialCard(),

                    const SizedBox(height: 24),

                    // Alerts Section
                    _buildAlertsSection(),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildWelcomeHeader(String userName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_getGreeting()}, $userName!',
            style: AppTheme.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getFormattedDate(),
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Chamada - Primary (black)
          Expanded(
            child: _QuickActionCard(
              icon: LucideIcons.clipboardCheck,
              label: 'Chamada',
              isPrimary: true,
              onTap: () => context.go('/admin/chamada'),
            ),
          ),
          const SizedBox(width: 12),
          // Novo Aluno
          Expanded(
            child: _QuickActionCard(
              icon: LucideIcons.userPlus,
              label: 'Novo Aluno',
              isPrimary: false,
              onTap: () => context.go('/admin/alunos/novo'),
            ),
          ),
          const SizedBox(width: 12),
          // Financeiro
          Expanded(
            child: _QuickActionCard(
              icon: LucideIcons.dollarSign,
              label: 'Financeiro',
              isPrimary: false,
              onTap: () => context.go('/admin/financeiro'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCarousel() {
    final stats = _studentStats ?? {};
    final byStatus = stats['byStatus'] as Map<String, dynamic>? ?? {};
    final summary = _monthlySummary ?? {};

    final totalActive = byStatus['active'] ?? 0;
    final totalStudents = stats['total'] ?? 0;
    final monthlyRevenue = (summary['paid']?['value'] ?? 0).toDouble();
    final paidCount = summary['paid']?['count'] ?? 0;

    return Column(
      children: [
        SizedBox(
          height: 100,
          child: PageView.builder(
            controller: _statsPageController,
            onPageChanged: (page) {
              setState(() => _currentStatsPage = page);
            },
            itemCount: 2,
            itemBuilder: (context, index) {
              final cards = [
                // Alunos Ativos
                _StatsCarouselCard(
                  icon: LucideIcons.users,
                  label: 'Alunos Ativos',
                  value: totalActive.toString(),
                  subtitle: 'de $totalStudents total',
                  onTap: () => context.go('/admin/alunos'),
                ),
                // Receita do Mes
                _StatsCarouselCard(
                  icon: LucideIcons.dollarSign,
                  iconBgColor: AppTheme.successLight,
                  iconColor: AppTheme.success,
                  label: 'Receita do Mes',
                  value: _formatCurrency(monthlyRevenue),
                  subtitle: '$paidCount pagamentos',
                  onTap: () => context.go('/admin/financeiro'),
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
            2,
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

  Widget _buildMonthlyFinancialCard() {
    final summary = _monthlySummary ?? {};
    final totalExpected = (summary['totalExpected'] ?? 0).toDouble();
    final totalPaid = (summary['paid']?['value'] ?? 0).toDouble();
    final totalPending = (summary['pending']?['value'] ?? 0).toDouble();
    final totalOverdue = (summary['overdue']?['value'] ?? 0).toDouble();
    final paidCount = summary['paid']?['count'] ?? 0;
    final pendingCount = summary['pending']?['count'] ?? 0;
    final overdueCount = summary['overdue']?['count'] ?? 0;

    final percentPaid =
        totalExpected > 0 ? (totalPaid / totalExpected * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Text(
                'Mensalidades',
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Dark summary card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.textPrimary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // Main value
                  Text(
                    _formatCurrency(totalPaid),
                    style: AppTheme.headlineMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'recebido de ${_formatCurrency(totalExpected)}',
                    style: AppTheme.bodySmall.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Progress bar
                  Row(
                    children: [
                      Text(
                        'Taxa de recebimento',
                        style: AppTheme.labelSmall.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${percentPaid.toStringAsFixed(0)}%',
                        style: AppTheme.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentPaid / 100,
                      backgroundColor: Colors.white24,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppTheme.success),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Breakdown rows
            _FinancialBreakdownRow(
              icon: LucideIcons.dollarSign,
              label: 'Recebido',
              count: paidCount,
              value: _formatCurrency(totalPaid),
            ),
            _FinancialBreakdownRow(
              icon: LucideIcons.clock,
              label: 'Pendente',
              count: pendingCount,
              value: _formatCurrency(totalPending),
            ),
            _FinancialBreakdownRow(
              icon: LucideIcons.alertTriangle,
              label: 'Vencido',
              count: overdueCount,
              value: _formatCurrency(totalOverdue),
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsSection() {
    final hasOverdue = _overduePayments != null && _overduePayments!.isNotEmpty;

    if (!hasOverdue) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alertas',
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _AlertCard(
            icon: LucideIcons.alertTriangle,
            title: '${_overduePayments!.length} pagamento(s) em atraso',
            subtitle: 'Verificar cobrancas pendentes',
            color: AppTheme.error,
            onTap: () => context.go('/admin/financeiro'),
          ),
        ],
      ),
    );
  }
}

/// Quick Action Card - Matches webapp design
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.textPrimary : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: isPrimary ? null : Border.all(color: AppTheme.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isPrimary
                    ? Colors.white.withValues(alpha: 0.15)
                    : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isPrimary ? Colors.white : AppTheme.textPrimary,
                size: 22,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: AppTheme.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                color: isPrimary ? Colors.white : AppTheme.textPrimary,
              ),
            ),
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
  final VoidCallback? onTap;

  const _StatsCarouselCard({
    required this.icon,
    this.iconBgColor,
    this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }
}

/// Financial Breakdown Row
class _FinancialBreakdownRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final String value;
  final bool isLast;

  const _FinancialBreakdownRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppTheme.divider, width: 1),
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
            child: Icon(icon, size: 18, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$count pag.',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Alert Card
class _AlertCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AlertCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
