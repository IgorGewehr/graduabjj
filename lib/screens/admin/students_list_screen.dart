import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';
import '../../widgets/common/grade_display.dart';

/// Students List Screen - Fintech style matching webapp
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
  bool? _accountFilter; // null=all, true=linked, false=unlinked
  String _sortBy = 'name';

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

    // Account filter
    if (_accountFilter != null) {
      if (_accountFilter!) {
        filtered = filtered.where((s) => s.linkedUserId != null && s.linkedUserId!.isNotEmpty).toList();
      } else {
        filtered = filtered.where((s) => s.linkedUserId == null || s.linkedUserId!.isEmpty).toList();
      }
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

  bool _hasActiveFilters() {
    return _statusFilter != null || _categoryFilter != null || _beltFilter != null || _accountFilter != null;
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _categoryFilter = null;
      _beltFilter = null;
      _accountFilter = null;
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadStudents,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: _buildHeader(),
            ),

            // Search and filters
            SliverToBoxAdapter(
              child: _buildSearchAndFilters(),
            ),

            // Active filter chips
            if (_hasActiveFilters())
              SliverToBoxAdapter(
                child: _buildActiveFilterChips(),
              ),

            // Student list
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _filteredStudents.isEmpty
                    ? SliverFillRemaining(child: _buildEmptyState())
                    : _buildStudentSliverList(),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/admin/alunos/novo'),
        backgroundColor: AppTheme.textPrimary,
        child: const Icon(LucideIcons.userPlus, color: Colors.white),
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
            child: Text(
              '${_students.length} alunos',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadStudents,
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

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar aluno...',
                  hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textDisabled),
                  prefixIcon: Icon(LucideIcons.search, color: AppTheme.textSecondary, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(LucideIcons.x, color: AppTheme.textSecondary, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _applyFilters();
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _applyFilters();
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Filter button
          GestureDetector(
            onTap: _showFilterBottomSheet,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _hasActiveFilters() ? AppTheme.primary : AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasActiveFilters() ? AppTheme.primary : AppTheme.divider,
                ),
              ),
              child: Icon(
                LucideIcons.sliders,
                size: 20,
                color: _hasActiveFilters() ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
              label: 'Faixa ${_getBeltLabel(_beltFilter!)}',
              onRemove: () {
                setState(() {
                  _beltFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_accountFilter != null)
            _FilterChip(
              label: _accountFilter! ? 'Com conta' : 'Sem conta',
              onRemove: () {
                setState(() {
                  _accountFilter = null;
                  _applyFilters();
                });
              },
            ),
          GestureDetector(
            onTap: _clearFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Limpar',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSliverList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final student = _filteredStudents[index];
            return _StudentCard(
              student: student,
              onTap: () => context.go('/admin/alunos/${student.id}'),
            );
          },
          childCount: _filteredStudents.length,
        ),
      ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        statusFilter: _statusFilter,
        categoryFilter: _categoryFilter,
        beltFilter: _beltFilter,
        accountFilter: _accountFilter,
        sortBy: _sortBy,
        onApply: (status, category, belt, account, sort) {
          setState(() {
            _statusFilter = status;
            _categoryFilter = category;
            _beltFilter = belt;
            _accountFilter = account;
            _sortBy = sort;
            _applyFilters();
          });
          Navigator.pop(context);
        },
        onClear: () {
          setState(() {
            _statusFilter = null;
            _categoryFilter = null;
            _beltFilter = null;
            _accountFilter = null;
            _sortBy = 'name';
            _applyFilters();
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  String _getBeltLabel(String belt) {
    return getGradeLabel(SportId.bjj, belt);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.users,
              size: 32,
              color: AppTheme.textDisabled,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _hasActiveFilters() ? 'Nenhum aluno encontrado' : 'Nenhum aluno cadastrado',
            style: AppTheme.titleMedium.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _hasActiveFilters()
                ? 'Tente ajustar os filtros'
                : 'Adicione o primeiro aluno da academia',
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          if (!_hasActiveFilters()) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/admin/alunos/novo'),
              icon: const Icon(LucideIcons.userPlus),
              label: const Text('Cadastrar Aluno'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Filter chip widget
class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _FilterChip({
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              LucideIcons.x,
              size: 14,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Student Card Widget - Fintech style
class _StudentCard extends StatelessWidget {
  final Student student;
  final VoidCallback? onTap;

  const _StudentCard({
    required this.student,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          student.fullName,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (student.status != StudentStatus.active)
                        _buildStatusBadge(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      GradeDisplay(
                        sportId: student.getPrimarySport(),
                        grade: student.currentBelt,
                        stripes: student.currentStripes,
                        size: GradeDisplaySize.small,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.textDisabled,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${student.totalAttendanceCount} presencas',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        student.category.label,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _getBeltColor(student.currentBelt),
        borderRadius: BorderRadius.circular(12),
      ),
      child: student.photoUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                student.photoUrl!,
                fit: BoxFit.cover,
              ),
            )
          : Center(
              child: Text(
                student.displayName[0].toUpperCase(),
                style: TextStyle(
                  color: student.currentBelt == 'white' ? Colors.black87 : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
            ),
    );
  }

  Widget _buildStatusBadge() {
    Color color;
    switch (student.status) {
      case StudentStatus.injured:
        color = AppTheme.warning;
        break;
      case StudentStatus.inactive:
        color = AppTheme.textSecondary;
        break;
      case StudentStatus.suspended:
        color = AppTheme.error;
        break;
      default:
        color = AppTheme.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        student.status.label,
        style: AppTheme.labelSmall.copyWith(
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
      'grey': Color(0xFF6B7280),
      'yellow': Color(0xFFF59E0B),
      'orange': Color(0xFFF97316),
      'green': Color(0xFF22C55E),
    };
    final baseBelt = belt.split('-').first;
    return colors[baseBelt] ?? Colors.grey;
  }
}

/// Filter Bottom Sheet
class _FilterBottomSheet extends StatefulWidget {
  final StudentStatus? statusFilter;
  final StudentCategory? categoryFilter;
  final String? beltFilter;
  final bool? accountFilter;
  final String sortBy;
  final Function(StudentStatus?, StudentCategory?, String?, bool?, String) onApply;
  final VoidCallback onClear;

  const _FilterBottomSheet({
    required this.statusFilter,
    required this.categoryFilter,
    required this.beltFilter,
    required this.accountFilter,
    required this.sortBy,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late StudentStatus? _status;
  late StudentCategory? _category;
  late String? _belt;
  late bool? _account;
  late String _sort;

  @override
  void initState() {
    super.initState();
    _status = widget.statusFilter;
    _category = widget.categoryFilter;
    _belt = widget.beltFilter;
    _account = widget.accountFilter;
    _sort = widget.sortBy;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
              'Filtros',
              style: AppTheme.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),

            // Status filter
            _buildSectionTitle('Status'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StudentStatus.values.map((status) {
                final isSelected = _status == status;
                return GestureDetector(
                  onTap: () => setState(() => _status = isSelected ? null : status),
                  child: _buildChip(status.label, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Category filter
            _buildSectionTitle('Categoria'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StudentCategory.values.map((category) {
                final isSelected = _category == category;
                return GestureDetector(
                  onTap: () => setState(() => _category = isSelected ? null : category),
                  child: _buildChip(category.label, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Belt filter
            _buildSectionTitle('Faixa'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['white', 'blue', 'purple', 'brown', 'black'].map((belt) {
                final isSelected = _belt == belt;
                return GestureDetector(
                  onTap: () => setState(() => _belt = isSelected ? null : belt),
                  child: _buildChip(_getBeltLabel(belt), isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Account filter
            _buildSectionTitle('Conta'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                (true, 'Com conta'),
                (false, 'Sem conta'),
              ].map((item) {
                final isSelected = _account == item.$1;
                return GestureDetector(
                  onTap: () => setState(() => _account = isSelected ? null : item.$1),
                  child: _buildChip(item.$2, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Sort by
            _buildSectionTitle('Ordenar por'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ('name', 'Nome'),
                ('attendance', 'Presencas'),
                ('belt', 'Faixa'),
              ].map((item) {
                final isSelected = _sort == item.$1;
                return GestureDetector(
                  onTap: () => setState(() => _sort = item.$1),
                  child: _buildChip(item.$2, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onClear,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: AppTheme.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Limpar',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.onApply(_status, _category, _belt, _account, _sort),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Aplicar',
                      style: AppTheme.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: AppTheme.bodyMedium.copyWith(
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
        ),
      ),
      child: Text(
        label,
        style: AppTheme.bodySmall.copyWith(
          color: isSelected ? Colors.white : AppTheme.textPrimary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  String _getBeltLabel(String belt) {
    return getGradeLabel(SportId.bjj, belt);
  }
}
