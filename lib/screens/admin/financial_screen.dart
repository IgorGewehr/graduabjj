import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/academy_page_header.dart';
import '../../widgets/polish/polish.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';
import 'paying_students_screen.dart';
import 'financial_reports_screen.dart';

/// Admin Financial Screen - Matching webapp design
class AdminFinancialScreen extends ConsumerStatefulWidget {
  const AdminFinancialScreen({super.key});

  @override
  ConsumerState<AdminFinancialScreen> createState() =>
      _AdminFinancialScreenState();
}

class _AdminFinancialScreenState extends ConsumerState<AdminFinancialScreen>
    with SingleTickerProviderStateMixin {
  // Data
  List<Payment> _allPayments = [];
  List<Plan> _plans = [];
  List<Student> _students = [];
  Map<String, dynamic>? _monthlySummary;
  bool _isLoading = true;

  // State
  DateTime _selectedMonth = DateTime.now();
  late TabController _tabController;
  StreamSubscription<List<Payment>>? _paymentsSub;

  // Payments filter state
  String _paymentFilter = 'all'; // all, paid, pending, overdue, cancelled
  String _paymentSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _paymentsSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  /// Recomputes the monthly summary buckets from a payments list (mirrors
  /// PaymentService.getMonthlySummary) so the live stream keeps the stat cards
  /// in sync without an extra query.
  Map<String, dynamic> _summaryFromPayments(List<Payment> payments) {
    double totalExpected = 0, totalPaid = 0, totalPending = 0, totalOverdue = 0;
    int countPaid = 0, countPending = 0, countOverdue = 0, countCancelled = 0;
    for (final p in payments) {
      if (p.status == PaymentStatus.cancelled) {
        countCancelled++;
        continue;
      }
      // Cobrança indevida a reembolsar (subscription_overcharge) — não é
      // receita; fica fora das somas/contagens (espelha getMonthlySummary).
      if (p.isOvercharge) continue;
      totalExpected += p.value;
      if (p.status == PaymentStatus.paid) {
        totalPaid += p.value;
        countPaid++;
      } else if (p.isOverdue || p.status == PaymentStatus.overdue) {
        totalOverdue += p.value;
        countOverdue++;
      } else if (p.status == PaymentStatus.pending) {
        totalPending += p.value;
        countPending++;
      }
    }
    return {
      'referenceMonth': _currentMonthKey,
      'totalExpected': totalExpected,
      'paid': {'value': totalPaid, 'count': countPaid},
      'pending': {'value': totalPending, 'count': countPending},
      'overdue': {'value': totalOverdue, 'count': countOverdue},
      'cancelled': countCancelled,
      'collectionRate': totalExpected > 0 ? (totalPaid / totalExpected * 100) : 0,
    };
  }

  String get _currentMonthKey => DateFormat('yyyy-MM').format(_selectedMonth);

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Resolve the academy from the authenticated user (not the mutable global
      // static, which could be stale and read the wrong academy).
      final user = await ref.read(currentUserProvider.future);
      final academyId = user?.academyId ?? FirebaseService.academyId;
      final paymentService = PaymentService(academyId);

      // Reconcile overdue statuses before reading. Without this, dueDate-passed
      // records remain "pending" in Firestore and downstream queries that filter
      // by status alone (notifications, reports) miss them.
      await paymentService.markOverduePayments();

      final results = await Future.wait([
        paymentService.getByMonth(_currentMonthKey),
        PlanService(academyId).list(),
        StudentService(academyId).getActive(),
        paymentService.getMonthlySummary(_currentMonthKey),
      ]);

      if (!mounted) return;
      setState(() {
        _allPayments = results[0] as List<Payment>;
        _plans = results[1] as List<Plan>;
        _students = results[2] as List<Student>;
        _monthlySummary = results[3] as Map<String, dynamic>;
        _isLoading = false;
      });

      // Live updates: reflect a webhook flip to `paid` in real time (the
      // one-shot read above could otherwise show a just-paid charge as open).
      _paymentsSub?.cancel();
      _paymentsSub =
          paymentService.streamByMonth(_currentMonthKey).listen((payments) {
        if (!mounted) return;
        setState(() {
          _allPayments = payments;
          _monthlySummary = _summaryFromPayments(payments);
        });
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    _loadData();
  }

  String _formatCurrency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  // Computed values
  // Pending: status is pending AND not overdue (dueDate hasn't passed)
  List<Payment> get _pendingPayments =>
      _allPayments.where((p) => p.status == PaymentStatus.pending && !p.isOverdue).toList();

  // Overdue: isOverdue computed property (status pending/overdue AND dueDate passed)
  List<Payment> get _overduePayments =>
      _allPayments.where((p) => p.isOverdue || p.status == PaymentStatus.overdue).toList();

  double get _expectedRevenue {
    double total = 0;
    for (final plan in _plans.where((p) => p.isActive)) {
      final periodRevenue = plan.studentIds
          .fold(0.0, (sum, sid) => sum + plan.getStudentValue(sid));
      total += periodRevenue / plan.billingPeriod.months;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: _buildFAB(),
      body: _isLoading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: PolishSkeleton.list(count: 5),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverToBoxAdapter(child: _buildMonthSelector()),

                  // Stats Grid
                  SliverToBoxAdapter(child: _buildStatsGrid()),

                  // Tab Bar
                  SliverToBoxAdapter(child: _buildTabBar()),

                  // Tab Content
                  SliverFillRemaining(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPlansTab(),
                        _buildPaymentsTab(),
                        _buildReportsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFAB() {
    // FAB changes based on current tab
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        if (_tabController.index == 1) {
          // Pagamentos tab - Gerar Mensalidades
          return FloatingActionButton.extended(
            onPressed: _showGenerateTuitionsDialog,
            backgroundColor: AppTheme.primary,
            icon: const Icon(LucideIcons.receipt, size: 20),
            label: const Text('Gerar'),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildHeader() {
    return AcademyPageHeader(
      icon: LucideIcons.dollarSign,
      title: 'Financeiro',
      description: 'Mensalidades e pagamentos',
      actions: [
        IconButton(
          onPressed: _loadData,
          icon: const Icon(LucideIcons.refreshCw, size: 20),
          tooltip: 'Atualizar',
        ),
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PayingStudentsScreen(
                students: _students,
                plans: _plans,
              ),
            ),
          ),
          icon: const Icon(LucideIcons.users, size: 20),
          tooltip: 'Alunos Pagantes',
        ),
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminFinancialReportsScreen(),
            ),
          ),
          icon: const Icon(LucideIcons.barChart2, size: 20),
          tooltip: 'Relatórios',
        ),
      ],
    );
  }

  Widget _buildMonthSelector() {
    final monthYear = DateFormat("MMM 'De' yyyy", 'pt_BR')
        .format(_selectedMonth)
        .replaceFirst(
          DateFormat("MMM", 'pt_BR').format(_selectedMonth),
          DateFormat("MMM", 'pt_BR').format(_selectedMonth).capitalize(),
        );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => _changeMonth(-1),
            child: const Icon(
              LucideIcons.chevronLeft,
              size: 24,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            monthYear,
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          GestureDetector(
            onTap: () => _changeMonth(1),
            child: const Icon(
              LucideIcons.chevronRight,
              size: 24,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final summary = _monthlySummary ?? {};
    final totalPaid = (summary['paid']?['value'] ?? 0).toDouble();
    final totalPending = (summary['pending']?['value'] ?? 0).toDouble();
    final totalOverdue = (summary['overdue']?['value'] ?? 0).toDouble();
    final paidCount = summary['paid']?['count'] ?? 0;
    final pendingCount = summary['pending']?['count'] ?? 0;
    final overdueCount = summary['overdue']?['count'] ?? 0;
    final totalExpected = (summary['totalExpected'] ?? 0).toDouble();

    final rate = totalExpected > 0 ? (totalPaid / totalExpected * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // 3-column stats grid (always visible)
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: LucideIcons.checkCircle,
                  iconColor: AppTheme.success,
                  label: 'Recebido',
                  value: _formatCurrency(totalPaid),
                  subtitle: '$paidCount pagos',
                ).entrance(index: 0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  icon: LucideIcons.clock,
                  iconColor: AppTheme.warning,
                  label: 'Pendente',
                  value: _formatCurrency(totalPending),
                  subtitle: '$pendingCount pend.',
                ).entrance(index: 1),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  icon: LucideIcons.alertTriangle,
                  iconColor: AppTheme.error,
                  label: 'Atrasado',
                  value: _formatCurrency(totalOverdue),
                  subtitle: '$overdueCount atras.',
                ).entrance(index: 2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar for collection rate
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.trendingUp,
                  size: 18,
                  color: rate >= 70 ? AppTheme.success : rate >= 40 ? AppTheme.warning : AppTheme.error,
                ),
                const SizedBox(width: 10),
                AnimatedCountUp(
                  value: rate,
                  prefix: 'Taxa: ',
                  suffix: '%',
                  style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: rate / 100,
                      minHeight: 8,
                      backgroundColor: AppTheme.divider,
                      valueColor: AlwaysStoppedAnimation(
                        rate >= 70 ? AppTheme.success : rate >= 40 ? AppTheme.warning : AppTheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final pendingTotal = _pendingPayments.length + _overduePayments.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppTheme.textPrimary,
        unselectedLabelColor: AppTheme.textSecondary,
        labelStyle: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTheme.labelMedium,
        indicatorColor: AppTheme.textPrimary,
        indicatorWeight: 2,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        tabs: [
          const Tab(text: 'Planos'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Pagamentos'),
                if (pendingTotal > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warning,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$pendingTotal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Tab(text: 'Relatórios'),
        ],
      ),
    );
  }

  Widget _buildPlansTab() {
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
                    'Receita esperada: ${_formatCurrency(_expectedRevenue)}/mes',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: _showCreatePlanDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.textPrimary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          ..._plans.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PlanCard(
                  plan: entry.value,
                  formatCurrency: _formatCurrency,
                  onEdit: () => _showEditPlanDialog(entry.value),
                  onDelete: () => _showDeletePlanDialog(entry.value),
                  onManageStudents: () => _showManageStudentsDialog(entry.value),
                ).entrance(index: entry.key),
              )),

          if (_plans.isEmpty)
            const PolishedEmptyState(
              icon: LucideIcons.package,
              title: 'Nenhum plano cadastrado',
              subtitle: 'Crie um plano para começar a cobrar mensalidades.',
            ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  /// Unified payments tab with filter chips and search
  Widget _buildPaymentsTab() {
    // Filter payments based on current filter
    List<Payment> filteredPayments = _allPayments;
    
    switch (_paymentFilter) {
      case 'paid':
        filteredPayments = _allPayments.where((p) => p.status == PaymentStatus.paid).toList();
        break;
      case 'pending':
        filteredPayments = _pendingPayments;
        break;
      case 'overdue':
        filteredPayments = _overduePayments;
        break;
      case 'cancelled':
        filteredPayments = _allPayments.where((p) => p.status == PaymentStatus.cancelled).toList();
        break;
    }

    // Apply search filter
    if (_paymentSearch.isNotEmpty) {
      filteredPayments = filteredPayments.where((p) =>
        p.studentName.toLowerCase().contains(_paymentSearch.toLowerCase())
      ).toList();
    }

    return Column(
      children: [
        // Filter chips and search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              // Search bar
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome...',
                    hintStyle: AppTheme.bodySmall.copyWith(color: AppTheme.textDisabled),
                    prefixIcon: Icon(LucideIcons.search, size: 18, color: AppTheme.textSecondary),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    suffixIcon: _paymentSearch.isNotEmpty
                        ? IconButton(
                            icon: Icon(LucideIcons.x, size: 16, color: AppTheme.textSecondary),
                            onPressed: () => setState(() => _paymentSearch = ''),
                          )
                        : null,
                  ),
                  onChanged: (value) => setState(() => _paymentSearch = value),
                ),
              ),
              const SizedBox(height: 12),
              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Todos',
                      count: _allPayments.length,
                      isSelected: _paymentFilter == 'all',
                      onTap: () => setState(() => _paymentFilter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Pagos',
                      count: _allPayments.where((p) => p.status == PaymentStatus.paid).length,
                      isSelected: _paymentFilter == 'paid',
                      color: AppTheme.success,
                      onTap: () => setState(() => _paymentFilter = 'paid'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Pendentes',
                      count: _pendingPayments.length,
                      isSelected: _paymentFilter == 'pending',
                      color: AppTheme.warning,
                      onTap: () => setState(() => _paymentFilter = 'pending'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Atrasados',
                      count: _overduePayments.length,
                      isSelected: _paymentFilter == 'overdue',
                      color: AppTheme.error,
                      onTap: () => setState(() => _paymentFilter = 'overdue'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Cancelados',
                      count: _allPayments.where((p) => p.status == PaymentStatus.cancelled).length,
                      isSelected: _paymentFilter == 'cancelled',
                      color: AppTheme.textDisabled,
                      onTap: () => setState(() => _paymentFilter = 'cancelled'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Payments list
        Expanded(
          child: filteredPayments.isEmpty
              ? PolishedEmptyState(
                  icon: LucideIcons.receipt,
                  title: 'Nenhum pagamento',
                  subtitle: _paymentSearch.isNotEmpty
                      ? 'Nenhum resultado para "$_paymentSearch"'
                      : 'Não há pagamentos nesta categoria',
                  accent: AppTheme.textSecondary,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: filteredPayments.length,
                  itemBuilder: (context, index) {
                    final payment = filteredPayments[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PaymentCard(
                        payment: payment,
                        formatCurrency: _formatCurrency,
                        onMarkPaid: payment.status != PaymentStatus.paid && payment.status != PaymentStatus.cancelled
                            ? () => _showMarkPaidDialog(payment)
                            : null,
                        onSendReminder: payment.status != PaymentStatus.paid && payment.status != PaymentStatus.cancelled
                            ? () => _sendReminder(payment)
                            : null,
                        onCancel: payment.status != PaymentStatus.paid && payment.status != PaymentStatus.cancelled
                            ? () => _cancelPayment(payment)
                            : null,
                        onReactivate: payment.status == PaymentStatus.cancelled
                            ? () => _reactivatePayment(payment)
                            : null,
                      ).entrance(index: index),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Reports tab - shows summary and link to detailed reports
  Widget _buildReportsTab() {
    final summary = _monthlySummary ?? {};
    final totalPaid = (summary['paid']?['value'] ?? 0).toDouble();
    final totalExpected = (summary['totalExpected'] ?? 0).toDouble();
    final rate = totalExpected > 0 ? (totalPaid / totalExpected * 100) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick summary
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
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(LucideIcons.pieChart, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resumo do Mês',
                            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            DateFormat("MMMM 'de' yyyy", 'pt_BR').format(_selectedMonth).capitalize(),
                            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recebido', style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(_formatCurrency(totalPaid), style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700, color: AppTheme.success)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Esperado', style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(_formatCurrency(totalExpected), style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Taxa', style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text('${rate.toStringAsFixed(0)}%', style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w700, 
                            color: rate >= 70 ? AppTheme.success : rate >= 40 ? AppTheme.warning : AppTheme.error,
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Detailed reports button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminFinancialReportsScreen(),
                ),
              ),
              icon: const Icon(LucideIcons.externalLink, size: 18),
              label: const Text('Ver Relatórios Detalhados'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Quick info cards
          Text(
            'Insights Rápidos',
            style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _QuickInsightCard(
            icon: LucideIcons.users,
            title: 'Alunos Pagantes',
            value: '${_plans.expand((p) => p.studentIds).toSet().length}',
            subtitle: 'com planos ativos',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PayingStudentsScreen(
                  students: _students,
                  plans: _plans,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _QuickInsightCard(
            icon: LucideIcons.package,
            title: 'Planos Ativos',
            value: '${_plans.where((p) => p.isActive).length}',
            subtitle: 'de ${_plans.length} total',
          ),
        ],
      ),
    );
  }

  // ============================================
  // DIALOGS
  // ============================================

  void _showGenerateTuitionsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GenerateTuitionsSheet(
        month: _selectedMonth,
        monthKey: _currentMonthKey,
        plans: _plans,
        students: _students,
        payments: _allPayments,
        onGenerate: (planId) async {
          try {
            final service = PaymentService(FirebaseService.academyId);
            final payments = await service.generateMonthlyTuitions(
              referenceMonth: _currentMonthKey,
              planId: planId,
            );
            if (mounted) {
              Navigator.pop(context);
              this.context.showSuccess('${payments.length} mensalidade${payments.length != 1 ? 's' : ''} gerada${payments.length != 1 ? 's' : ''}!');
              _loadData();
            }
          } catch (e) {
            if (mounted) {
              this.context.showError('Erro: $e');
            }
          }
        },
      ),
    );
  }

  void _showCreatePlanDialog() {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    final dueDayController = TextEditingController(text: '10');
    int? classesPerWeek;
    BillingPeriod billingPeriod = BillingPeriod.monthly;
    PaymentMethodPolicy paymentMethodPolicy = PaymentMethodPolicy.both;
    final recurringMonthsController = TextEditingController();

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
                  'Novo Plano',
                  style:
                      AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),

                _buildFormField('Nome do Plano', nameController, 'Ex: Mensal'),

                // Billing period selector
                _BillingPeriodSelector(
                  selected: billingPeriod,
                  onChanged: (p) => setDialogState(() => billingPeriod = p),
                ),
                const SizedBox(height: 16),

                _buildFormField(
                  billingPeriod == BillingPeriod.monthly
                      ? 'Valor (R\$)'
                      : 'Valor por ${billingPeriod.periodLabel.capitalize()} (R\$)',
                  valueController,
                  billingPeriod == BillingPeriod.monthly ? 'Ex: 150' : 'Ex: 400',
                  keyboardType: TextInputType.number,
                ),

                _buildFormField('Dia de Vencimento', dueDayController, '1-31',
                    keyboardType: TextInputType.number),

                const SizedBox(height: 4),
                _PaymentMethodPolicySelector(
                  selected: paymentMethodPolicy,
                  isMonthly: billingPeriod == BillingPeriod.monthly,
                  onChanged: (p) =>
                      setDialogState(() => paymentMethodPolicy = p),
                ),
                if (billingPeriod == BillingPeriod.monthly &&
                    paymentMethodPolicy == PaymentMethodPolicy.cardOnly)
                  _buildFormField(
                    'Duração da assinatura (meses; vazio = sem fim)',
                    recurringMonthsController,
                    'Ex: 8',
                    keyboardType: TextInputType.number,
                  ),
                const SizedBox(height: 16),

                Text(
                  'Aulas por Semana',
                  style:
                      AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _ClassesChip(
                      label: 'Ilimitado',
                      isSelected: classesPerWeek == null,
                      onTap: () =>
                          setDialogState(() => classesPerWeek = null),
                    ),
                    ...List.generate(5, (i) {
                      final count = i + 1;
                      return _ClassesChip(
                        label: '$count',
                        isSelected: classesPerWeek == count,
                        onTap: () =>
                            setDialogState(() => classesPerWeek = count),
                      );
                    }),
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
                          if (nameController.text.isEmpty ||
                              valueController.text.isEmpty) {
                            return;
                          }
                          try {
                            final service =
                                PlanService(FirebaseService.academyId);
                            final enteredValue =
                                double.tryParse(valueController.text) ?? 0;
                            await service.create(
                              name: nameController.text,
                              monthlyValue: billingPeriod == BillingPeriod.monthly
                                  ? enteredValue
                                  : enteredValue / billingPeriod.months,
                              periodValue: billingPeriod == BillingPeriod.monthly
                                  ? null
                                  : enteredValue,
                              billingPeriod: billingPeriod,
                              defaultDueDay:
                                  int.tryParse(dueDayController.text) ?? 10,
                              classesPerWeek: classesPerWeek,
                              paymentMethodPolicy: paymentMethodPolicy,
                              recurringMonths: (billingPeriod ==
                                          BillingPeriod.monthly &&
                                      paymentMethodPolicy ==
                                          PaymentMethodPolicy.cardOnly)
                                  ? int.tryParse(recurringMonthsController.text)
                                  : null,
                              billingDay: (billingPeriod ==
                                          BillingPeriod.monthly &&
                                      paymentMethodPolicy ==
                                          PaymentMethodPolicy.cardOnly)
                                  ? int.tryParse(dueDayController.text)
                                  : null,
                            );
                            if (mounted) {
                              Navigator.pop(context);
                              this.context.showSuccess('Plano criado!');
                              _loadData();
                            }
                          } catch (e) {
                            if (mounted) {
                              this.context.showError('Erro: $e');
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

  Widget _buildFormField(
    String label,
    TextEditingController controller,
    String hint, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: AppTheme.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditPlanDialog(Plan plan) {
    final nameController = TextEditingController(text: plan.name);
    final valueController = TextEditingController(
      text: plan.effectivePeriodValue.toStringAsFixed(2),
    );
    final dueDayController =
        TextEditingController(text: plan.defaultDueDay.toString());
    int? classesPerWeek = plan.classesPerWeek;
    bool isActive = plan.isActive;
    BillingPeriod billingPeriod = plan.billingPeriod;
    PaymentMethodPolicy paymentMethodPolicy = plan.paymentMethodPolicy;
    final recurringMonthsController = TextEditingController(
      text: (plan.recurringMonths ?? 0) > 0
          ? plan.recurringMonths.toString()
          : '',
    );

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
                  'Editar Plano',
                  style:
                      AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),

                _buildFormField('Nome do Plano', nameController, ''),

                _BillingPeriodSelector(
                  selected: billingPeriod,
                  onChanged: (p) => setDialogState(() => billingPeriod = p),
                ),
                const SizedBox(height: 16),

                _buildFormField(
                  billingPeriod == BillingPeriod.monthly
                      ? 'Valor (R\$)'
                      : 'Valor por ${billingPeriod.periodLabel.capitalize()} (R\$)',
                  valueController,
                  '',
                  keyboardType: TextInputType.number,
                ),

                _buildFormField('Dia de Vencimento', dueDayController, '',
                    keyboardType: TextInputType.number),

                const SizedBox(height: 4),
                _PaymentMethodPolicySelector(
                  selected: paymentMethodPolicy,
                  isMonthly: billingPeriod == BillingPeriod.monthly,
                  onChanged: (p) =>
                      setDialogState(() => paymentMethodPolicy = p),
                ),
                if (billingPeriod == BillingPeriod.monthly &&
                    paymentMethodPolicy == PaymentMethodPolicy.cardOnly)
                  _buildFormField(
                    'Duração da assinatura (meses; vazio = sem fim)',
                    recurringMonthsController,
                    'Ex: 8',
                    keyboardType: TextInputType.number,
                  ),
                const SizedBox(height: 16),

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
                      onChanged: (v) => setDialogState(() => isActive = v),
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
                            final service =
                                PlanService(FirebaseService.academyId);
                            final enteredValue =
                                double.tryParse(valueController.text) ?? 0;
                            await service.update(plan.id, {
                              'name': nameController.text,
                              'billingPeriod': billingPeriod.name,
                              'paymentMethodPolicy': paymentMethodPolicy.value,
                              'monthlyValue':
                                  billingPeriod == BillingPeriod.monthly
                                      ? enteredValue
                                      : enteredValue / billingPeriod.months,
                              'periodValue':
                                  billingPeriod == BillingPeriod.monthly
                                      ? null
                                      : enteredValue,
                              'defaultDueDay':
                                  int.tryParse(dueDayController.text) ?? 10,
                              'classesPerWeek': classesPerWeek,
                              'isActive': isActive,
                              // Recurring fields only meaningful for monthly +
                              // card-only plans; clear otherwise.
                              'recurringMonths': (billingPeriod ==
                                          BillingPeriod.monthly &&
                                      paymentMethodPolicy ==
                                          PaymentMethodPolicy.cardOnly)
                                  ? (int.tryParse(
                                          recurringMonthsController.text) ??
                                      0)
                                  : 0,
                              'billingDay': (billingPeriod ==
                                          BillingPeriod.monthly &&
                                      paymentMethodPolicy ==
                                          PaymentMethodPolicy.cardOnly)
                                  ? (int.tryParse(dueDayController.text) ?? 10)
                                  : null,
                            });
                            if (mounted) {
                              Navigator.pop(context);
                              this.context.showSuccess('Plano atualizado!');
                              _loadData();
                            }
                          } catch (e) {
                            if (mounted) {
                              this.context.showError('Erro: $e');
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

  void _showDeletePlanDialog(Plan plan) {
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
                final service = PlanService(FirebaseService.academyId);
                await service.delete(plan.id);
                if (mounted) {
                  Navigator.pop(context);
                  this.context.showSuccess('Plano excluido!');
                  _loadData();
                }
              } catch (e) {
                if (mounted) {
                  this.context.showError('Erro: $e');
                }
              }
            },
            child: const Text('Excluir', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  void _showManageStudentsDialog(Plan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ManageStudentsSheet(
        plan: plan,
        students: _students,
        onClose: () {
          Navigator.pop(context);
          _loadData();
        },
      ),
    );
  }

  void _showMarkPaidDialog(Payment payment) {
    PaymentMethod selectedMethod = PaymentMethod.pix;
    bool isSaving = false;

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
          padding: const EdgeInsets.all(24),
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
                'Confirmar Pagamento',
                style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),

              // Payment info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          payment.studentName.isNotEmpty
                              ? payment.studentName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: AppTheme.primary,
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
                            payment.studentName,
                            style: AppTheme.bodyMedium
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Vencimento: ${DateFormat('dd/MM').format(payment.dueDate)}',
                            style: AppTheme.bodySmall
                                .copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatCurrency(payment.value),
                      style: AppTheme.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Payment method
              Text(
                'Metodo de pagamento',
                style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PaymentMethod.values.map((method) {
                  final isSelected = selectedMethod == method;
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => selectedMethod = method),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.textPrimary
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.textPrimary
                              : AppTheme.divider,
                        ),
                      ),
                      child: Text(
                        method.label,
                        style: AppTheme.bodySmall.copyWith(
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Buttons
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
                      onPressed: isSaving ? null : () async {
                        setDialogState(() => isSaving = true);
                        try {
                          final service =
                              PaymentService(FirebaseService.academyId);
                          await service.markAsPaid(payment.id,
                              method: selectedMethod);
                          if (mounted) {
                            Navigator.pop(context);
                            Celebration.confetti(this.context);
                            this.context.showSuccess('Pagamento confirmado!');
                            _loadData();
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            this.context.showError('Erro: $e');
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
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
                          : const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  void _sendReminder(Payment payment) async {
    try {
      final studentService = StudentService(FirebaseService.academyId);
      final student = await studentService.getById(payment.studentId);
      if (student?.phone == null) {
        if (mounted) {
          context.showWarning('Aluno nao possui telefone cadastrado');
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

      if (mounted) {
        context.showInfo('Abrir WhatsApp: $whatsappLink');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    }
  }

  Future<void> _cancelPayment(Payment payment) async {
    try {
      final paymentService = PaymentService(FirebaseService.academyId);
      await paymentService.cancel(payment.id);
      if (mounted) {
        context.showSuccess('Pagamento cancelado');
        _loadData(); // Reload data
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao cancelar: $e');
      }
    }
  }

  Future<void> _reactivatePayment(Payment payment) async {
    try {
      final paymentService = PaymentService(FirebaseService.academyId);
      await paymentService.reactivate(payment.id);
      if (mounted) {
        context.showSuccess('Pagamento reativado');
        _loadData(); // Reload data
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao reativar: $e');
      }
    }
  }
}

// ============================================
// HELPER WIDGETS
// ============================================

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final String Function(double) formatCurrency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManageStudents;

  const _PlanCard({
    required this.plan,
    required this.formatCurrency,
    required this.onEdit,
    required this.onDelete,
    required this.onManageStudents,
  });

  @override
  Widget build(BuildContext context) {
    final expectedRevenue = plan.studentIds.fold(0.0, (sum, sid) => sum + plan.getStudentValue(sid));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: plan.isActive ? AppTheme.successLight : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plan.isActive ? 'Ativo' : 'Inativo',
                  style: AppTheme.labelSmall.copyWith(
                    color:
                        plan.isActive ? AppTheme.success : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEdit,
                child: const Icon(LucideIcons.pencil,
                    size: 18, color: AppTheme.textSecondary),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(LucideIcons.trash2,
                    size: 18, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Info chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: LucideIcons.dollarSign,
                label: plan.formattedValue,
              ),
              _InfoChip(
                icon: LucideIcons.calendarClock,
                label: plan.billingPeriod.label,
              ),
              _InfoChip(
                icon: LucideIcons.layoutGrid,
                label: plan.classesPerWeek == null
                    ? 'Ilimitado'
                    : '${plan.classesPerWeek}x/sem',
              ),
              _InfoChip(
                icon: LucideIcons.users,
                label: '${plan.studentCount} aluno${plan.studentCount != 1 ? 's' : ''}',
              ),
              if (plan.customValues.isNotEmpty)
                _InfoChip(
                  icon: LucideIcons.tag,
                  label: '${plan.customValues.length} c/ valor personalizado',
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Expected revenue
          Text(
            'Receita Esperada/${plan.billingPeriod.periodLabel.capitalize()}',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.success,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            formatCurrency(expectedRevenue),
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(height: 16),

          // Manage students button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onManageStudents,
              icon: const Icon(LucideIcons.users, size: 18),
              label: const Text('Gerenciar Alunos'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppTheme.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final Payment payment;
  final String Function(double) formatCurrency;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onSendReminder;
  final VoidCallback? onCancel;
  final VoidCallback? onReactivate;

  const _PaymentCard({
    required this.payment,
    required this.formatCurrency,
    this.onMarkPaid,
    this.onSendReminder,
    this.onCancel,
    this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = payment.isOverdue;
    final isPaid = payment.status == PaymentStatus.paid;
    final isCancelled = payment.status == PaymentStatus.cancelled;

    return Opacity(
      opacity: isCancelled ? 0.6 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isOverdue
              ? AppTheme.error.withValues(alpha: 0.05)
              : isPaid
                  ? AppTheme.success.withValues(alpha: 0.05)
                  : isCancelled
                      ? AppTheme.surfaceVariant
                      : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOverdue
                ? AppTheme.error.withValues(alpha: 0.2)
                : isPaid
                    ? AppTheme.success.withValues(alpha: 0.2)
                    : isCancelled
                        ? AppTheme.divider
                        : AppTheme.divider,
          ),
        ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isOverdue
                      ? AppTheme.error.withValues(alpha: 0.1)
                      : isPaid
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    payment.studentName.isNotEmpty
                        ? payment.studentName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: isOverdue
                          ? AppTheme.error
                          : isPaid
                              ? AppTheme.success
                              : AppTheme.textPrimary,
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
                      payment.studentName,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            payment.description ?? 'Mensalidade',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: const BoxDecoration(
                            color: AppTheme.textDisabled,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          'Venc: ${DateFormat('dd/MM').format(payment.dueDate)}',
                          style: AppTheme.labelSmall.copyWith(
                            color:
                                isOverdue ? AppTheme.error : AppTheme.textSecondary,
                            fontWeight:
                                isOverdue ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(payment.value),
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isPaid ? AppTheme.success : AppTheme.textPrimary,
                    ),
                  ),
                  // Cobrança indevida de assinatura: está 'paid' no gateway,
                  // mas é dinheiro a devolver — destaca em vez de 'Pago'.
                  if (isPaid && payment.isOvercharge)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Reembolso pendente',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else if (isPaid)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Pago',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (isCancelled)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.textDisabled.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Cancelado',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textDisabled,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              // Menu de ações
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 20),
                itemBuilder: (context) => [
                  if (!isPaid && !isCancelled)
                    const PopupMenuItem(
                      value: 'mark_paid',
                      child: Row(
                        children: [
                          Icon(LucideIcons.check, size: 16),
                          SizedBox(width: 8),
                          Text('Dar Baixa'),
                        ],
                      ),
                    ),
                  if (!isPaid && !isCancelled)
                    PopupMenuItem(
                      value: 'cancel',
                      child: Row(
                        children: [
                          Icon(LucideIcons.x, size: 16, color: AppTheme.error),
                          const SizedBox(width: 8),
                          Text('Cancelar', style: TextStyle(color: AppTheme.error)),
                        ],
                      ),
                    ),
                  if (isCancelled)
                    PopupMenuItem(
                      value: 'reactivate',
                      child: Row(
                        children: [
                          Icon(LucideIcons.rotateCcw, size: 16, color: AppTheme.success),
                          const SizedBox(width: 8),
                          Text('Reativar', style: TextStyle(color: AppTheme.success)),
                        ],
                      ),
                    ),
                  if (isPaid)
                    const PopupMenuItem(
                      value: 'none',
                      enabled: false,
                      child: Text('Sem ações disponíveis', style: TextStyle(color: AppTheme.textDisabled)),
                    ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'mark_paid':
                      onMarkPaid?.call();
                      break;
                    case 'cancel':
                      onCancel?.call();
                      break;
                    case 'reactivate':
                      onReactivate?.call();
                      break;
                  }
                },
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
                    icon: Icon(LucideIcons.messageSquare,
                        size: 16, color: AppTheme.textSecondary),
                    label: Text(
                      'Lembrar',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                  ),
                if (onMarkPaid != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onMarkPaid,
                    icon: const Icon(LucideIcons.check, size: 16),
                    label: const Text('Confirmar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      textStyle:
                          AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                    ),
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

class _ClassesChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ClassesChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.textPrimary : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
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

/// Manage Students Sheet - Improved UX
class _ManageStudentsSheet extends StatefulWidget {
  final Plan plan;
  final List<Student> students;
  final VoidCallback onClose;

  const _ManageStudentsSheet({
    required this.plan,
    required this.students,
    required this.onClose,
  });

  @override
  State<_ManageStudentsSheet> createState() => _ManageStudentsSheetState();
}

class _ManageStudentsSheetState extends State<_ManageStudentsSheet> {
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

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      result = result.where((s) =>
          s.fullName.toLowerCase().contains(_searchQuery) ||
          (s.nickname?.toLowerCase().contains(_searchQuery) ?? false)
      ).toList();
    }

    // Sort: enrolled first, then alphabetically
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
      final service = PlanService(FirebaseService.academyId);
      await service.toggleStudent(widget.plan.id, student.id);

      // Update local state optimistically
      setState(() {
        if (_enrolledIds.contains(student.id)) {
          _enrolledIds.remove(student.id);
        } else {
          _enrolledIds.add(student.id);
        }
      });
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
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title row
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
                      // Enrolled count badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.users,
                              size: 16,
                              color: AppTheme.success,
                            ),
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
                          horizontal: 16,
                          vertical: 14,
                        ),
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
                          Icon(
                            LucideIcons.userX,
                            size: 48,
                            color: AppTheme.textDisabled,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum aluno encontrado',
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: _filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = _filteredStudents[index];
                        final isInPlan = _enrolledIds.contains(student.id);

                        return _StudentToggleCard(
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
                12 + bottomPadding + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                  top: BorderSide(color: AppTheme.divider),
                ),
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

/// Student Toggle Card for managing plan enrollment
class _StudentToggleCard extends StatelessWidget {
  final Student student;
  final bool isInPlan;
  final bool isLoading;
  final VoidCallback onTap;

  const _StudentToggleCard({
    required this.student,
    required this.isInPlan,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: isLoading ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isInPlan
              ? AppTheme.success.withValues(alpha: 0.05)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isInPlan ? AppTheme.success : AppTheme.divider,
            width: isInPlan ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Toggle indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isInPlan ? AppTheme.success : AppTheme.surfaceVariant,
                shape: BoxShape.circle,
                border: isInPlan
                    ? null
                    : Border.all(color: AppTheme.divider, width: 2),
              ),
              child: isInPlan
                  ? const Icon(
                      LucideIcons.check,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isInPlan
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  student.fullName[0].toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: isInPlan ? AppTheme.success : AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.nickname ?? student.fullName.split(' ').first,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isInPlan ? AppTheme.success : AppTheme.textPrimary,
                    ),
                  ),
                  if (student.nickname != null)
                    Text(
                      student.fullName,
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Status text
            Text(
              isInPlan ? 'Vinculado' : 'Adicionar',
              style: AppTheme.labelSmall.copyWith(
                color: isInPlan ? AppTheme.success : AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Generate Tuitions Sheet
// ============================================
class _GenerateTuitionsSheet extends StatefulWidget {
  final DateTime month;
  final String monthKey;
  final List<Plan> plans;
  final List<Student> students;
  final List<Payment> payments;
  final Future<void> Function(String? planId) onGenerate;

  const _GenerateTuitionsSheet({
    required this.month,
    required this.monthKey,
    required this.plans,
    required this.students,
    required this.payments,
    required this.onGenerate,
  });

  @override
  State<_GenerateTuitionsSheet> createState() => _GenerateTuitionsSheetState();
}

class _GenerateTuitionsSheetState extends State<_GenerateTuitionsSheet> {
  String _filterType = 'all'; // 'all' or 'specific'
  String? _selectedPlanId;
  bool _generating = false;

  List<Plan> get _activePlans => widget.plans.where((p) => p.isActive).toList();

  // Calculate stats based on filter
  ({int totalInPlans, int alreadyHave, int willReceive}) get _stats {
    // Get students who already have tuition for this month
    final studentsWithTuition = widget.payments
        .where((p) => p.referenceMonth == widget.monthKey)
        .map((p) => p.studentId)
        .toSet();

    // Get plans to process based on filter
    final plansToProcess = _filterType == 'specific' && _selectedPlanId != null
        ? _activePlans.where((p) => p.id == _selectedPlanId).toList()
        : _activePlans;

    final studentsInPlans = <String>{};
    final studentsToGenerate = <String>{};

    for (final plan in plansToProcess) {
      for (final studentId in plan.studentIds) {
        final student = widget.students.cast<Student?>().firstWhere(
          (s) => s?.id == studentId && s?.status == StudentStatus.active,
          orElse: () => null,
        );
        if (student != null) {
          studentsInPlans.add(studentId);
          if (!studentsWithTuition.contains(studentId)) {
            studentsToGenerate.add(studentId);
          }
        }
      }
    }

    return (
      totalInPlans: studentsInPlans.length,
      alreadyHave: studentsInPlans.length - studentsToGenerate.length,
      willReceive: studentsToGenerate.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final monthLabel = DateFormat("MMMM 'de' yyyy", 'pt_BR').format(widget.month);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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

            // Title
            Text(
              'Gerar Mensalidades',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Gera apenas para alunos sem mensalidade do mes',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),

            // Month info
            Container(
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
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.calendar, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mes de referencia',
                        style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                      ),
                      Text(
                        monthLabel.capitalize(),
                        style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Filter section
            Text(
              'Filtrar por plano',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // All plans option
            _FilterOption(
              title: 'Todos os planos ativos',
              subtitle: 'Gera para todos os alunos em qualquer plano',
              isSelected: _filterType == 'all',
              onTap: () => setState(() {
                _filterType = 'all';
                _selectedPlanId = null;
              }),
            ),
            const SizedBox(height: 8),

            // Specific plan option
            _FilterOption(
              title: 'Plano especifico',
              subtitle: 'Gera apenas para alunos de um plano',
              isSelected: _filterType == 'specific',
              onTap: () => setState(() => _filterType = 'specific'),
            ),

            // Plan dropdown
            if (_filterType == 'specific') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.divider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedPlanId,
                    hint: const Text('Selecione o plano'),
                    items: _activePlans.map((plan) {
                      return DropdownMenuItem(
                        value: plan.id,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                plan.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${plan.studentCount} aluno${plan.studentCount != 1 ? 's' : ''}',
                                style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedPlanId = value),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Stats box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: stats.willReceive > 0
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: stats.willReceive > 0
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : AppTheme.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        stats.willReceive > 0 ? LucideIcons.checkCircle : LucideIcons.alertCircle,
                        color: stats.willReceive > 0 ? AppTheme.success : AppTheme.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stats.willReceive > 0
                              ? '${stats.willReceive} aluno${stats.willReceive != 1 ? 's' : ''} receberao mensalidade'
                              : 'Nenhuma mensalidade sera gerada',
                          style: AppTheme.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: stats.willReceive > 0 ? AppTheme.success : AppTheme.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatItem(
                          label: 'Total no${_filterType == 'specific' ? ' plano' : 's planos'}',
                          value: stats.totalInPlans.toString(),
                        ),
                      ),
                      Expanded(
                        child: _StatItem(
                          label: 'Ja possuem',
                          value: stats.alreadyHave.toString(),
                        ),
                      ),
                      Expanded(
                        child: _StatItem(
                          label: 'Novos',
                          value: stats.willReceive.toString(),
                          highlight: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Warning if specific plan not selected
            if (_filterType == 'specific' && _selectedPlanId == null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.info, color: AppTheme.info, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selecione um plano para continuar',
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.info),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Buttons
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
                    onPressed: _generating ||
                            stats.willReceive == 0 ||
                            (_filterType == 'specific' && _selectedPlanId == null)
                        ? null
                        : () async {
                            setState(() => _generating = true);
                            await widget.onGenerate(
                              _filterType == 'specific' ? _selectedPlanId : null,
                            );
                            // Parent pops the sheet on success; on error it stays
                            // open, so re-enable the button.
                            if (mounted) setState(() => _generating = false);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      disabledBackgroundColor: AppTheme.divider,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _generating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text('Gerar ${stats.willReceive}'),
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

class _FilterOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterOption({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primary,
                        ),
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
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
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

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatItem({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
        Text(
          value,
          style: AppTheme.titleSmall.copyWith(
            fontWeight: FontWeight.w600,
            color: highlight ? AppTheme.success : AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Compact stat card for the 3-column stats grid
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Filter chip for payment status filtering
class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.textPrimary;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.1) : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? chipColor : AppTheme.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTheme.labelSmall.copyWith(
                color: isSelected ? chipColor : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? chipColor : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick insight card for reports tab
class _QuickInsightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  const _QuickInsightCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                  ),
                  Row(
                    children: [
                      Text(
                        value,
                        style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        subtitle,
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(LucideIcons.chevronRight, size: 18, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _BillingPeriodSelector extends StatelessWidget {
  final BillingPeriod selected;
  final ValueChanged<BillingPeriod> onChanged;

  const _BillingPeriodSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Periodicidade',
          style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: BillingPeriod.values.map((period) {
            final isSelected = selected == period;
            return GestureDetector(
              onTap: () => onChanged(period),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.textPrimary
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  period.label,
                  style: AppTheme.labelMedium.copyWith(
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Picker for the accepted payment methods of a plan (PIX e Cartão / Somente
/// PIX / Somente Cartão). Shows a hint that monthly card-only plans become an
/// automatic recurring subscription.
class _PaymentMethodPolicySelector extends StatelessWidget {
  final PaymentMethodPolicy selected;
  final ValueChanged<PaymentMethodPolicy> onChanged;
  final bool isMonthly;

  const _PaymentMethodPolicySelector({
    required this.selected,
    required this.onChanged,
    required this.isMonthly,
  });

  @override
  Widget build(BuildContext context) {
    final showRecurringHint =
        isMonthly && selected == PaymentMethodPolicy.cardOnly;
    // Non-monthly (trimestral/anual) card-only is a one-off full-period charge,
    // NOT a recurring subscription — make that explicit so admins don't expect
    // auto-renewal.
    final showSinglePeriodHint =
        !isMonthly && selected == PaymentMethodPolicy.cardOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Formas de pagamento aceitas',
          style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: PaymentMethodPolicy.values.map((policy) {
            final isSelected = selected == policy;
            return GestureDetector(
              onTap: () => onChanged(policy),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.textPrimary
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  policy.label,
                  style: AppTheme.labelMedium.copyWith(
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (showRecurringHint) ...[
          const SizedBox(height: 8),
          Text(
            'Plano mensal somente no cartão vira assinatura automática: '
            'o aluno assina uma vez e o cartão é cobrado todo mês.',
            style: AppTheme.labelSmall.copyWith(color: AppTheme.primary),
          ),
        ],
        if (showSinglePeriodHint) ...[
          const SizedBox(height: 8),
          Text(
            'Cobrança única do período — NÃO é assinatura automática.',
            style: AppTheme.labelSmall.copyWith(color: AppTheme.warning),
          ),
        ],
      ],
    );
  }
}

// String extension for capitalize
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
