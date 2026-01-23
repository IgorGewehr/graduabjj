import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

/// Admin Reports Screen - Analytics and reports
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // Attendance data
  Map<String, int> _attendanceByDay = {};
  int _totalAttendanceThisMonth = 0;
  double _averageAttendancePerClass = 0;

  // Financial data
  double _totalRevenue = 0;
  double _totalPending = 0;
  int _paidPayments = 0;
  int _overduePayments = 0;

  // Student data
  int _totalStudents = 0;
  int _activeStudents = 0;
  int _inactiveStudents = 0;
  Map<String, int> _beltDistribution = {};
  Map<String, int> _categoryDistribution = {};

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
      // Handle error
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadAttendanceData() async {
    final academyId = FirebaseService.academyId;
    final attendanceService = AttendanceService(academyId);

    // Get attendance for this month
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    final attendances = await attendanceService.getByDateRange(startOfMonth, endOfMonth);

    // Group by day of week
    final byDay = <String, int>{};
    for (final a in attendances) {
      final dayName = DateFormat('EEEE', 'pt_BR').format(a.date);
      byDay[dayName] = (byDay[dayName] ?? 0) + 1;
    }

    setState(() {
      _attendanceByDay = byDay;
      _totalAttendanceThisMonth = attendances.length;
      _averageAttendancePerClass = attendances.isNotEmpty
          ? attendances.length / (now.day)
          : 0;
    });
  }

  Future<void> _loadFinancialData() async {
    final academyId = FirebaseService.academyId;
    final paymentService = PaymentService(academyId);

    final currentMonth = DateFormat('yyyy-MM').format(DateTime.now());
    final summary = await paymentService.getMonthlySummary(currentMonth);
    final pending = await paymentService.getPending();
    final overdue = await paymentService.getOverdue();
    final paid = await paymentService.getPaidThisMonth();

    setState(() {
      _totalRevenue = (summary['totalPaid'] ?? 0.0) as double;
      _totalPending = (summary['totalPending'] ?? 0.0) as double;
      _paidPayments = paid.length;
      _overduePayments = overdue.length;
    });
  }

  Future<void> _loadStudentData() async {
    final academyId = FirebaseService.academyId;
    final studentService = StudentService(academyId);
    final beltService = BeltProgressionService(academyId);

    final students = await studentService.getAll();
    final beltDist = await beltService.getBeltDistribution();

    // Calculate category distribution
    final categoryDist = <String, int>{};
    for (final s in students) {
      final cat = s.category?.label ?? 'Indefinido';
      categoryDist[cat] = (categoryDist[cat] ?? 0) + 1;
    }

    setState(() {
      _totalStudents = students.length;
      _activeStudents = students.where((s) => s.status == StudentStatus.active).length;
      _inactiveStudents = students.where((s) => s.status != StudentStatus.active).length;
      _beltDistribution = beltDist;
      _categoryDistribution = categoryDist;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Presenças'),
            Tab(text: 'Financeiro'),
            Tab(text: 'Alunos'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAttendanceTab(),
                _buildFinancialTab(),
                _buildStudentsTab(),
              ],
            ),
    );
  }

  Widget _buildAttendanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header
          Text(
            DateFormat("MMMM 'de' yyyy", 'pt_BR').format(DateTime.now()),
            style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Summary cards
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Total de Presenças',
                  value: _totalAttendanceThisMonth.toString(),
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Média/Dia',
                  value: _averageAttendancePerClass.toStringAsFixed(1),
                  icon: Icons.trending_up,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Attendance by day
          Text(
            'Presenças por Dia da Semana',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildAttendanceChart(),
        ],
      ),
    );
  }

  Widget _buildAttendanceChart() {
    final days = ['segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'];
    final maxValue = _attendanceByDay.values.fold(1, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: days.map((day) {
            final value = _attendanceByDay[day] ?? 0;
            final percentage = value / maxValue;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      _shortDayName(day),
                      style: AppTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: percentage,
                          child: Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    child: Text(
                      value.toString(),
                      style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _shortDayName(String fullName) {
    final shortNames = {
      'segunda-feira': 'Seg',
      'terça-feira': 'Ter',
      'quarta-feira': 'Qua',
      'quinta-feira': 'Qui',
      'sexta-feira': 'Sex',
      'sábado': 'Sáb',
      'domingo': 'Dom',
    };
    return shortNames[fullName] ?? fullName;
  }

  Widget _buildFinancialTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat("MMMM 'de' yyyy", 'pt_BR').format(DateTime.now()),
            style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Revenue cards
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Recebido',
                  value: 'R\$ ${_totalRevenue.toStringAsFixed(0)}',
                  icon: Icons.arrow_downward,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Pendente',
                  value: 'R\$ ${_totalPending.toStringAsFixed(0)}',
                  icon: Icons.schedule,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Pagamentos',
                  value: _paidPayments.toString(),
                  icon: Icons.check,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Atrasados',
                  value: _overduePayments.toString(),
                  icon: Icons.warning,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Collection rate
          Text(
            'Taxa de Recebimento',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildCollectionRate(),
        ],
      ),
    );
  }

  Widget _buildCollectionRate() {
    final total = _totalRevenue + _totalPending;
    final rate = total > 0 ? _totalRevenue / total : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recebido', style: AppTheme.bodyMedium),
                Text(
                  '${(rate * 100).toStringAsFixed(1)}%',
                  style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 12,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  rate > 0.8 ? Colors.green : (rate > 0.5 ? Colors.orange : Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildLegendItem('Recebido', Colors.green, 'R\$ ${_totalRevenue.toStringAsFixed(0)}'),
                _buildLegendItem('Pendente', Colors.orange, 'R\$ ${_totalPending.toStringAsFixed(0)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, String value) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
            Text(value, style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildStudentsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student summary
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Total',
                  value: _totalStudents.toString(),
                  icon: Icons.people,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Ativos',
                  value: _activeStudents.toString(),
                  icon: Icons.person,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Inativos',
                  value: _inactiveStudents.toString(),
                  icon: Icons.person_off,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Belt distribution
          Text(
            'Distribuição por Faixa',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildBeltDistribution(),
          const SizedBox(height: 24),

          // Category distribution
          Text(
            'Distribuição por Categoria',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildCategoryDistribution(),
        ],
      ),
    );
  }

  Widget _buildBeltDistribution() {
    final belts = ['white', 'blue', 'purple', 'brown', 'black'];
    final beltNames = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
    };
    final beltColors = {
      'white': const Color(0xFFF5F5F5),
      'blue': const Color(0xFF2563EB),
      'purple': const Color(0xFF7C3AED),
      'brown': const Color(0xFF92400E),
      'black': const Color(0xFF171717),
    };

    final total = _beltDistribution.values.fold(0, (a, b) => a + b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: belts.map((belt) {
            final count = _beltDistribution[belt] ?? 0;
            final percentage = total > 0 ? count / total : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: beltColors[belt],
                      borderRadius: BorderRadius.circular(4),
                      border: belt == 'white'
                          ? Border.all(color: Colors.grey.shade300)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 60,
                    child: Text(beltNames[belt] ?? belt),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: percentage,
                          child: Container(
                            height: 20,
                            decoration: BoxDecoration(
                              color: beltColors[belt],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      count.toString(),
                      style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCategoryDistribution() {
    final total = _categoryDistribution.values.fold(0, (a, b) => a + b);
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: _categoryDistribution.entries.toList().asMap().entries.map((entry) {
            final index = entry.key;
            final category = entry.value.key;
            final count = entry.value.value;
            final percentage = total > 0 ? count / total : 0.0;
            final color = colors[index % colors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: Text(category, style: AppTheme.bodySmall),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: percentage,
                          child: Container(
                            height: 20,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '$count (${(percentage * 100).toStringAsFixed(0)}%)',
                      style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
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

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
