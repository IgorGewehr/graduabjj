import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/attendance_dto.dart' as api_att;
import '../../api/repositories.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/selected_academy_provider.dart' show selectedAcademyIdProvider, safeAcademyIdProvider;
import '../../services/services.dart';
import '../../widgets/cached_image.dart';
import 'monitor_student_detail/student_detail_helpers.dart';
import 'monitor_student_detail/student_info_tab.dart';
import 'monitor_student_detail/student_attendance_tab.dart';
import 'monitor_student_detail/student_history_tab.dart';
import 'monitor_student_detail/student_global_tab.dart';

/// Monitor Student Detail Screen - View student info (no financial access)
class MonitorStudentDetailScreen extends ConsumerStatefulWidget {
  final String studentId;

  const MonitorStudentDetailScreen({super.key, required this.studentId});

  @override
  ConsumerState<MonitorStudentDetailScreen> createState() =>
      _MonitorStudentDetailScreenState();
}

class _MonitorStudentDetailScreenState
    extends ConsumerState<MonitorStudentDetailScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  Student? _student;
  List<Attendance> _attendances = [];
  List<BeltProgression> _progressions = [];
  List<Achievement> _achievements = [];
  CrossAcademyStudentHistory? _globalHistory;
  bool _isLoading = true;
  bool _isLoadingGlobal = false;
  bool _hasLinkedUser = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _initTabController() {
    _tabController?.dispose();
    final tabCount = _hasLinkedUser ? 4 : 3;
    _tabController = TabController(length: tabCount, vsync: this);
    _tabController!.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_hasLinkedUser &&
        _tabController!.index == 3 &&
        _globalHistory == null &&
        !_isLoadingGlobal) {
      _loadGlobalHistory();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = ref.read(safeAcademyIdProvider) ?? '';

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

      Future<List<BeltProgression>> beltFuture() async {
        final r = tatami.studentRef(academyId, widget.studentId);
        ref.invalidate(tatami.tatamiBeltProgressionsLegacyProvider(r));
        return ref.read(tatami.tatamiBeltProgressionsLegacyProvider(r).future);
      }

      Future<List<Achievement>> achievementsFuture() async {
        final r = tatami.studentRef(academyId, widget.studentId);
        ref.invalidate(tatami.tatamiAchievementsLegacyProvider(r));
        return ref.read(tatami.tatamiAchievementsLegacyProvider(r).future);
      }

      final futures = await Future.wait<dynamic>([
        studentFuture(),
        attendanceFuture(),
        beltFuture(),
        achievementsFuture(),
      ]);

      final student = futures[0] as Student?;
      final attendances = futures[1] as List<Attendance>;
      final progressions = futures[2] as List<BeltProgression>;
      final achievements = futures[3] as List<Achievement>;

      setState(() {
        _student = student;
        _attendances = attendances;
        _progressions = progressions;
        _achievements = achievements;
        _hasLinkedUser = student?.linkedUserId != null;
        _isLoading = false;
      });

      _initTabController();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadGlobalHistory() async {
    if (_student?.linkedUserId == null) return;

    setState(() => _isLoadingGlobal = true);

    try {
      // TODO(tatami): CrossAcademyService.getStudentGlobalHistory faz queries
      //   multi-academia direto no Firestore. Migrar para endpoint tatami quando
      //   backend expor GET /v1/users/{uid}/global-history (cross-academy).
      final history = await crossAcademyService.getStudentGlobalHistory(
        _student!.linkedUserId!,
        currentAcademyId: ref.read(safeAcademyIdProvider) ?? '',
      );
      setState(() {
        _globalHistory = history;
        _isLoadingGlobal = false;
      });
    } catch (e) {
      setState(() => _isLoadingGlobal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _student == null
          ? const Center(child: Text('Aluno nao encontrado'))
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                _buildSliverAppBar(),
              ],
              body: Column(
                children: [
                  Container(
                    color: AppTheme.surface,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: AppTheme.textPrimary,
                      unselectedLabelColor: AppTheme.textSecondary,
                      indicatorColor: AppTheme.primary,
                      tabs: [
                        const Tab(text: 'Info'),
                        const Tab(text: 'Presencas'),
                        const Tab(text: 'Historico'),
                        if (_hasLinkedUser)
                          const Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.globe, size: 14),
                                SizedBox(width: 4),
                                Text('Global'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        StudentInfoTab(
                          student: _student!,
                          attendanceCount: _student!.totalAttendanceCount,
                          progressionsCount: _progressions.length,
                        ),
                        StudentAttendanceTab(attendances: _attendances),
                        StudentHistoryTab(
                          progressions: _progressions,
                          achievements: _achievements,
                        ),
                        if (_hasLinkedUser)
                          StudentGlobalTab(
                            isLoadingGlobal: _isLoadingGlobal,
                            globalHistory: _globalHistory,
                            currentAcademyId: ref.read(safeAcademyIdProvider) ?? '',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: studentBeltColor(_student!.currentBelt),
      foregroundColor: _student!.currentBelt == 'white'
          ? Colors.black
          : Colors.white,
      actions: [
        if (_student != null && _student!.linkedUserId == null)
          IconButton(
            icon: const Icon(LucideIcons.link),
            tooltip: 'Gerar Codigo de Acesso',
            onPressed: _generateLinkCode,
          ),
        IconButton(
          icon: const Icon(LucideIcons.edit),
          onPressed: () {
            context.push('/portal/alunos/${widget.studentId}/editar');
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                studentBeltColor(_student!.currentBelt),
                studentBeltColor(_student!.currentBelt).withValues(alpha: 0.7),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Hero(
                        tag: 'student-avatar-${_student!.id}',
                        child: (_student!.photoUrl ?? '').isNotEmpty
                            ? AppCachedAvatar(
                                imageUrl: _student!.photoUrl,
                                radius: 40,
                              )
                            : CircleAvatar(
                                radius: 40,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.3),
                                child: Text(
                                  _student!.fullName
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: _student!.currentBelt == 'white'
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _student!.fullName,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _student!.currentBelt == 'white'
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                BeltBadge(student: _student!),
                                const SizedBox(width: 8),
                                StudentStatusBadge(student: _student!),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _generateLinkCode() async {
    try {
      final academyId = ref.read(selectedAcademyIdProvider);
      if (academyId == null) {
        context.showError('Selecione uma academia.');
        return;
      }
      final src = await ref.read(linkCodeRepoProvider).createForStudent(
            academyId,
            studentId: _student!.id,
          );
      if (mounted) {
        _showLinkCodeDialog(src.code);
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao gerar codigo: $e');
      }
    }
  }

  void _showLinkCodeDialog(String code) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.link, color: AppTheme.primary),
            const SizedBox(width: 8),
            const Text('Codigo Gerado'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Compartilhe com ${_student!.fullName}:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary, width: 2),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Valido por 24 horas',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              context.showSuccess('Codigo copiado!');
            },
            icon: const Icon(LucideIcons.copy, size: 16),
            label: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
