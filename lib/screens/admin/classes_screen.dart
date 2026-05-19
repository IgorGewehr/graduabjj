import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';
import 'classes/class_detail.dart';
import 'classes/class_form.dart';
import 'classes/class_students.dart';
import 'classes/class_widgets.dart';

/// Admin Classes Screen — coordinator (≤400 LOC).
///
/// All heavy UI lives in `lib/screens/admin/classes/`:
///   - class_widgets.dart   — ClassCard, StatsCarouselSection, filter chips, etc.
///   - class_form.dart      — create / edit bottom-sheet
///   - class_detail.dart    — detail + delete-confirmation bottom-sheets
///   - class_students.dart  — manage-students bottom-sheet
///   - class_helpers.dart   — shared helpers + ScheduleEntry model
class AdminClassesScreen extends ConsumerStatefulWidget {
  const AdminClassesScreen({super.key});

  @override
  ConsumerState<AdminClassesScreen> createState() => _AdminClassesScreenState();
}

class _AdminClassesScreenState extends ConsumerState<AdminClassesScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  List<BJJClass> _classes = [];
  bool _isLoading = true;
  String _searchQuery = '';
  StudentCategory? _selectedCategory;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  // ── Data loading ───────────────────────────────────────────────────────────
  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final academyId = currentUser!.academyId!;
      final q = tatami.ClassesQuery(academyId: academyId);
      ref.invalidate(tatami.tatamiClassesLegacyProvider(q));
      final classes =
          await ref.read(tatami.tatamiClassesLegacyProvider(q).future);
      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ── Filtering ──────────────────────────────────────────────────────────────
  List<BJJClass> get _filteredClasses {
    var filtered = _classes;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }
    if (_selectedCategory != null) {
      filtered =
          filtered.where((c) => c.category == _selectedCategory).toList();
    }
    return filtered;
  }

  // ── Sheet launchers ────────────────────────────────────────────────────────
  void _openCreate() =>
      showCreateClassSheet(context, ref, onCreated: _loadClasses);

  void _openEdit(BJJClass cls) =>
      showEditClassSheet(context, ref, cls, onUpdated: _loadClasses);

  void _openDetail(BJJClass cls) {
    showClassDetails(
      context,
      ref,
      cls,
      onEdit: () => _openEdit(cls),
      onManageStudents: () => _openManageStudents(cls),
      onDeleteDone: _loadClasses,
    );
  }

  void _openManageStudents(BJJClass cls) =>
      showManageStudentsSheet(context, cls, onChanged: _loadClasses);

  void _openDeleteConfirmation(BJJClass cls) =>
      showDeleteConfirmation(context, ref, cls, onDeleteDone: _loadClasses);

  // ── Filter bottom-sheet ────────────────────────────────────────────────────
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text(
              'Filtrar por Categoria',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ...StudentCategory.values.map(
              (cat) => ListTile(
                leading: Icon(
                  _selectedCategory == cat
                      ? LucideIcons.checkCircle2
                      : LucideIcons.circle,
                  color: _selectedCategory == cat
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                ),
                title: Text(cat.label),
                onTap: () {
                  setState(() => _selectedCategory = cat);
                  Navigator.pop(sheetCtx);
                },
              ),
            ),
            ListTile(
              leading: Icon(
                _selectedCategory == null
                    ? LucideIcons.checkCircle2
                    : LucideIcons.circle,
                color: _selectedCategory == null
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
              ),
              title: const Text('Todas'),
              onTap: () {
                setState(() => _selectedCategory = null);
                Navigator.pop(sheetCtx);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final canWrite =
        user?.hasPermission(TatamiPermissions.studentsWrite) ?? false;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadClasses,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(
              child: StatsCarouselSection(classes: _classes),
            ),
            SliverToBoxAdapter(child: _buildSearchAndFilter()),
            SliverToBoxAdapter(child: _buildCategoryChips()),
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _filteredClasses.isEmpty
                ? SliverFillRemaining(child: _buildEmptyState())
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final cls = _filteredClasses[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ClassCard(
                              bjjClass: cls,
                              onTap: () => _openDetail(cls),
                              onEdit: canWrite ? () => _openEdit(cls) : null,
                              onDelete: canWrite
                                  ? () => _openDeleteConfirmation(cls)
                                  : null,
                            ),
                          );
                        },
                        childCount: _filteredClasses.length,
                      ),
                    ),
                  ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              backgroundColor: AppTheme.textPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(LucideIcons.plus, size: 20),
              label: const Text('Nova Turma'),
            )
          : null,
    );
  }

  // ── Section builders ───────────────────────────────────────────────────────

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
              '${_classes.length} turmas',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadClasses,
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

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(LucideIcons.search, color: AppTheme.textSecondary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Buscar turma...',
                  hintStyle: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textDisabled,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            Container(width: 1, height: 24, color: AppTheme.divider),
            IconButton(
              icon: Icon(
                LucideIcons.slidersHorizontal,
                color: _selectedCategory != null
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
                size: 20,
              ),
              onPressed: _showFilterSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          ClassFilterChip(
            label: 'Todas',
            isSelected: _selectedCategory == null,
            onTap: () => setState(() => _selectedCategory = null),
          ),
          const SizedBox(width: 8),
          ...StudentCategory.values.map(
            (cat) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClassFilterChip(
                label: cat.label,
                isSelected: _selectedCategory == cat,
                onTap: () => setState(() => _selectedCategory = cat),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              LucideIcons.users,
              size: 40,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma turma encontrada',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie uma nova turma para comecar',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
