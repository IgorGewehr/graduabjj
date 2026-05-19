import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
      final competitionService = CompetitionService(academyId);
      final enrollmentService = CompetitionEnrollmentService(academyId);

      Future<Competition?> competitionFuture() async {
        final api = await ref
            .read(competitionRepoProvider)
            .getById(academyId, widget.competitionId);
        return Competition.fromApi(api);
      }

      final futures = await Future.wait<dynamic>([
        competitionFuture(),
        competitionService
            .getResultsForCompetition(widget.competitionId)
            .catchError((_) => <CompetitionResult>[]),
        enrollmentService
            .getByCompetition(widget.competitionId)
            .catchError((_) => <CompetitionEnrollment>[]),
      ]);

      if (!mounted) return;

      setState(() {
        _competition = futures[0] as Competition?;
        _results = futures[1] as List<CompetitionResult>;
        _enrollments = futures[2] as List<CompetitionEnrollment>;
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
      await CompetitionService(academyId).deleteResult(result.id);
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

    final competitionService = CompetitionService(academyId);

    try {
      if (existingResult != null) {
        await competitionService.updateResult(existingResult.id, {
          'position': position,
          'ageCategory': ageCategory,
          'weightCategory': weightCategory,
          'modality': modality,
          'divisionType': divisionType,
          'notes': notes,
        });
      } else {
        await competitionService.addResult(
          competitionId: _competition!.id,
          competitionName: _competition!.name,
          studentId: studentId,
          studentName: studentName,
          position: position,
          ageCategory: ageCategory,
          weightCategory: weightCategory,
          modality: modality,
          divisionType: divisionType,
          notes: notes,
          date: _competition!.date,
        );

        // Achievement is created server-side automatically when a result is recorded.

        // Auto-enroll if not already enrolled
        final alreadyEnrolled =
            _enrollments.any((e) => e.studentId == studentId);
        if (!alreadyEnrolled) {
          try {
            final enrollmentService = CompetitionEnrollmentService(academyId);
            final enrollment = await enrollmentService.enroll(
              competitionId: _competition!.id,
              competitionName: _competition!.name,
              studentId: studentId,
              studentName: studentName,
              ageCategory: ageCategory,
              weightCategory: weightCategory,
              transportPreference: TransportPreference.undecided,
            );
            _enrollments = [..._enrollments, enrollment];

            try {
              await CompetitionService(academyId)
                  .enrollStudent(_competition!.id, studentId);
            } catch (_) {}
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
      ),
    );
  }
}
