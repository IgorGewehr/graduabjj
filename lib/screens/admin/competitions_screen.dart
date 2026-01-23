import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

/// Admin Competitions Screen - Manage competitions
class AdminCompetitionsScreen extends ConsumerStatefulWidget {
  const AdminCompetitionsScreen({super.key});

  @override
  ConsumerState<AdminCompetitionsScreen> createState() => _AdminCompetitionsScreenState();
}

class _AdminCompetitionsScreenState extends ConsumerState<AdminCompetitionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Competition> _upcomingCompetitions = [];
  List<Competition> _pastCompetitions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCompetitions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCompetitions() async {
    setState(() => _isLoading = true);

    try {
      final service = CompetitionService(FirebaseService.academyId);
      final upcoming = await service.getUpcoming();
      // Get all and filter for past
      final all = await service.list();
      final now = DateTime.now();
      final past = all.where((c) => c.date.isBefore(now)).toList();

      setState(() {
        _upcomingCompetitions = upcoming;
        _pastCompetitions = past;
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
        title: const Text('Campeonatos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCompetitions,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Próximos (${_upcomingCompetitions.length})'),
            Tab(text: 'Passados (${_pastCompetitions.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCompetitionList(_upcomingCompetitions, isUpcoming: true),
                _buildCompetitionList(_pastCompetitions, isUpcoming: false),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCompetitionDialog,
        icon: const Icon(Icons.add),
        label: const Text('Novo Campeonato'),
      ),
    );
  }

  Widget _buildCompetitionList(List<Competition> competitions, {required bool isUpcoming}) {
    if (competitions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_outlined, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              isUpcoming ? 'Nenhum campeonato agendado' : 'Nenhum campeonato passado',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: competitions.length,
      itemBuilder: (context, index) {
        final competition = competitions[index];
        return _CompetitionCard(
          competition: competition,
          onTap: () => _showCompetitionDetails(competition),
          onEdit: () => _showEditCompetitionDialog(competition),
          onDelete: () => _showDeleteConfirmation(competition),
          onManageEnrollments: () => _showEnrollmentsDialog(competition),
        );
      },
    );
  }

  void _showCreateCompetitionDialog() {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? selectedDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Novo Campeonato'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Campeonato *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setDialogState(() => selectedDate = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data *',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        selectedDate != null
                            ? DateFormat('dd/MM/yyyy').format(selectedDate!)
                            : 'Selecionar data',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Local',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  if (nameController.text.isEmpty || selectedDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Preencha os campos obrigatórios')),
                    );
                    return;
                  }

                  Navigator.pop(context);

                  try {
                    final service = CompetitionService(FirebaseService.academyId);
                    await service.create(
                      name: nameController.text,
                      date: selectedDate!,
                      location: locationController.text.isEmpty ? null : locationController.text,
                      description: descriptionController.text.isEmpty
                          ? null
                          : descriptionController.text,
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Campeonato criado com sucesso!')),
                      );
                      _loadCompetitions();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e')),
                      );
                    }
                  }
                },
                child: const Text('Criar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditCompetitionDialog(Competition competition) {
    final nameController = TextEditingController(text: competition.name);
    final locationController = TextEditingController(text: competition.location ?? '');
    final descriptionController = TextEditingController(text: competition.description ?? '');
    DateTime selectedDate = competition.date;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Editar Campeonato'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Campeonato *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setDialogState(() => selectedDate = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data *',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Local',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  if (nameController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nome é obrigatório')),
                    );
                    return;
                  }

                  Navigator.pop(context);

                  try {
                    final service = CompetitionService(FirebaseService.academyId);
                    await service.update(competition.id, {
                      'name': nameController.text,
                      'date': selectedDate,
                      'location': locationController.text.isEmpty ? null : locationController.text,
                      'description': descriptionController.text.isEmpty
                          ? null
                          : descriptionController.text,
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Campeonato atualizado!')),
                      );
                      _loadCompetitions();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e')),
                      );
                    }
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCompetitionDetails(Competition competition) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(competition.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (competition.description != null) ...[
                Text(competition.description!),
                const SizedBox(height: 16),
              ],
              _DetailRow(
                label: 'Data',
                value: DateFormat('dd/MM/yyyy').format(competition.date),
              ),
              if (competition.location != null)
                _DetailRow(label: 'Local', value: competition.location!),
              _DetailRow(
                label: 'Status',
                value: competition.status.label,
              ),
              _DetailRow(
                label: 'Inscritos',
                value: '${competition.enrolledCount}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _showEnrollmentsDialog(competition);
            },
            child: const Text('Ver Inscrições'),
          ),
        ],
      ),
    );
  }

  void _showEnrollmentsDialog(Competition competition) async {
    final enrollmentService = CompetitionEnrollmentService(FirebaseService.academyId);
    final enrollments = await enrollmentService.getByCompetition(competition.id);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Inscrições - ${competition.name}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: enrollments.isEmpty
              ? const Center(child: Text('Nenhuma inscrição'))
              : ListView.builder(
                  itemCount: enrollments.length,
                  itemBuilder: (context, index) {
                    final enrollment = enrollments[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primary,
                        child: Text(
                          enrollment.studentName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(enrollment.studentName),
                      subtitle: Text(
                        '${enrollment.ageCategory ?? 'Sem categoria'} - ${enrollment.weightCategory ?? 'Sem peso'}',
                      ),
                      trailing: Text(
                        enrollment.transportPreference.label,
                        style: AppTheme.bodySmall,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _showAddEnrollmentDialog(competition);
            },
            child: const Text('Adicionar Inscrição'),
          ),
        ],
      ),
    );
  }

  void _showAddEnrollmentDialog(Competition competition) async {
    final studentService = StudentService(FirebaseService.academyId);
    final students = await studentService.getActive();

    if (!mounted) return;

    Student? selectedStudent;
    final categoryController = TextEditingController();
    final weightController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Adicionar Inscrição'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Student>(
                    value: selectedStudent,
                    decoration: const InputDecoration(
                      labelText: 'Aluno *',
                      border: OutlineInputBorder(),
                    ),
                    items: students.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(s.fullName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedStudent = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(
                      labelText: 'Categoria de Idade',
                      hintText: 'Ex: Adulto',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: weightController,
                    decoration: const InputDecoration(
                      labelText: 'Categoria de Peso',
                      hintText: 'Ex: Leve',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  if (selectedStudent == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Selecione um aluno')),
                    );
                    return;
                  }

                  Navigator.pop(context);

                  try {
                    final service = CompetitionEnrollmentService(FirebaseService.academyId);
                    await service.enroll(
                      competitionId: competition.id,
                      competitionName: competition.name,
                      studentId: selectedStudent!.id,
                      studentName: selectedStudent!.fullName,
                      ageCategory: categoryController.text.isEmpty ? null : categoryController.text,
                      weightCategory: weightController.text.isEmpty ? null : weightController.text,
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Inscrição adicionada!')),
                      );
                      _loadCompetitions();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e')),
                      );
                    }
                  }
                },
                child: const Text('Inscrever'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(Competition competition) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Campeonato'),
        content: Text(
          'Deseja excluir o campeonato "${competition.name}"? Esta ação também removerá todas as inscrições.',
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
                final service = CompetitionService(FirebaseService.academyId);
                await service.delete(competition.id);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Campeonato excluído!')),
                  );
                  _loadCompetitions();
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
}

/// Competition Card Widget
class _CompetitionCard extends StatelessWidget {
  final Competition competition;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManageEnrollments;

  const _CompetitionCard({
    required this.competition,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onManageEnrollments,
  });

  @override
  Widget build(BuildContext context) {
    final daysUntil = competition.date.difference(DateTime.now()).inDays;
    final isUpcoming = daysUntil >= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.emoji_events, color: Colors.amber, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          competition.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (competition.location != null)
                          Text(
                            competition.location!,
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                      if (value == 'enrollments') onManageEnrollments();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'enrollments',
                        child: Row(
                          children: [
                            Icon(Icons.people),
                            SizedBox(width: 8),
                            Text('Inscrições'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit),
                            SizedBox(width: 8),
                            Text('Editar'),
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
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.calendar_today,
                    label: DateFormat('dd/MM/yyyy').format(competition.date),
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.people,
                    label: '${competition.enrolledCount} inscritos',
                  ),
                  const Spacer(),
                  if (isUpcoming && daysUntil <= 30)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: daysUntil <= 7 ? Colors.red : Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        daysUntil == 0
                            ? 'Hoje!'
                            : daysUntil == 1
                                ? 'Amanhã'
                                : 'Em $daysUntil dias',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Info Chip Widget
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Detail Row Widget
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
