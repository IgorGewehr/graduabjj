import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/attendance_dto.dart' as api_att;
import '../../api/dto/student_dto.dart' as api_student;
import '../../api/repositories.dart';
import '../../api/tatami_exception.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/checkin.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import '../../services/checkin_service.dart'; // TODO(tatami): remove when pending-queue endpoints are available
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
  // Persists across widget rebuilds caused by shell navigation
  static String? _lastSelectedClassId;

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

      final classes = results[0] as List<BJJClass>;
      final restoredClass = _lastSelectedClassId != null
          ? classes.where((c) => c.id == _lastSelectedClassId).firstOrNull
          : null;

      setState(() {
        _classes = classes;
        _students = results[1] as List<Student>;
        _selectedClass = restoredClass;
        _isLoading = false;
      });

      if (restoredClass != null) {
        await _loadAttendanceForClass();
      }
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

      // TODO(tatami): replace with attendanceRepoProvider when
      // GET /v1/academies/{id}/pending-checkins is available in tatami.
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
      // TODO(tatami): replace with attendanceRepoProvider.delete when
      // DELETE /v1/academies/{id}/pending-checkins/{id} exists in tatami.
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
      // Tatami: POST /v1/academies/{id}/students/{sid}/attendance
      // Manual check-in is treated as a direct attendance record (no pending queue).
      final repo = ref.read(attendanceRepoProvider);
      await repo.markPresent(
        currentUser!.academyId!,
        student.id,
        api_att.AttendanceSingleRequest(
          classId: _selectedClass!.id,
          date: _selectedDate,
        ),
      );
      await _loadAttendanceForClass();
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
      final repo = ref.read(attendanceRepoProvider);
      final academyId = currentUser!.academyId!;
      // Resolve full Checkin objects from the loaded pending list.
      final toConfirm =
          _pendingCheckins.where((c) => checkinIds.contains(c.id)).toList();

      int success = 0;
      for (final checkin in toConfirm) {
        try {
          // Tatami: POST /v1/academies/{id}/students/{sid}/attendance
          await repo.markPresent(
            academyId,
            checkin.studentId,
            api_att.AttendanceSingleRequest(
              classId: checkin.classId,
              date: checkin.scheduleDate,
            ),
          );
          // TODO(tatami): remove Firestore pending-queue cleanup once tatami
          // manages the pending-checkin lifecycle end-to-end.
          final checkinService = CheckinService(academyId);
          await checkinService.removeCheckin(checkin.id);
          success++;
        } catch (_) {
          // Student may already be present (duplicate) — skip silently.
        }
      }

      if (mounted) {
        context.showSuccess('$success presenca(s) confirmada(s)!');
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

      final repo = ref.read(attendanceRepoProvider);
      final academyId = currentUser!.academyId!;
      final req = api_att.AttendanceSingleRequest(
        classId: _selectedClass!.id,
        date: _selectedDate,
      );
      final wasPresent = _presentStudentIds.contains(student.id);

      if (wasPresent) {
        // Tatami: DELETE /v1/academies/{id}/students/{sid}/attendance
        await repo.unmarkPresent(academyId, student.id, req);
        setState(() => _presentStudentIds.remove(student.id));
      } else {
        // Tatami: POST /v1/academies/{id}/students/{sid}/attendance
        try {
          await repo.markPresent(academyId, student.id, req);
        } on DioException catch (e) {
          final exc = e.error;
          if (exc is TatamiException &&
              exc.detail?.contains('sport') == true &&
              _selectedClass?.sport != null) {
            // Backend rejeita porque o aluno não tem o esporte da turma
            // registrado. Corrige automaticamente e re-tenta.
            final classSport = _selectedClass!.sport!;
            final current = student.sportsList ?? [];
            if (!current.contains(classSport)) {
              await ref.read(studentRepoProvider).update(
                    academyId,
                    student.id,
                    api_student.UpdateStudentRequest(
                      sportsList: [...current, classSport],
                    ),
                  );
            }
            await repo.markPresent(academyId, student.id, req);
          } else {
            rethrow;
          }
        }
        setState(() => _presentStudentIds.add(student.id));
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Erro ao registrar presença';
        if (e is DioException && e.error is TatamiException) {
          msg = (e.error as TatamiException).forUser(fallback: msg);
        }
        context.showError(msg);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

      final repo = ref.read(attendanceRepoProvider);
      final studentsToMark = filteredStudents
          .where((s) => !_presentStudentIds.contains(s.id))
          .toList();

      if (studentsToMark.isEmpty) {
        if (mounted) context.showInfo('Todos ja estavam marcados.');
        return;
      }

      // Tatami: POST /v1/academies/{id}/attendance/bulk
      final recorded = await repo.bulkRecord(
        currentUser!.academyId!,
        _selectedClass!.id,
        studentsToMark.map((s) => s.id).toList(),
      );

      // Only mark locally the ones the backend actually saved
      await _loadAttendanceForClass();

      if (mounted) {
        if (recorded == studentsToMark.length) {
          context.showSuccess('$recorded alunos marcados!');
        } else {
          final skipped = studentsToMark.length - recorded;
          context.showInfo(
            '$recorded marcados, $skipped ignorados (modalidade incompatível)',
          );
        }
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

      // Tatami: DELETE /v1/academies/{id}/students/{sid}/attendance per student.
      // No bulk-unmark endpoint exists yet — iterate present IDs.
      // TODO(tatami): replace with a single bulk-delete call when available.
      final repo = ref.read(attendanceRepoProvider);
      final academyId = currentUser!.academyId!;
      final req = api_att.AttendanceSingleRequest(
        classId: _selectedClass!.id,
        date: _selectedDate,
      );
      for (final studentId in _presentStudentIds.toList()) {
        await repo.unmarkPresent(academyId, studentId, req);
      }
      final removed = _presentStudentIds.length;

      if (mounted) setState(() => _presentStudentIds.clear());

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
                                    _lastSelectedClassId = value?.id;
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
