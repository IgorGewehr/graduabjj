import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';

/// Kids belts order
const List<String> kidsBeltOrder = [
  'grey',
  'grey_white',
  'yellow',
  'yellow_white',
  'orange',
  'orange_white',
  'green',
  'green_white',
];

/// Adult belts order
const List<String> adultBeltOrder = [
  'white',
  'blue',
  'purple',
  'brown',
  'black',
];

/// Admin Reports Screen - Complete dashboard with separated stats
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  late TabController _tabController;

  // Attendance data
  Map<String, int> _attendanceByDay = {};
  int _totalAttendanceThisMonth = 0;
  int _totalAttendanceLastMonth = 0;
  double _averageAttendancePerDay = 0;
  int _peakDay = 0;
  String _peakDayName = '';

  // Financial data
  double _totalRevenue = 0;
  double _totalPending = 0;
  double _totalOverdue = 0;
  int _paidPayments = 0;
  int _pendingPayments = 0;
  int _overduePayments = 0;
  double _lastMonthRevenue = 0;
  double _averageTicket = 0;

  // Student data
  int _totalStudents = 0;
  int _activeStudents = 0;
  int _inactiveStudents = 0;
  int _injuredStudents = 0;
  int _kidsCount = 0;
  int _adultsCount = 0;
  Map<String, int> _kidsBeltDistribution = {};
  Map<String, int> _adultBeltDistribution = {};
  List<Student> _students = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadAttendanceData(),
        _loadFinancialData(),
        _loadStudentData(),
      ]);
    } catch (e) {
      debugPrint('Error loading reports: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadAttendanceData() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    final academyId = currentUser!.academyId!;
    final attendanceService = AttendanceService(academyId);

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);
    final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
    final endOfLastMonth = DateTime(now.year, now.month, 0);

    final attendances = await attendanceService.getByDateRange(startOfMonth, endOfMonth);
    final lastMonthAttendances = await attendanceService.getByDateRange(startOfLastMonth, endOfLastMonth);

    final byDay = <String, int>{};
    for (final a in attendances) {
      final dayName = DateFormat('EEEE', 'pt_BR').format(a.date);
      byDay[dayName] = (byDay[dayName] ?? 0) + 1;
    }

    // Find peak day
    String peakDayName = '';
    int peakCount = 0;
    byDay.forEach((day, count) {
      if (count > peakCount) {
        peakCount = count;
        peakDayName = day;
      }
    });

    // Calculate average per training day (weekdays with classes)
    final daysWithClasses = byDay.values.where((v) => v > 0).length;
    final average = daysWithClasses > 0 ? attendances.length / daysWithClasses : 0.0;

    setState(() {
      _attendanceByDay = byDay;
      _totalAttendanceThisMonth = attendances.length;
      _totalAttendanceLastMonth = lastMonthAttendances.length;
      _averageAttendancePerDay = average.toDouble();
      _peakDay = peakCount;
      _peakDayName = peakDayName;
    });
  }

  Future<void> _loadFinancialData() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    final academyId = currentUser!.academyId!;
    final paymentService = PaymentService(academyId);

    final now = DateTime.now();
    final currentMonth = DateFormat('yyyy-MM').format(now);
    final lastMonth = DateFormat('yyyy-MM').format(DateTime(now.year, now.month - 1));

    final summary = await paymentService.getMonthlySummary(currentMonth);
    final lastMonthSummary = await paymentService.getMonthlySummary(lastMonth);
    final pending = await paymentService.getPending();
    final overdue = await paymentService.getOverdue();
    final paid = await paymentService.getPaidThisMonth();

    // Calculate average ticket
    final avgTicket = paid.isNotEmpty
        ? paid.map((p) => p.value).reduce((a, b) => a + b) / paid.length
        : 0.0;

    // Calculate overdue total
    final overdueTotal = overdue.isNotEmpty
        ? overdue.map((p) => p.value).reduce((a, b) => a + b)
        : 0.0;

    setState(() {
      _totalRevenue = (summary['totalPaid'] ?? 0.0) as double;
      _totalPending = (summary['totalPending'] ?? 0.0) as double;
      _totalOverdue = overdueTotal;
      _paidPayments = paid.length;
      _pendingPayments = pending.length;
      _overduePayments = overdue.length;
      _lastMonthRevenue = (lastMonthSummary['totalPaid'] ?? 0.0) as double;
      _averageTicket = avgTicket;
    });
  }

  Future<void> _loadStudentData() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    final academyId = currentUser!.academyId!;
    final studentService = StudentService(academyId);

    final students = await studentService.getAll();

    // Separate by category
    final kids = students.where((s) => s.category == StudentCategory.kids).toList();
    final adults = students.where((s) => s.category == StudentCategory.adult).toList();

    // Kids belt distribution
    final kidsDistribution = <String, int>{};
    for (final belt in kidsBeltOrder) {
      kidsDistribution[belt] = 0;
    }
    for (final student in kids.where((s) => s.status == StudentStatus.active)) {
      final belt = student.currentBelt;
      kidsDistribution[belt] = (kidsDistribution[belt] ?? 0) + 1;
    }

    // Adults belt distribution
    final adultsDistribution = <String, int>{};
    for (final belt in adultBeltOrder) {
      adultsDistribution[belt] = 0;
    }
    for (final student in adults.where((s) => s.status == StudentStatus.active)) {
      final belt = student.currentBelt;
      adultsDistribution[belt] = (adultsDistribution[belt] ?? 0) + 1;
    }

    setState(() {
      _students = students;
      _totalStudents = students.length;
      _activeStudents = students.where((s) => s.status == StudentStatus.active).length;
      _inactiveStudents = students.where((s) => s.status == StudentStatus.inactive).length;
      _injuredStudents = students.where((s) => s.status == StudentStatus.injured).length;
      _kidsCount = kids.where((s) => s.status == StudentStatus.active).length;
      _adultsCount = adults.where((s) => s.status == StudentStatus.active).length;
      _kidsBeltDistribution = kidsDistribution;
      _adultBeltDistribution = adultsDistribution;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(child: _buildHeader()),

            // Tabs
            SliverToBoxAdapter(child: _buildTabBar()),

            // Content
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height - 200,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAttendanceTab(),
                          _buildFinancialTab(),
                          _buildStudentsTab(),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.calendar, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  DateFormat("MMMM 'de' yyyy", 'pt_BR').format(DateTime.now()),
                  style: AppTheme.labelMedium.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadAllData,
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

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppTheme.textPrimary,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.textSecondary,
        labelStyle: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w500),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Presencas'),
          Tab(text: 'Financeiro'),
          Tab(text: 'Alunos'),
        ],
      ),
    );
  }

  Widget _buildAttendanceTab() {
    // Calculate month-over-month change
    final change = _totalAttendanceLastMonth > 0
        ? ((_totalAttendanceThisMonth - _totalAttendanceLastMonth) / _totalAttendanceLastMonth * 100)
        : 0.0;
    final isPositive = change >= 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main stat card
          _buildMainStatCard(
            title: 'Total de Presencas',
            value: _totalAttendanceThisMonth.toString(),
            subtitle: 'neste mes',
            icon: LucideIcons.checkCircle,
            color: AppTheme.success,
            change: change,
            isPositive: isPositive,
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.trendingUp,
                  label: 'Media/Dia',
                  value: _averageAttendancePerDay.toStringAsFixed(1),
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.flame,
                  label: 'Pico',
                  value: '$_peakDay',
                  subtitle: _shortDayName(_peakDayName),
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Chart
          _ReportCard(
            title: 'Presencas por Dia',
            icon: LucideIcons.barChart3,
            child: Column(
              children: [
                'segunda-feira',
                'terca-feira',
                'quarta-feira',
                'quinta-feira',
                'sexta-feira',
                'sabado'
              ].map((day) {
                final value = _attendanceByDay[day] ?? 0;
                final maxValue = _attendanceByDay.values.fold(1, (a, b) => a > b ? a : b);
                final percentage = value / maxValue;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          _shortDayName(day),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: percentage,
                              child: Container(
                                height: 28,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.primary,
                                      AppTheme.primary.withValues(alpha: 0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 32,
                        child: Text(
                          value.toString(),
                          style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialTab() {
    final total = _totalRevenue + _totalPending + _totalOverdue;
    final revenueRate = total > 0 ? _totalRevenue / total : 0.0;
    final revenueChange = _lastMonthRevenue > 0
        ? ((_totalRevenue - _lastMonthRevenue) / _lastMonthRevenue * 100)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main stat card
          _buildMainStatCard(
            title: 'Receita do Mes',
            value: 'R\$ ${_formatCurrency(_totalRevenue)}',
            subtitle: '$_paidPayments pagamentos',
            icon: LucideIcons.dollarSign,
            color: AppTheme.success,
            change: revenueChange,
            isPositive: revenueChange >= 0,
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.clock,
                  label: 'Pendente',
                  value: 'R\$ ${_formatCurrency(_totalPending)}',
                  subtitle: '$_pendingPayments pagtos',
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.alertCircle,
                  label: 'Atrasado',
                  value: 'R\$ ${_formatCurrency(_totalOverdue)}',
                  subtitle: '$_overduePayments pagtos',
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Extra stats
          Row(
            children: [
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.receipt,
                  label: 'Ticket Medio',
                  value: 'R\$ ${_formatCurrency(_averageTicket)}',
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.percent,
                  label: 'Taxa Recebimento',
                  value: '${(revenueRate * 100).toStringAsFixed(0)}%',
                  color: revenueRate > 0.8
                      ? AppTheme.success
                      : (revenueRate > 0.5 ? AppTheme.warning : AppTheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Revenue breakdown
          _ReportCard(
            title: 'Resumo Financeiro',
            icon: LucideIcons.pieChart,
            child: Column(
              children: [
                _ProgressRow(
                  label: 'Recebido',
                  value: 'R\$ ${_formatCurrency(_totalRevenue)}',
                  percentage: total > 0 ? _totalRevenue / total : 0,
                  color: AppTheme.success,
                ),
                const SizedBox(height: 16),
                _ProgressRow(
                  label: 'Pendente',
                  value: 'R\$ ${_formatCurrency(_totalPending)}',
                  percentage: total > 0 ? _totalPending / total : 0,
                  color: AppTheme.warning,
                ),
                const SizedBox(height: 16),
                _ProgressRow(
                  label: 'Atrasado',
                  value: 'R\$ ${_formatCurrency(_totalOverdue)}',
                  percentage: total > 0 ? _totalOverdue / total : 0,
                  color: AppTheme.error,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Esperado',
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'R\$ ${_formatCurrency(total)}',
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsTab() {
    final activeKids = _kidsCount;
    final activeAdults = _adultsCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main stat card
          _buildMainStatCard(
            title: 'Total de Alunos',
            value: _totalStudents.toString(),
            subtitle: '$_activeStudents ativos',
            icon: LucideIcons.users,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.userCheck,
                  label: 'Ativos',
                  value: _activeStudents.toString(),
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.userX,
                  label: 'Inativos',
                  value: _inactiveStudents.toString(),
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.cross,
                  label: 'Lesionados',
                  value: _injuredStudents.toString(),
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category breakdown
          Row(
            children: [
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.baby,
                  label: 'Infantil',
                  value: activeKids.toString(),
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStatCard(
                  icon: LucideIcons.user,
                  label: 'Adulto',
                  value: activeAdults.toString(),
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Kids belt distribution
          if (activeKids > 0) ...[
            _ReportCard(
              title: 'Faixas Infantil',
              icon: LucideIcons.award,
              badge: '$activeKids alunos',
              child: _buildBeltChart(_kidsBeltDistribution, kidsBeltOrder, true),
            ),
            const SizedBox(height: 16),
          ],

          // Adults belt distribution
          if (activeAdults > 0)
            _ReportCard(
              title: 'Faixas Adulto',
              icon: LucideIcons.award,
              badge: '$activeAdults alunos',
              child: _buildBeltChart(_adultBeltDistribution, adultBeltOrder, false),
            ),
        ],
      ),
    );
  }

  Widget _buildBeltChart(Map<String, int> distribution, List<String> order, bool isKids) {
    final total = distribution.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Nenhum aluno nesta categoria'),
        ),
      );
    }

    // Filter out belts with 0 students
    final activeBelts = order.where((belt) => (distribution[belt] ?? 0) > 0).toList();

    return Column(
      children: activeBelts.map((belt) {
        final count = distribution[belt] ?? 0;
        final percentage = total > 0 ? count / total : 0.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              // Belt color indicator
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _getBeltColor(belt, isKids),
                  borderRadius: BorderRadius.circular(6),
                  border: belt == 'white' || belt.contains('white')
                      ? Border.all(color: AppTheme.divider, width: 1)
                      : null,
                  gradient: belt.contains('_')
                      ? LinearGradient(
                          colors: _getGradientColors(belt),
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 70,
                child: Text(
                  _getBeltLabel(belt, isKids),
                  style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: percentage,
                      child: Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: _getBeltDisplayColor(belt, isKids),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 50,
                child: Text(
                  '$count (${(percentage * 100).toStringAsFixed(0)}%)',
                  style: AppTheme.labelSmall.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMainStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    double? change,
    bool? isPositive,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (change != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (isPositive ?? false)
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (isPositive ?? false) ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                    size: 14,
                    color: (isPositive ?? false) ? AppTheme.success : AppTheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${change.abs().toStringAsFixed(0)}%',
                    style: AppTheme.labelSmall.copyWith(
                      color: (isPositive ?? false) ? AppTheme.success : AppTheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(0);
  }

  String _shortDayName(String fullName) {
    final shortNames = {
      'segunda-feira': 'Seg',
      'terca-feira': 'Ter',
      'quarta-feira': 'Qua',
      'quinta-feira': 'Qui',
      'sexta-feira': 'Sex',
      'sabado': 'Sab',
      'domingo': 'Dom',
    };
    return shortNames[fullName] ?? fullName;
  }

  String _getBeltLabel(String belt, bool isKids) {
    if (isKids) {
      const labels = {
        'grey': 'Cinza',
        'grey_white': 'Cinza/Br',
        'yellow': 'Amarela',
        'yellow_white': 'Amar/Br',
        'orange': 'Laranja',
        'orange_white': 'Larj/Br',
        'green': 'Verde',
        'green_white': 'Verde/Br',
        'white': 'Branca',
      };
      return labels[belt] ?? belt;
    } else {
      const labels = {
        'white': 'Branca',
        'blue': 'Azul',
        'purple': 'Roxa',
        'brown': 'Marrom',
        'black': 'Preta',
      };
      return labels[belt] ?? belt;
    }
  }

  Color _getBeltColor(String belt, bool isKids) {
    if (isKids) {
      const colors = {
        'grey': Color(0xFF9E9E9E),
        'grey_white': Color(0xFFE0E0E0),
        'yellow': Color(0xFFFFEB3B),
        'yellow_white': Color(0xFFFFF9C4),
        'orange': Color(0xFFFF9800),
        'orange_white': Color(0xFFFFE0B2),
        'green': Color(0xFF4CAF50),
        'green_white': Color(0xFFC8E6C9),
        'white': Color(0xFFF5F5F5),
      };
      return colors[belt] ?? Colors.grey;
    } else {
      const colors = {
        'white': Color(0xFFF5F5F5),
        'blue': Color(0xFF2563EB),
        'purple': Color(0xFF7C3AED),
        'brown': Color(0xFF92400E),
        'black': Color(0xFF171717),
      };
      return colors[belt] ?? Colors.grey;
    }
  }

  List<Color> _getGradientColors(String belt) {
    // For combined belts like grey_white, yellow_white, etc.
    if (belt.contains('_white')) {
      final baseBelt = belt.replaceAll('_white', '');
      return [_getBeltColor(baseBelt, true), const Color(0xFFF5F5F5)];
    }
    return [Colors.grey, Colors.grey];
  }

  Color _getBeltDisplayColor(String belt, bool isKids) {
    if (isKids) {
      const colors = {
        'grey': Color(0xFF757575),
        'grey_white': Color(0xFF9E9E9E),
        'yellow': Color(0xFFFBC02D),
        'yellow_white': Color(0xFFFFD54F),
        'orange': Color(0xFFF57C00),
        'orange_white': Color(0xFFFFB74D),
        'green': Color(0xFF388E3C),
        'green_white': Color(0xFF66BB6A),
        'white': Color(0xFF9E9E9E),
      };
      return colors[belt] ?? Colors.grey;
    } else {
      const colors = {
        'white': Color(0xFF9E9E9E),
        'blue': Color(0xFF2563EB),
        'purple': Color(0xFF7C3AED),
        'brown': Color(0xFF92400E),
        'black': Color(0xFF171717),
      };
      return colors[belt] ?? Colors.grey;
    }
  }
}

/// Mini Stat Card Widget
class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const _MiniStatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle ?? label,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Report Card Widget
class _ReportCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final String? badge;

  const _ReportCard({
    required this.title,
    required this.icon,
    required this.child,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppTheme.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badge!,
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

/// Progress Row for financial breakdown
class _ProgressRow extends StatelessWidget {
  final String label;
  final String value;
  final double percentage;
  final Color color;

  const _ProgressRow({
    required this.label,
    required this.value,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(label, style: AppTheme.bodySmall),
              ],
            ),
            Text(
              value,
              style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            FractionallySizedBox(
              widthFactor: percentage.clamp(0.0, 1.0),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
