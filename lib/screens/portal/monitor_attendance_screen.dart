import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/attendance_dto.dart' as api_att;
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/checkin.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../api/repositories.dart';
import '../../providers/portal_providers.dart';
import '../../services/checkin_service.dart'; // TODO(tatami): remove when pending-queue endpoints are available
import '../../services/class_service.dart';
import '../../widgets/checkin_confirm_dialog.dart';
import 'monitor_attendance/attendance_action_buttons.dart';
import 'monitor_attendance/attendance_class_controls.dart';
import 'monitor_attendance/attendance_filter_chips.dart';
import 'monitor_attendance/attendance_student_card.dart';

/// Monitor Attendance Screen - For student monitors to take attendance
class MonitorAttendanceScreen extends ConsumerStatefulWidget {
  const MonitorAttendanceScreen({super.key});

  @override
  ConsumerState<MonitorAttendanceScreen> createState() =>
      _MonitorAttendanceScreenState();
}

class _MonitorAttendanceScreenState
    extends ConsumerState<MonitorAttendanceScreen> {
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
  String _filterMode = 'all';

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
        final q = tatami.ClassesQuery(academyId: academyId, isActive: true);
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
      final dayStart =
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
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

      setState(() => _presentStudentIds = list.map((a) => a.studentId).toSet());
      await _loadPendingCheckins();
    } catch (e) {
      // ignore
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
      // ignore
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
      // Resolve studentIds from the pending checkins list and mark present in Tatami.
      final toConfirm = _pendingCheckins
          .where((c) => checkinIds.contains(c.id))
          .toList();
      for (final c in toConfirm) {
        await repo.markPresent(
          academyId,
          c.studentId,
          api_att.AttendanceSingleRequest(
            classId: _selectedClass!.id,
            date: _selectedDate,
          ),
        );
      }
      // TODO(tatami): remove Firestore pending-queue cleanup once tatami
      // manages the pending-checkin lifecycle end-to-end.
      final checkinService = CheckinService(academyId);
      for (final id in checkinIds) {
        await checkinService.removeCheckin(id);
      }
      if (mounted) {
        context.showSuccess('${toConfirm.length} presenca(s) confirmada(s)!');
      }
      await _loadAttendanceForClass();
    } catch (e) {
      if (mounted) context.showError('Erro ao confirmar check-ins: $e');
    } finally {
      if (mounted) setState(() => _isConfirmingCheckins = false);
    }
  }

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
        await repo.unmarkPresent(academyId, student.id, req);
        setState(() => _presentStudentIds.remove(student.id));
      } else {
        await repo.markPresent(academyId, student.id, req);
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

      final repo = ref.read(attendanceRepoProvider);
      final academyId = currentUser!.academyId!;
      final absentIds = filteredStudents
          .where((s) => !_presentStudentIds.contains(s.id))
          .map((s) => s.id)
          .toList();

      if (absentIds.isNotEmpty) {
        await repo.bulkRecord(academyId, _selectedClass!.id, absentIds);
        setState(() => _presentStudentIds.addAll(absentIds));
      }
      if (mounted) {
        context.showSuccess('${absentIds.length} alunos marcados!');
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

      final repo = ref.read(attendanceRepoProvider);
      final academyId = currentUser!.academyId!;
      for (final studentId in _presentStudentIds.toList()) {
        await repo.unmarkPresent(
          academyId,
          studentId,
          api_att.AttendanceSingleRequest(
            classId: _selectedClass!.id,
            date: _selectedDate,
          ),
        );
      }
      setState(() => _presentStudentIds.clear());
      if (mounted) context.showInfo('Presencas removidas!');
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  List<Student> _getFilteredStudents() {
    var result = _students;
    if (_searchQuery.isNotEmpty) {
      result = result
          .where((s) =>
              s.fullName.toLowerCase().contains(_searchQuery) ||
              (s.nickname?.toLowerCase().contains(_searchQuery) ?? false))
          .toList();
    }
    if (_selectedClass != null && _selectedClass!.studentIds.isNotEmpty) {
      result = result
          .where((s) => _selectedClass!.studentIds.contains(s.id))
          .toList();
    }
    if (_filterMode == 'present') {
      result = result.where((s) => _presentStudentIds.contains(s.id)).toList();
    } else if (_filterMode == 'absent') {
      result =
          result.where((s) => !_presentStudentIds.contains(s.id)).toList();
    }
    result.sort((a, b) => a.fullName.compareTo(b.fullName));
    return result;
  }

  int get _totalCount {
    if (_selectedClass != null && _selectedClass!.studentIds.isNotEmpty) {
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: () async {
                HapticFeedback.mediumImpact();
                await _loadData();
              },
              child: CustomScrollView(
                slivers: [
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
                            onDateChanged: (date) {
                              setState(() => _selectedDate = date);
                              _loadAttendanceForClass();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_selectedClass != null) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: AttendanceSearchBar(
                          controller: _searchController,
                          searchQuery: _searchQuery,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value.toLowerCase()),
                          onClear: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                      ),
                    ),
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
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: AttendanceActionButtons(
                          checkinEnabled: _checkinEnabled,
                          pendingCheckinsCount: _pendingCheckins.length,
                          isSaving: _isSaving,
                          presentCount: _presentCount,
                          onShowCheckins: _showCheckinDialog,
                          onMarkAll: _markAllPresent,
                          onClearAll: _unmarkAllPresent,
                        ),
                      ),
                    ),
                  ],
                  _selectedClass == null
                      ? const SliverFillRemaining(
                          child: AttendanceSelectClassState(),
                        )
                      : _buildStudentSliverList(),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
    );
  }

  Widget _buildStudentSliverList() {
    final filteredStudents = _getFilteredStudents();

    if (filteredStudents.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.userX, size: 48, color: AppTheme.textDisabled),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Nenhum aluno encontrado'
                    : 'Nenhum aluno nesta turma',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final student = filteredStudents[index];
            final isPresent = _presentStudentIds.contains(student.id);
            return AttendanceStudentCard(
              student: student,
              isPresent: isPresent,
              onTap: () => _toggleAttendance(student),
            );
          },
          childCount: filteredStudents.length,
        ),
      ),
    );
  }
}
