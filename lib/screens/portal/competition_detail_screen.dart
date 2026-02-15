import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/competitions/competition_gallery.dart';
import '../../widgets/competitions/photo_upload_sheet.dart';

/// Position display config
const _positionConfig = {
  'gold': {'label': 'Ouro', 'icon': '🥇', 'color': 0xFFFFD700},
  'silver': {'label': 'Prata', 'icon': '🥈', 'color': 0xFFC0C0C0},
  'bronze': {'label': 'Bronze', 'icon': '🥉', 'color': 0xFFCD7F32},
  'participant': {'label': 'Participante', 'icon': '🎖️', 'color': 0xFF666666},
};

/// Competition Detail Screen - Shows results + gallery for a specific competition
class CompetitionDetailScreen extends ConsumerStatefulWidget {
  final String competitionId;

  const CompetitionDetailScreen({
    super.key,
    required this.competitionId,
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

      final results = await Future.wait([
        competitionService.getById(widget.competitionId),
        competitionService.getResultsForCompetition(widget.competitionId),
        enrollmentService.getByCompetition(widget.competitionId),
      ]);

      if (!mounted) return;

      setState(() {
        _competition = results[0] as Competition?;
        _results = results[1] as List<CompetitionResult>;
        _enrollments = results[2] as List<CompetitionEnrollment>;
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
                        Icon(LucideIcons.alertCircle,
                            size: 48, color: AppTheme.error),
                        const SizedBox(height: 16),
                        Text(
                          'Erro ao carregar dados',
                          style: AppTheme.titleMedium
                              .copyWith(color: AppTheme.textSecondary),
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
                        _buildInfoCard(student),

                        // Tabs
                        Container(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom:
                                  BorderSide(color: AppTheme.divider, width: 1),
                            ),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            labelColor: AppTheme.textPrimary,
                            unselectedLabelColor: AppTheme.textSecondary,
                            labelStyle: AppTheme.labelMedium
                                .copyWith(fontWeight: FontWeight.w600),
                            unselectedLabelStyle: AppTheme.labelMedium,
                            indicatorColor: AppTheme.primary,
                            indicatorWeight: 2,
                            tabs: [
                              Tab(
                                  text:
                                      'Resultados (${_results.length})'),
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
                              _buildResultsTab(student),

                              // Gallery Tab
                              _buildGalleryTab(
                                  student, academyId),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildInfoCard(Student? student) {
    final competition = _competition!;
    final studentId = student?.id;
    final isEnrolled = studentId != null && _enrollments.any((e) => e.studentId == studentId);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  competition.name,
                  style:
                      AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _buildStatusChip(competition.status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(LucideIcons.calendar,
                  size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR')
                    .format(competition.date),
                style:
                    AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
          if (competition.location != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(LucideIcons.mapPin,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    competition.location!,
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (competition.description != null &&
              competition.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              competition.description!,
              style:
                  AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // Self-enrollment button
          if (studentId != null && competition.status != CompetitionStatus.completed) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isEnrolled
                  ? OutlinedButton(
                      onPressed: _isEnrolling ? null : () => _cancelEnrollment(studentId),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(_isEnrolling ? 'Cancelando...' : 'Cancelar Inscricao'),
                    )
                  : ElevatedButton.icon(
                      onPressed: _isEnrolling ? null : () => _selfEnroll(student!),
                      icon: const Icon(LucideIcons.userPlus, size: 16),
                      label: Text(_isEnrolling ? 'Inscrevendo...' : 'Inscrever-se'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(CompetitionStatus status) {
    final config = {
      CompetitionStatus.upcoming: {
        'label': 'Proxima',
        'color': AppTheme.warning,
      },
      CompetitionStatus.ongoing: {
        'label': 'Em Andamento',
        'color': AppTheme.info,
      },
      CompetitionStatus.completed: {
        'label': 'Concluida',
        'color': AppTheme.success,
      },
    };

    final c = config[status] ?? config[CompetitionStatus.upcoming]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (c['color'] as Color).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        c['label'] as String,
        style: AppTheme.labelSmall.copyWith(
          color: c['color'] as Color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildResultsTab(Student? student) {
    final studentId = student?.id;
    final myResult =
        _results.where((r) => r.studentId == studentId).firstOrNull;
    final myEnrollment =
        _enrollments.where((e) => e.studentId == studentId).firstOrNull;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // My Result Card
          if (studentId != null)
            _buildMyResultCard(
              studentId: studentId,
              studentName: student?.fullName ?? '',
              myResult: myResult,
              myEnrollment: myEnrollment,
            ),

          const SizedBox(height: 16),

          // All Results
          _buildAllResultsCard(studentId),
        ],
      ),
    );
  }

  Widget _buildMyResultCard({
    required String studentId,
    required String studentName,
    CompetitionResult? myResult,
    CompetitionEnrollment? myEnrollment,
  }) {
    final pos = myResult != null
        ? _positionConfig[myResult.position] ?? _positionConfig['participant']!
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: myResult != null
              ? Color(pos!['color'] as int).withValues(alpha: 0.5)
              : AppTheme.primary.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MEU RESULTADO',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          if (myResult != null) ...[
            Row(
              children: [
                Text(
                  pos!['icon'] as String,
                  style: const TextStyle(fontSize: 36),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pos['label'] as String,
                        style: AppTheme.titleMedium
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (myResult.ageCategory != null ||
                          myResult.weightCategory != null)
                        Text(
                          [myResult.ageCategory, myResult.weightCategory]
                              .where((e) => e != null)
                              .join(' - '),
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary),
                        ),
                      if (myResult.notes != null)
                        Text(
                          myResult.notes!,
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showResultDialog(
                    studentId: studentId,
                    studentName: studentName,
                    existingResult: myResult,
                    enrollment: myEnrollment,
                  ),
                  icon: const Icon(LucideIcons.edit, size: 18),
                  color: AppTheme.textSecondary,
                ),
                IconButton(
                  onPressed: () => _deleteResult(myResult),
                  icon: const Icon(LucideIcons.trash2, size: 18),
                  color: Colors.red.shade400,
                ),
              ],
            ),
          ] else ...[
            InkWell(
              onTap: () => _showResultDialog(
                studentId: studentId,
                studentName: studentName,
                existingResult: null,
                enrollment: myEnrollment,
              ),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.medal,
                        size: 18, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Registrar meu resultado',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAllResultsCard(String? currentStudentId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.users, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Todos os Resultados',
                style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(LucideIcons.medal,
                        size: 40, color: AppTheme.textDisabled),
                    const SizedBox(height: 8),
                    Text(
                      'Nenhum resultado registrado ainda',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_results.length, (index) {
              final result = _results[index];
              final pos = _positionConfig[result.position] ??
                  _positionConfig['participant']!;
              final isMe = result.studentId == currentStudentId;

              return Container(
                margin: EdgeInsets.only(top: index > 0 ? 8 : 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe
                      ? AppTheme.primary.withValues(alpha: 0.05)
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: isMe
                      ? Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  children: [
                    Text(
                      pos['icon'] as String,
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  result.studentName,
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight:
                                        isMe ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Voce',
                                    style: AppTheme.labelSmall.copyWith(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${pos['label'] as String}${result.weightCategory != null ? ' - ${result.weightCategory}' : ''}',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildGalleryTab(Student? student, String? academyId) {
    if (academyId == null) {
      return const Center(child: Text('Academia nao selecionada'));
    }

    final isEnrolled =
        _enrollments.any((e) => e.studentId == student?.id);
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
        isAdmin: false,
        enrolledStudents: enrolledStudents,
      ),
    );
  }

  // ============================================
  // Self Enrollment
  // ============================================
  Future<void> _selfEnroll(Student student) async {
    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null || _competition == null) return;

    setState(() => _isEnrolling = true);
    try {
      final enrollmentService = CompetitionEnrollmentService(academyId);
      final enrollment = await enrollmentService.enroll(
        competitionId: _competition!.id,
        competitionName: _competition!.name,
        studentId: student.id,
        studentName: student.fullName,
        ageCategory: 'adult',
        weightCategory: '',
        transportPreference: TransportPreference.undecided,
      );

      // Also update legacy enrolledStudentIds
      try {
        final competitionService = CompetitionService(academyId);
        await competitionService.enrollStudent(_competition!.id, student.id);
      } catch (_) {}

      setState(() {
        _enrollments = [..._enrollments, enrollment];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inscrito com sucesso!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is Exception ? e.toString() : 'Erro ao se inscrever';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isEnrolling = false);
    }
  }

  Future<void> _cancelEnrollment(String studentId) async {
    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null || _competition == null) return;

    final myEnrollment = _enrollments.where((e) => e.studentId == studentId).firstOrNull;
    if (myEnrollment == null) return;

    setState(() => _isEnrolling = true);
    try {
      final enrollmentService = CompetitionEnrollmentService(academyId);
      await enrollmentService.delete(myEnrollment.id);

      // Also remove from legacy array
      try {
        final competitionService = CompetitionService(academyId);
        await competitionService.unenrollStudent(_competition!.id, studentId);
      } catch (_) {}

      setState(() {
        _enrollments = _enrollments.where((e) => e.id != myEnrollment.id).toList();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inscricao cancelada'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao cancelar inscricao'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isEnrolling = false);
    }
  }

  /// Show result registration/edit dialog
  void _showResultDialog({
    required String studentId,
    required String studentName,
    CompetitionResult? existingResult,
    CompetitionEnrollment? enrollment,
  }) {
    String position = existingResult?.position ?? 'participant';
    String ageCategory =
        existingResult?.ageCategory ?? enrollment?.ageCategory ?? 'adult';
    String weightCategory =
        existingResult?.weightCategory ?? enrollment?.weightCategory ?? '';
    String modality = existingResult?.modality ?? 'gi';
    String divisionType = existingResult?.divisionType ?? 'weight';
    String notes = existingResult?.notes ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
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

                  Text(
                    existingResult != null
                        ? 'Editar Resultado'
                        : 'Registrar Resultado',
                    style:
                        AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),

                  // Position selector
                  Text('Resultado',
                      style: AppTheme.labelMedium
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _positionConfig.entries.map((entry) {
                      final isSelected = position == entry.key;
                      return ChoiceChip(
                        label: Text(
                            '${entry.value['icon']} ${entry.value['label']}'),
                        selected: isSelected,
                        onSelected: (_) {
                          setSheetState(() => position = entry.key);
                        },
                        selectedColor:
                            Color(entry.value['color'] as int).withValues(alpha: 0.2),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Modality: Gi / No-Gi
                  Text('Modalidade',
                      style: AppTheme.labelMedium
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Gi'),
                          selected: modality == 'gi',
                          onSelected: (_) {
                            setSheetState(() => modality = 'gi');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('No-Gi'),
                          selected: modality == 'nogi',
                          onSelected: (_) {
                            setSheetState(() => modality = 'nogi');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Division Type: Peso / Absoluto
                  Text('Divisao',
                      style: AppTheme.labelMedium
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Peso'),
                          selected: divisionType == 'weight',
                          onSelected: (_) {
                            setSheetState(() => divisionType = 'weight');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Absoluto'),
                          selected: divisionType == 'absolute',
                          onSelected: (_) {
                            setSheetState(() => divisionType = 'absolute');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Weight category
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Categoria de Peso',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    controller: TextEditingController(text: weightCategory),
                    onChanged: (v) => weightCategory = v,
                  ),
                  const SizedBox(height: 12),

                  // Notes
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Observacoes (opcional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    controller: TextEditingController(text: notes),
                    onChanged: (v) => notes = v,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: weightCategory.isEmpty
                          ? null
                          : () => _saveResult(
                                studentId: studentId,
                                studentName: studentName,
                                position: position,
                                ageCategory: ageCategory,
                                weightCategory: weightCategory,
                                modality: modality,
                                divisionType: divisionType,
                                notes: notes.isNotEmpty ? notes : null,
                                existingResult: existingResult,
                              ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        existingResult != null
                            ? 'Atualizar Resultado'
                            : 'Salvar Resultado',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteResult(CompetitionResult result) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Resultado'),
        content: const Text('Deseja excluir seu resultado desta competição?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final academyId = ref.read(selectedAcademyIdProvider);
    if (academyId == null) return;

    final competitionService = CompetitionService(academyId);

    try {
      await competitionService.deleteResult(result.id);
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

        // Create achievement
        final achievementService = AchievementService(academyId);
        final compPosition = CompetitionPosition.values.firstWhere(
          (p) => p.value == position,
          orElse: () => CompetitionPosition.participant,
        );
        await achievementService.createCompetitionAchievement(
          studentId: studentId,
          studentName: studentName,
          competitionId: _competition!.id,
          competitionName: _competition!.name,
          position: compPosition,
          date: _competition!.date,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(); // Close bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existingResult != null
                ? 'Resultado atualizado!'
                : 'Resultado registrado!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData(); // Refresh
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
}
