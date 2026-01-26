import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

/// Monitor Student Detail Screen - View student info (no financial access)
class MonitorStudentDetailScreen extends ConsumerStatefulWidget {
  final String studentId;

  const MonitorStudentDetailScreen({super.key, required this.studentId});

  @override
  ConsumerState<MonitorStudentDetailScreen> createState() => _MonitorStudentDetailScreenState();
}

class _MonitorStudentDetailScreenState extends ConsumerState<MonitorStudentDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Student? _student;
  List<Attendance> _attendances = [];
  List<BeltProgression> _progressions = [];
  List<Achievement> _achievements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Only 3 tabs: Info, Presencas, Historico (no Financial)
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
      final academyId = FirebaseService.academyId;
      final studentService = StudentService(academyId);
      final attendanceService = AttendanceService(academyId);
      final beltService = BeltProgressionService(academyId);
      final achievementService = AchievementService(academyId);

      final student = await studentService.getById(widget.studentId);
      final attendances = await attendanceService.getByStudent(widget.studentId);
      final progressions = await beltService.getByStudent(widget.studentId);
      final achievements = await achievementService.getForStudent(widget.studentId);

      setState(() {
        _student = student;
        _attendances = attendances;
        _progressions = progressions;
        _achievements = achievements;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _student == null
              ? const Center(child: Text('Aluno nao encontrado'))
              : NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    _buildSliverAppBar(),
                  ],
                  body: Column(
                    children: [
                      Container(
                        color: AppTheme.surface,
                        child: TabBar(
                          controller: _tabController,
                          labelColor: AppTheme.textPrimary,
                          unselectedLabelColor: AppTheme.textSecondary,
                          indicatorColor: AppTheme.primary,
                          tabs: const [
                            Tab(text: 'Info'),
                            Tab(text: 'Presencas'),
                            Tab(text: 'Historico'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildInfoTab(),
                            _buildAttendanceTab(),
                            _buildHistoryTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: _getBeltColor(_student!.currentBelt),
      foregroundColor: _student!.currentBelt == 'white' ? Colors.black : Colors.white,
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.edit),
          onPressed: () {
            context.push('/portal/alunos/${widget.studentId}/editar');
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _getBeltColor(_student!.currentBelt),
                _getBeltColor(_student!.currentBelt).withValues(alpha: 0.7),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Avatar
                      _student!.photoUrl != null
                          ? CircleAvatar(
                              radius: 40,
                              backgroundImage: NetworkImage(_student!.photoUrl!),
                            )
                          : CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.white.withValues(alpha: 0.3),
                              child: Text(
                                _student!.fullName.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: _student!.currentBelt == 'white' ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _student!.fullName,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _student!.currentBelt == 'white' ? Colors.black : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _buildBeltBadge(),
                                const SizedBox(width: 8),
                                _buildStatusBadge(),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBeltBadge() {
    final beltNames = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
      'grey': 'Cinza',
      'yellow': 'Amarela',
      'orange': 'Laranja',
      'green': 'Verde',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            beltNames[_student!.currentBelt] ?? _student!.currentBelt,
            style: TextStyle(
              color: _student!.currentBelt == 'white' ? Colors.black : Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_student!.currentStripes > 0) ...[
            const SizedBox(width: 4),
            Text(
              '${_student!.currentStripes} grau(s)',
              style: TextStyle(
                color: _student!.currentBelt == 'white' ? Colors.black54 : Colors.white70,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final statusColors = {
      StudentStatus.active: AppTheme.success,
      StudentStatus.inactive: AppTheme.textSecondary,
      StudentStatus.suspended: AppTheme.warning,
      StudentStatus.injured: AppTheme.info,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColors[_student!.status]?.withValues(alpha: 0.3) ?? Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _student!.status.label,
        style: TextStyle(
          color: _student!.currentBelt == 'white' ? Colors.black : Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats cards
          Row(
            children: [
              Expanded(child: _buildStatCard('Presencas', '${_student!.totalAttendanceCount}', LucideIcons.clipboardCheck)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Graduacoes', '${_progressions.length}', LucideIcons.award)),
            ],
          ),
          const SizedBox(height: 24),

          // Personal Info
          _buildSectionTitle('Informacoes Pessoais'),
          const SizedBox(height: 12),
          _buildInfoCard([
            if (_student!.nickname != null)
              _InfoRow(label: 'Apelido', value: _student!.nickname!),
            _InfoRow(label: 'Categoria', value: _student!.category.label),
            if (_student!.birthDate != null)
              _InfoRow(
                label: 'Nascimento',
                value: DateFormat('dd/MM/yyyy').format(_student!.birthDate!),
              ),
            if (_student!.email != null)
              _InfoRow(label: 'Email', value: _student!.email!),
            if (_student!.phone != null)
              _InfoRow(label: 'Telefone', value: _student!.phone!),
          ]),

          // Guardian Info (for kids)
          if (_student!.category == StudentCategory.kids && _student!.guardianName != null) ...[
            const SizedBox(height: 24),
            _buildSectionTitle('Responsavel'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoRow(label: 'Nome', value: _student!.guardianName!),
              if (_student!.guardianPhone != null)
                _InfoRow(label: 'Telefone', value: _student!.guardianPhone!),
              if (_student!.guardianEmail != null)
                _InfoRow(label: 'Email', value: _student!.guardianEmail!),
            ]),
          ],

          // Medical Info
          if (_student!.medicalNotes != null && _student!.medicalNotes!.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSectionTitle('Observacoes Medicas'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Text(
                _student!.medicalNotes!,
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTheme.titleSmall.copyWith(
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildInfoCard(List<_InfoRow> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: rows.map((row) {
          final isLast = rows.last == row;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: isLast ? null : Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(row.label, style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary)),
                Text(row.value, style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAttendanceTab() {
    if (_attendances.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.clipboardX, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Nenhuma presenca registrada',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    // Group by month
    final grouped = <String, List<Attendance>>{};
    for (final attendance in _attendances) {
      final key = DateFormat('MMMM yyyy', 'pt_BR').format(attendance.date);
      grouped.putIfAbsent(key, () => []).add(attendance);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final month = grouped.keys.elementAt(index);
        final items = grouped[month]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    month,
                    style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${items.length} presencas',
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
            ),
            ...items.map((attendance) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${attendance.date.day}',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600,
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
                          attendance.className,
                          style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          DateFormat('EEEE', 'pt_BR').format(attendance.date),
                          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.checkCircle, color: AppTheme.success, size: 20),
                ],
              ),
            )),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    final allItems = <_HistoryItem>[];

    // Add belt progressions
    for (final p in _progressions) {
      allItems.add(_HistoryItem(
        date: p.date,
        title: 'Graduacao: ${_getBeltName(p.belt)} ${p.stripes > 0 ? "(${p.stripes} grau)" : ""}',
        icon: LucideIcons.award,
        color: AppTheme.primary,
      ));
    }

    // Add achievements
    for (final a in _achievements) {
      allItems.add(_HistoryItem(
        date: a.awardedAt,
        title: a.title,
        subtitle: a.description,
        icon: LucideIcons.trophy,
        color: AppTheme.warning,
      ));
    }

    // Sort by date descending
    allItems.sort((a, b) => b.date.compareTo(a.date));

    if (allItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.history, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Nenhum historico registrado',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                      ),
                    Text(
                      DateFormat('dd/MM/yyyy').format(item.date),
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textDisabled),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getBeltName(String belt) {
    const names = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
      'grey': 'Cinza',
      'yellow': 'Amarela',
      'orange': 'Laranja',
      'green': 'Verde',
    };
    return names[belt] ?? belt;
  }

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFFF5F5F5),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
      'grey': Color(0xFF6B7280),
      'yellow': Color(0xFFF59E0B),
      'orange': Color(0xFFF97316),
      'green': Color(0xFF22C55E),
    };
    final baseBelt = belt.split('-').first;
    return colors[baseBelt] ?? Colors.grey;
  }
}

class _InfoRow {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});
}

class _HistoryItem {
  final DateTime date;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const _HistoryItem({
    required this.date,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
  });
}
