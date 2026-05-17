import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/attendance_dto.dart' as api_att;
import '../../api/dto/financial_dto.dart' as api_fin;
import '../../api/feature_flags.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';
import '../../providers/portal_providers.dart';

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

  // Retention data
  List<StudentRiskScore> _atRiskStudents = [];
  RetentionMetrics? _retentionMetrics;
  bool _isRetentionLoading = true;
  RiskLevel? _selectedRetentionFilter;
  final PageController _retentionPageController = PageController(
    viewportFraction: 0.92,
  );
  int _retentionCurrentPage = 0;

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadAllData();
    _loadRetentionData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _retentionPageController.dispose();
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

  Future<void> _loadRetentionData() async {
    setState(() => _isRetentionLoading = true);

    try {
      final academyId = FirebaseService.academyId;
      final studentService = StudentService(academyId);
      final collections = Collections(academyId);

      final allStudents = await studentService.getAll();

      // Fetch attendance from last 30 days
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final attendanceSnapshot = await collections.attendance
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo),
          )
          .get();

      final attendanceMap = <String, List<Map<String, dynamic>>>{};
      for (final doc in attendanceSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final studentId = data['studentId'] as String? ?? '';
        if (studentId.isNotEmpty) {
          attendanceMap.putIfAbsent(studentId, () => []);
          attendanceMap[studentId]!.add(data);
        }
      }

      // Fetch financials
      final financialsSnapshot = await collections.payments.get();
      final financialsMap = <String, List<Map<String, dynamic>>>{};
      for (final doc in financialsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final studentId = data['studentId'] as String? ?? '';
        if (studentId.isNotEmpty) {
          financialsMap.putIfAbsent(studentId, () => []);
          financialsMap[studentId]!.add(data);
        }
      }

      // Compute risk scores
      final retentionService = RetentionService();
      final riskScores = retentionService.getAtRiskStudents(
        allStudents,
        attendanceMap,
        financialsMap,
      );

      final metrics = retentionService.getRetentionMetrics(
        allStudents,
        riskScores,
      );

      // Compute average frequency
      final activeStudents = allStudents
          .where((s) => s.status == StudentStatus.active)
          .toList();
      double totalFrequency = 0;
      for (final student in activeStudents) {
        final records = attendanceMap[student.id] ?? [];
        final last30 = records.where((r) {
          final raw = r['date'];
          if (raw == null) return false;
          final date = raw is Timestamp ? raw.toDate() : DateTime.now();
          return now.difference(date).inDays <= 30;
        }).length;
        totalFrequency += last30;
      }
      final avgFrequency = activeStudents.isNotEmpty
          ? totalFrequency / activeStudents.length
          : 0.0;

      setState(() {
        _atRiskStudents = riskScores;
        _retentionMetrics = RetentionMetrics(
          totalAtRisk: metrics.totalAtRisk,
          atRiskPercentage: metrics.atRiskPercentage,
          averageFrequency: avgFrequency,
          paymentComplianceRate: metrics.paymentComplianceRate,
          distributionByRisk: metrics.distributionByRisk,
        );
        _isRetentionLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading retention data: $e');
      setState(() => _isRetentionLoading = false);
    }
  }

  List<StudentRiskScore> get _filteredRetentionStudents {
    if (_selectedRetentionFilter == null) return _atRiskStudents;
    return _atRiskStudents
        .where((s) => s.level == _selectedRetentionFilter)
        .toList();
  }

  Color _riskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return Colors.green;
      case RiskLevel.medium:
        return Colors.amber;
      case RiskLevel.high:
        return Colors.orange;
      case RiskLevel.critical:
        return Colors.red;
    }
  }

  List<String> _getSuggestedActions(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return [
          'Manter acompanhamento regular',
          'Incentivar participacao em eventos',
        ];
      case RiskLevel.medium:
        return [
          'Enviar mensagem de acompanhamento',
          'Verificar satisfacao com as aulas',
          'Oferecer aula experimental em outro horario',
        ];
      case RiskLevel.high:
        return [
          'Contato direto por telefone ou WhatsApp',
          'Agendar conversa presencial',
          'Oferecer flexibilidade no pagamento',
          'Avaliar mudanca de plano/horario',
        ];
      case RiskLevel.critical:
        return [
          'Contato urgente com o aluno',
          'Reuniao presencial com professor',
          'Oferecer condicoes especiais de retorno',
          'Avaliar renegociacao financeira',
          'Envolver lideranca da academia',
        ];
    }
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
    final flags = ref.read(tatamiFlagsProvider);

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

    Future<List<Attendance>> rangeFuture(DateTime from, DateTime to) async {
      if (flags.useTatamiAttendance) {
        try {
          // dateTo é exclusivo no contrato Tatami; getByDateRange legacy é
          // inclusivo end-of-day. Adiciona +1 dia para casar a janela.
          final exclusiveTo = DateTime(to.year, to.month, to.day)
              .add(const Duration(days: 1));
          final q = tatami.AttendanceQuery(
            academyId: academyId,
            filter: api_att.AttendanceFilter(
              dateFrom: DateTime(from.year, from.month, from.day),
              dateTo: exclusiveTo,
              limit: 1000,
            ),
          );
          ref.invalidate(tatami.tatamiAttendanceLegacyProvider(q));
          return await ref.read(
            tatami.tatamiAttendanceLegacyProvider(q).future,
          );
        } catch (_) {
          // fallback
        }
      }
      return attendanceService.getByDateRange(from, to);
    }

    // Sprint 5 — fetch current and previous month attendance in parallel.
    final ranges = await Future.wait([
      rangeFuture(startOfMonth, endOfMonth),
      rangeFuture(startOfLastMonth, endOfLastMonth),
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
    final flags = ref.read(tatamiFlagsProvider);

    final currentMonth = DateFormat('yyyy-MM').format(_selectedMonth);
    final lastMonth = DateFormat(
      'yyyy-MM',
    ).format(DateTime(_selectedMonth.year, _selectedMonth.month - 1));

    // Payments do mês — Tatami via tatamiPaymentsLegacyProvider
    // (janela [first, last+1) do _selectedMonth).
    Future<List<Payment>> currentMonthPaymentsFuture() async {
      if (flags.useTatamiFinancials) {
        try {
          final first =
              DateTime(_selectedMonth.year, _selectedMonth.month, 1);
          final last =
              DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
          final q = tatami.FinancialsQuery(
            academyId: academyId,
            filter: api_fin.FinancialFilter(
              dueFrom: first,
              dueTo: last,
              limit: 500,
            ),
          );
          ref.invalidate(tatami.tatamiPaymentsLegacyProvider(q));
          return await ref.read(
            tatami.tatamiPaymentsLegacyProvider(q).future,
          );
        } catch (_) {
          // fallback
        }
      }
      return paymentService.getByMonth(currentMonth);
    }

    // Sprint 5 — three independent reads in parallel (current summary,
    // last-month summary, current month payments). Os summaries
    // agregados client-side seguem legacy (sem equivalente shape no
    // tatamiMonthlyReportProvider).
    final results = await Future.wait<dynamic>([
      paymentService.getMonthlySummary(currentMonth),
      paymentService.getMonthlySummary(lastMonth),
      currentMonthPaymentsFuture(),
    ]);
    final summary = results[0] as Map<String, dynamic>;
    final lastMonthSummary = results[1] as Map<String, dynamic>;

    // Get payments for the selected month
    final monthPayments = results[2] as List<Payment>;
    final paidInMonth = monthPayments
        .where((p) => p.status.value == 'paid')
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
    final flags = ref.read(tatamiFlagsProvider);

    List<StoreOrder> orders;
    if (flags.useTatamiStore) {
      try {
        final q = tatami.OrdersQuery(academyId: academyId, limit: 500);
        ref.invalidate(tatami.tatamiStoreOrdersLegacyProvider(q));
        orders = await ref.read(
          tatami.tatamiStoreOrdersLegacyProvider(q).future,
        );
      } catch (_) {
        orders = await storeService.getOrders();
      }
    } else {
      orders = await storeService.getOrders();
    }

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
    final flags = ref.read(tatamiFlagsProvider);

    List<Student> students;
    if (flags.useTatamiReads) {
      try {
        final q = tatami.StudentsQuery(academyId: academyId);
        ref.invalidate(tatami.tatamiStudentsLegacyProvider(q));
        students = await ref.read(
          tatami.tatamiStudentsLegacyProvider(q).future,
        );
      } catch (_) {
        students = await studentService.getAll();
      }
    } else {
      students = await studentService.getAll();
    }

    // Separate by category
    final kids = students
        .where((s) => s.category == StudentCategory.kids)
        .toList();
    final adults = students
        .where((s) => s.category == StudentCategory.adult)
        .toList();

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
    for (final student in adults.where(
      (s) => s.status == StudentStatus.active,
    )) {
      final belt = student.currentBelt;
      adultsDistribution[belt] = (adultsDistribution[belt] ?? 0) + 1;
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
                          _buildRetentionTab(),
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
    // On retention tab, show only a refresh button
    if (_tabController.index == 3) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            const Spacer(),
            IconButton(
              onPressed: _loadRetentionData,
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
          Tab(text: 'Retencao'),
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
          ),
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
          ),
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
              child: _buildBeltChart(
                _kidsBeltDistribution,
                kidsBeltOrder,
                true,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Adults belt distribution
          if (activeAdults > 0)
            _ReportCard(
              title: 'Faixas Adulto',
              icon: LucideIcons.award,
              badge: '$activeAdults alunos',
              child: _buildBeltChart(
                _adultBeltDistribution,
                adultBeltOrder,
                false,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBeltChart(
    Map<String, int> distribution,
    List<String> order,
    bool isKids,
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

    // Filter out belts with 0 students
    final activeBelts = order
        .where((belt) => (distribution[belt] ?? 0) > 0)
        .toList();

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
                  style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
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

  // ============================================
  // Retention Tab
  // ============================================
  Widget _buildRetentionTab() {
    if (_isRetentionLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredRetentionStudents;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Carousel
          _buildRetentionKpiCards(),

          // Filter Chips
          _buildRetentionFilterChips(),

          // Student List
          if (filtered.isEmpty)
            SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.shieldCheck,
                      size: 64,
                      color: AppTheme.success.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _selectedRetentionFilter != null
                          ? 'Nenhum aluno neste nivel de risco'
                          : 'Nenhum aluno em risco!',
                      style: AppTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedRetentionFilter != null
                          ? 'Tente outro filtro'
                          : 'Otimo trabalho!',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filtered.map(
              (riskScore) => _buildRetentionStudentItem(riskScore),
            ),
        ],
      ),
    );
  }

  Widget _buildRetentionKpiCards() {
    if (_retentionMetrics == null) return const SizedBox.shrink();

    final dist = _retentionMetrics!.distributionByRisk;
    final total = _atRiskStudents.length;

    final pages = [
      // Page 1: Overview
      _RetentionCarouselPage(
        children: [
          _RetentionKpiTile(
            icon: LucideIcons.users,
            label: 'Alunos em Risco',
            value: '${_retentionMetrics!.totalAtRisk}',
            subtitle: 'de $total ativos',
          ),
          _RetentionKpiTile(
            icon: LucideIcons.trendingDown,
            label: 'Taxa de Evasao',
            value: '${_retentionMetrics!.atRiskPercentage.toStringAsFixed(1)}%',
            subtitle: 'score >= 25',
          ),
        ],
      ),
      // Page 2: Attendance & Payment
      _RetentionCarouselPage(
        children: [
          _RetentionKpiTile(
            icon: LucideIcons.calendarCheck,
            label: 'Frequencia Media',
            value: _retentionMetrics!.averageFrequency.toStringAsFixed(1),
            subtitle: 'presencas/mes',
          ),
          _RetentionKpiTile(
            icon: LucideIcons.checkCircle,
            label: 'Adimplencia',
            value:
                '${_retentionMetrics!.paymentComplianceRate.toStringAsFixed(0)}%',
            subtitle: 'em dia',
          ),
        ],
      ),
      // Page 3: Risk Distribution
      _RetentionCarouselPage(
        children: [
          _RetentionDistTile(label: 'Baixo', count: dist[RiskLevel.low] ?? 0),
          _RetentionDistTile(
            label: 'Medio',
            count: dist[RiskLevel.medium] ?? 0,
          ),
          _RetentionDistTile(label: 'Alto', count: dist[RiskLevel.high] ?? 0),
          _RetentionDistTile(
            label: 'Critico',
            count: dist[RiskLevel.critical] ?? 0,
          ),
        ],
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 120,
          child: PageView.builder(
            controller: _retentionPageController,
            itemCount: pages.length,
            onPageChanged: (i) => setState(() => _retentionCurrentPage = i),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: pages[index],
                ),
              );
            },
          ),
        ),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pages.length, (i) {
            final isActive = i == _retentionCurrentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.textPrimary
                    : AppTheme.textDisabled.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildRetentionFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: _selectedRetentionFilter == null,
              onSelected: (_) =>
                  setState(() => _selectedRetentionFilter = null),
              selectedColor: AppTheme.primary,
              labelStyle: TextStyle(
                color: _selectedRetentionFilter == null
                    ? Colors.white
                    : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            ...RiskLevel.values.map((level) {
              final isSelected = _selectedRetentionFilter == level;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(level.label),
                  selected: isSelected,
                  onSelected: (_) => setState(
                    () => _selectedRetentionFilter = isSelected ? null : level,
                  ),
                  selectedColor: _riskColor(level),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRetentionStudentItem(StudentRiskScore riskScore) {
    final color = _riskColor(riskScore.level);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          onTap: () => _showRetentionDetailBottomSheet(riskScore),
          leading: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
            ),
            child: CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              child: Text(
                riskScore.studentName.isNotEmpty
                    ? riskScore.studentName[0].toUpperCase()
                    : '?',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          title: Text(riskScore.studentName, style: AppTheme.titleMedium),
          subtitle: Text(
            'Score: ${riskScore.score} | '
            'Ultima presenca: ${riskScore.daysSinceLastAttendance} dias atras | '
            '${riskScore.overduePayments} pagamentos vencidos',
            style: AppTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Chip(
            label: Text(
              riskScore.level.label,
              style: AppTheme.labelSmall.copyWith(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
            backgroundColor: color,
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }

  void _showRetentionDetailBottomSheet(StudentRiskScore riskScore) {
    final color = _riskColor(riskScore.level);
    final actions = _getSuggestedActions(riskScore.level);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 3),
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: color.withOpacity(0.1),
                          child: Text(
                            riskScore.studentName.isNotEmpty
                                ? riskScore.studentName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: color,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              riskScore.studentName,
                              style: AppTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Score: ${riskScore.score}',
                                  style: AppTheme.titleMedium.copyWith(
                                    color: color,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Chip(
                                  label: Text(
                                    riskScore.level.label,
                                    style: AppTheme.labelSmall.copyWith(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                  backgroundColor: color,
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Risk Factors
                  Text('Fatores de Risco', style: AppTheme.headlineSmall),
                  const SizedBox(height: 12),

                  if (riskScore.factors.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.checkCircle,
                            color: AppTheme.success,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Nenhum fator de risco identificado',
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.success,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...riskScore.factors.map((factor) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${factor.score}',
                                  style: AppTheme.titleMedium.copyWith(
                                    color: color,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(factor.name, style: AppTheme.titleSmall),
                                  const SizedBox(height: 2),
                                  Text(
                                    factor.details,
                                    style: AppTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Peso: ${factor.weight}',
                              style: AppTheme.labelSmall,
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 24),

                  // Suggested Actions
                  Text('Acoes Sugeridas', style: AppTheme.headlineSmall),
                  const SizedBox(height: 12),

                  ...actions.map((action) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.arrowRight, size: 16, color: color),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(action, style: AppTheme.bodyMedium),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 24),

                  // Close button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fechar'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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

/// Carousel Page for retention KPI cards
class _RetentionCarouselPage extends StatelessWidget {
  final List<Widget> children;
  const _RetentionCarouselPage({required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(children: children.expand((w) => [Expanded(child: w)]).toList());
  }
}

/// KPI Tile for retention carousel
class _RetentionKpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;

  const _RetentionKpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTheme.headlineSmall.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textDisabled),
        ),
      ],
    );
  }
}

/// Distribution Tile for retention carousel
class _RetentionDistTile extends StatelessWidget {
  final String label;
  final int count;

  const _RetentionDistTile({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$count',
          style: AppTheme.headlineSmall.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
