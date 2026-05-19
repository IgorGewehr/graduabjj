import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import '../../widgets/common/academy_page_header.dart';
import 'students_list/quick_add_student_sheet.dart';
import 'students_list/student_card.dart';
import 'students_list/student_filters.dart';

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
  SportId? _sportFilter;
  String? _beltFilter;
  bool? _accountFilter; // null=all, true=linked, false=unlinked
  String _sortBy = 'name';

  // Auto-graduation snapshot (only loaded when feature is on)
  Map<String, EligibilitySnapshotEntry> _eligibilityByStudent = {};

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
      final academyId = FirebaseService.academyId;

      // Invalidate to force a fresh fetch on pull-to-refresh.
      ref.invalidate(
        tatami.tatamiStudentsLegacyProvider(
          tatami.StudentsQuery(academyId: academyId),
        ),
      );
      final students = await ref.read(
        tatami.tatamiStudentsLegacyProvider(
          tatami.StudentsQuery(academyId: academyId),
        ).future,
      );
      // Match legacy sort (alphabetical by fullName) — Tatami list may not
      // preserve client-side ordering by default.
      students.sort((a, b) => a.fullName.compareTo(b.fullName));

      // Eligibility snapshot — only loaded when the academy has auto-graduation
      // enabled. Reading the academy settings is cheap (single doc) and lets
      // us skip the expensive batch query otherwise.
      final settings = ref.read(academySettingsProvider).valueOrNull;
      Map<String, EligibilitySnapshotEntry> eligibility = {};
      if (settings?.autoGraduationEnabled == true) {
        final beltService = BeltProgressionService(FirebaseService.academyId);
        final snapshot = await beltService.getEligibilitySnapshot();
        eligibility = {for (final e in snapshot) e.studentId: e};
      }

      setState(() {
        _students = students;
        _eligibilityByStudent = eligibility;
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
      filtered = filtered
          .where(
            (s) =>
                s.fullName.toLowerCase().contains(query) ||
                (s.nickname?.toLowerCase().contains(query) ?? false) ||
                (s.email?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }

    // Status filter
    if (_statusFilter != null) {
      filtered = filtered.where((s) => s.status == _statusFilter).toList();
    }

    // Category filter
    if (_categoryFilter != null) {
      filtered = filtered.where((s) => s.category == _categoryFilter).toList();
    }

    // Sport filter — student must practice this modality
    if (_sportFilter != null) {
      filtered = filtered
          .where((s) => s.getSports().contains(_sportFilter))
          .toList();
    }

    // Belt filter — sport-aware. If a sport is selected, match the grade
    // for that sport; otherwise fall back to the legacy BJJ field for backward
    // compatibility with single-sport academies.
    if (_beltFilter != null) {
      filtered = filtered.where((s) {
        final sport = _sportFilter ?? s.getPrimarySport();
        final grade = s.getGrade(sport);
        return grade?.currentGrade == _beltFilter;
      }).toList();
    }

    // Account filter
    if (_accountFilter != null) {
      if (_accountFilter!) {
        filtered = filtered
            .where((s) => s.linkedUserId != null && s.linkedUserId!.isNotEmpty)
            .toList();
      } else {
        filtered = filtered
            .where((s) => s.linkedUserId == null || s.linkedUserId!.isEmpty)
            .toList();
      }
    }

    // Sorting
    switch (_sortBy) {
      case 'name':
        filtered.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case 'attendance':
        filtered.sort(
          (a, b) => b.totalAttendanceCount.compareTo(a.totalAttendanceCount),
        );
        break;
      case 'belt':
        filtered.sort((a, b) {
          final sportA = _sportFilter ?? a.getPrimarySport();
          final sportB = _sportFilter ?? b.getPrimarySport();
          final gradesA = getGradesForSport(sportA, category: a.category.value);
          final gradesB = getGradesForSport(sportB, category: b.category.value);
          final gradeA = a.getGrade(sportA)?.currentGrade ?? 'white';
          final gradeB = b.getGrade(sportB)?.currentGrade ?? 'white';
          final aIndex = gradesA.indexWhere((g) => g.id == gradeA);
          final bIndex = gradesB.indexWhere((g) => g.id == gradeB);
          if (aIndex != bIndex) return bIndex.compareTo(aIndex);
          final stripesA = a.getGrade(sportA)?.currentStripes ?? 0;
          final stripesB = b.getGrade(sportB)?.currentStripes ?? 0;
          return stripesB.compareTo(stripesA);
        });
        break;
      case 'eligible_first':
        // Eligible students float to the top, then closest-to-eligible by
        // progress fraction, then alphabetical as tiebreaker.
        filtered.sort((a, b) {
          final ea = _eligibilityByStudent[a.id];
          final eb = _eligibilityByStudent[b.id];
          final ael = ea?.eligible == true ? 1 : 0;
          final bel = eb?.eligible == true ? 1 : 0;
          if (ael != bel) return bel - ael;
          final aProg = (ea != null && ea.requiredClasses > 0)
              ? ea.currentClasses / ea.requiredClasses
              : 0.0;
          final bProg = (eb != null && eb.requiredClasses > 0)
              ? eb.currentClasses / eb.requiredClasses
              : 0.0;
          if (aProg != bProg) return bProg.compareTo(aProg);
          return a.fullName.compareTo(b.fullName);
        });
        break;
    }

    setState(() => _filteredStudents = filtered);
  }

  bool _hasActiveFilters() {
    return _statusFilter != null ||
        _categoryFilter != null ||
        _sportFilter != null ||
        _beltFilter != null ||
        _accountFilter != null;
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _categoryFilter = null;
      _sportFilter = null;
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
            // Multi-academy aware header — shows current academy + switcher
            SliverToBoxAdapter(
              child: AcademyPageHeader(
                icon: LucideIcons.users,
                title: 'Alunos',
                description: '${_students.length} alunos cadastrados',
                actions: [
                  IconButton(
                    onPressed: _loadStudents,
                    icon: const Icon(LucideIcons.refreshCw, size: 20),
                    tooltip: 'Atualizar',
                  ),
                ],
              ),
            ),

            // Search and filters
            SliverToBoxAdapter(child: _buildSearchAndFilters()),

            // Active filter chips
            if (_hasActiveFilters())
              SliverToBoxAdapter(child: _buildActiveFilterChips()),

            // Student list
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _filteredStudents.isEmpty
                ? SliverFillRemaining(child: _buildEmptyState())
                : _buildStudentSliverList(),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showQuickAddSheet,
        backgroundColor: AppTheme.textPrimary,
        child: const Icon(LucideIcons.userPlus, color: Colors.white),
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
                  hintStyle: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textDisabled,
                  ),
                  prefixIcon: Icon(
                    LucideIcons.search,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            LucideIcons.x,
                            color: AppTheme.textSecondary,
                            size: 18,
                          ),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
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
          ),
          const SizedBox(width: 12),
          // Filter button
          GestureDetector(
            onTap: _showFilterBottomSheet,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _hasActiveFilters()
                    ? AppTheme.primary
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasActiveFilters()
                      ? AppTheme.primary
                      : AppTheme.divider,
                ),
              ),
              child: Icon(
                LucideIcons.sliders,
                size: 20,
                color: _hasActiveFilters()
                    ? Colors.white
                    : AppTheme.textSecondary,
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
            StudentFilterChip(
              label: _statusFilter!.label,
              onRemove: () {
                setState(() {
                  _statusFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_categoryFilter != null)
            StudentFilterChip(
              label: _categoryFilter!.label,
              onRemove: () {
                setState(() {
                  _categoryFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_sportFilter != null)
            StudentFilterChip(
              label: sports[_sportFilter]!.label,
              onRemove: () {
                setState(() {
                  _sportFilter = null;
                  // Belt selection only makes sense within a sport — reset it.
                  _beltFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_beltFilter != null)
            StudentFilterChip(
              label:
                  'Faixa ${getGradeLabel(_sportFilter ?? SportId.bjj, _beltFilter!)}',
              onRemove: () {
                setState(() {
                  _beltFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_accountFilter != null)
            StudentFilterChip(
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
        delegate: SliverChildBuilderDelegate((context, index) {
          final student = _filteredStudents[index];
          return StudentCard(
            student: student,
            eligibility: _eligibilityByStudent[student.id],
            onTap: () => context.go('/admin/alunos/${student.id}'),
          );
        }, childCount: _filteredStudents.length),
      ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterBottomSheet(
        statusFilter: _statusFilter,
        categoryFilter: _categoryFilter,
        sportFilter: _sportFilter,
        beltFilter: _beltFilter,
        accountFilter: _accountFilter,
        sortBy: _sortBy,
        onApply: (status, category, sport, belt, account, sort) {
          setState(() {
            _statusFilter = status;
            _categoryFilter = category;
            _sportFilter = sport;
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
            _sportFilter = null;
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

  void _showQuickAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => QuickAddStudentSheet(
        onCreated: (student) {
          // Refresh list with the new student.
          _loadStudents();
        },
      ),
    );
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
            _hasActiveFilters()
                ? 'Nenhum aluno encontrado'
                : 'Nenhum aluno cadastrado',
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
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

