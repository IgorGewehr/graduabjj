import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

/// Admin Student Detail Screen - View and manage student
class AdminStudentDetailScreen extends ConsumerStatefulWidget {
  final String studentId;

  const AdminStudentDetailScreen({super.key, required this.studentId});

  @override
  ConsumerState<AdminStudentDetailScreen> createState() => _AdminStudentDetailScreenState();
}

class _AdminStudentDetailScreenState extends ConsumerState<AdminStudentDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Student? _student;
  List<Attendance> _attendances = [];
  List<Payment> _payments = [];
  List<BeltProgression> _progressions = [];
  List<Achievement> _achievements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      final paymentService = PaymentService(academyId);
      final beltService = BeltProgressionService(academyId);
      final achievementService = AchievementService(academyId);

      final student = await studentService.getById(widget.studentId);
      final attendances = await attendanceService.getByStudent(widget.studentId);
      final payments = await paymentService.getByStudent(widget.studentId);
      final progressions = await beltService.getByStudent(widget.studentId);
      final achievements = await achievementService.getForStudent(widget.studentId);

      setState(() {
        _student = student;
        _attendances = attendances;
        _payments = payments;
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _student == null
              ? const Center(child: Text('Aluno não encontrado'))
              : NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    _buildSliverAppBar(),
                  ],
                  body: Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'Info'),
                          Tab(text: 'Presenças'),
                          Tab(text: 'Financeiro'),
                          Tab(text: 'Histórico'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildInfoTab(),
                            _buildAttendanceTab(),
                            _buildFinancialTab(),
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
      actions: [
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () {
            // Navigate to edit screen
            // TODO: Implement navigation
          },
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'promote') _showPromoteDialog();
            if (value == 'toggle_status') _toggleStatus();
            if (value == 'delete') _showDeleteConfirmation();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'promote',
              child: Row(
                children: [
                  Icon(Icons.military_tech),
                  SizedBox(width: 8),
                  Text('Graduar'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'toggle_status',
              child: Row(
                children: [
                  Icon(_student!.status == StudentStatus.active
                      ? Icons.person_off
                      : Icons.person),
                  const SizedBox(width: 8),
                  Text(_student!.status == StudentStatus.active
                      ? 'Desativar'
                      : 'Ativar'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Excluir', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
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
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
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
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          ),
          if (_student!.currentStripes > 0) ...[
            const SizedBox(width: 4),
            Text(
              '${_student!.currentStripes} grau(s)',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final statusColors = {
      StudentStatus.active: Colors.green,
      StudentStatus.inactive: Colors.grey,
      StudentStatus.suspended: Colors.orange,
      StudentStatus.injured: Colors.blue,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColors[_student!.status]?.withValues(alpha: 0.3) ?? Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _student!.status.label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick stats
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Presenças',
                  value: _student!.totalAttendanceCount.toString(),
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Mês atual',
                  value: _attendances.where((a) =>
                    a.date.month == DateTime.now().month &&
                    a.date.year == DateTime.now().year
                  ).length.toString(),
                  icon: Icons.calendar_today,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Conquistas',
                  value: _achievements.length.toString(),
                  icon: Icons.emoji_events,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Personal info
          _buildSection('Informações Pessoais', [
            _InfoRow(label: 'Nome completo', value: _student!.fullName),
            if (_student!.nickname != null)
              _InfoRow(label: 'Apelido', value: _student!.nickname!),
            if (_student!.email != null)
              _InfoRow(label: 'E-mail', value: _student!.email!),
            if (_student!.phone != null)
              _InfoRow(label: 'Telefone', value: _student!.phone!),
            if (_student!.birthDate != null)
              _InfoRow(
                label: 'Nascimento',
                value: DateFormat('dd/MM/yyyy').format(_student!.birthDate!),
              ),
            if (_student!.category != null)
              _InfoRow(label: 'Categoria', value: _student!.category!.label),
          ]),
          const SizedBox(height: 16),

          // Academy info
          _buildSection('Informações da Academia', [
            _InfoRow(
              label: 'Data de início',
              value: DateFormat('dd/MM/yyyy').format(_student!.startDate),
            ),
            if (_student!.planId != null)
              _InfoRow(label: 'Plano ID', value: _student!.planId!),
            _InfoRow(
              label: 'Mensalidade',
              value: 'R\$ ${_student!.tuitionValue.toStringAsFixed(2)}',
            ),
            _InfoRow(
              label: 'Dia de vencimento',
              value: _student!.tuitionDay.toString(),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceTab() {
    if (_attendances.isEmpty) {
      return const Center(child: Text('Nenhuma presença registrada'));
    }

    // Group by month
    final grouped = <String, List<Attendance>>{};
    for (final a in _attendances) {
      final key = DateFormat('MMMM yyyy', 'pt_BR').format(a.date);
      grouped.putIfAbsent(key, () => []).add(a);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    entry.key,
                    style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${entry.value.length} presenças',
                      style: TextStyle(color: AppTheme.primary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.map((a) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(Icons.check, color: Colors.green),
                ),
                title: Text(a.className),
                subtitle: Text(DateFormat('EEEE, d', 'pt_BR').format(a.date)),
                trailing: Text(
                  DateFormat('HH:mm').format(a.createdAt),
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
              ),
            )),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildFinancialTab() {
    if (_payments.isEmpty) {
      return const Center(child: Text('Nenhum pagamento registrado'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _payments.length,
      itemBuilder: (context, index) {
        final payment = _payments[index];
        return _PaymentCard(payment: payment);
      },
    );
  }

  Widget _buildHistoryTab() {
    final allHistory = <_HistoryItem>[];

    // Add progressions
    for (final p in _progressions) {
      allHistory.add(_HistoryItem(
        date: p.promotionDate,
        title: p.isBeltChange ? 'Faixa ${p.newBelt}' : 'Grau ${p.newStripes}',
        subtitle: p.notes,
        icon: Icons.military_tech,
        color: _getBeltColor(p.newBelt),
      ));
    }

    // Add achievements
    for (final a in _achievements) {
      allHistory.add(_HistoryItem(
        date: a.date,
        title: a.title,
        subtitle: a.description,
        icon: Icons.emoji_events,
        color: Colors.amber,
      ));
    }

    // Sort by date descending
    allHistory.sort((a, b) => b.date.compareTo(a.date));

    if (allHistory.isEmpty) {
      return const Center(child: Text('Nenhum histórico'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allHistory.length,
      itemBuilder: (context, index) {
        final item = allHistory[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: item.color.withValues(alpha: 0.2),
              child: Icon(item.icon, color: item.color),
            ),
            title: Text(item.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.subtitle != null) Text(item.subtitle!),
                Text(
                  DateFormat('dd/MM/yyyy').format(item.date),
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPromoteDialog() {
    bool isStripe = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Graduar Aluno'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Aluno: ${_student!.fullName}'),
                Text('Faixa atual: ${_student!.currentBelt} - ${_student!.currentStripes} grau(s)'),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Grau')),
                    ButtonSegment(value: false, label: Text('Faixa')),
                  ],
                  selected: {isStripe},
                  onSelectionChanged: (value) {
                    setDialogState(() => isStripe = value.first);
                  },
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
                    final service = BeltProgressionService(FirebaseService.academyId);

                    if (isStripe) {
                      await service.addStripe(
                        studentId: _student!.id,
                        studentName: _student!.fullName,
                        promotedBy: 'admin',
                        promotedByName: 'Administrador',
                      );
                    } else {
                      final nextBelt = _getNextBelt(_student!.currentBelt);
                      await service.changeBelt(
                        studentId: _student!.id,
                        studentName: _student!.fullName,
                        newBelt: nextBelt,
                        promotedBy: 'admin',
                        promotedByName: 'Administrador',
                      );
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Graduação realizada com sucesso!')),
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

  String _getNextBelt(String current) {
    const order = ['white', 'blue', 'purple', 'brown', 'black'];
    final index = order.indexOf(current);
    if (index < order.length - 1) {
      return order[index + 1];
    }
    return current;
  }

  void _toggleStatus() async {
    try {
      final service = StudentService(FirebaseService.academyId);
      final newStatus = _student!.status == StudentStatus.active
          ? StudentStatus.inactive
          : StudentStatus.active;

      await service.updateStatus(_student!.id, newStatus);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == StudentStatus.active
                  ? 'Aluno ativado!'
                  : 'Aluno desativado!',
            ),
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
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Aluno'),
        content: Text(
          'Deseja excluir ${_student!.fullName}? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);

              try {
                final service = StudentService(FirebaseService.academyId);
                await service.delete(_student!.id);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Aluno excluído!')),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e')),
                  );
                }
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Color _getBeltColor(String belt) {
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

/// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Info Row Widget
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// Payment Card Widget
class _PaymentCard extends StatelessWidget {
  final Payment payment;

  const _PaymentCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    final statusColors = {
      PaymentStatus.pending: Colors.orange,
      PaymentStatus.paid: Colors.green,
      PaymentStatus.overdue: Colors.red,
      PaymentStatus.cancelled: Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColors[payment.status]?.withValues(alpha: 0.2),
          child: Icon(
            payment.status == PaymentStatus.paid ? Icons.check : Icons.receipt,
            color: statusColors[payment.status],
          ),
        ),
        title: Text(payment.description ?? 'Mensalidade'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Venc: ${DateFormat('dd/MM/yyyy').format(payment.dueDate)}'),
            if (payment.paidAt != null)
              Text(
                'Pago em: ${DateFormat('dd/MM/yyyy').format(payment.paidAt!)}',
                style: const TextStyle(color: Colors.green),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'R\$ ${payment.value.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColors[payment.status]?.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                payment.status.label,
                style: TextStyle(
                  fontSize: 10,
                  color: statusColors[payment.status],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// History Item Helper Class
class _HistoryItem {
  final DateTime date;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  _HistoryItem({
    required this.date,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
  });
}
