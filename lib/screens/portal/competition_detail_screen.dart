import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/dto/competition_dto.dart';
import '../../api/repositories.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/competitions/competition_gallery.dart';
import '../../widgets/competitions/photo_upload_sheet.dart';
import 'competition_detail/competition_enrollment_actions.dart';
import 'competition_detail/competition_info_card.dart';
import 'competition_detail/competition_result_dialogs.dart';
import 'competition_detail/competition_results_tab.dart';

/// Competition Detail Screen - Shows results + gallery for a specific competition.
/// Used by both portal (student) and admin views.
class CompetitionDetailScreen extends ConsumerStatefulWidget {
  final String competitionId;
  final bool isAdmin;

  const CompetitionDetailScreen({
    super.key,
    required this.competitionId,
    this.isAdmin = false,
  });

  @override
  ConsumerState<CompetitionDetailScreen> createState() =>
      _CompetitionDetailScreenState();
}

class _CompetitionDetailScreenState
    extends ConsumerState<CompetitionDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Competition? _competition;
  List<CompetitionResult> _results = [];
  List<CompetitionEnrollment> _enrollments = [];
  bool _isLoading = true;
  bool _isEnrolling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ============================================
  // Data loading
  // ============================================

  /// Converte [ApiResult] para [CompetitionResult] (modelo legado).
  CompetitionResult _apiResultToLegacy(
    ApiResult r,
    String competitionName,
  ) {
    return CompetitionResult(
      id: r.id,
      competitionId: r.competitionId,
      competitionName: competitionName,
      studentId: r.studentId,
      // studentName não vem na API — usa studentId como fallback.
      studentName: r.studentId,
      position: r.position.wire,
      beltCategory: r.beltCategory,
      ageCategory: r.ageCategory,
      weightCategory: r.weightCategory,
      modality: r.modality.wire,
      notes: null,
      date: r.recordedAt,
      createdAt: r.recordedAt,
    );
  }

  /// Converte [ApiEnrollment] para [CompetitionEnrollment] (modelo legado).
  CompetitionEnrollment _apiEnrollmentToLegacy(ApiEnrollment e) {
    return CompetitionEnrollment(
      id: e.id,
      competitionId: e.competitionId,
      // studentName não vem na API — usa studentId como fallback.
      studentName: e.studentId,
      studentId: e.studentId,
      ageCategory: e.ageCategory,
      weightCategory: e.weightCategory,
      transportPreference: _apiTransportToLegacy(
        e.transportPreference ?? ApiTransportPreference.undecided,
      ),
      enrolledAt: e.enrolledAt,
    );
  }

  TransportPreference _apiTransportToLegacy(ApiTransportPreference p) {
    switch (p) {
      case ApiTransportPreference.need_transport:
        return TransportPreference.needTransport;
      case ApiTransportPreference.own_transport:
        return TransportPreference.ownTransport;
      case ApiTransportPreference.undecided:
        return TransportPreference.undecided;
    }
  }

  Future<void> _loadData() async {
    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null) {
      setState(() {
        _error = 'Academia nao selecionada';
        _isLoading = false;
      });
      return;
    }

    try {
      final repo = ref.read(competitionRepoProvider);

      final results = await Future.wait<dynamic>([
        repo.getById(academyId, widget.competitionId),
        repo
            .listResults(academyId, widget.competitionId, limit: 200)
            .catchError((_) => ResultsPage(items: [])),
        repo
            .listEnrollments(academyId, widget.competitionId, limit: 200)
            .catchError((_) => EnrollmentsPage(items: [])),
      ]);

      if (!mounted) return;

      final competition = Competition.fromApi(results[0] as ApiCompetition);
      final apiResults = (results[1] as ResultsPage).items;
      final apiEnrollments = (results[2] as EnrollmentsPage).items;

      setState(() {
        _competition = competition;
        _results = apiResults
            .map((r) => _apiResultToLegacy(r, competition.name))
            .toList();
        _enrollments = apiEnrollments.map(_apiEnrollmentToLegacy).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ============================================
  // Self-enrollment
  // ============================================

  Future<void> _selfEnroll(Student student) async {
    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null || _competition == null) return;
    await selfEnroll(
      context: context,
      academyId: academyId,
      competition: _competition!,
      student: student,
      competitionRepo: ref.read(competitionRepoProvider),
      onSetLoading: (v) { if (mounted) setState(() => _isEnrolling = v); },
      onSuccess: (enrollment) {
        if (mounted) setState(() => _enrollments = [..._enrollments, enrollment]);
      },
    );
  }

  Future<void> _cancelEnrollment(String studentId) async {
    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null || _competition == null) return;
    await cancelEnrollment(
      context: context,
      academyId: academyId,
      competition: _competition!,
      studentId: studentId,
      enrollments: _enrollments,
      competitionRepo: ref.read(competitionRepoProvider),
      onSetLoading: (v) { if (mounted) setState(() => _isEnrolling = v); },
      onSuccess: (deletedId) {
        if (mounted) {
          setState(() {
            _enrollments = _enrollments.where((e) => e.id != deletedId).toList();
          });
        }
      },
    );
  }

  // ============================================
  // Result management
  // ============================================

  Future<void> _deleteResult(CompetitionResult result) async {
    final confirmed = await showDeleteResultDialog(context);

    if (confirmed != true) return;

    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null) return;

    try {
      await ref
          .read(competitionRepoProvider)
          .deleteResult(academyId, _competition!.id, result.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resultado excluído!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir resultado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveResult({
    required String studentId,
    required String studentName,
    required String position,
    required String ageCategory,
    required String weightCategory,
    String? modality,
    String? divisionType,
    String? notes,
    CompetitionResult? existingResult,
  }) async {
    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null || _competition == null) return;

    final repo = ref.read(competitionRepoProvider);

    try {
      if (existingResult != null) {
        // TODO(tatami): API não tem updateResult — recria deletando e
        // inserindo novamente, ou aguarda endpoint PATCH /results/{id}.
        await repo.deleteResult(academyId, _competition!.id, existingResult.id);
        await repo.recordResult(
          academyId,
          _competition!.id,
          CreateResultRequest(
            studentId: studentId,
            position: ApiPositionX.fromWire(position),
            modality: modality == 'nogi' ? ApiModality.nogi : ApiModality.gi,
            beltCategory: null,
            ageCategory: ageCategory.isEmpty ? null : ageCategory,
            weightCategory: weightCategory.isEmpty ? null : weightCategory,
          ),
        );
      } else {
        await repo.recordResult(
          academyId,
          _competition!.id,
          CreateResultRequest(
            studentId: studentId,
            position: ApiPositionX.fromWire(position),
            modality: modality == 'nogi' ? ApiModality.nogi : ApiModality.gi,
            beltCategory: null,
            ageCategory: ageCategory.isEmpty ? null : ageCategory,
            weightCategory: weightCategory.isEmpty ? null : weightCategory,
          ),
        );

        // Achievement is created server-side automatically when a result is recorded.

        // Auto-enroll via Tatami se ainda não estiver inscrito.
        final alreadyEnrolled =
            _enrollments.any((e) => e.studentId == studentId);
        if (!alreadyEnrolled) {
          try {
            final apiEnrollment = await repo.enroll(
              academyId,
              _competition!.id,
              CreateEnrollmentRequest(
                studentId: studentId,
                modality: modality == 'nogi' ? ApiModality.nogi : ApiModality.gi,
                ageCategory: ageCategory.isEmpty ? null : ageCategory,
                weightCategory: weightCategory.isEmpty ? null : weightCategory,
              ),
            );
            final enrollment = CompetitionEnrollment(
              id: apiEnrollment.id,
              competitionId: apiEnrollment.competitionId,
              studentId: apiEnrollment.studentId,
              studentName: studentName,
              ageCategory: apiEnrollment.ageCategory,
              weightCategory: apiEnrollment.weightCategory,
              transportPreference: TransportPreference.undecided,
              enrolledAt: apiEnrollment.enrolledAt,
            );
            _enrollments = [..._enrollments, enrollment];
          } catch (_) {}
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existingResult != null
                  ? 'Resultado atualizado!'
                  : 'Resultado registrado!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar resultado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================
  // Dialog openers (delegate to helpers)
  // ============================================

  void _openTeamResultDialog() {
    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null || _competition == null) return;
    showTeamResultDialog(
      context,
      competition: _competition!,
      academyId: academyId,
      repo: ref.read(competitionRepoProvider),
      onSaved: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Resultado da equipe salvo!'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      },
    );
  }

  Future<void> _openRemoveTeamResult() async {
    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null || _competition == null) return;
    await showRemoveTeamResultDialog(
      context,
      competition: _competition!,
      academyId: academyId,
      repo: ref.read(competitionRepoProvider),
      onRemoved: _loadData,
    );
  }

  void _openAdminAddResultDialog() {
    showAdminAddResultDialog(
      context,
      enrollments: _enrollments,
      onStudentSelected: (enrollment) => _openResultDialog(
        studentId: enrollment.studentId,
        studentName: enrollment.studentName,
        existingResult: null,
        enrollment: enrollment,
      ),
    );
  }

  void _openResultDialog({
    required String studentId,
    required String studentName,
    CompetitionResult? existingResult,
    CompetitionEnrollment? enrollment,
  }) {
    showResultDialog(
      context,
      studentId: studentId,
      studentName: studentName,
      existingResult: existingResult,
      enrollment: enrollment,
      onSave: _saveResult,
    );
  }

  // ============================================
  // Build
  // ============================================

  @override
  Widget build(BuildContext context) {
    final studentAsync = ref.watch(currentStudentProvider);
    final student = studentAsync.valueOrNull;
    final academyId = ref.watch(selectedAcademyIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_competition?.name ?? 'Competicao'),
        backgroundColor: AppTheme.surface,
      ),
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.alertCircle,
                      size: 48,
                      color: AppTheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Erro ao carregar dados',
                      style: AppTheme.titleMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _error = null;
                        });
                        _loadData();
                      },
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Tentar novamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textPrimary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _competition == null
          ? const Center(child: Text('Competicao nao encontrada'))
          : Column(
              children: [
                // Competition Info
                CompetitionInfoCard(
                  competition: _competition!,
                  enrollments: _enrollments,
                  student: student,
                  isAdmin: widget.isAdmin,
                  isEnrolling: _isEnrolling,
                  onEnroll: student != null
                      ? () => _selfEnroll(student)
                      : null,
                  onCancelEnrollment: student != null
                      ? () => _cancelEnrollment(student.id)
                      : null,
                ),

                // Tabs
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppTheme.divider, width: 1),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppTheme.textPrimary,
                    unselectedLabelColor: AppTheme.textSecondary,
                    labelStyle: AppTheme.labelMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: AppTheme.labelMedium,
                    indicatorColor: AppTheme.primary,
                    indicatorWeight: 2,
                    tabs: [
                      Tab(text: 'Resultados (${_results.length})'),
                      const Tab(text: 'Galeria'),
                    ],
                  ),
                ),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Results Tab
                      CompetitionResultsTab(
                        competition: _competition!,
                        results: _results,
                        enrollments: _enrollments,
                        student: student,
                        isAdmin: widget.isAdmin,
                        onRefresh: _loadData,
                        onShowTeamResultDialog: _openTeamResultDialog,
                        onRemoveTeamResult: _openRemoveTeamResult,
                        onShowAdminAddResultDialog: _enrollments.isEmpty
                            ? null
                            : _openAdminAddResultDialog,
                        onShowResultDialog: ({
                          required studentId,
                          required studentName,
                          existingResult,
                          enrollment,
                        }) =>
                            _openResultDialog(
                              studentId: studentId,
                              studentName: studentName,
                              existingResult: existingResult,
                              enrollment: enrollment,
                            ),
                        onDeleteResult: _deleteResult,
                      ),

                      // Gallery Tab
                      _buildGalleryTab(student, academyId),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildGalleryTab(Student? student, String? academyId) {
    if (academyId == null) {
      return const Center(child: Text('Academia nao selecionada'));
    }

    final isEnrolled = _enrollments.any((e) => e.studentId == student?.id);
    final enrolledStudents = _enrollments
        .map((e) => EnrolledStudent(id: e.studentId, name: e.studentName))
        .toList();

    return SingleChildScrollView(
      child: CompetitionGallery(
        academyId: academyId,
        competitionId: widget.competitionId,
        competitionName: _competition?.name ?? '',
        studentId: student?.id,
        studentName: student?.fullName,
        isEnrolled: isEnrolled,
        isAdmin: widget.isAdmin,
        enrolledStudents: enrolledStudents,
        competitionRepo: ref.read(competitionRepoProvider),
        uploadsRepo: ref.read(uploadsRepoProvider),
      ),
    );
  }
}
