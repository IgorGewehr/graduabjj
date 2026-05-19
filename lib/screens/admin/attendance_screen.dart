import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/attendance_dto.dart' as api_att;
import '../../api/repositories.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/checkin.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import '../../services/checkin_service.dart';
import '../../widgets/checkin_confirm_dialog.dart';
import 'attendance/attendance_action_buttons.dart';
import 'attendance/attendance_calendar_sheet.dart';
import 'attendance/attendance_filters.dart';
import 'attendance/attendance_list.dart';

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

  // ============================================
  // Data loading
  // ============================================

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final academyId = currentUser!.academyId!;

      Future<List<BJJClass>> classesFuture() async {
        final q = tatami.ClassesQuery(
          academyId: academyId,
          isActive: true,
        );
        ref.invalidate(tatami.tatamiClassesLegacyProvider(q));
        return ref.read(tatami.tatamiClassesLegacyProvider(q).future);
      }

      Future<List<Student>> studentsFuture() async {
        final q = tatami.StudentsQuery(academyId: academyId);
        ref.invalidate(tatami.tatamiStudentsLegacyProvider(q));
        final all =
            await ref.read(tatami.tatamiStudentsLegacyProvider(q).future);
        return all
            .where((s) =>
                s.status == StudentStatus.active ||
                s.status == StudentStatus.injured)
            .toList();
      }

      final results = await Future.wait<dynamic>([
        classesFuture(),
        studentsFuture(),
      ]);

      setState(() {
        _classes = results[0] as List<BJJClass>;
        _students = results[1] as List<Student>;
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

      final academyId = currentUser!.academyId!;
      final dayStart = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));
      final q = tatami.AttendanceQuery(
        academyId: academyId,
        filter: api_att.AttendanceFilter(
          classId: _selectedClass!.id,
          dateFrom: dayStart,
          dateTo: dayEnd,
          limit: 200,
        ),
      );
      ref.invalidate(tatami.tatamiAttendanceLegacyProvider(q));
      final list =
          await ref.read(tatami.tatamiAttendanceLegacyProvider(q).future);

      setState(() {
        _presentStudentIds = list.map((a) => a.studentId).toSet();
      });

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

  // ============================================
  // Check-in management
  // ============================================

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
      if (mounted) setState(() => _isRemovingCheckin = false);
    }
  }

  Future<void> _handleAddManualCheckin(Student student) async {
    if (_selectedClass == null) return;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;

    setState(() => _isAddingCheckin = true);
    try {
      final checkinService = CheckinService(currentUser!.academyId!);
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
      if (mounted) setState(() => _isAddingCheckin = false);
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
        'Administrador',
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
      if (mounted) setState(() => _isConfirmingCheckins = false);
    }
  }

  // ============================================
  // Attendance toggling
  // ============================================

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
        setState(() => _presentStudentIds.remove(student.id));
      } else {
        await attendanceService.markPresent(
          studentId: student.id,
          studentName: student.fullName,
          classId: _selectedClass!.id,
          className: _selectedClass!.name,
          verifiedBy: 'admin',
          verifiedByName: 'Administrador',
          date: _selectedDate,
          weight: _selectedClass!.effectiveWeight(),
        );
        setState(() => _presentStudentIds.add(student.id));
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _markAllPresent() async {
    if (_selectedClass == null || _isSaving) return;

    final filteredStudents = _getFilteredStudents();
    if (filteredStudents.isEmpty) return;

    final confirmed = await showMarkAllPresentDialog(
      context,
      filteredStudents.length,
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final attendanceService = AttendanceService(currentUser!.academyId!);
      final studentsToMark = filteredStudents
          .where((s) => !_presentStudentIds.contains(s.id))
          .toList();

      if (studentsToMark.isEmpty) {
        if (mounted) context.showInfo('Todos ja estavam marcados.');
        return;
      }

      await attendanceService.bulkMarkPresent(
        students: studentsToMark
            .map((s) => (studentId: s.id, studentName: s.fullName))
            .toList(),
        classId: _selectedClass!.id,
        className: _selectedClass!.name,
        verifiedBy: 'admin',
        verifiedByName: 'Administrador',
        date: _selectedDate,
        weight: _selectedClass!.effectiveWeight(),
        repo: ref.read(attendanceRepoProvider),
      );

      _presentStudentIds.addAll(studentsToMark.map((s) => s.id));
      setState(() {});

      if (mounted) {
        context.showSuccess('${studentsToMark.length} alunos marcados!');
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _unmarkAllPresent() async {
    if (_selectedClass == null || _isSaving || _presentStudentIds.isEmpty) {
      return;
    }

    final confirmed = await showUnmarkAllPresentDialog(context);

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final attendanceService = AttendanceService(currentUser!.academyId!);
      final removed = await attendanceService.bulkUnmarkPresent(
        classId: _selectedClass!.id,
        date: _selectedDate,
      );

      setState(() => _presentStudentIds.clear());

      if (mounted) context.showInfo('$removed presencas removidas!');
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // ============================================
  // Calendar
  // ============================================

  void _showCalendarBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AttendanceCalendarSheet(
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

  // ============================================
  // Filtering
  // ============================================

  List<Student> _getFilteredStudents() {
    var filtered = _students;

    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((s) =>
              s.fullName.toLowerCase().contains(_searchQuery) ||
              (s.nickname?.toLowerCase().contains(_searchQuery) ?? false))
          .toList();
    }

    if (_selectedClass != null && _selectedClass!.studentIds.isNotEmpty) {
      filtered = filtered
          .where((s) => _selectedClass!.studentIds.contains(s.id))
          .toList();
    }

    if (_filterMode == 'present') {
      filtered =
          filtered.where((s) => _presentStudentIds.contains(s.id)).toList();
    } else if (_filterMode == 'absent') {
      filtered =
          filtered.where((s) => !_presentStudentIds.contains(s.id)).toList();
    }

    filtered.sort((a, b) => a.fullName.compareTo(b.fullName));
    return filtered;
  }

  int get _totalCount {
    if (_selectedClass != null && _selectedClass!.studentIds.isNotEmpty) {
      return _selectedClass!.studentIds.length;
    }
    return _students.length;
  }

  int get _presentCount => _presentStudentIds.length;
  int get _absentCount => _totalCount - _presentCount;

  // ============================================
  // Build
  // ============================================

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
              ? const Center(child: CircularProgressIndicator())
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
                              Expanded(
                                child: AttendanceClassDropdown(
                                  classes: _classes,
                                  selectedClass: _selectedClass,
                                  onChanged: (value) {
                                    setState(() => _selectedClass = value);
                                    _loadAttendanceForClass();
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              AttendanceDateButton(
                                selectedDate: _selectedDate,
                                isToday: _isToday,
                                onTap: _showCalendarBottomSheet,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Search bar
                      if (_selectedClass != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: AttendanceSearchBar(
                              controller: _searchController,
                              searchQuery: _searchQuery,
                              onChanged: (v) =>
                                  setState(() => _searchQuery = v),
                            ),
                          ),
                        ),

                      // Filter chips
                      if (_selectedClass != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: AttendanceFilterChips(
                              filterMode: _filterMode,
                              totalCount: _totalCount,
                              presentCount: _presentCount,
                              absentCount: _absentCount,
                              onFilterChanged: (mode) =>
                                  setState(() => _filterMode = mode),
                            ),
                          ),
                        ),

                      // Action buttons
                      if (_selectedClass != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: AttendanceActionButtons(
                              checkinEnabled: _checkinEnabled,
                              pendingCheckins: _pendingCheckins,
                              isSaving: _isSaving,
                              presentCount: _presentCount,
                              onShowCheckinDialog: _showCheckinDialog,
                              onMarkAllPresent: _markAllPresent,
                              onUnmarkAllPresent: _unmarkAllPresent,
                            ),
                          ),
                        ),

                      // Student list or empty state
                      _selectedClass == null
                          ? const SliverFillRemaining(
                              child: AttendanceSelectClassState(),
                            )
                          : AttendanceStudentSliverList(
                              filteredStudents: _getFilteredStudents(),
                              presentStudentIds: _presentStudentIds,
                              searchQuery: _searchQuery,
                              onToggleAttendance: _toggleAttendance,
                            ),

                      // Bottom padding
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),

          // Loading overlay
          if (_isSaving) const AttendanceSavingOverlay(),
        ],
      ),
    );
  }

}
