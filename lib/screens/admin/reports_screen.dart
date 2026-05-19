import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/attendance_dto.dart' as api_att;
import '../../api/dto/financial_dto.dart' as api_fin;
import '../../api/repositories.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/financial_report_provider.dart';
import '../../services/services.dart';

import 'reports/attendance_tab.dart';
import 'reports/financial_tab.dart';
import 'reports/students_tab.dart';
import 'reports/retention_tab.dart';

/// Admin Reports Screen — thin coordinator widget
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
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));

      // --- Students via Tatami ---
      Future<List<Student>> studentsFuture() async {
        final q = tatami.StudentsQuery(academyId: academyId);
        ref.invalidate(tatami.tatamiStudentsLegacyProvider(q));
        return ref.read(tatami.tatamiStudentsLegacyProvider(q).future);
      }

      // --- Attendance (last 30 days) via Tatami ---
      Future<Map<String, List<Map<String, dynamic>>>>
          attendanceMapFuture() async {
        final q = tatami.AttendanceQuery(
          academyId: academyId,
          filter: api_att.AttendanceFilter(
            dateFrom: thirtyDaysAgo,
            limit: 500,
          ),
        );
        ref.invalidate(tatami.tatamiAttendanceProvider(q));
        final page = await ref.read(tatami.tatamiAttendanceProvider(q).future);
        final m = <String, List<Map<String, dynamic>>>{};
        for (final a in page.items) {
          m.putIfAbsent(a.studentId, () => []).add({
            'studentId': a.studentId,
            'date': a.date,
          });
        }
        return m;
      }

      // --- Financials via Tatami ---
      Future<Map<String, List<Map<String, dynamic>>>>
          financialsMapFuture() async {
        final q = tatami.FinancialsQuery(
          academyId: academyId,
          filter: const api_fin.FinancialFilter(limit: 500),
        );
        ref.invalidate(tatami.tatamiFinancialsProvider(q));
        final page =
            await ref.read(tatami.tatamiFinancialsProvider(q).future);
        final m = <String, List<Map<String, dynamic>>>{};
        for (final f in page.items) {
          m.putIfAbsent(f.studentId, () => []).add({
            'studentId': f.studentId,
            'status': f.status.wire,
            'dueDate': f.dueDate,
          });
        }
        return m;
      }

      // Fan-out — students + attendance + financials são independentes
      final results = await Future.wait<dynamic>([
        studentsFuture(),
        attendanceMapFuture(),
        financialsMapFuture(),
      ]);
      final allStudents = results[0] as List<Student>;
      final attendanceMap =
          results[1] as Map<String, List<Map<String, dynamic>>>;
      final financialsMap =
          results[2] as Map<String, List<Map<String, dynamic>>>;

      // Compute risk scores (client-side — gap BE Sprint B)
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

      // Compute average frequency from attendance data
      final activeStudents =
          allStudents.where((s) => s.status == StudentStatus.active).toList();
      double totalFrequency = 0;
      for (final student in activeStudents) {
        final records = attendanceMap[student.id] ?? [];
        final last30 = records.where((r) {
          final raw = r['date'];
          if (raw == null) return false;
          final date = raw is DateTime ? raw : DateTime.now();
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
                        const monthNames = [
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
      return ref.read(tatami.tatamiAttendanceLegacyProvider(q).future);
    }

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
    byDay.forEach((day, dayCount) {
      if (dayCount > peakCount) {
        peakCount = dayCount;
        peakDayName = day;
      }
    });

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

    final currentMonth = DateFormat('yyyy-MM').format(_selectedMonth);
    final lastMonth = DateFormat(
      'yyyy-MM',
    ).format(DateTime(_selectedMonth.year, _selectedMonth.month - 1));

    Future<List<Payment>> currentMonthPaymentsFuture() async {
      final first = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final last = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
      final q = tatami.FinancialsQuery(
        academyId: academyId,
        filter: api_fin.FinancialFilter(
          dueFrom: first,
          dueTo: last,
          limit: 500,
        ),
      );
      ref.invalidate(tatami.tatamiPaymentsLegacyProvider(q));
      return ref.read(tatami.tatamiPaymentsLegacyProvider(q).future);
    }

    final summaryCurrentKey = tatami.AcademyMonth(
      academyId: academyId,
      month: currentMonth,
    );
    final summaryLastKey = tatami.AcademyMonth(
      academyId: academyId,
      month: lastMonth,
    );
    ref.invalidate(tatami.tatamiMonthlyReportLegacyProvider(summaryCurrentKey));
    ref.invalidate(tatami.tatamiMonthlyReportLegacyProvider(summaryLastKey));
    final results = await Future.wait<dynamic>([
      ref.read(
        tatami.tatamiMonthlyReportLegacyProvider(summaryCurrentKey).future,
      ),
      ref.read(
        tatami.tatamiMonthlyReportLegacyProvider(summaryLastKey).future,
      ),
      currentMonthPaymentsFuture(),
    ]);
    final summary = results[0] as Map<String, dynamic>;
    final lastMonthSummary = results[1] as Map<String, dynamic>;

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

    final avgTicket = paidInMonth.isNotEmpty
        ? paidInMonth.map((p) => p.value).reduce((a, b) => a + b) /
              paidInMonth.length
        : 0.0;

    final overdueTotal = overdueInMonth.isNotEmpty
        ? overdueInMonth.map((p) => p.value).reduce((a, b) => a + b)
        : 0.0;

    double readMapValue(Map<String, dynamic> s, String key) {
      final entry = s[key];
      if (entry is Map<String, dynamic>) {
        final v = entry['value'];
        return v is num ? v.toDouble() : 0.0;
      }
      return 0.0;
    }

    setState(() {
      _totalRevenue = readMapValue(summary, 'paid');
      _totalPending = readMapValue(summary, 'pending');
      _totalOverdue = overdueTotal;
      _paidPayments = paidInMonth.length;
      _pendingPayments = pendingInMonth.length;
      _overduePayments = overdueInMonth.length;
      _lastMonthRevenue = readMapValue(lastMonthSummary, 'paid');
      _averageTicket = avgTicket;
    });
  }

  Future<void> _loadStoreData() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    final academyId = currentUser!.academyId!;
    final q = tatami.OrdersQuery(academyId: academyId, limit: 500);
    ref.invalidate(tatami.tatamiStoreOrdersLegacyProvider(q));
    final orders =
        await ref.read(tatami.tatamiStoreOrdersLegacyProvider(q).future);

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
    final q = tatami.StudentsQuery(academyId: academyId);
    ref.invalidate(tatami.tatamiStudentsLegacyProvider(q));
    final students =
        await ref.read(tatami.tatamiStudentsLegacyProvider(q).future);

    final kids = students
        .where((s) => s.category == StudentCategory.kids)
        .toList();
    final adults = students
        .where((s) => s.category == StudentCategory.adult)
        .toList();

    final kidsDistribution = <String, int>{};
    for (final belt in kidsBeltOrder) {
      kidsDistribution[belt] = 0;
    }
    for (final student in kids.where((s) => s.status == StudentStatus.active)) {
      final belt = student.currentBelt;
      kidsDistribution[belt] = (kidsDistribution[belt] ?? 0) + 1;
    }

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
      final repo = ref.read(financialRepoProvider);
      final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
      final now = DateTime.now();

      // Last 6 months in chronological order (oldest first)
      final months = List.generate(6, (i) {
        final d = DateTime(now.year, now.month - (5 - i), 1);
        return '${d.year}-${d.month.toString().padLeft(2, '0')}';
      });

      final apiReports = await Future.wait(
        months.map((m) => repo.getMonthlyReport(academyId, month: m)),
      );

      final historical = <MonthlyReportData>[];
      for (int i = 0; i < apiReports.length; i++) {
        final prevRevenue = i == 0
            ? 0.0
            : (double.tryParse(apiReports[i - 1].totalRevenue) ?? 0.0);
        final api = apiReports[i];
        final confirmedRevenue =
            double.tryParse(api.totalRevenue) ?? 0.0;
        final outstanding = double.tryParse(api.outstanding) ?? 0.0;
        final totalExpected = confirmedRevenue + outstanding;
        final collectionRate = totalExpected > 0
            ? (confirmedRevenue / totalExpected) * 100
            : 0.0;
        final growthMoM = prevRevenue > 0
            ? ((confirmedRevenue - prevRevenue) / prevRevenue) * 100
            : 0.0;
        historical.add(MonthlyReportData(
          month: months[i],
          confirmedRevenue: confirmedRevenue,
          pendingRevenue: outstanding,
          overdueRevenue: 0.0,
          totalExpected: totalExpected,
          collectionRate: collectionRate,
          growthMoM: growthMoM,
          totalPayments: api.paidCount + api.pendingCount + api.overdueCount,
          paidCount: api.paidCount,
          pendingCount: api.pendingCount,
          overdueCount: api.overdueCount,
        ));
      }

      // Revenue projections (linear regression — kept client-side)
      final revenues = historical.map((r) => r.confirmedRevenue).toList();
      final sum = revenues.fold<double>(0, (a, v) => a + v);
      final avg = revenues.isNotEmpty ? sum / revenues.length : 0.0;
      final n = revenues.length;
      double trend = 0;
      if (n > 1) {
        double sX = 0, sY = 0, sXY = 0, sX2 = 0;
        for (int i = 0; i < n; i++) {
          sX += i; sY += revenues[i]; sXY += i * revenues[i]; sX2 += i * i;
        }
        final denom = n * sX2 - sX * sX;
        if (denom != 0) trend = (n * sXY - sX * sY) / denom;
      }
      final projections = List.generate(3, (i) {
        final fd = DateTime(now.year, now.month + i + 1, 1);
        final ms =
            '${fd.year}-${fd.month.toString().padLeft(2, '0')}';
        final projected = avg + trend * (n + i);
        return RevenueProjectionData(
          month: ms,
          projected: projected < 0 ? 0 : projected,
          confidence: 'medium',
          basis: 'Media movel de $n meses com tendencia linear',
        );
      });

      // Report for selected month
      MonthlyReportData report;
      final inWindow = historical.where((r) => r.month == monthKey);
      if (inWindow.isNotEmpty) {
        report = inWindow.first;
      } else {
        // On-demand fetch if outside the 6-month window
        final api = await repo.getMonthlyReport(academyId, month: monthKey);
        final c = double.tryParse(api.totalRevenue) ?? 0.0;
        final o = double.tryParse(api.outstanding) ?? 0.0;
        final te = c + o;
        report = MonthlyReportData(
          month: monthKey,
          confirmedRevenue: c,
          pendingRevenue: o,
          overdueRevenue: 0.0,
          totalExpected: te,
          collectionRate: te > 0 ? (c / te) * 100 : 0.0,
          growthMoM: 0.0,
          totalPayments: api.paidCount + api.pendingCount + api.overdueCount,
          paidCount: api.paidCount,
          pendingCount: api.pendingCount,
          overdueCount: api.overdueCount,
        );
      }

      // Revenue by plan (billing type) — fetched from individual financials
      final parts = monthKey.split('-');
      final yr = int.parse(parts[0]);
      final mn = int.parse(parts[1]);
      final page = await repo.list(
        academyId,
        filter: api_fin.FinancialFilter(
          dueFrom: DateTime(yr, mn, 1),
          dueTo: DateTime(yr, mn + 1, 1),
          limit: 500,
        ),
      );

      final groupRev = <String, double>{};
      final groupStudents = <String, Set<String>>{};
      for (final f in page.items) {
        if (f.status == api_fin.ApiFinancialStatus.cancelled) continue;
        final key = f.type.wire;
        final amount = double.tryParse(f.amount) ?? 0.0;
        groupRev[key] = (groupRev[key] ?? 0) + amount;
        groupStudents.putIfAbsent(key, () => <String>{});
        groupStudents[key]!.add(f.studentId);
      }
      final grandTotal = groupRev.values.fold<double>(0, (a, v) => a + v);
      final revenueByPlan = groupRev.entries.map((e) {
        const labels = {
          'monthly_tuition': 'Mensalidade',
          'uniform': 'Kimono',
          'seminar': 'Seminario',
          'graduation': 'Graduacao',
          'competition': 'Competicao',
        };
        return RevenueByPlanData(
          planId: e.key,
          planName: labels[e.key] ?? 'Outros',
          studentCount: groupStudents[e.key]?.length ?? 0,
          totalRevenue: e.value,
          percentage: grandTotal > 0 ? (e.value / grandTotal) * 100 : 0,
        );
      }).toList()
        ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

      // Recommendations (client-side engine)
      final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      final recs = <FinancialRecommendationData>[];
      if (report.collectionRate < 70) {
        recs.add(FinancialRecommendationData(
          type: 'warning',
          title: 'Taxa de cobranca baixa',
          description:
              'A taxa de cobranca este mes esta em '
              '${report.collectionRate.toStringAsFixed(1)}%.',
        ));
      }
      if (report.growthMoM < -10) {
        recs.add(FinancialRecommendationData(
          type: 'warning',
          title: 'Queda na receita',
          description:
              'A receita caiu '
              '${report.growthMoM.abs().toStringAsFixed(1)}% em relacao ao mes anterior.',
        ));
      }
      if (report.growthMoM > 10) {
        recs.add(FinancialRecommendationData(
          type: 'success',
          title: 'Crescimento na receita',
          description:
              'A receita cresceu ${report.growthMoM.toStringAsFixed(1)}% '
              'em relacao ao mes anterior. Continue com as estrategias atuais!',
        ));
      }
      if (report.overdueRevenue > report.confirmedRevenue * 0.3) {
        recs.add(FinancialRecommendationData(
          type: 'error',
          title: 'Alto volume de inadimplencia',
          description:
              'O valor vencido (${fmt.format(report.overdueRevenue)}) '
              'representa mais de 30% da receita confirmada.',
        ));
      }
      final avgTicket = report.paidCount > 0
          ? report.confirmedRevenue / report.paidCount
          : 0.0;
      recs.add(FinancialRecommendationData(
        type: 'info',
        title: 'Ticket medio',
        description:
            'O ticket medio dos pagamentos confirmados este mes e de '
            '${fmt.format(avgTicket)}.',
      ));

      setState(() {
        _monthlyReport = report;
        _historicalData = historical;
        _projections = projections;
        _revenueByPlan = revenueByPlan;
        _recommendations = recs;
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

      // exportCSV is pure — no Firestore; create a throwaway instance to reuse logic.
      final csvString =
          FinancialReportService(currentUser!.academyId!).exportCSV(_historicalData);

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
                          AttendanceTab(
                            attendanceByDay: _attendanceByDay,
                            totalAttendanceThisMonth: _totalAttendanceThisMonth,
                            totalAttendanceLastMonth: _totalAttendanceLastMonth,
                            averageAttendancePerDay: _averageAttendancePerDay,
                            peakDay: _peakDay,
                            peakDayName: _peakDayName,
                          ),
                          FinancialTab(
                            totalRevenue: _totalRevenue,
                            totalPending: _totalPending,
                            totalOverdue: _totalOverdue,
                            paidPayments: _paidPayments,
                            pendingPayments: _pendingPayments,
                            overduePayments: _overduePayments,
                            lastMonthRevenue: _lastMonthRevenue,
                            averageTicket: _averageTicket,
                            storeRevenue: _storeRevenue,
                            storeOrderCount: _storeOrderCount,
                            storePending: _storePending,
                            storePendingCount: _storePendingCount,
                            monthlyReport: _monthlyReport,
                            historicalData: _historicalData,
                            projections: _projections,
                            revenueByPlan: _revenueByPlan,
                            recommendations: _recommendations,
                            isExporting: _isExporting,
                            onExportCsv: _exportCsv,
                          ),
                          StudentsTab(
                            totalStudents: _totalStudents,
                            activeStudents: _activeStudents,
                            inactiveStudents: _inactiveStudents,
                            injuredStudents: _injuredStudents,
                            kidsCount: _kidsCount,
                            adultsCount: _adultsCount,
                            kidsBeltDistribution: _kidsBeltDistribution,
                            adultBeltDistribution: _adultBeltDistribution,
                          ),
                          RetentionTab(
                            isLoading: _isRetentionLoading,
                            atRiskStudents: _atRiskStudents,
                            retentionMetrics: _retentionMetrics,
                          ),
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
}
