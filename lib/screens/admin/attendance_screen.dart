import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/checkin.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import '../../services/checkin_service.dart';
import '../../widgets/checkin_confirm_dialog.dart';
import '../../widgets/polish/polish.dart';

/// Admin Attendance Screen - Mobile-optimized matching webapp UX
class AdminAttendanceScreen extends ConsumerStatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  ConsumerState<AdminAttendanceScreen> createState() =>
      _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends ConsumerState<AdminAttendanceScreen> {
  List<BJJClass> _classes = [];
  List<Student> _students = [];
  Set<String> _presentStudentIds = {};
  List<Checkin> _pendingCheckins = [];
  BJJClass? _selectedClass;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isConfirmingCheckins = false;
  bool _isRemovingCheckin = false;
  bool _isAddingCheckin = false;
  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'present', 'absent'

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Real display name of the logged-in professor/admin to stamp on
  /// attendance records (verifiedByName). Returns '' when there is no real
  /// name set — the Jornada treats '' as "sem nome". We never fall back to a
  /// generic label like "Administrador".
  String get _verifierName =>
      ref.read(currentUserProvider).valueOrNull?.displayName.trim() ?? '';

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final currentUser = await ref.read(currentUserProvider.future);
      if (currentUser?.academyId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final academyId = currentUser!.academyId!;
      final classService = ClassService(academyId);
      final studentService = StudentService(academyId);

      // Sprint 5 — class list and active students are independent reads;
      // run them in parallel.
      final results = await Future.wait<dynamic>([
        classService.list(),
        studentService.getActive(),
      ]);
      final classes = results[0] as List<BJJClass>;
      final students = results[1] as List<Student>;

      setState(() {
        _classes = classes;
        _students = students;
        _selectedClass = null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAttendanceForClass() async {
    if (_selectedClass == null) {
      setState(() => _presentStudentIds = {});
      return;
    }

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final attendanceService = AttendanceService(currentUser!.academyId!);

      final attendance = await attendanceService.getByDateAndClass(
        _selectedDate,
        _selectedClass!.id,
      );

      setState(() {
        _presentStudentIds = attendance.map((a) => a.studentId).toSet();
      });

      // Load pending check-ins
      await _loadPendingCheckins();
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _loadPendingCheckins() async {
    if (_selectedClass == null) {
      setState(() => _pendingCheckins = []);
      return;
    }

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final checkinService = CheckinService(currentUser!.academyId!);
      final checkins = await checkinService.getPendingByClassAndDate(
        _selectedClass!.id,
        _selectedDate,
      );

      setState(() => _pendingCheckins = checkins);
    } catch (e) {
      // Handle error
    }
  }

  bool get _checkinEnabled {
    final settings = ref.read(academySettingsProvider).valueOrNull;
    return settings?.studentCheckinEnabled ?? false;
  }

  Future<void> _showCheckinDialog() async {
    if (_selectedClass == null) return;

    await showDialog(
      context: context,
      builder: (context) => CheckinConfirmDialog(
        selectedClass: _selectedClass!,
        checkins: _pendingCheckins,
        allStudents: _students,
        onRemoveCheckin: _handleRemoveCheckin,
        onAddManualCheckin: _handleAddManualCheckin,
        onConfirmCheckins: _handleConfirmCheckins,
        isConfirming: _isConfirmingCheckins,
        isRemoving: _isRemovingCheckin,
        isAdding: _isAddingCheckin,
      ),
    );
  }

  Future<void> _handleRemoveCheckin(String checkinId) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    setState(() => _isRemovingCheckin = true);
    try {
      final checkinService = CheckinService(currentUser!.academyId!);
      await checkinService.removeCheckin(checkinId);
      await _loadPendingCheckins();
    } finally {
      if (mounted) {
        setState(() => _isRemovingCheckin = false);
      }
    }
  }

  Future<void> _handleAddManualCheckin(Student student) async {
    if (_selectedClass == null) return;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    setState(() => _isAddingCheckin = true);
    try {
      final checkinService = CheckinService(currentUser!.academyId!);

      // Get schedule for today
      final dayOfWeek = _selectedDate.weekday % 7;
      final schedule = _selectedClass!.schedule.firstWhere(
        (s) => s.dayOfWeek == dayOfWeek,
        orElse: () => _selectedClass!.schedule.first,
      );

      await checkinService.addManualCheckin(
        studentId: student.id,
        studentName: student.fullName,
        classId: _selectedClass!.id,
        className: _selectedClass!.name,
        scheduleStartTime: schedule.startTime,
        scheduleEndTime: schedule.endTime,
        scheduleDayOfWeek: dayOfWeek,
        date: _selectedDate,
      );
      await _loadPendingCheckins();
    } catch (e) {
      if (mounted) {
        context.showError(e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingCheckin = false);
      }
    }
  }

  Future<void> _handleConfirmCheckins(List<String> checkinIds) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    setState(() => _isConfirmingCheckins = true);
    try {
      final checkinService = CheckinService(currentUser!.academyId!);
      final result = await checkinService.confirmCheckins(
        checkinIds,
        'admin',
        _verifierName,
      );

      if (mounted) {
        context.showSuccess('${result['success']} presenca(s) confirmada(s)!');
      }

      await _loadAttendanceForClass();
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao confirmar check-ins: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isConfirmingCheckins = false);
      }
    }
  }

  /// Opens a picker to add a student to the current class roll-call.
  /// Lists active students not yet in the class; the chosen one is enrolled
  /// in the class (and its sport) and immediately marked present. Also offers
  /// registering a brand-new student.
  Future<void> _showAddStudentDialog() async {
    if (_selectedClass == null) return;

    final outsiders = _students
        .where((s) => !_selectedClass!.studentIds.contains(s.id))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    final result = await showModalBottomSheet<_AddStudentResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddStudentSheet(outsiders: outsiders),
    );

    if (result == null || !mounted) return;

    if (result.createNew) {
      await context.push('/admin/alunos/novo');
      if (mounted) await _loadData();
      return;
    }

    if (result.student != null) {
      await _addExistingStudentToSession(result.student!);
    }
  }

  Future<void> _addExistingStudentToSession(Student student) async {
    if (_selectedClass == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final academyId = currentUser!.academyId!;
      final classService = ClassService(academyId);

      // Enroll in the class (adds to studentIds + seeds the sport's grade),
      // so the student becomes part of the roster and can graduate in it.
      final updated = await classService.addStudent(_selectedClass!.id, student.id);

      // Mark present for this session right away.
      if (!_presentStudentIds.contains(student.id)) {
        final attendanceService = AttendanceService(academyId);
        await attendanceService.markPresent(
          studentId: student.id,
          studentName: student.fullName,
          classId: _selectedClass!.id,
          className: _selectedClass!.name,
          verifiedBy: 'admin',
          verifiedByName: _verifierName,
          date: _selectedDate,
          weight: _selectedClass!.effectiveWeight(),
          sport: _selectedClass!.sport,
        );
      }

      setState(() {
        final idx = _classes.indexWhere((c) => c.id == updated.id);
        if (idx != -1) _classes[idx] = updated;
        _selectedClass = updated;
        _presentStudentIds.add(student.id);
      });

      if (mounted) {
        context.showSuccess('${student.fullName} adicionado(a) e presente!');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleAttendance(Student student) async {
    if (_selectedClass == null || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final attendanceService = AttendanceService(currentUser!.academyId!);
      final wasPresent = _presentStudentIds.contains(student.id);

      if (wasPresent) {
        await attendanceService.unmarkPresent(
          student.id,
          _selectedClass!.id,
          _selectedDate,
        );
        setState(() {
          _presentStudentIds.remove(student.id);
        });
      } else {
        await attendanceService.markPresent(
          studentId: student.id,
          studentName: student.fullName,
          classId: _selectedClass!.id,
          className: _selectedClass!.name,
          verifiedBy: 'admin',
          verifiedByName: _verifierName,
          date: _selectedDate,
          weight: _selectedClass!.effectiveWeight(),
          sport: _selectedClass!.sport,
        );
        setState(() {
          _presentStudentIds.add(student.id);
        });
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _markAllPresent() async {
    if (_selectedClass == null || _isSaving) return;

    final filteredStudents = _getFilteredStudents();
    if (filteredStudents.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar Todos Presentes'),
        content: Text(
          'Deseja marcar todos os ${filteredStudents.length} alunos como presentes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('Marcar Todos'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final attendanceService = AttendanceService(currentUser!.academyId!);

      // Filter students not already marked present
      final studentsToMark = filteredStudents
          .where((s) => !_presentStudentIds.contains(s.id))
          .toList();

      if (studentsToMark.isEmpty) {
        if (mounted) context.showInfo('Todos ja estavam marcados.');
        return;
      }

      // bulkMarkPresent collapses everything into a single Firestore batch —
      // one round trip total instead of ~3N (insert + counter update + read)
      // that the previous Future.wait+markPresent path was producing.
      await attendanceService.bulkMarkPresent(
        students: studentsToMark
            .map((s) => (studentId: s.id, studentName: s.fullName))
            .toList(),
        classId: _selectedClass!.id,
        className: _selectedClass!.name,
        verifiedBy: 'admin',
        verifiedByName: _verifierName,
        date: _selectedDate,
        weight: _selectedClass!.effectiveWeight(),
        sport: _selectedClass!.sport,
      );

      // Update local state
      _presentStudentIds.addAll(studentsToMark.map((s) => s.id));
      setState(() {});

      if (mounted) {
        context.showSuccess('${studentsToMark.length} alunos marcados!');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _unmarkAllPresent() async {
    if (_selectedClass == null || _isSaving || _presentStudentIds.isEmpty)
      return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Todas Presencas'),
        content: const Text('Deseja remover todas as presencas registradas?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remover Todas'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final attendanceService = AttendanceService(currentUser!.academyId!);

      // bulkUnmarkPresent collapses the previous N parallel unmarkPresent
      // calls (each: query + delete + counter update = 3 round trips per
      // student) into a single query + single batch commit.
      final removed = await attendanceService.bulkUnmarkPresent(
        classId: _selectedClass!.id,
        date: _selectedDate,
      );

      setState(() {
        _presentStudentIds.clear();
      });

      if (mounted) {
        context.showInfo('$removed presencas removidas!');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showCalendarBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CalendarBottomSheet(
        selectedDate: _selectedDate,
        onDateSelected: (date) {
          Navigator.pop(context);
          setState(() => _selectedDate = date);
          _loadAttendanceForClass();
        },
      ),
    );
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  List<Student> _getFilteredStudents() {
    var filteredStudents = _students;

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      filteredStudents = filteredStudents
          .where(
            (s) =>
                s.fullName.toLowerCase().contains(_searchQuery) ||
                (s.nickname?.toLowerCase().contains(_searchQuery) ?? false),
          )
          .toList();
    }

    // Filter by class students
    if (_selectedClass != null) {
      filteredStudents = filteredStudents
          .where((s) => _selectedClass!.studentIds.contains(s.id))
          .toList();
    }

    // Filter by presence status
    if (_filterMode == 'present') {
      filteredStudents = filteredStudents
          .where((s) => _presentStudentIds.contains(s.id))
          .toList();
    } else if (_filterMode == 'absent') {
      filteredStudents = filteredStudents
          .where((s) => !_presentStudentIds.contains(s.id))
          .toList();
    }

    // Sort alphabetically
    filteredStudents.sort((a, b) => a.fullName.compareTo(b.fullName));

    return filteredStudents;
  }

  int get _totalCount {
    if (_selectedClass != null) {
      return _selectedClass!.studentIds.length;
    }
    return _students.length;
  }

  int get _presentCount => _presentStudentIds.length;
  int get _absentCount => _totalCount - _presentCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: _isSaving
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/admin/chamada/qr'),
              icon: const Icon(LucideIcons.qrCode, size: 18),
              label: const Text('Chamada por QR'),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
      body: Stack(
        children: [
          _isLoading
              ? PolishSkeleton.list(count: 6)
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    slivers: [
                      // Class + Date Selectors
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              // Class Dropdown
                              Expanded(child: _buildClassDropdown()),
                              const SizedBox(width: 12),
                              // Date Button
                              _buildDateButton(),
                            ],
                          ),
                        ),
                      ),

                      // Search bar
                      if (_selectedClass != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: _buildSearchBar(),
                          ),
                        ),

                      // Filter chips
                      if (_selectedClass != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: _buildFilterChips(),
                          ),
                        ),

                      // Action buttons
                      if (_selectedClass != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: _buildActionButtons(),
                          ),
                        ),

                      // Student list or empty state
                      _selectedClass == null
                          ? SliverFillRemaining(child: _buildSelectClassState())
                          : _buildStudentSliverList(),

                      // Bottom padding
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
          // Loading overlay: covers the screen while a bulk operation runs.
          // Blocks taps and shows a clear "doing work" affordance — without
          // this the user sees a frozen UI for several seconds with no signal.
          if (_isSaving)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Processando presencas...',
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClassDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<BJJClass>(
        value: _selectedClass,
        isExpanded: true,
        icon: Icon(
          LucideIcons.chevronDown,
          color: AppTheme.textSecondary,
          size: 20,
        ),
        decoration: InputDecoration(
          labelText: 'Turma',
          labelStyle: AppTheme.bodySmall.copyWith(
            color: AppTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
        ),
        items: _classes.map((cls) {
          return DropdownMenuItem<BJJClass>(
            value: cls,
            child: Text(
              cls.name,
              style: AppTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (value) {
          setState(() => _selectedClass = value);
          _loadAttendanceForClass();
        },
        dropdownColor: AppTheme.surface,
      ),
    );
  }

  Widget _buildDateButton() {
    return GestureDetector(
      onTap: _showCalendarBottomSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.textPrimary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.calendar, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              _isToday ? 'Hoje' : '${_selectedDate.day}/${_selectedDate.month}',
              style: AppTheme.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
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
                    setState(() => _searchQuery = '');
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
          setState(() => _searchQuery = value.toLowerCase());
        },
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Todos
          _FilterChipButton(
            label: 'Todos ($_totalCount)',
            isSelected: _filterMode == 'all',
            onTap: () => setState(() => _filterMode = 'all'),
          ),
          const SizedBox(width: 8),
          // Presentes
          _FilterChipButton(
            label: 'Presentes ($_presentCount)',
            icon: LucideIcons.checkCircle,
            iconColor: AppTheme.success,
            isSelected: _filterMode == 'present',
            onTap: () => setState(
              () => _filterMode = _filterMode == 'present' ? 'all' : 'present',
            ),
          ),
          const SizedBox(width: 8),
          // Ausentes
          _FilterChipButton(
            label: 'Ausentes ($_absentCount)',
            icon: LucideIcons.circle,
            iconColor: AppTheme.textSecondary,
            isSelected: _filterMode == 'absent',
            onTap: () => setState(
              () => _filterMode = _filterMode == 'absent' ? 'all' : 'absent',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Check-ins button (only show if enabled and has pending check-ins)
        if (_checkinEnabled && _pendingCheckins.isNotEmpty) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showCheckinDialog,
              icon: const Icon(LucideIcons.userCheck, size: 18),
              label: Text('Check-ins (${_pendingCheckins.length})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        Row(
          children: [
            // Adicionar (green) - only if no check-ins button
            if (!(_checkinEnabled && _pendingCheckins.isNotEmpty))
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_selectedClass == null || _isSaving)
                      ? null
                      : _showAddStudentDialog,
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: const Text('Adicionar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (!(_checkinEnabled && _pendingCheckins.isNotEmpty))
              const SizedBox(width: 8),
            // Todos (outlined)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _markAllPresent,
                icon: const Icon(LucideIcons.checkCheck, size: 18),
                label: const Text('Todos'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: BorderSide(color: AppTheme.divider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Limpar (outlined)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving || _presentCount == 0
                    ? null
                    : _unmarkAllPresent,
                icon: const Icon(LucideIcons.x, size: 18),
                label: const Text('Limpar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: BorderSide(color: AppTheme.divider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectClassState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.users,
                size: 36,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Selecione uma turma',
              style: AppTheme.titleMedium.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Escolha uma turma acima para\nregistrar as presencas',
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentSliverList() {
    final filteredStudents = _getFilteredStudents();

    if (filteredStudents.isEmpty) {
      return SliverFillRemaining(
        child: PolishedEmptyState(
          icon: LucideIcons.userX,
          title: _searchQuery.isNotEmpty
              ? 'Nenhum aluno encontrado'
              : 'Nenhum aluno nesta turma',
          subtitle: _searchQuery.isNotEmpty
              ? 'Tente outro termo de busca.'
              : 'Adicione alunos para registrar presenca.',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final student = filteredStudents[index];
          final isPresent = _presentStudentIds.contains(student.id);

          return _AttendanceStudentCard(
            student: student,
            isPresent: isPresent,
            onTap: () => _toggleAttendance(student),
          ).entrance(index: index);
        }, childCount: filteredStudents.length),
      ),
    );
  }
}

/// Filter Chip Button - matches webapp style
class _FilterChipButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    this.icon,
    this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : iconColor,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTheme.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Calendar Bottom Sheet
class _CalendarBottomSheet extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const _CalendarBottomSheet({
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<_CalendarBottomSheet> createState() => _CalendarBottomSheetState();
}

class _CalendarBottomSheetState extends State<_CalendarBottomSheet> {
  late DateTime _viewMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _viewMonth = widget.selectedDate;
    _selectedDate = widget.selectedDate;
  }

  List<DateTime> _getDaysInMonth() {
    final firstDayOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    final lastDayOfMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 0);
    final startDate = firstDayOfMonth.subtract(
      Duration(days: firstDayOfMonth.weekday % 7),
    );
    final endDate = lastDayOfMonth.add(
      Duration(days: 6 - (lastDayOfMonth.weekday % 7)),
    );

    final days = <DateTime>[];
    var current = startDate;
    while (!current.isAfter(endDate)) {
      days.add(current);
      current = current.add(const Duration(days: 1));
    }
    return days;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
  bool _isToday(DateTime date) => _isSameDay(date, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth();
    final weekdays = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
    final months = [
      'Janeiro',
      'Fevereiro',
      'Marco',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
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
          const SizedBox(height: 16),

          // Title
          Text(
            'Selecionar Data',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),

          // Month Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => setState(
                  () => _viewMonth = DateTime(
                    _viewMonth.year,
                    _viewMonth.month - 1,
                    1,
                  ),
                ),
                icon: const Icon(LucideIcons.chevronLeft, size: 20),
              ),
              Row(
                children: [
                  Text(
                    '${months[_viewMonth.month - 1]} ${_viewMonth.year}',
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!_isSameMonth(_viewMonth, DateTime.now())) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        final today = DateTime.now();
                        setState(() {
                          _viewMonth = today;
                          _selectedDate = today;
                        });
                        widget.onDateSelected(today);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Hoje',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              IconButton(
                onPressed: () => setState(
                  () => _viewMonth = DateTime(
                    _viewMonth.year,
                    _viewMonth.month + 1,
                    1,
                  ),
                ),
                icon: const Icon(LucideIcons.chevronRight, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Weekday headers
          Row(
            children: weekdays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),

          // Calendar Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              final isCurrentMonth = _isSameMonth(day, _viewMonth);
              final isSelected = _isSameDay(day, _selectedDate);
              final isTodayDate = _isToday(day);
              final isFuture = day.isAfter(DateTime.now());

              return GestureDetector(
                onTap: isFuture || !isCurrentMonth
                    ? null
                    : () {
                        setState(() => _selectedDate = day);
                        widget.onDateSelected(day);
                      },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary
                        : isTodayDate
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isTodayDate && !isSelected
                        ? Border.all(color: AppTheme.primary, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${day.day}',
                      style: AppTheme.bodySmall.copyWith(
                        color: isSelected
                            ? Colors.white
                            : !isCurrentMonth || isFuture
                            ? AppTheme.textDisabled
                            : AppTheme.textPrimary,
                        fontWeight: isSelected || isTodayDate
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Attendance Student Card - matches webapp mobile design
class _AttendanceStudentCard extends StatelessWidget {
  final Student student;
  final bool isPresent;
  final VoidCallback onTap;

  const _AttendanceStudentCard({
    required this.student,
    required this.isPresent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: PolishMotion.fast,
        curve: PolishMotion.transition,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPresent
              ? AppTheme.success.withValues(alpha: 0.05)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPresent ? AppTheme.success : AppTheme.divider,
            width: isPresent ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Toggle Circle
            AnimatedContainer(
              duration: PolishMotion.fast,
              curve: PolishMotion.transition,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isPresent ? AppTheme.success : AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: AnimatedSwitcher(
                duration: PolishMotion.fast,
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  isPresent ? LucideIcons.checkCircle : LucideIcons.circle,
                  key: ValueKey(isPresent),
                  color: isPresent ? Colors.white : AppTheme.textDisabled,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (student.fullName.isNotEmpty ? student.fullName[0] : '?')
                      .toUpperCase(),
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.nickname ?? student.fullName.split(' ').first,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isPresent
                          ? AppTheme.success
                          : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    student.fullName,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Belt stripes indicator
            _buildBeltIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildBeltIndicator() {
    final beltColor = _getBeltColor(student.currentBelt, sportId: student.getPrimarySport());
    final stripes = student.currentStripes.clamp(0, 4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Belt bar
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: beltColor,
            borderRadius: BorderRadius.circular(2),
            border: student.currentBelt == 'white'
                ? Border.all(color: AppTheme.divider)
                : null,
          ),
        ),
        if (stripes > 0) ...[
          const SizedBox(width: 4),
          // Stripes
          Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              stripes,
              (_) => Container(
                width: 6,
                height: 2,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Color _getBeltColor(String belt, {SportId sportId = SportId.bjj}) =>
      getGradeColor(sportId, belt);
}

/// Result of the add-student picker: either an existing student to enroll,
/// or a request to register a brand-new student.
class _AddStudentResult {
  final Student? student;
  final bool createNew;
  const _AddStudentResult.existing(this.student) : createNew = false;
  const _AddStudentResult.create()
      : student = null,
        createNew = true;
}

/// Bottom sheet that lists active students not yet in the selected class,
/// with search, plus a "register new student" shortcut.
class _AddStudentSheet extends StatefulWidget {
  const _AddStudentSheet({required this.outsiders});

  final List<Student> outsiders;

  @override
  State<_AddStudentSheet> createState() => _AddStudentSheetState();
}

class _AddStudentSheetState extends State<_AddStudentSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.outsiders
        : widget.outsiders
            .where(
              (s) =>
                  s.fullName.toLowerCase().contains(_query) ||
                  (s.nickname?.toLowerCase().contains(_query) ?? false),
            )
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Adicionar aluno',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (v) =>
                    setState(() => _query = v.toLowerCase().trim()),
                decoration: InputDecoration(
                  hintText: 'Buscar aluno...',
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, const _AddStudentResult.create()),
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: const Text('Cadastrar novo aluno'),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('Nenhum aluno fora da turma.'),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final s = filtered[i];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                s.fullName.isNotEmpty
                                    ? s.fullName[0].toUpperCase()
                                    : '?',
                              ),
                            ),
                            title: Text(s.fullName),
                            subtitle:
                                (s.nickname != null && s.nickname!.isNotEmpty)
                                    ? Text(s.nickname!)
                                    : null,
                            trailing: const Icon(LucideIcons.plus, size: 18),
                            onTap: () => Navigator.pop(
                              context,
                              _AddStudentResult.existing(s),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
