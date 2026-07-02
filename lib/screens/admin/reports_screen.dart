import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand_tokens.dart';
import '../../core/responsive.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import '../../widgets/polish/polish.dart';

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

  // Month selection
  late DateTime _selectedMonth;

  // Attendance data
  Map<String, int> _attendanceByDay = {};
  int _totalAttendanceThisMonth = 0;
  int _totalAttendanceLastMonth = 0;
  double _averageAttendancePerDay = 0;
  int _peakDay = 0;
  String _peakDayName = '';

  // Financial data (tuitions)
  double _totalRevenue = 0;
  double _totalPending = 0;
  double _totalOverdue = 0;
  int _paidPayments = 0;
  int _pendingPayments = 0;
  int _overduePayments = 0;
  double _lastMonthRevenue = 0;
  double _averageTicket = 0;

  // Store data
  double _storeRevenue = 0;
  int _storeOrderCount = 0;
  double _storePending = 0;
  int _storePendingCount = 0;

  // Financial report data (from FinancialReportService)
  MonthlyReportData? _monthlyReport;
  List<MonthlyReportData> _historicalData = [];
  List<RevenueProjectionData> _projections = [];
  List<RevenueByPlanData> _revenueByPlan = [];
  List<FinancialRecommendationData> _recommendations = [];
  bool _isExporting = false;

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  // Student data
  int _totalStudents = 0;
  int _activeStudents = 0;
  int _inactiveStudents = 0;
  int _injuredStudents = 0;
  int _kidsCount = 0;
  int _adultsCount = 0;
  Map<String, int> _kidsBeltDistribution = {};
  Map<String, int> _adultBeltDistribution = {};
  // Distribuição por esporte (modalidades não-BJJ): {sportValue: {beltId: count}}.
  Map<String, Map<String, int>> _otherSportDistribution = {};

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
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
        _loadStoreData(),
        _loadStudentData(),
        _loadFinancialReportData(),
      ]);
    } catch (e) {
      debugPrint('Error loading reports: $e');
    }

    setState(() => _isLoading = false);
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    _loadAllData();
  }

  void _showMonthPicker() {
    final now = DateTime.now();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        int tempYear = _selectedMonth.year;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Year selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => setSheetState(() => tempYear--),
                        icon: const Icon(LucideIcons.chevronLeft, size: 20),
                      ),
                      Text(
                        '$tempYear',
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        onPressed: tempYear < now.year
                            ? () => setSheetState(() => tempYear++)
                            : null,
                        icon: const Icon(LucideIcons.chevronRight, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Month grid
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 4,
                      childAspectRatio: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: List.generate(12, (index) {
                        final month = index + 1;
                        final isSelected =
                            tempYear == _selectedMonth.year &&
                            month == _selectedMonth.month;
                        final isFuture = DateTime(
                          tempYear,
                          month,
                        ).isAfter(DateTime(now.year, now.month));
                        final monthNames = [
                          'Jan',
                          'Fev',
                          'Mar',
                          'Abr',
                          'Mai',
                          'Jun',
                          'Jul',
                          'Ago',
                          'Set',
                          'Out',
                          'Nov',
                          'Dez',
                        ];
                        return GestureDetector(
                          onTap: isFuture
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  setState(() {
                                    _selectedMonth = DateTime(tempYear, month);
                                  });
                                  _loadAllData();
                                },
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.textPrimary
                                  : isFuture
                                  ? AppTheme.surfaceVariant.withValues(
                                      alpha: 0.5,
                                    )
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              monthNames[index],
                              style: AppTheme.bodySmall.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : isFuture
                                    ? AppTheme.textSecondary.withValues(
                                        alpha: 0.4,
                                      )
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadAttendanceData() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    final academyId = currentUser!.academyId!;
    final attendanceService = AttendanceService(academyId);

    final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    );
    final startOfLastMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month - 1,
      1,
    );
    final endOfLastMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      0,
    );

    // Sprint 5 — fetch current and previous month attendance in parallel.
    final ranges = await Future.wait([
      attendanceService.getByDateRange(startOfMonth, endOfMonth),
      attendanceService.getByDateRange(startOfLastMonth, endOfLastMonth),
    ]);
    final attendances = ranges[0];
    final lastMonthAttendances = ranges[1];

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
    final average = daysWithClasses > 0
        ? attendances.length / daysWithClasses
        : 0.0;

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

    final currentMonth = DateFormat('yyyy-MM').format(_selectedMonth);
    final lastMonth = DateFormat(
      'yyyy-MM',
    ).format(DateTime(_selectedMonth.year, _selectedMonth.month - 1));

    // Sprint 5 — three independent reads in parallel (current summary,
    // last-month summary, current month payments).
    final results = await Future.wait<dynamic>([
      paymentService.getMonthlySummary(currentMonth),
      paymentService.getMonthlySummary(lastMonth),
      paymentService.getByMonth(currentMonth),
    ]);
    final summary = results[0] as Map<String, dynamic>;
    final lastMonthSummary = results[1] as Map<String, dynamic>;

    // Get payments for the selected month
    final monthPayments = results[2] as List<Payment>;
    // Receita confirmada: exclui cobranças indevidas a reembolsar
    // (subscription_overcharge) — pagas no gateway, mas não são receita.
    final paidInMonth = monthPayments
        .where((p) => p.status.value == 'paid' && !p.isOvercharge)
        .toList();
    final pendingInMonth = monthPayments
        .where((p) => p.status.value == 'pending')
        .toList();
    final overdueInMonth = monthPayments
        .where((p) => p.status.value == 'overdue')
        .toList();

    // Calculate average ticket
    final avgTicket = paidInMonth.isNotEmpty
        ? paidInMonth.map((p) => p.value).reduce((a, b) => a + b) /
              paidInMonth.length
        : 0.0;

    // Calculate overdue total
    final overdueTotal = overdueInMonth.isNotEmpty
        ? overdueInMonth.map((p) => p.value).reduce((a, b) => a + b)
        : 0.0;

    setState(() {
      _totalRevenue = (summary['totalPaid'] ?? 0.0) as double;
      _totalPending = (summary['totalPending'] ?? 0.0) as double;
      _totalOverdue = overdueTotal;
      _paidPayments = paidInMonth.length;
      _pendingPayments = pendingInMonth.length;
      _overduePayments = overdueInMonth.length;
      _lastMonthRevenue = (lastMonthSummary['totalPaid'] ?? 0.0) as double;
      _averageTicket = avgTicket;
    });
  }

  Future<void> _loadStoreData() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    final academyId = currentUser!.academyId!;
    final storeService = StoreService(academyId);

    final orders = await storeService.getOrders();

    // Filter orders by selected month
    final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
      23,
      59,
      59,
    );

    final monthOrders = orders.where((o) {
      final date = o.paidAt ?? o.createdAt;
      return date.isAfter(startOfMonth.subtract(const Duration(seconds: 1))) &&
          date.isBefore(endOfMonth.add(const Duration(seconds: 1)));
    }).toList();

    double revenue = 0;
    int paidCount = 0;
    double pending = 0;
    int pendingCount = 0;

    for (final order in monthOrders) {
      if (order.isPaid) {
        revenue += order.total;
        paidCount++;
      } else if (order.status == StoreOrderStatus.pendingPayment) {
        pending += order.total;
        pendingCount++;
      }
    }

    setState(() {
      _storeRevenue = revenue;
      _storeOrderCount = paidCount;
      _storePending = pending;
      _storePendingCount = pendingCount;
    });
  }

  Future<void> _loadStudentData() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    final academyId = currentUser!.academyId!;
    final studentService = StudentService(academyId);

    final students = await studentService.getAll();

    // Separate by category (contagem geral por categoria — todos os esportes)
    final kids = students
        .where((s) => s.category == StudentCategory.kids)
        .toList();
    final adults = students
        .where((s) => s.category == StudentCategory.adult)
        .toList();

    // Distribuição de faixas SEGMENTADA por esporte. BJJ mantém o recorte
    // kids/adulto (faixas distintas); demais esportes entram cada um na sua
    // própria seção. Cada aluno usa a faixa da modalidade primária (sportData).
    final kidsDistribution = <String, int>{};
    final adultsDistribution = <String, int>{};
    final otherSportDistribution = <String, Map<String, int>>{};
    for (final student
        in students.where((s) => s.status == StudentStatus.active)) {
      final sport = student.getPrimarySport();
      final grade = student.getGrade(sport);
      final belt = grade?.currentGrade ?? student.currentBelt;
      if (sport == SportId.bjj) {
        if (student.category == StudentCategory.kids) {
          kidsDistribution[belt] = (kidsDistribution[belt] ?? 0) + 1;
        } else {
          adultsDistribution[belt] = (adultsDistribution[belt] ?? 0) + 1;
        }
      } else {
        final m = otherSportDistribution[sport.value] ??= <String, int>{};
        m[belt] = (m[belt] ?? 0) + 1;
      }
    }

    setState(() {
      _totalStudents = students.length;
      _activeStudents = students
          .where((s) => s.status == StudentStatus.active)
          .length;
      _inactiveStudents = students
          .where((s) => s.status == StudentStatus.inactive)
          .length;
      _injuredStudents = students
          .where((s) => s.status == StudentStatus.injured)
          .length;
      _kidsCount = kids.where((s) => s.status == StudentStatus.active).length;
      _adultsCount = adults
          .where((s) => s.status == StudentStatus.active)
          .length;
      _kidsBeltDistribution = kidsDistribution;
      _adultBeltDistribution = adultsDistribution;
      _otherSportDistribution = otherSportDistribution;
    });
  }

  Future<void> _loadFinancialReportData() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    try {
      final academyId = currentUser!.academyId!;
      final service = FinancialReportService(academyId);
      await service.loadAll();

      final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
      final historical = service.getHistoricalData(months: 6);
      final projections = service.projectRevenue(monthsAhead: 3);
      final revenueByPlan = service.getRevenueByPlan(monthKey);

      final report = historical.firstWhere(
        (r) => r.month == monthKey,
        orElse: () => service.generateMonthlyReport(monthKey),
      );

      final recommendations = service.generateRecommendations(
        report,
        historical,
      );

      setState(() {
        _monthlyReport = report;
        _historicalData = historical;
        _projections = projections;
        _revenueByPlan = revenueByPlan;
        _recommendations = recommendations;
      });
    } catch (e) {
      debugPrint('Error loading financial report data: $e');
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _isExporting = true);

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final service = FinancialReportService(currentUser!.academyId!);
      final csvString = service.exportCSV(_historicalData);

      await Clipboard.setData(ClipboardData(text: csvString));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Relatorio copiado para a area de transferencia!',
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ContentBounded(
        maxWidth: kContentMaxWidthList,
        child: RefreshIndicator(
          onRefresh: _loadAllData,
          child: CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(child: _buildHeader()),

              // Tabs
              SliverToBoxAdapter(child: _buildTabBar()),

              // Content
              _isLoading
                  ? SliverFillRemaining(child: _buildLoadingState())
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
      ),
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: PolishSkeleton.shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skeletonBox(height: 96, radius: 16),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _skeletonBox(height: 64, radius: 12)),
                const SizedBox(width: 12),
                Expanded(child: _skeletonBox(height: 64, radius: 12)),
              ],
            ),
            const SizedBox(height: 24),
            _skeletonBox(height: 280, radius: 16),
          ],
        ),
      ),
    );
  }

  Widget _skeletonBox({
    double? width,
    required double height,
    double radius = 8,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildHeader() {
    final isCurrentMonth =
        _selectedMonth.year == DateTime.now().year &&
        _selectedMonth.month == DateTime.now().month;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          // Previous month
          GestureDetector(
            onTap: () => _changeMonth(-1),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.chevronLeft,
                size: 16,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Month/year chip - tappable
          GestureDetector(
            onTap: _showMonthPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.calendar,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat(
                      "MMMM 'de' yyyy",
                      'pt_BR',
                    ).format(_selectedMonth),
                    style: AppTheme.labelMedium.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    LucideIcons.chevronDown,
                    size: 12,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Next month
          GestureDetector(
            onTap: isCurrentMonth ? null : () => _changeMonth(1),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: isCurrentMonth
                    ? AppTheme.textSecondary.withValues(alpha: 0.3)
                    : AppTheme.textSecondary,
              ),
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
        unselectedLabelStyle: AppTheme.bodySmall.copyWith(
          fontWeight: FontWeight.w500,
        ),
        dividerColor: Colors.transparent,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
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
        ? ((_totalAttendanceThisMonth - _totalAttendanceLastMonth) /
              _totalAttendanceLastMonth *
              100)
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
          ).entrance(index: 0),
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
              children:
                  [
                    'segunda-feira',
                    'terca-feira',
                    'quarta-feira',
                    'quinta-feira',
                    'sexta-feira',
                    'sabado',
                  ].map((day) {
                    final value = _attendanceByDay[day] ?? 0;
                    final maxValue = _attendanceByDay.values.fold(
                      1,
                      (a, b) => a > b ? a : b,
                    );
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
                                          AppTheme.primary.withValues(
                                            alpha: 0.7,
                                          ),
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
                              style: AppTheme.bodySmall.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
            ),
          ).entrance(index: 2),
        ],
      ),
    );
  }

  Widget _buildFinancialTab() {
    final tuitionTotal = _totalRevenue + _totalPending + _totalOverdue;
    final tuitionRevenueRate = tuitionTotal > 0
        ? _totalRevenue / tuitionTotal
        : 0.0;
    final revenueChange = _lastMonthRevenue > 0
        ? ((_totalRevenue - _lastMonthRevenue) / _lastMonthRevenue * 100)
        : 0.0;
    final hasStore =
        _storeRevenue > 0 || _storeOrderCount > 0 || _storePendingCount > 0;

    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final isStorePublished = settings?.storePublished ?? false;
    final showStore = hasStore || isStorePublished;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Export CSV button
          if (_historicalData.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isExporting ? null : _exportCsv,
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.download, size: 16),
                label: const Text('Exportar CSV'),
              ),
            ),

          // =============================================
          // SECTION: Mensalidades
          // =============================================
          _buildSectionHeader(
            title: 'Mensalidades',
            icon: LucideIcons.creditCard,
          ),
          const SizedBox(height: 12),

          // KPI Cards (from FinancialReportService — tuition only)
          if (_monthlyReport != null) ...[
            _buildKpiCards(),
            const SizedBox(height: 16),

            // Status Distribution
            _buildStatusDistribution(),
            const SizedBox(height: 16),
          ],

          // Main stat card - tuition only
          _buildMainStatCard(
            title: 'Receita Mensalidades',
            value: 'R\$ ${_formatCurrency(_totalRevenue)}',
            subtitle: '$_paidPayments pagamentos recebidos',
            icon: LucideIcons.dollarSign,
            color: AppTheme.success,
            change: revenueChange,
            isPositive: revenueChange >= 0,
          ).entrance(index: 1),
          const SizedBox(height: 16),

          // Tuition stats
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
                  value: '${(tuitionRevenueRate * 100).toStringAsFixed(0)}%',
                  color: tuitionRevenueRate > 0.8
                      ? AppTheme.success
                      : (tuitionRevenueRate > 0.5
                            ? AppTheme.warning
                            : AppTheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tuition breakdown card
          _ReportCard(
            title: 'Detalhamento',
            icon: LucideIcons.pieChart,
            badge: '$_paidPayments recebidos',
            child: Column(
              children: [
                _ProgressRow(
                  label: 'Recebido',
                  value: 'R\$ ${_formatCurrency(_totalRevenue)}',
                  percentage: tuitionTotal > 0
                      ? _totalRevenue / tuitionTotal
                      : 0,
                  color: AppTheme.success,
                ),
                const SizedBox(height: 16),
                _ProgressRow(
                  label: 'Pendente',
                  value: 'R\$ ${_formatCurrency(_totalPending)}',
                  percentage: tuitionTotal > 0
                      ? _totalPending / tuitionTotal
                      : 0,
                  color: AppTheme.warning,
                ),
                const SizedBox(height: 16),
                _ProgressRow(
                  label: 'Atrasado',
                  value: 'R\$ ${_formatCurrency(_totalOverdue)}',
                  percentage: tuitionTotal > 0
                      ? _totalOverdue / tuitionTotal
                      : 0,
                  color: AppTheme.error,
                ),
              ],
            ),
          ),

          // =============================================
          // SECTION: Vendas da Loja
          // =============================================
          if (showStore) ...[
            const SizedBox(height: 32),
            _buildSectionHeader(
              title: 'Vendas da Loja',
              icon: LucideIcons.shoppingBag,
            ),
            const SizedBox(height: 12),

            if (hasStore) ...[
              // Store main stat
              _buildMainStatCard(
                title: 'Receita da Loja',
                value: 'R\$ ${_formatCurrency(_storeRevenue)}',
                subtitle: '$_storeOrderCount pedidos pagos',
                icon: LucideIcons.shoppingBag,
                color: AppTheme.primary,
              ),
              const SizedBox(height: 16),

              if (_storePendingCount > 0)
                Row(
                  children: [
                    Expanded(
                      child: _MiniStatCard(
                        icon: LucideIcons.checkCircle,
                        label: 'Recebido',
                        value: 'R\$ ${_formatCurrency(_storeRevenue)}',
                        subtitle: '$_storeOrderCount pedidos',
                        color: AppTheme.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniStatCard(
                        icon: LucideIcons.clock,
                        label: 'Aguardando Pagto',
                        value: 'R\$ ${_formatCurrency(_storePending)}',
                        subtitle: '$_storePendingCount pedidos',
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
            ] else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.shoppingBag,
                      size: 32,
                      color: AppTheme.textSecondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nenhuma venda neste mes',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // =============================================
          // SECTION: Resumo Geral (only if store has data)
          // =============================================
          if (hasStore) ...[
            const SizedBox(height: 32),
            _buildSectionHeader(
              title: 'Resumo Geral',
              icon: LucideIcons.barChart3,
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.textPrimary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Recebido',
                        style: AppTheme.bodyMedium.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        'R\$ ${_formatCurrency(_totalRevenue + _storeRevenue)}',
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppTheme.success,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Mensalidades',
                            style: AppTheme.bodySmall.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'R\$ ${_formatCurrency(_totalRevenue)}',
                        style: AppTheme.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Vendas da Loja',
                            style: AppTheme.bodySmall.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'R\$ ${_formatCurrency(_storeRevenue)}',
                        style: AppTheme.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // =============================================
          // SECTION: Analise Avancada
          // =============================================
          if (_historicalData.isNotEmpty ||
              _revenueByPlan.isNotEmpty ||
              _projections.isNotEmpty ||
              _recommendations.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildSectionHeader(
              title: 'Analise Avancada',
              icon: LucideIcons.trendingUp,
            ),
            const SizedBox(height: 12),
          ],

          // Historical Revenue Section
          if (_historicalData.isNotEmpty) ...[
            _buildHistoricalSection(),
            const SizedBox(height: 20),
          ],

          // Revenue by Plan
          if (_revenueByPlan.isNotEmpty) ...[
            _buildRevenueByPlan(),
            const SizedBox(height: 20),
          ],

          // Projections
          if (_projections.isNotEmpty) ...[
            _buildProjections(),
            const SizedBox(height: 20),
          ],

          // Recommendations
          if (_recommendations.isNotEmpty) _buildRecommendations(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required IconData icon}) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: AppTheme.divider)),
      ],
    );
  }

  // ============================================
  // Financial Report Widgets (from FinancialReportService)
  // ============================================

  Widget _buildKpiCards() {
    if (_monthlyReport == null) return const SizedBox.shrink();

    final report = _monthlyReport!;
    final nextMonthProjection = _projections.isNotEmpty
        ? _projections.first.projected
        : 0.0;

    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildKpiCard(
            icon: LucideIcons.dollarSign,
            label: 'Receita Confirmada',
            value: _currencyFormat.format(report.confirmedRevenue),
            color: AppTheme.success,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            icon: LucideIcons.percent,
            label: 'Taxa Cobranca',
            value: '${report.collectionRate.toStringAsFixed(1)}%',
            color: AppTheme.info,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            icon: report.growthMoM >= 0
                ? LucideIcons.trendingUp
                : LucideIcons.trendingDown,
            label: 'Crescimento MoM',
            value:
                '${report.growthMoM >= 0 ? '+' : ''}${report.growthMoM.toStringAsFixed(1)}%',
            color: report.growthMoM >= 0 ? AppTheme.success : AppTheme.error,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            icon: LucideIcons.target,
            label: 'Projecao Proximo Mes',
            value: _currencyFormat.format(nextMonthProjection),
            color: const Color(0xFF7C3AED),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.labelSmall.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTheme.titleMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDistribution() {
    if (_monthlyReport == null) return const SizedBox.shrink();

    final report = _monthlyReport!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Distribuicao por Status', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatusCard(
                label: 'Pago',
                amount: report.confirmedRevenue,
                count: report.paidCount,
                color: AppTheme.success,
                icon: LucideIcons.checkCircle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatusCard(
                label: 'Pendente',
                amount: report.pendingRevenue,
                count: report.pendingCount,
                color: AppTheme.warning,
                icon: LucideIcons.clock,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatusCard(
                label: 'Vencido',
                amount: report.overdueRevenue,
                count: report.overdueCount,
                color: AppTheme.error,
                icon: LucideIcons.alertCircle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard({
    required String label,
    required double amount,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(label, style: AppTheme.labelSmall.copyWith(color: color)),
          const SizedBox(height: 4),
          Text(
            _currencyFormat.format(amount),
            style: AppTheme.titleSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '$count pagamentos',
            style: AppTheme.labelSmall.copyWith(
              color: color.withOpacity(0.7),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricalSection() {
    if (_historicalData.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Historico de Receita', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _historicalData.map((data) {
                      final maxExpected = _historicalData
                          .map((d) => d.totalExpected)
                          .fold<double>(0, (a, b) => a > b ? a : b);
                      final barHeight = maxExpected > 0
                          ? (data.confirmedRevenue / maxExpected * 120).clamp(
                              4.0,
                              120.0,
                            )
                          : 4.0;
                      final expectedHeight = maxExpected > 0
                          ? (data.totalExpected / maxExpected * 120).clamp(
                              4.0,
                              120.0,
                            )
                          : 4.0;

                      final monthLabel = data.month.length >= 7
                          ? data.month.substring(5, 7)
                          : data.month;

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Container(
                                    width: 24,
                                    height: expectedHeight,
                                    decoration: BoxDecoration(
                                      color: AppTheme.divider,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  Container(
                                    width: 24,
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      color: AppTheme.success,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                monthLabel,
                                style: AppTheme.labelSmall.copyWith(
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Pago', style: AppTheme.labelSmall),
                    const SizedBox(width: 16),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Esperado', style: AppTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: 12),
                ...List.generate(_historicalData.length, (index) {
                  final data = _historicalData[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(data.month, style: AppTheme.bodySmall),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _currencyFormat.format(data.confirmedRevenue),
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _currencyFormat.format(data.totalExpected),
                            style: AppTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: LinearProgressIndicator(
                            value: data.collectionRate / 100,
                            backgroundColor: AppTheme.divider,
                            color: data.collectionRate >= 80
                                ? AppTheme.success
                                : data.collectionRate >= 50
                                ? AppTheme.warning
                                : AppTheme.error,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRevenueByPlan() {
    if (_revenueByPlan.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Receita por Plano', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text('Plano', style: AppTheme.labelMedium),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Alunos',
                          style: AppTheme.labelMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Receita',
                          style: AppTheme.labelMedium,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          '%',
                          style: AppTheme.labelMedium,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ...List.generate(_revenueByPlan.length, (index) {
                  final plan = _revenueByPlan[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            plan.planName,
                            style: AppTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${plan.studentCount}',
                            style: AppTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _currencyFormat.format(plan.totalRevenue),
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${plan.percentage.toStringAsFixed(0)}%',
                            style: AppTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProjections() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Projecoes', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _projections.map((projection) {
                final confidenceLabel = _confidenceLabel(projection.confidence);
                final confidenceColor = _confidenceColor(projection.confidence);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.target,
                        size: 16,
                        color: Color(0xFF7C3AED),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          projection.month,
                          style: AppTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        _currencyFormat.format(projection.projected),
                        style: AppTheme.titleMedium.copyWith(
                          color: const Color(0xFF7C3AED),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: confidenceColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          confidenceLabel,
                          style: AppTheme.labelSmall.copyWith(
                            color: confidenceColor,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _confidenceLabel(String confidence) {
    switch (confidence) {
      case 'high':
        return 'Alta';
      case 'medium':
        return 'Media';
      case 'low':
        return 'Baixa';
      default:
        return confidence;
    }
  }

  Color _confidenceColor(String confidence) {
    switch (confidence) {
      case 'high':
        return AppTheme.success;
      case 'medium':
        return AppTheme.warning;
      case 'low':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  Widget _buildRecommendations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recomendacoes', style: AppTheme.headlineSmall),
        const SizedBox(height: 12),
        ...List.generate(_recommendations.length, (index) {
          final rec = _recommendations[index];
          final color = _recommendationColor(rec.type);
          final icon = _recommendationIcon(rec.type);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 80,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 20, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rec.title, style: AppTheme.titleSmall),
                              const SizedBox(height: 4),
                              Text(rec.description, style: AppTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _recommendationColor(String type) {
    switch (type) {
      case 'success':
        return AppTheme.success;
      case 'warning':
        return AppTheme.warning;
      case 'error':
        return AppTheme.error;
      case 'info':
        return AppTheme.info;
      default:
        return AppTheme.textSecondary;
    }
  }

  IconData _recommendationIcon(String type) {
    switch (type) {
      case 'success':
        return LucideIcons.checkCircle;
      case 'warning':
        return LucideIcons.alertTriangle;
      case 'error':
        return LucideIcons.alertCircle;
      case 'info':
        return LucideIcons.info;
      default:
        return LucideIcons.info;
    }
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
          ).entrance(index: 0),
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

          // Faixas — BJJ Infantil
          if (_kidsBeltDistribution.values.fold<int>(0, (a, b) => a + b) >
              0) ...[
            _ReportCard(
              title: 'Faixas Infantil (BJJ)',
              icon: LucideIcons.award,
              badge:
                  '${_kidsBeltDistribution.values.fold<int>(0, (a, b) => a + b)} alunos',
              child: _buildBeltChart(_kidsBeltDistribution, SportId.bjj, 'kids'),
            ),
            const SizedBox(height: 16),
          ],

          // Faixas — BJJ Adulto
          if (_adultBeltDistribution.values.fold<int>(0, (a, b) => a + b) >
              0) ...[
            _ReportCard(
              title: 'Faixas Adulto (BJJ)',
              icon: LucideIcons.award,
              badge:
                  '${_adultBeltDistribution.values.fold<int>(0, (a, b) => a + b)} alunos',
              child:
                  _buildBeltChart(_adultBeltDistribution, SportId.bjj, 'adult'),
            ),
            const SizedBox(height: 16),
          ],

          // Faixas — demais modalidades (uma seção por esporte)
          ..._otherSportDistribution.entries.map((entry) {
            final sportId = SportId.fromString(entry.key);
            final dist = entry.value;
            final t = dist.values.fold<int>(0, (a, b) => a + b);
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ReportCard(
                title: 'Faixas — ${getSport(sportId).label}',
                icon: LucideIcons.award,
                badge: '$t alunos',
                child: _buildBeltChart(dist, sportId, 'adult'),
              ),
            );
          }),

          // Atalho para a tela de Retencao
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => context.push('/admin/retencao'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Brand.blood.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Brand.blood.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Brand.blood.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.heartPulse,
                      color: Brand.blood,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Ver Retencao',
                      style: AppTheme.titleSmall.copyWith(
                        color: Brand.blood,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    LucideIcons.arrowRight,
                    size: 16,
                    color: Brand.blood,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeltChart(
    Map<String, int> distribution,
    SportId sportId,
    String category,
  ) {
    final total = distribution.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Nenhum aluno nesta categoria'),
        ),
      );
    }

    // Ordem das faixas pela escada do esporte (ids canônicos). Muay Thai tem
    // DOIS sistemas (CBMT e CBMTT) e a academia pode ter alunos em qualquer um,
    // então concatenamos as duas escadas pra ordenar ambos. Faixas fora da
    // escada (legado/órfão) vão ao final; faixas sem alunos são filtradas.
    final orderIds = <String>[
      if (sportId == SportId.muaythai) ...[
        ...getGradesForSport(sportId, muaythaiVariant: muaythaiVariantCbmt)
            .map((g) => g.id),
        ...getGradesForSport(sportId, muaythaiVariant: muaythaiVariantCbmtt)
            .map((g) => g.id),
      ] else
        ...getGradesForSport(sportId, category: category).map((g) => g.id),
    ];
    final activeBelts = <String>[
      ...orderIds.where((id) => (distribution[id] ?? 0) > 0),
      ...distribution.keys.where(
          (b) => (distribution[b] ?? 0) > 0 && !orderIds.contains(b)),
    ];

    return Column(
      children: activeBelts.map((belt) {
        final count = distribution[belt] ?? 0;
        final percentage = total > 0 ? count / total : 0.0;
        final color = getGradeColor(sportId, belt);
        final light = color.computeLuminance() > 0.85;
        final barColor = light ? const Color(0xFF9E9E9E) : color;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              // Belt color indicator
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: light
                      ? Border.all(color: AppTheme.divider, width: 1)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 70,
                child: Text(
                  getGradeLabel(sportId, belt),
                  style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
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
                          color: barColor,
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
                  style: AppTheme.labelSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTheme.headlineMedium.copyWith(
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
                    (isPositive ?? false)
                        ? LucideIcons.trendingUp
                        : LucideIcons.trendingDown,
                    size: 14,
                    color: (isPositive ?? false)
                        ? AppTheme.success
                        : AppTheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${change.abs().toStringAsFixed(0)}%',
                    style: AppTheme.labelSmall.copyWith(
                      color: (isPositive ?? false)
                          ? AppTheme.success
                          : AppTheme.error,
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
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
                  style: AppTheme.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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

