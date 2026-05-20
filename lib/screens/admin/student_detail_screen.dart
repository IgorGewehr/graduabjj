import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/attendance_dto.dart' as api_att;
import '../../api/dto/financial_dto.dart' as api_fin;
import '../../api/dto/student_dto.dart'
    show UpdateStudentRequest, ApiStudentStatusX;
import '../../api/repositories.dart' as tatami_repos;
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../models/user.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import 'student_detail/achievements_tab.dart';
import 'student_detail/attendance_tab.dart';
import 'student_detail/behavior_tab.dart';
import 'student_detail/financial_tab.dart';
import 'student_detail/history_tab.dart';
import 'student_detail/info_tab.dart';
import 'student_detail/link_code_dialog.dart';
import 'student_detail/promote_dialog.dart';
import 'student_detail/student_header.dart';
import 'student_detail/tab_with_badge.dart';

/// Admin Student Detail Screen — thin coordinator.
///
/// Owns all state and data-loading; delegates every rendering concern to
/// sub-widgets inside `student_detail/`.
class AdminStudentDetailScreen extends ConsumerStatefulWidget {
  final String studentId;

  const AdminStudentDetailScreen({super.key, required this.studentId});

  @override
  ConsumerState<AdminStudentDetailScreen> createState() =>
      _AdminStudentDetailScreenState();
}

class _AdminStudentDetailScreenState
    extends ConsumerState<AdminStudentDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Student? _student;
  List<Attendance> _attendances = [];
  List<Payment> _payments = [];
  List<StoreOrder> _storeOrders = [];
  List<BeltProgression> _progressions = [];
  List<Achievement> _achievements = [];
  List<Assessment> _assessments = [];
  List<Plan> _studentPlans = [];
  bool _isLoading = true;
  EligibilityResult? _eligibility;
  bool _autoGradEnabled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Data loading
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = ref.read(safeAcademyIdProvider) ?? '';
      if (academyId.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      Future<Student?> studentFuture() async {
        try {
          ref.invalidate(tatami.tatamiStudentByIdLegacyProvider(
            tatami.studentRef(academyId, widget.studentId),
          ));
          return await ref.read(
            tatami.tatamiStudentByIdLegacyProvider(
              tatami.studentRef(academyId, widget.studentId),
            ).future,
          );
        } catch (_) {
          return null;
        }
      }

      Future<List<Attendance>> attendanceFuture() async {
        final q = tatami.AttendanceQuery(
          academyId: academyId,
          filter: api_att.AttendanceFilter(
            studentId: widget.studentId,
            limit: 200,
          ),
        );
        ref.invalidate(tatami.tatamiAttendanceLegacyProvider(q));
        return ref.read(tatami.tatamiAttendanceLegacyProvider(q).future);
      }

      Future<List<Payment>> paymentsFuture() async {
        final q = tatami.FinancialsQuery(
          academyId: academyId,
          filter: api_fin.FinancialFilter(
            studentId: widget.studentId,
            limit: 100,
          ),
        );
        ref.invalidate(tatami.tatamiPaymentsLegacyProvider(q));
        return ref.read(tatami.tatamiPaymentsLegacyProvider(q).future);
      }

      Future<List<BeltProgression>> progressionsFuture() async {
        final page = await ref
            .read(tatami_repos.beltProgressionRepoProvider)
            .getHistory(academyId, widget.studentId, limit: 100);
        return page.items.map(BeltProgression.fromApi).toList()
          ..sort((a, b) => b.promotionDate.compareTo(a.promotionDate));
      }

      Future<List<Achievement>> achievementsFuture() async {
        final page = await ref
            .read(tatami_repos.achievementRepoProvider)
            .getByStudent(academyId, widget.studentId, limit: 100);
        return page.items
            .map((a) => Achievement.fromApiRepo(a))
            .toList();
      }

      Future<List<Assessment>> assessmentsFuture() async {
        final page = await ref
            .read(tatami_repos.assessmentRepoProvider)
            .getByStudent(academyId, widget.studentId, limit: 100);
        return page.items.map(Assessment.fromApi).toList();
      }

      Future<List<StoreOrder>> storeOrdersFuture() async {
        final page = await ref
            .read(tatami_repos.storeRepoProvider)
            .listOrders(academyId, studentId: widget.studentId, limit: 50);
        return page.items.map(StoreOrder.fromApi).toList();
      }

      final futures = await Future.wait<dynamic>([
        studentFuture(),
        attendanceFuture(),
        paymentsFuture(),
        storeOrdersFuture(),
        progressionsFuture(),
        achievementsFuture(),
        assessmentsFuture(),
        ref
            .read(tatami_repos.planRepoProvider)
            .list(academyId)
            .then(
              (apiPlans) => apiPlans
                  .map(Plan.fromApi)
                  .where((p) => p.studentIds.contains(widget.studentId))
                  .toList(),
            ),
      ]);

      final student = futures[0] as Student?;
      final attendances = futures[1] as List<Attendance>;
      final payments = futures[2] as List<Payment>;
      final storeOrders = futures[3] as List<StoreOrder>;
      final progressions = futures[4] as List<BeltProgression>;
      final achievements = futures[5] as List<Achievement>;
      final assessments = futures[6] as List<Assessment>;
      final studentPlans = futures[7] as List<Plan>;

      final settings = ref.read(academySettingsProvider).valueOrNull;
      final autoGradOn = settings?.autoGraduationEnabled == true;
      EligibilityResult? eligibility;
      if (autoGradOn && student != null) {
        eligibility = await _loadEligibility(academyId, student);
      }

      setState(() {
        _student = student;
        _attendances = attendances;
        _payments = payments;
        _storeOrders = storeOrders;
        _progressions = progressions;
        _achievements = achievements;
        _assessments = assessments;
        _studentPlans = studentPlans;
        _autoGradEnabled = autoGradOn;
        _eligibility = eligibility;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// Carrega a elegibilidade do aluno via Tatami e adapta para [EligibilityResult].
  Future<EligibilityResult?> _loadEligibility(
    String academyId,
    Student student,
  ) async {
    try {
      final el = await ref
          .read(tatami_repos.beltProgressionRepoProvider)
          .getEligibility(academyId, student.id);
      return EligibilityResult(
        eligible: el.eligible,
        nextBelt: el.nextBelt?.name,
        nextStripes: el.nextStripes,
        currentClasses: el.currentCount,
        requiredClasses: el.requiredCount,
        missingClasses: el.attendancesNeeded,
        message: el.eligible
            ? (el.nextStripes != null && el.nextStripes! > 0
                ? 'Elegível para ${el.nextStripes}º grau!'
                : 'Elegível para próxima faixa!')
            : 'Faltam ${el.attendancesNeeded} aulas',
      );
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Actions
  // ──────────────────────────────────────────────────────────────────────────

  void _showPromoteDialog() => showPromoteDialog(
        context: context,
        ref: ref,
        student: _student!,
        onSuccess: _loadData,
      );

  void _toggleStatus() async {
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final academyId = ref.read(safeAcademyIdProvider) ?? '';
      final newStatus = _student!.status == StudentStatus.active
          ? StudentStatus.inactive
          : StudentStatus.active;

      await ref.read(tatami_repos.studentRepoProvider).update(
            academyId,
            _student!.id,
            UpdateStudentRequest(
              status: ApiStudentStatusX.fromWire(newStatus.value),
            ),
          );

      if (mounted) {
        context.showSuccess(
          newStatus == StudentStatus.active
              ? 'Aluno ativado!'
              : 'Aluno desativado!',
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    }
  }

  void _showDeleteConfirmation() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Aluno'),
        content: Text(
          'Deseja excluir ${_student!.fullName}? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                final currentUser =
                    ref.read(currentUserProvider).valueOrNull;
                final academyId = ref.read(safeAcademyIdProvider) ?? '';
                await ref
                    .read(tatami_repos.studentRepoProvider)
                    .delete(academyId, _student!.id);
                if (!mounted || !ctx.mounted) return;
                Navigator.pop(ctx);
                context.showSuccess('Aluno excluído!');
                context.go('/admin/alunos');
              } catch (e) {
                if (mounted) context.showError('Erro: $e');
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _generateLinkCode() => showGenerateLinkCodeFlow(
        context: context,
        ref: ref,
        studentId: _student!.id,
        studentName: _student!.fullName,
      );

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_student == null) {
      return const Scaffold(
        body: Center(child: Text('Aluno não encontrado')),
      );
    }

    final user = ref.watch(currentUserProvider).valueOrNull;
    final canEdit =
        user?.hasPermission(TatamiPermissions.studentsWrite) ?? false;
    final canDelete = canEdit && (user?.isAdmin ?? false);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          StudentDetailSliverAppBar(
            student: _student!,
            ref: ref,
            canEdit: canEdit,
            canDelete: canDelete,
            onEdit: () async {
              final result = await context.push(
                '/admin/alunos/${widget.studentId}/editar',
              );
              if (result == true && mounted) _loadData();
            },
            onPromote: _showPromoteDialog,
            onToggleStatus: _toggleStatus,
            onGenerateCode: _generateLinkCode,
            onDelete: _showDeleteConfirmation,
            onPhotoUpdated: _loadData,
          ),
        ],
        body: Column(
          children: [
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  StudentInfoTab(
                    student: _student!,
                    attendances: _attendances,
                    achievements: _achievements,
                    autoGradEnabled: _autoGradEnabled,
                    eligibility: _eligibility,
                    onShowPromoteDialog: _showPromoteDialog,
                  ),
                  StudentAttendanceTab(attendances: _attendances),
                  StudentFinancialTab(
                    studentId: widget.studentId,
                    payments: _payments,
                    storeOrders: _storeOrders,
                    studentPlans: _studentPlans,
                    onRefresh: _loadData,
                    ref: ref,
                  ),
                  StudentBehaviorTab(
                    student: _student!,
                    assessments: _assessments,
                    ref: ref,
                    onRefresh: _loadData,
                  ),
                  StudentAchievementsTab(
                    student: _student!,
                    achievements: _achievements,
                    onRefresh: _loadData,
                  ),
                  StudentHistoryTab(
                    progressions: _progressions,
                    achievements: _achievements,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.primary, width: 3),
          ),
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(LucideIcons.info, size: 16),
                SizedBox(width: 6),
                Text('Info'),
              ],
            ),
          ),
          Tab(
            child: TabWithBadge(
              icon: LucideIcons.clipboardCheck,
              label: 'Presenças',
              count: _attendances.length,
            ),
          ),
          Tab(
            child: TabWithBadge(
              icon: LucideIcons.dollarSign,
              label: 'Financeiro',
              count: _payments.length + _storeOrders.length,
            ),
          ),
          Tab(
            child: TabWithBadge(
              icon: LucideIcons.star,
              label: 'Comportamento',
              count: _assessments.length,
            ),
          ),
          Tab(
            child: TabWithBadge(
              icon: LucideIcons.trophy,
              label: 'Conquistas',
              count: _achievements.length,
            ),
          ),
          Tab(
            child: TabWithBadge(
              icon: LucideIcons.history,
              label: 'Histórico',
              count: _progressions.length + _achievements.length,
            ),
          ),
        ],
      ),
    );
  }
}
