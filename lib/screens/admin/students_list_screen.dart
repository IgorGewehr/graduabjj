import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

/// Students List Screen (Admin)
class StudentsListScreen extends ConsumerStatefulWidget {
  const StudentsListScreen({super.key});

  @override
  ConsumerState<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends ConsumerState<StudentsListScreen> {
  List<Student> _students = [];
  List<Student> _filteredStudents = [];
  bool _isLoading = true;

  // Filters
  String _searchQuery = '';
  StudentStatus? _statusFilter;
  StudentCategory? _categoryFilter;
  String? _beltFilter;
  String _sortBy = 'name'; // name, attendance, belt

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);

    try {
      final service = StudentService(FirebaseService.academyId);
      final students = await service.getAll();
      setState(() {
        _students = students;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = _students.toList();

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((s) =>
          s.fullName.toLowerCase().contains(query) ||
          (s.nickname?.toLowerCase().contains(query) ?? false) ||
          (s.email?.toLowerCase().contains(query) ?? false)
      ).toList();
    }

    // Status filter
    if (_statusFilter != null) {
      filtered = filtered.where((s) => s.status == _statusFilter).toList();
    }

    // Category filter
    if (_categoryFilter != null) {
      filtered = filtered.where((s) => s.category == _categoryFilter).toList();
    }

    // Belt filter
    if (_beltFilter != null) {
      filtered = filtered.where((s) => s.currentBelt == _beltFilter).toList();
    }

    // Sorting
    switch (_sortBy) {
      case 'name':
        filtered.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case 'attendance':
        filtered.sort((a, b) => b.totalAttendanceCount.compareTo(a.totalAttendanceCount));
        break;
      case 'belt':
        const beltOrder = ['white', 'blue', 'purple', 'brown', 'black'];
        filtered.sort((a, b) {
          final aIndex = beltOrder.indexOf(a.currentBelt);
          final bIndex = beltOrder.indexOf(b.currentBelt);
          if (aIndex != bIndex) return bIndex.compareTo(aIndex);
          return b.currentStripes.compareTo(a.currentStripes);
        });
        break;
    }

    setState(() => _filteredStudents = filtered);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alunos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStudents,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar aluno...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _applyFilters();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _applyFilters();
                });
              },
            ),
          ),

          // Active Filters Chips
          if (_hasActiveFilters())
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_statusFilter != null)
                      _FilterChip(
                        label: _statusFilter!.label,
                        onRemove: () {
                          setState(() {
                            _statusFilter = null;
                            _applyFilters();
                          });
                        },
                      ),
                    if (_categoryFilter != null)
                      _FilterChip(
                        label: _categoryFilter!.label,
                        onRemove: () {
                          setState(() {
                            _categoryFilter = null;
                            _applyFilters();
                          });
                        },
                      ),
                    if (_beltFilter != null)
                      _FilterChip(
                        label: 'Faixa ${_beltFilter!}',
                        onRemove: () {
                          setState(() {
                            _beltFilter = null;
                            _applyFilters();
                          });
                        },
                      ),
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Limpar filtros'),
                    ),
                  ],
                ),
              ),
            ),

          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredStudents.length} aluno(s)',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
                PopupMenuButton<String>(
                  initialValue: _sortBy,
                  onSelected: (value) {
                    setState(() {
                      _sortBy = value;
                      _applyFilters();
                    });
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'name', child: Text('Nome')),
                    const PopupMenuItem(value: 'attendance', child: Text('Presenças')),
                    const PopupMenuItem(value: 'belt', child: Text('Faixa')),
                  ],
                  child: Row(
                    children: [
                      const Icon(Icons.sort, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        _getSortLabel(),
                        style: AppTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Student List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredStudents.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _filteredStudents.length,
                        itemBuilder: (context, index) {
                          final student = _filteredStudents[index];
                          return _StudentCard(
                            student: student,
                            onTap: () => context.go('/admin/alunos/${student.id}'),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/admin/alunos/novo'),
        icon: const Icon(Icons.person_add),
        label: const Text('Novo Aluno'),
      ),
    );
  }

  bool _hasActiveFilters() {
    return _statusFilter != null || _categoryFilter != null || _beltFilter != null;
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _categoryFilter = null;
      _beltFilter = null;
      _applyFilters();
    });
  }

  String _getSortLabel() {
    switch (_sortBy) {
      case 'name':
        return 'Nome';
      case 'attendance':
        return 'Presenças';
      case 'belt':
        return 'Faixa';
      default:
        return 'Nome';
    }
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filtros',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // Status filter
                const Text('Status', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: StudentStatus.values.map((status) {
                    return ChoiceChip(
                      label: Text(status.label),
                      selected: _statusFilter == status,
                      onSelected: (selected) {
                        setModalState(() {
                          _statusFilter = selected ? status : null;
                        });
                        setState(() => _applyFilters());
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Category filter
                const Text('Categoria', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: StudentCategory.values.map((category) {
                    return ChoiceChip(
                      label: Text(category.label),
                      selected: _categoryFilter == category,
                      onSelected: (selected) {
                        setModalState(() {
                          _categoryFilter = selected ? category : null;
                        });
                        setState(() => _applyFilters());
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Belt filter
                const Text('Faixa', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['white', 'blue', 'purple', 'brown', 'black'].map((belt) {
                    return ChoiceChip(
                      label: Text(_getBeltLabel(belt)),
                      selected: _beltFilter == belt,
                      onSelected: (selected) {
                        setModalState(() {
                          _beltFilter = selected ? belt : null;
                        });
                        setState(() => _applyFilters());
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        _clearFilters();
                        Navigator.pop(context);
                      },
                      child: const Text('Limpar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Aplicar'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _getBeltLabel(String belt) {
    const labels = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
    };
    return labels[belt] ?? belt;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            _hasActiveFilters() ? 'Nenhum aluno encontrado' : 'Nenhum aluno cadastrado',
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
          if (!_hasActiveFilters()) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/admin/alunos/novo'),
              icon: const Icon(Icons.person_add),
              label: const Text('Cadastrar Aluno'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Filter Chip Widget
class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _FilterChip({
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: onRemove,
      ),
    );
  }
}

/// Student Card Widget
class _StudentCard extends StatelessWidget {
  final Student student;
  final VoidCallback? onTap;

  const _StudentCard({
    required this.student,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: _buildAvatar(),
        title: Text(
          student.fullName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Row(
          children: [
            _buildBeltIndicator(),
            const SizedBox(width: 8),
            Text('${student.totalAttendanceCount} presenças'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusBadge(),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildAvatar() {
    if (student.photoUrl != null) {
      return CircleAvatar(
        backgroundImage: NetworkImage(student.photoUrl!),
      );
    }
    return CircleAvatar(
      backgroundColor: _getBeltColor(student.currentBelt),
      child: Text(
        student.fullName.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: student.currentBelt == 'white' ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  Widget _buildBeltIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getBeltColor(student.currentBelt),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getBeltShortLabel(student.currentBelt),
            style: TextStyle(
              fontSize: 10,
              color: student.currentBelt == 'white' ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (student.currentStripes > 0) ...[
            const SizedBox(width: 4),
            Text(
              '• ${student.currentStripes}',
              style: TextStyle(
                fontSize: 10,
                color: student.currentBelt == 'white' ? Colors.black : Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (student.status == StudentStatus.active) return const SizedBox.shrink();

    Color color;
    switch (student.status) {
      case StudentStatus.injured:
        color = Colors.orange;
        break;
      case StudentStatus.inactive:
        color = Colors.grey;
        break;
      case StudentStatus.suspended:
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        student.status.label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
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

  String _getBeltShortLabel(String belt) {
    const labels = {
      'white': 'BR',
      'blue': 'AZ',
      'purple': 'RX',
      'brown': 'MR',
      'black': 'PT',
    };
    return labels[belt] ?? belt.toUpperCase().substring(0, 2);
  }
}
