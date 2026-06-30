import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/formatters.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

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
    // 4 tabs if student has linkedUserId, otherwise 3
    final tabCount = _hasLinkedUser ? 4 : 3;
    _tabController = TabController(length: tabCount, vsync: this);
    _tabController!.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    // Load global history when switching to Global tab
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
      final academyId = FirebaseService.academyId;
      final studentService = StudentService(academyId);
      final attendanceService = AttendanceService(academyId);
      final beltService = BeltProgressionService(academyId);
      final achievementService = AchievementService(academyId);

      // Sprint 5 — fan out the four independent reads in parallel. Cuts
      // total wait from sum-of-latencies to max-of-latencies.
      final futures = await Future.wait<dynamic>([
        studentService.getById(widget.studentId),
        attendanceService.getByStudent(widget.studentId),
        beltService.getByStudent(widget.studentId),
        achievementService.getForStudent(widget.studentId),
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
      final history = await crossAcademyService.getStudentGlobalHistory(
        _student!.linkedUserId!,
        currentAcademyId: FirebaseService.academyId,
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
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: PolishSkeleton.list(count: 6, itemHeight: 72),
            )
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
                        _buildInfoTab(),
                        _buildAttendanceTab(),
                        _buildHistoryTab(),
                        if (_hasLinkedUser) _buildGlobalTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliverAppBar() {
    final sport = _student!.getPrimarySport();
    final grade = _student!.getGrade(sport);
    final gradeId = grade?.currentGrade ?? 'white';
    final isWhite = gradeId == 'white';

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: _getBeltColor(gradeId, sportId: sport),
      foregroundColor: isWhite ? Colors.black : Colors.white,
      actions: [
        // Generate link code button (only if student not linked)
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
                _getBeltColor(gradeId, sportId: sport),
                _getBeltColor(gradeId, sportId: sport).withValues(alpha: 0.7),
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
                      // Avatar
                      Hero(
                        tag: 'student-avatar-${_student!.id}',
                        child: (_student!.photoUrl ?? '').isNotEmpty
                            ? AppCachedAvatar(
                                imageUrl: _student!.photoUrl,
                                radius: 40,
                              )
                            : CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.3,
                                ),
                                child: Text(
                                  _student!.fullName.isNotEmpty
                                      ? _student!.fullName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: isWhite ? Colors.black : Colors.white,
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
                                color: isWhite ? Colors.black : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _buildBeltBadge(),
                                const SizedBox(width: 8),
                                _buildStatusBadge(),
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

  Widget _buildBeltBadge() {
    final sport = _student!.getPrimarySport();
    // Esportes sem sistema de graduação (boxe/MMA/musculação) não têm faixa.
    if (getSport(sport).gradeSystem == GradeSystem.none) {
      return const SizedBox.shrink();
    }

    final grade = _student!.getGrade(sport);
    final gradeId = grade?.currentGrade ?? 'white';
    final stripes = grade?.currentStripes ?? 0;
    final isWhite = gradeId == 'white';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getBeltName(gradeId, sportId: sport),
            style: TextStyle(
              color: isWhite ? Colors.black : Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (stripes > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$stripes grau(s)',
              style: TextStyle(
                color: isWhite ? Colors.black54 : Colors.white70,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final sport = _student!.getPrimarySport();
    final gradeId = _student!.getGrade(sport)?.currentGrade ?? 'white';
    final isWhite = gradeId == 'white';
    final statusColors = {
      StudentStatus.active: AppTheme.success,
      StudentStatus.inactive: AppTheme.textSecondary,
      StudentStatus.suspended: AppTheme.warning,
      StudentStatus.injured: AppTheme.info,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            statusColors[_student!.status]?.withValues(alpha: 0.3) ??
            Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _student!.status.label,
        style: TextStyle(
          color: isWhite ? Colors.black : Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Presencas',
                  _student!.totalAttendanceCount,
                  LucideIcons.clipboardCheck,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Graduacoes',
                  _progressions.length,
                  LucideIcons.award,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Personal Info
          _buildSectionTitle('Informacoes Pessoais'),
          const SizedBox(height: 12),
          _buildInfoCard([
            if (_student!.nickname != null)
              _InfoRow(label: 'Apelido', value: _student!.nickname!),
            _InfoRow(label: 'Categoria', value: _student!.category.label),
            if (_student!.birthDate != null)
              _InfoRow(
                label: 'Nascimento',
                value: DateFormat('dd/MM/yyyy').format(_student!.birthDate!),
              ),
            if (_student!.email != null)
              _InfoRow(label: 'Email', value: _student!.email!),
            if (_student!.phone != null)
              _InfoRow(label: 'Telefone', value: formatPhone(_student!.phone)),
          ]),

          // Guardian Info (for kids)
          if (_student!.category == StudentCategory.kids &&
              _student!.guardianName != null) ...[
            const SizedBox(height: 24),
            _buildSectionTitle('Responsavel'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoRow(label: 'Nome', value: _student!.guardianName!),
              if (_student!.guardianPhone != null)
                _InfoRow(label: 'Telefone', value: formatPhone(_student!.guardianPhone)),
              if (_student!.guardianEmail != null)
                _InfoRow(label: 'Email', value: _student!.guardianEmail!),
            ]),
          ],

          // Medical Info — dado sensível: só staff real (admin ou quem pode
          // gerenciar alunos) vê. Monitores comuns não têm acesso.
          Builder(
            builder: (context) {
              if (_student!.medicalNotes == null ||
                  _student!.medicalNotes!.isEmpty) {
                return const SizedBox.shrink();
              }
              final currentUser = ref.watch(currentUserProvider).valueOrNull;
              final canSeeMedical = currentUser != null &&
                  (currentUser.isAdmin ||
                      currentUser.hasPermission('students:manage'));
              if (!canSeeMedical) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  _buildSectionTitle('Observacoes Medicas'),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Text(
                      _student!.medicalNotes!,
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Turmas section — visible to admins and users with students:manage
          Builder(
            builder: (context) {
              final currentUser =
                  ref.watch(currentUserProvider).valueOrNull;
              final canManage = currentUser != null &&
                  currentUser.hasPermission('students:manage');
              if (!canManage) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Turmas'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showManageClassesDialog,
                        icon: const Icon(LucideIcons.users, size: 16),
                        label: const Text('Gerenciar turmas'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showManageClassesDialog() async {
    final academyId = FirebaseService.academyId;
    final classService = ClassService(academyId);

    List<BJJClass> classes;
    try {
      classes = await classService.list();
    } catch (e) {
      if (mounted) context.showError('Erro ao carregar turmas');
      return;
    }

    if (!mounted) return;

    final studentId = _student!.id;
    final enrolled = <String, bool>{
      for (final c in classes) c.id: c.studentIds.contains(studentId),
    };

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(LucideIcons.users, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Gerenciar turmas'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: classes.isEmpty
                    ? const Text('Nenhuma turma cadastrada.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: classes.length,
                        itemBuilder: (_, i) {
                          final cls = classes[i];
                          final isIn = enrolled[cls.id] ?? false;
                          return SwitchListTile(
                            dense: true,
                            title: Text(cls.name),
                            value: isIn,
                            activeColor: AppTheme.primary,
                            onChanged: (value) async {
                              try {
                                if (value) {
                                  await classService.addStudentToClass(
                                    cls.id,
                                    studentId,
                                  );
                                } else {
                                  await classService.removeStudentFromClass(
                                    cls.id,
                                    studentId,
                                  );
                                }
                                setDialogState(() => enrolled[cls.id] = value);
                              } catch (e) {
                                if (ctx.mounted) {
                                  ctx.showError('Erro ao atualizar turma');
                                }
                              }
                            },
                          );
                        },
                      ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _loadData();
                  },
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(String label, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primary, size: 24),
          const SizedBox(height: 8),
          AnimatedCountUp(
            value: value,
            style: AppTheme.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTheme.titleSmall.copyWith(
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildInfoCard(List<_InfoRow> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: rows.map((row) {
          final isLast = rows.last == row;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  row.label,
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  row.value,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Full-width "Adicionar presença" button for the attendance tab. Visible
  /// only to admins / professors with the 'attendance:take' extra permission.
  /// Registers a manual presence WITHOUT creating any charge.
  Widget _buildAddPresenceButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _showAddPresenceDialog,
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Adicionar presença'),
        ),
      ),
    );
  }

  /// Registers a MANUAL presence for the student — no charge is created. Uses
  /// [AttendanceService.markManualPresence], which allows multiple presences on
  /// the same day (non-colliding doc id).
  void _showAddPresenceDialog() {
    DateTime selectedDate = DateTime.now();
    final noteController = TextEditingController();
    final sports = _student?.getSports() ?? [SportId.bjj];
    SportId sport = _student?.getPrimarySport() ?? SportId.bjj;
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar presença'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registra uma presença manual para o aluno, sem gerar '
                      'cobrança.',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Data',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 365)),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.calendar,
                                size: 16, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('dd/MM/yyyy').format(selectedDate),
                              style: AppTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (sports.length > 1) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Esporte',
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: sports.map((s) {
                          return ChoiceChip(
                            label: Text(getSport(s).label),
                            selected: sport == s,
                            onSelected: (_) =>
                                setDialogState(() => sport = s),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Observação (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    final currentUser =
                        ref.read(currentUserProvider).valueOrNull;
                    final note = noteController.text.trim();
                    try {
                      await AttendanceService(FirebaseService.academyId)
                          .markManualPresence(
                        studentId: widget.studentId,
                        studentName: _student?.fullName ?? '',
                        verifiedBy: currentUser?.id ?? '',
                        verifiedByName: currentUser?.displayName ?? '',
                        date: selectedDate,
                        sport: sport.value,
                        note: note.isEmpty ? null : note,
                      );
                    } catch (e) {
                      if (parentContext.mounted) {
                        parentContext.showError('Erro ao registrar presença');
                      }
                      return;
                    }
                    if (parentContext.mounted) {
                      parentContext.showSuccess('Presença registrada');
                    }
                    _loadData();
                  },
                  child: const Text('Registrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAttendanceTab() {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    // Even on the monitor (read-only) screen, an admin or a professor with the
    // 'attendance:take' extra permission can grant a manual presence.
    final canTakeAttendance = currentUser != null &&
        (currentUser.isAdmin || currentUser.hasPermission('attendance:take'));

    if (_attendances.isEmpty) {
      return Column(
        children: [
          if (canTakeAttendance) _buildAddPresenceButton(),
          Expanded(
            child: PolishedEmptyState(
              icon: LucideIcons.clipboardX,
              title: 'Nenhuma presenca registrada',
              subtitle: canTakeAttendance
                  ? 'Toque em "Adicionar presença" para registrar uma presença manual.'
                  : null,
            ),
          ),
        ],
      );
    }

    // Group by month
    final grouped = <String, List<Attendance>>{};
    for (final attendance in _attendances) {
      final key = DateFormat('MMMM yyyy', 'pt_BR').format(attendance.date);
      grouped.putIfAbsent(key, () => []).add(attendance);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length + (canTakeAttendance ? 1 : 0),
      itemBuilder: (context, index) {
        if (canTakeAttendance && index == 0) {
          return _buildAddPresenceButton();
        }
        final groupIndex = canTakeAttendance ? index - 1 : index;
        final month = grouped.keys.elementAt(groupIndex);
        final items = grouped[month]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    month,
                    style: AppTheme.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${items.length} presencas',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...items.map(
              (attendance) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${attendance.date.day}',
                          style: AppTheme.titleSmall.copyWith(
                            color: AppTheme.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attendance.className,
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            DateFormat('EEEE', 'pt_BR').format(attendance.date),
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      LucideIcons.checkCircle,
                      color: AppTheme.success,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ).entrance(index: index);
      },
    );
  }

  Widget _buildHistoryTab() {
    final allItems = <_HistoryItem>[];

    // Add belt progressions
    for (final p in _progressions) {
      allItems.add(
        _HistoryItem(
          date: p.date,
          title:
              'Graduacao: ${_getBeltName(p.belt, sportId: SportId.fromString(p.sport ?? 'bjj'))} ${p.stripes > 0 ? "(${p.stripes} grau)" : ""}',
          icon: LucideIcons.award,
          color: AppTheme.primary,
        ),
      );
    }

    // Add achievements
    for (final a in _achievements) {
      allItems.add(
        _HistoryItem(
          date: a.awardedAt,
          title: a.title,
          subtitle: a.description,
          icon: LucideIcons.trophy,
          color: AppTheme.warning,
        ),
      );
    }

    // Sort by date descending
    allItems.sort((a, b) => b.date.compareTo(a.date));

    if (allItems.isEmpty) {
      return const PolishedEmptyState(
        icon: LucideIcons.history,
        title: 'Nenhum historico registrado',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    Text(
                      DateFormat('dd/MM/yyyy').format(item.date),
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).entrance(index: index);
      },
    );
  }

  Widget _buildGlobalTab() {
    if (_isLoadingGlobal) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: PolishSkeleton.list(count: 5, itemHeight: 72),
      );
    }

    if (_globalHistory == null) {
      return const PolishedEmptyState(
        icon: LucideIcons.globe,
        title: 'Nao foi possivel carregar o historico global',
      );
    }

    final history = _globalHistory!;
    final currentAcademyId = FirebaseService.academyId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy Notice
          if (!history.isProfilePublic)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.lock, size: 16, color: AppTheme.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'O perfil deste aluno e privado. Apenas informacoes basicas sao exibidas.',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.info),
                    ),
                  ),
                ],
              ),
            ),

          // Academies Overview
          if (history.academies.length > 1) ...[
            _buildSectionTitle(
              'Academias Vinculadas (${history.academies.length})',
            ),
            const SizedBox(height: 12),
            ...history.academies.map(
              (academy) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: academy.academyId == currentAcademyId
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: academy.academyId == currentAcademyId
                        ? AppTheme.success.withValues(alpha: 0.3)
                        : AppTheme.divider,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _getBeltColor(academy.currentBelt, sportId: _student!.getPrimarySport()),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            academy.academyName,
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${CrossAcademyService.beltLabels[academy.currentBelt] ?? academy.currentBelt} - ${academy.currentStripes} grau(s)',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (academy.academyId == currentAcademyId)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Atual',
                          style: AppTheme.labelSmall.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Global Attendance Stats
          if (history.attendanceStats.length > 1) ...[
            _buildSectionTitle('Presencas por Academia'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...history.attendanceStats.map(
                  (stat) => Container(
                    width: (MediaQuery.of(context).size.width - 48) / 2,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: stat.academyId == currentAcademyId
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${stat.totalCount}',
                          style: AppTheme.headlineMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: stat.academyId == currentAcademyId
                                ? AppTheme.success
                                : AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          stat.academyName,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: (MediaQuery.of(context).size.width - 48) / 2,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${history.totalAttendance}',
                        style: AppTheme.headlineMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                      Text(
                        'Total Global',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Belt Progressions from Other Academies
          if (history.beltProgressions.isNotEmpty) ...[
            _buildSectionTitle('Graduacoes em Outras Academias'),
            const SizedBox(height: 12),
            ...history.beltProgressions
                .take(10)
                .map(
                  (progression) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            LucideIcons.award,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      progression.newStripes >
                                              (progression.previousStripes ?? 0)
                                          ? '${progression.newStripes}º grau - ${CrossAcademyService.beltLabels[progression.newBelt] ?? progression.newBelt}'
                                          : 'Faixa ${CrossAcademyService.beltLabels[progression.newBelt] ?? progression.newBelt}',
                                      style: AppTheme.bodyMedium.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildAcademyBadge(progression.academyName),
                                ],
                              ),
                              Text(
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(progression.promotionDate),
                                style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.textDisabled,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _getBeltColor(progression.newBelt, sportId: _student!.getPrimarySport()),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 24),
          ],

          // Competition Results from Other Academies
          if (history.competitionResults.isNotEmpty) ...[
            _buildSectionTitle('Competicoes em Outras Academias'),
            const SizedBox(height: 12),
            ...history.competitionResults.take(10).map((result) {
              final positionIcons = {
                'gold': '🥇',
                'silver': '🥈',
                'bronze': '🥉',
                'participant': '🎖️',
              };
              final positionLabels = {
                'gold': 'Ouro',
                'silver': 'Prata',
                'bronze': 'Bronze',
                'participant': 'Participante',
              };

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(
                  children: [
                    Text(
                      positionIcons[result.position] ?? '🎖️',
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  result.competitionName,
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.warning.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Lutou por ${result.academyName}',
                                  style: AppTheme.labelSmall.copyWith(
                                    color: AppTheme.warning,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat('dd/MM/yyyy').format(result.date)} - ${positionLabels[result.position] ?? result.position}',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textDisabled,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 24),
          ],

          // Global Medal Count
          if (history.medalCount.total > 0) ...[
            _buildSectionTitle('Total de Medalhas (Todas Academias)'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMedalCard(
                    '🥇',
                    history.medalCount.gold,
                    'Ouros',
                    const Color(0xFFFFD700),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMedalCard(
                    '🥈',
                    history.medalCount.silver,
                    'Pratas',
                    const Color(0xFFC0C0C0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMedalCard(
                    '🥉',
                    history.medalCount.bronze,
                    'Bronzes',
                    const Color(0xFFCD7F32),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMedalCard(
                    '🏆',
                    history.medalCount.total,
                    'Total',
                    AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Empty State
          if (history.beltProgressions.isEmpty &&
              history.competitionResults.isEmpty &&
              history.academies.length <= 1)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.globe,
                      size: 48,
                      color: AppTheme.textDisabled,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Este aluno nao possui historico em outras academias',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAcademyBadge(String academyName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.building2, size: 10, color: Color(0xFF6366F1)),
          const SizedBox(width: 4),
          Text(
            academyName,
            style: AppTheme.labelSmall.copyWith(
              color: const Color(0xFF6366F1),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedalCard(String emoji, int count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  String _getBeltName(String belt, {SportId sportId = SportId.bjj}) =>
      getGradeLabel(sportId, belt);

  Color _getBeltColor(String belt, {SportId sportId = SportId.bjj}) =>
      getGradeColor(sportId, belt);

  Future<void> _generateLinkCode() async {
    try {
      final linkCodeService = LinkCodeService(FirebaseService.academyId);
      final linkCode = await linkCodeService.generate(
        studentId: _student!.id,
        studentName: _student!.fullName,
        createdBy: 'monitor',
      );

      if (mounted) {
        Celebration.confetti(context);
        _showLinkCodeDialog(linkCode);
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao gerar codigo: $e');
      }
    }
  }

  void _showLinkCodeDialog(LinkCode linkCode) {
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
            Text('Compartilhe com ${linkCode.studentName}:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary, width: 2),
              ),
              child: SelectableText(
                linkCode.code,
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
              Clipboard.setData(ClipboardData(text: linkCode.code));
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

class _InfoRow {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});
}

class _HistoryItem {
  final DateTime date;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const _HistoryItem({
    required this.date,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
  });
}
