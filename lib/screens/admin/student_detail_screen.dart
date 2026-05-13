import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants.dart';
import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/portal_providers.dart';
import '../../providers/providers.dart';
import '../../services/belt_progression_service.dart';
import '../../services/services.dart';
import '../../widgets/common/profile_photo_picker.dart';
import '../../widgets/common/sport_chip.dart';

/// Admin Student Detail Screen - View and manage student
class AdminStudentDetailScreen extends ConsumerStatefulWidget {
  final String studentId;

  const AdminStudentDetailScreen({super.key, required this.studentId});

  @override
  ConsumerState<AdminStudentDetailScreen> createState() => _AdminStudentDetailScreenState();
}

class _AdminStudentDetailScreenState extends ConsumerState<AdminStudentDetailScreen>
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;
      final studentService = StudentService(academyId);
      final attendanceService = AttendanceService(academyId);
      final paymentService = PaymentService(academyId);
      final beltService = BeltProgressionService(academyId);
      final achievementService = AchievementService(academyId);

      final storeService = StoreService(academyId);
      final assessmentService = AssessmentService(academyId);
      final planService = PlanService(academyId);

      final student = await studentService.getById(widget.studentId);
      final attendances = await attendanceService.getByStudent(widget.studentId);
      final payments = await paymentService.getByStudent(widget.studentId);
      final storeOrders = await storeService.getOrdersByStudent(widget.studentId);
      final progressions = await beltService.getByStudent(widget.studentId);
      final achievements = await achievementService.getForStudent(widget.studentId);
      final assessments = await assessmentService.getByStudent(widget.studentId);
      final studentPlans = await planService.getPlansForStudent(widget.studentId);

      // Auto-graduation eligibility — only computed when the academy has
      // the feature on (cheap settings doc read first, then the actual math).
      final settings = ref.read(academySettingsProvider).valueOrNull;
      final autoGradOn = settings?.autoGraduationEnabled == true;
      EligibilityResult? eligibility;
      if (autoGradOn && student != null) {
        eligibility = await beltService.checkEligibilityForStudent(
          student.id,
          sportId: student.getPrimarySport(),
        );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _student == null
              ? const Center(child: Text('Aluno não encontrado'))
              : NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    _buildSliverAppBar(),
                  ],
                  body: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          border: Border(
                            bottom: BorderSide(
                              color: AppTheme.divider,
                              width: 1,
                            ),
                          ),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          indicatorSize: TabBarIndicatorSize.label,
                          indicator: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppTheme.primary,
                                width: 3,
                              ),
                            ),
                          ),
                          tabs: [
                            Tab(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.info, size: 16),
                                  const SizedBox(width: 6),
                                  const Text('Info'),
                                ],
                              ),
                            ),
                            Tab(
                              child: _TabWithBadge(
                                icon: LucideIcons.clipboardCheck,
                                label: 'Presenças',
                                count: _attendances.length,
                              ),
                            ),
                            Tab(
                              child: _TabWithBadge(
                                icon: LucideIcons.dollarSign,
                                label: 'Financeiro',
                                count: _payments.length + _storeOrders.length,
                              ),
                            ),
                            Tab(
                              child: _TabWithBadge(
                                icon: LucideIcons.star,
                                label: 'Comportamento',
                                count: _assessments.length,
                              ),
                            ),
                            Tab(
                              child: _TabWithBadge(
                                icon: LucideIcons.trophy,
                                label: 'Conquistas',
                                count: _achievements.length,
                              ),
                            ),
                            Tab(
                              child: _TabWithBadge(
                                icon: LucideIcons.history,
                                label: 'Histórico',
                                count: _progressions.length + _achievements.length,
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
                            _buildFinancialTab(),
                            _buildBehaviorTab(),
                            _buildAchievementsTab(),
                            _buildHistoryTab(),
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
      actions: [
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () async {
            final result = await context.push('/admin/alunos/${widget.studentId}/editar');
            if (result == true && mounted) {
              _loadData();
            }
          },
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'promote') _showPromoteDialog();
            if (value == 'toggle_status') _toggleStatus();
            if (value == 'generate_code') _generateLinkCode();
            if (value == 'delete') _showDeleteConfirmation();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'promote',
              child: Row(
                children: [
                  Icon(Icons.military_tech),
                  SizedBox(width: 8),
                  Text('Graduar'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'toggle_status',
              child: Row(
                children: [
                  Icon(_student!.status == StudentStatus.active
                      ? Icons.person_off
                      : Icons.person),
                  const SizedBox(width: 8),
                  Text(_student!.status == StudentStatus.active
                      ? 'Desativar'
                      : 'Ativar'),
                ],
              ),
            ),
            // Only show if student doesn't have a linked account
            if (_student!.linkedUserId == null)
              const PopupMenuItem(
                value: 'generate_code',
                child: Row(
                  children: [
                    Icon(LucideIcons.link),
                    SizedBox(width: 8),
                    Text('Gerar Codigo de Acesso'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Excluir', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                getGradeColor(_student!.getPrimarySport(), _student!.currentBelt),
                getGradeColor(_student!.getPrimarySport(), _student!.currentBelt).withValues(alpha: 0.7),
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
                      // Avatar com borda colorida
                      ProfilePhotoPicker(
                        academyId: ref.watch(selectedAcademyIdProvider) ?? '',
                        studentId: _student!.id,
                        photoUrl: _student!.photoUrl,
                        fullName: _student!.fullName,
                        currentBelt: _student!.currentBelt,
                        editable: true,
                        size: 96.0,
                        onPhotoUpdated: () {
                          _loadData();
                        },
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _student!.fullName,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: (_student!.currentBelt == 'white' || _student!.currentBelt == 'yellow') ? Colors.black : Colors.white,
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
    final sports = _student!.getSports();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: sports.map((sportId) {
        final grade = _student!.getGrade(sportId);
        final gradeId = grade?.currentGrade ?? 'white';
        final stripes = grade?.currentStripes ?? 0;
        final gradeLabel = getGradeLabel(sportId, gradeId);
        final gradeColor = getGradeColor(sportId, gradeId);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sports.length > 1) ...[
                SportChip(sportId: sportId, size: SportChipSize.xs),
                const SizedBox(width: 4),
              ],
              Icon(LucideIcons.award, size: 16, color: gradeColor),
              const SizedBox(width: 6),
              Text(
                gradeLabel,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (stripes > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: gradeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$stripes grau${stripes > 1 ? "s" : ""}',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatusBadge() {
    final statusConfig = {
      StudentStatus.active: {'color': Colors.green, 'icon': LucideIcons.checkCircle2},
      StudentStatus.inactive: {'color': Colors.grey, 'icon': LucideIcons.pauseCircle},
      StudentStatus.suspended: {'color': Colors.orange, 'icon': LucideIcons.alertCircle},
      StudentStatus.injured: {'color': Colors.blue, 'icon': LucideIcons.heartPulse},
    };

    final config = statusConfig[_student!.status] ?? {'color': Colors.grey, 'icon': LucideIcons.circle};
    final statusColor = config['color'] as Color;
    final statusIcon = config['icon'] as IconData;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            size: 14,
            color: statusColor,
          ),
          const SizedBox(width: 6),
          Text(
            _student!.status.label,
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEligibilityBanner(EligibilityResult e) {
    final eligible = e.eligible;
    final color = eligible ? AppTheme.warning : AppTheme.info;
    final lightColor = eligible ? AppTheme.warningLight : AppTheme.infoLight;
    final icon = eligible ? LucideIcons.zap : LucideIcons.target;
    final unit = e.weighted ? 'pts' : 'aulas';
    final progress = e.requiredClasses > 0
        ? (e.currentClasses / e.requiredClasses).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lightColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  eligible ? 'Elegivel para graduar' : 'Proxima graduacao',
                  style: AppTheme.titleSmall.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (eligible)
                ElevatedButton.icon(
                  onPressed: _showPromoteDialog,
                  icon: const Icon(LucideIcons.award, size: 14),
                  label: const Text('Graduar agora'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    textStyle: AppTheme.labelSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            eligible
                ? '${e.currentClasses}/${e.requiredClasses} $unit — pronto para a proxima graduacao.'
                : 'Faltam ${e.missingClasses} $unit (${e.currentClasses}/${e.requiredClasses})',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Auto-graduation banner (only when feature is enabled)
          if (_autoGradEnabled && _eligibility != null) ...[
            _buildEligibilityBanner(_eligibility!),
            const SizedBox(height: 16),
          ],

          // Quick stats
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Presenças',
                  value: _student!.totalAttendanceCount.toString(),
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Mês atual',
                  value: _attendances.where((a) =>
                    a.date.month == DateTime.now().month &&
                    a.date.year == DateTime.now().year
                  ).length.toString(),
                  icon: Icons.calendar_today,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Conquistas',
                  value: _achievements.length.toString(),
                  icon: Icons.emoji_events,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Personal info
          _buildSection('Informações Pessoais', [
            _InfoRow(label: 'Nome completo', value: _student!.fullName),
            if (_student!.nickname != null)
              _InfoRow(label: 'Apelido', value: _student!.nickname!),
            if (_student!.email != null)
              _InfoRow(label: 'E-mail', value: _student!.email!),
            if (_student!.phone != null)
              _InfoRow(label: 'Telefone', value: _student!.phone!),
            if (_student!.birthDate != null)
              _InfoRow(
                label: 'Nascimento',
                value: DateFormat('dd/MM/yyyy').format(_student!.birthDate!),
              ),
            _InfoRow(label: 'Categoria', value: _student!.category.label),
          ]),
          const SizedBox(height: 16),

          // Academy info
          _buildSection('Informações da Academia', [
            _InfoRow(
              label: 'Data de início',
              value: DateFormat('dd/MM/yyyy').format(_student!.startDate),
            ),
            if (_student!.planId != null)
              _InfoRow(label: 'Plano ID', value: _student!.planId!),
            _InfoRow(
              label: 'Mensalidade',
              value: 'R\$ ${_student!.tuitionValue.toStringAsFixed(2)}',
            ),
            _InfoRow(
              label: 'Dia de vencimento',
              value: _student!.tuitionDay.toString(),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceTab() {
    if (_attendances.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.clipboardX,
                  size: 64,
                  color: AppTheme.primary.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Nenhuma presença registrada',
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'As presenças do aluno aparecerão aqui\nassim que forem registradas',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Group by month
    final grouped = <String, List<Attendance>>{};
    for (final a in _attendances) {
      final key = DateFormat('MMMM yyyy', 'pt_BR').format(a.date);
      grouped.putIfAbsent(key, () => []).add(a);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    entry.key,
                    style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${entry.value.length} presenças',
                      style: TextStyle(color: AppTheme.primary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.map((a) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(Icons.check, color: Colors.green),
                ),
                title: Text(a.className),
                subtitle: Text(DateFormat('EEEE, d', 'pt_BR').format(a.date)),
                trailing: Text(
                  DateFormat('HH:mm').format(a.createdAt),
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
              ),
            )),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildFinancialTab() {
    if (_payments.isEmpty && _storeOrders.isEmpty && _studentPlans.isEmpty) {
      return const Center(child: Text('Nenhum pagamento registrado'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Plan and value section
        if (_studentPlans.isNotEmpty) ...[
          Text(
            'PLANO E VALOR',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ..._studentPlans.map((plan) {
            final studentValue = plan.getStudentValue(widget.studentId);
            final hasCustomValue = plan.customValues.containsKey(widget.studentId);
            final studentDueDay = plan.getStudentDueDay(widget.studentId);
            final hasCustomDueDay = plan.customDueDays.containsKey(widget.studentId);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
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
                          plan.name,
                          style: AppTheme.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showCustomValueDialog(plan),
                        child: const Icon(LucideIcons.pencil, size: 18, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Valor padrão: R\$ ${plan.monthlyValue.toStringAsFixed(2)}',
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Valor do aluno: R\$ ${studentValue.toStringAsFixed(2)}',
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: hasCustomValue ? AppTheme.success : AppTheme.textPrimary,
                        ),
                      ),
                      if (hasCustomValue) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.successLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Valor personalizado',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Vencimento: dia $studentDueDay',
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: hasCustomDueDay ? AppTheme.success : AppTheme.textPrimary,
                        ),
                      ),
                      if (hasCustomDueDay) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.successLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Personalizado',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        // Tuition payments
        if (_payments.isNotEmpty) ...[
          Text(
            'MENSALIDADES',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ..._payments.map((payment) => _PaymentCard(payment: payment)),
        ],
        // Store orders
        if (_storeOrders.isNotEmpty) ...[
          if (_payments.isNotEmpty) const SizedBox(height: 16),
          Text(
            'PEDIDOS DA LOJA',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ..._storeOrders.map((order) => _StoreOrderCard(order: order)),
        ],
      ],
    );
  }

  void _showCustomValueDialog(Plan plan) {
    final studentValue = plan.getStudentValue(widget.studentId);
    final controller = TextEditingController(text: studentValue.toStringAsFixed(2));
    final hasCustomValue = plan.customValues.containsKey(widget.studentId);
    final studentDueDay = plan.getStudentDueDay(widget.studentId);
    final dueDayController = TextEditingController(text: studentDueDay.toString());
    final hasCustomDueDay = plan.customDueDays.containsKey(widget.studentId);
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Valor e Vencimento - ${plan.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Valor padrão do plano: R\$ ${plan.monthlyValue.toStringAsFixed(2)}',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor do aluno',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            if (hasCustomValue) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final planService = PlanService(FirebaseService.academyId);
                  await planService.removeCustomValue(plan.id, widget.studentId);
                  if (mounted) parentContext.showSuccess('Valor restaurado ao padrão do plano');
                  _loadData();
                },
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: const Text('Restaurar valor do plano'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Vencimento padrão do plano: dia ${plan.defaultDueDay}',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dueDayController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dia de vencimento',
                hintText: '1-31',
                border: OutlineInputBorder(),
              ),
            ),
            if (hasCustomDueDay) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final planService = PlanService(FirebaseService.academyId);
                  await planService.removeCustomDueDay(plan.id, widget.studentId);
                  if (mounted) parentContext.showSuccess('Vencimento restaurado ao padrão do plano');
                  _loadData();
                },
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: const Text('Restaurar vencimento do plano'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final value = double.tryParse(controller.text.replaceAll(',', '.'));
              if (value == null || value <= 0) return;
              final dueDay = int.tryParse(dueDayController.text);
              if (dueDay == null || dueDay < 1 || dueDay > 31) return;
              Navigator.of(dialogContext).pop();
              final planService = PlanService(FirebaseService.academyId);
              // Save value
              if (value == plan.monthlyValue) {
                await planService.removeCustomValue(plan.id, widget.studentId);
              } else {
                await planService.setCustomValue(plan.id, widget.studentId, value);
              }
              // Save due day
              if (dueDay == plan.defaultDueDay) {
                await planService.removeCustomDueDay(plan.id, widget.studentId);
              } else {
                await planService.setCustomDueDay(plan.id, widget.studentId, dueDay);
              }
              if (mounted) parentContext.showSuccess('Valor e vencimento atualizados');
              _loadData();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsTab() {
    return Stack(
      children: [
        _achievements.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.trophy,
                          size: 64,
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Nenhuma conquista ainda',
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Registre as conquistas e marcos\nimportantes do aluno',
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Toque em + para adicionar',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textDisabled,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: _achievements.length,
                itemBuilder: (context, index) {
                  final achievement = _achievements[index];
                  return _AchievementCard(
                    achievement: achievement,
                    onEdit: () => _showEditAchievementDialog(achievement),
                    onDelete: () => _showDeleteAchievementConfirmation(achievement),
                  );
                },
              ),
        // FAB to add achievement
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: _showAddAchievementDialog,
            backgroundColor: AppTheme.primary,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Adicionar', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  void _showAddAchievementDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    AchievementType selectedType = AchievementType.milestone;
    String? selectedBelt;
    int selectedStripes = 0;

    final beltOptions = _student?.category == StudentCategory.kids
        ? BeltConstants.kidsBelts
        : BeltConstants.adultBelts;

    // Store parent context before dialog
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Adicionar Conquista'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type selector
                  Text('Tipo', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AchievementType>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: AchievementType.graduation,
                        child: Text('Graduação (Faixa)'),
                      ),
                      const DropdownMenuItem(
                        value: AchievementType.stripe,
                        child: Text('Grau'),
                      ),
                      const DropdownMenuItem(
                        value: AchievementType.milestone,
                        child: Text('Marco/Conquista'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => selectedType = value!);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Belt selection for graduation type
                  if (selectedType == AchievementType.graduation) ...[
                    Text('Faixa Recebida', style: AppTheme.labelMedium),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedBelt,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        hintText: 'Selecione a faixa',
                      ),
                      items: beltOptions.map((belt) => DropdownMenuItem(
                        value: belt,
                        child: Text(BeltConstants.beltLabels[belt] ?? belt),
                      )).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedBelt = value);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Stripes for stripe type
                  if (selectedType == AchievementType.stripe) ...[
                    Text('Graus Recebidos', style: AppTheme.labelMedium),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: selectedStripes,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [1, 2, 3, 4].map((s) => DropdownMenuItem(
                        value: s,
                        child: Text('$s grau(s)'),
                      )).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedStripes = value!);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Title (for milestone type)
                  if (selectedType == AchievementType.milestone) ...[
                    Text('Título', style: AppTheme.labelMedium),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Ex: 100 Treinos, Campeão Regional...',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Description (optional)
                  Text('Descrição (opcional)', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Detalhes adicionais...',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date picker
                  Text('Data', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        locale: const Locale('pt', 'BR'),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.divider),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18),
                          const SizedBox(width: 8),
                          Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  // Validate
                  if (selectedType == AchievementType.graduation && selectedBelt == null) {
                    parentContext.showError('Selecione a faixa');
                    return;
                  }
                  if (selectedType == AchievementType.milestone && titleController.text.trim().isEmpty) {
                    parentContext.showError('Informe o título');
                    return;
                  }

                  Navigator.pop(dialogContext);

                  try {
                    final service = AchievementService(FirebaseService.academyId);

                    String title;
                    if (selectedType == AchievementType.graduation) {
                      title = 'Graduação para Faixa ${getBeltName(selectedBelt!)}';
                    } else if (selectedType == AchievementType.stripe) {
                      title = 'Recebeu $selectedStripes grau(s)';
                    } else {
                      title = titleController.text.trim();
                    }

                    await service.create(
                      studentId: _student!.id,
                      studentName: _student!.fullName,
                      type: selectedType,
                      title: title,
                      description: descriptionController.text.trim().isNotEmpty
                          ? descriptionController.text.trim()
                          : null,
                      date: selectedDate,
                      toBelt: selectedType == AchievementType.graduation ? selectedBelt : null,
                      toStripes: selectedType == AchievementType.stripe ? selectedStripes : null,
                      createdBy: 'admin',
                    );

                    if (mounted) {
                      parentContext.showSuccess('Conquista adicionada!');
                      await _loadData();
                    }
                  } catch (e) {
                    if (mounted) {
                      parentContext.showError('Erro: $e');
                    }
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditAchievementDialog(Achievement achievement) {
    DateTime selectedDate = achievement.date;

    // Store parent context before dialog
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Editar Data'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.bold),
                ),
                if (achievement.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    achievement.description!,
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
                const SizedBox(height: 24),
                Text('Data da Conquista', style: AppTheme.labelMedium),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      locale: const Locale('pt', 'BR'),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.divider),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 8),
                        Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                        const Spacer(),
                        const Icon(Icons.edit, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);

                  try {
                    final service = AchievementService(FirebaseService.academyId);
                    await service.update(achievement.id, {
                      'date': Timestamp.fromDate(selectedDate),
                    });

                    if (mounted) {
                      parentContext.showSuccess('Data atualizada!');
                      await _loadData();
                    }
                  } catch (e) {
                    if (mounted) {
                      parentContext.showError('Erro: $e');
                    }
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteAchievementConfirmation(Achievement achievement) {
    // Store parent context before dialog
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir Conquista'),
        content: Text('Deseja excluir "${achievement.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);

              try {
                final service = AchievementService(FirebaseService.academyId);
                await service.delete(achievement.id);

                if (mounted) {
                  parentContext.showSuccess('Conquista excluída!');
                  await _loadData();
                }
              } catch (e) {
                if (mounted) {
                  parentContext.showError('Erro: $e');
                }
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // BEHAVIOR TAB
  // ============================================
  Widget _buildBehaviorTab() {
    return Stack(
      children: [
        _assessments.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.star, size: 64, color: AppTheme.textDisabled),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma avaliação registrada',
                      style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Adicione avaliações comportamentais\npara que os pais possam acompanhar',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textDisabled),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: _assessments.length,
                itemBuilder: (context, index) {
                  final assessment = _assessments[index];
                  return _AssessmentCard(
                    assessment: assessment,
                    onEdit: () => _showEditAssessmentDialog(assessment),
                    onDelete: () => _showDeleteAssessmentConfirmation(assessment),
                  );
                },
              ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: _showAddAssessmentDialog,
            backgroundColor: AppTheme.primary,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Avaliar', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  void _showAddAssessmentDialog() {
    final scores = <AssessmentCategory, int>{
      AssessmentCategory.respeito: 3,
      AssessmentCategory.disciplina: 3,
      AssessmentCategory.pontualidade: 3,
      AssessmentCategory.tecnica: 3,
      AssessmentCategory.esforco: 3,
    };
    final notesController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          double average = scores.values.fold<int>(0, (acc, v) => acc + v) / scores.length;

          return AlertDialog(
            title: const Text('Nova Avaliação'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date
                  Text('Data', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        locale: const Locale('pt', 'BR'),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.divider),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 8),
                          Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Average display
                  Center(
                    child: Column(
                      children: [
                        Text(
                          average.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _getScoreColor(average),
                          ),
                        ),
                        Text(
                          _getScoreLabel(average),
                          style: TextStyle(
                            color: _getScoreColor(average),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Score sliders
                  ...AssessmentCategory.values.map((category) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(category.label, style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
                              Text(
                                '${scores[category]}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _getScoreColor(scores[category]!.toDouble()),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: scores[category]!.toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            activeColor: _getScoreColor(scores[category]!.toDouble()),
                            onChanged: (value) {
                              setDialogState(() => scores[category] = value.round());
                            },
                          ),
                        ],
                      ),
                    );
                  }),

                  // Notes
                  Text('Observações (opcional)', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Feedback para os pais...',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);

                  try {
                    final currentUser = ref.read(currentUserProvider).valueOrNull;
                    final service = AssessmentService(FirebaseService.academyId);
                    await service.create(
                      studentId: _student!.id,
                      studentName: _student!.fullName,
                      scores: scores.entries.map((e) =>
                        AssessmentScore(category: e.key, score: e.value),
                      ).toList(),
                      assessedBy: currentUser?.id ?? 'admin',
                      assessedByName: currentUser?.displayName ?? 'Professor',
                      date: selectedDate,
                      notes: notesController.text.trim().isNotEmpty
                          ? notesController.text.trim()
                          : null,
                    );

                    if (mounted) {
                      parentContext.showSuccess('Avaliação adicionada!');
                      await _loadData();
                    }
                  } catch (e) {
                    if (mounted) {
                      parentContext.showError('Erro: $e');
                    }
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditAssessmentDialog(Assessment assessment) {
    final scores = <AssessmentCategory, int>{};
    for (final category in AssessmentCategory.values) {
      scores[category] = assessment.getScoreForCategory(category) ?? 3;
    }
    final notesController = TextEditingController(text: assessment.notes);
    DateTime selectedDate = assessment.date;
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          double average = scores.values.fold<int>(0, (acc, v) => acc + v) / scores.length;

          return AlertDialog(
            title: const Text('Editar Avaliação'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date
                  Text('Data', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        locale: const Locale('pt', 'BR'),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.divider),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 8),
                          Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Average
                  Center(
                    child: Column(
                      children: [
                        Text(
                          average.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _getScoreColor(average),
                          ),
                        ),
                        Text(
                          _getScoreLabel(average),
                          style: TextStyle(
                            color: _getScoreColor(average),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Scores
                  ...AssessmentCategory.values.map((category) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(category.label, style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
                              Text(
                                '${scores[category]}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _getScoreColor(scores[category]!.toDouble()),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: scores[category]!.toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            activeColor: _getScoreColor(scores[category]!.toDouble()),
                            onChanged: (value) {
                              setDialogState(() => scores[category] = value.round());
                            },
                          ),
                        ],
                      ),
                    );
                  }),

                  // Notes
                  Text('Observações (opcional)', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Feedback para os pais...',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);

                  try {
                    final service = AssessmentService(FirebaseService.academyId);
                    final scoresMap = <String, int>{};
                    for (final e in scores.entries) {
                      scoresMap[e.key.value] = e.value;
                    }
                    await service.update(assessment.id, {
                      'date': Timestamp.fromDate(selectedDate),
                      'scores': scoresMap,
                      'notes': notesController.text.trim().isNotEmpty
                          ? notesController.text.trim()
                          : null,
                    });

                    if (mounted) {
                      parentContext.showSuccess('Avaliação atualizada!');
                      await _loadData();
                    }
                  } catch (e) {
                    if (mounted) {
                      parentContext.showError('Erro: $e');
                    }
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteAssessmentConfirmation(Assessment assessment) {
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir Avaliação'),
        content: Text('Deseja excluir a avaliação de ${DateFormat('dd/MM/yyyy').format(assessment.date)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);

              try {
                final service = AssessmentService(FirebaseService.academyId);
                await service.delete(assessment.id);

                if (mounted) {
                  parentContext.showSuccess('Avaliação excluída!');
                  await _loadData();
                }
              } catch (e) {
                if (mounted) {
                  parentContext.showError('Erro: $e');
                }
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 4.5) return Colors.green;
    if (score >= 4.0) return Colors.lightGreen;
    if (score >= 3.0) return Colors.orange;
    if (score >= 2.0) return Colors.deepOrange;
    return Colors.red;
  }

  String _getScoreLabel(double score) {
    if (score >= 4.5) return 'Excelente';
    if (score >= 4.0) return 'Muito Bom';
    if (score >= 3.0) return 'Bom';
    if (score >= 2.0) return 'Regular';
    return 'Precisa Melhorar';
  }

  Widget _buildHistoryTab() {
    final allHistory = <_HistoryItem>[];

    // Add progressions
    for (final p in _progressions) {
      allHistory.add(_HistoryItem(
        date: p.promotionDate,
        title: p.isBeltChange ? 'Faixa ${p.newBelt}' : 'Grau ${p.newStripes}',
        subtitle: p.notes,
        icon: Icons.military_tech,
        color: getGradeColor(p.getSport(), p.newBelt),
      ));
    }

    // Add achievements
    for (final a in _achievements) {
      allHistory.add(_HistoryItem(
        date: a.date,
        title: a.title,
        subtitle: a.description,
        icon: Icons.emoji_events,
        color: Colors.amber,
      ));
    }

    // Sort by date descending
    allHistory.sort((a, b) => b.date.compareTo(a.date));

    if (allHistory.isEmpty) {
      return const Center(child: Text('Nenhum histórico'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allHistory.length,
      itemBuilder: (context, index) {
        final item = allHistory[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: item.color.withValues(alpha: 0.2),
              child: Icon(item.icon, color: item.color),
            ),
            title: Text(item.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.subtitle != null) Text(item.subtitle!),
                Text(
                  DateFormat('dd/MM/yyyy').format(item.date),
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPromoteDialog() {
    final sports = _student!.getSports();
    SportId selectedSport = _student!.getPrimarySport();
    bool isStripe = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final grade = _student!.getGrade(selectedSport);
          final currentGrade = grade?.currentGrade ?? 'white';
          final currentStripes = grade?.currentStripes ?? 0;
          final sportDef = getSport(selectedSport);
          final hasStripes = sportDef.supportsStripes;
          final hasGrades = sportDef.gradeSystem != GradeSystem.none;

          return AlertDialog(
            title: const Text('Graduar Aluno'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Aluno: ${_student!.fullName}'),
                if (sports.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SportId>(
                    value: selectedSport,
                    items: sports.map((s) {
                      final sport = getSport(s);
                      return DropdownMenuItem(value: s, child: Text(sport.label));
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => selectedSport = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Esporte',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (hasGrades) ...[
                  const SizedBox(height: 8),
                  Text('Graduação atual: ${getGradeLabel(selectedSport, currentGrade)} - $currentStripes grau(s)'),
                ],
                if (hasGrades && hasStripes) ...[
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Grau')),
                      ButtonSegment(value: false, label: Text('Faixa')),
                    ],
                    selected: {isStripe},
                    onSelectionChanged: (value) {
                      setDialogState(() => isStripe = value.first);
                    },
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    final service = BeltProgressionService(FirebaseService.academyId);

                    if (isStripe && hasStripes) {
                      await service.addStripe(
                        studentId: _student!.id,
                        studentName: _student!.fullName,
                        promotedBy: 'admin',
                        promotedByName: 'Administrador',
                        sportId: selectedSport,
                      );
                    } else if (hasGrades) {
                      final nextGrade = _getNextGrade(selectedSport, currentGrade);
                      await service.changeBelt(
                        studentId: _student!.id,
                        studentName: _student!.fullName,
                        newBelt: nextGrade,
                        promotedBy: 'admin',
                        promotedByName: 'Administrador',
                        sportId: selectedSport,
                      );
                    }

                    if (mounted) {
                      Navigator.pop(context);
                      this.context.showSuccess('Graduação realizada com sucesso!');
                      _loadData();
                    }
                  } catch (e) {
                    if (mounted) {
                      this.context.showError('Erro: $e');
                    }
                  }
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getNextGrade(SportId sportId, String current) {
    final grades = getGradesForSport(sportId);
    final index = grades.indexWhere((g) => g.id == current);
    if (index >= 0 && index < grades.length - 1) {
      return grades[index + 1].id;
    }
    return current;
  }

  void _toggleStatus() async {
    try {
      final service = StudentService(FirebaseService.academyId);
      final newStatus = _student!.status == StudentStatus.active
          ? StudentStatus.inactive
          : StudentStatus.active;

      await service.updateStatus(_student!.id, newStatus);

      if (mounted) {
        context.showSuccess(
          newStatus == StudentStatus.active
              ? 'Aluno ativado!'
              : 'Aluno desativado!',
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Aluno'),
        content: Text(
          'Deseja excluir ${_student!.fullName}? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                final service = StudentService(FirebaseService.academyId);
                await service.delete(_student!.id);

                if (mounted) {
                  Navigator.pop(context);
                  this.context.showSuccess('Aluno excluído!');
                  this.context.go('/admin/alunos');
                }
              } catch (e) {
                if (mounted) {
                  this.context.showError('Erro: $e');
                }
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateLinkCode() async {
    try {
      final linkCodeService = LinkCodeService(FirebaseService.academyId);
      final linkCode = await linkCodeService.generate(
        studentId: _student!.id,
        studentName: _student!.fullName,
        createdBy: 'admin',
      );

      if (mounted) {
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

/// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  Color _getIconColor() {
    if (icon == Icons.check_circle) return const Color(0xFF22C55E); // Green
    if (icon == Icons.calendar_today) return const Color(0xFF3B82F6); // Blue
    if (icon == Icons.emoji_events) return const Color(0xFFF59E0B); // Amber
    return AppTheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getIconColor();

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Info Row Widget with icons
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  IconData _getDefaultIcon() {
    if (label.contains('Nome')) return LucideIcons.user;
    if (label.contains('Apelido')) return LucideIcons.userCircle;
    if (label.contains('E-mail')) return LucideIcons.mail;
    if (label.contains('Telefone')) return LucideIcons.phone;
    if (label.contains('Nascimento')) return LucideIcons.cake;
    if (label.contains('Categoria')) return LucideIcons.tag;
    if (label.contains('Data de início')) return LucideIcons.calendar;
    if (label.contains('Plano')) return LucideIcons.creditCard;
    if (label.contains('Mensalidade')) return LucideIcons.dollarSign;
    if (label.contains('vencimento')) return LucideIcons.clock;
    return LucideIcons.info;
  }

  @override
  Widget build(BuildContext context) {
    final displayIcon = _getDefaultIcon();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.divider.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              displayIcon,
              size: 16,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Payment Card Widget
class _PaymentCard extends StatelessWidget {
  final Payment payment;

  const _PaymentCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    final statusColors = {
      PaymentStatus.pending: Colors.orange,
      PaymentStatus.paid: Colors.green,
      PaymentStatus.overdue: Colors.red,
      PaymentStatus.cancelled: Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColors[payment.status]?.withValues(alpha: 0.2),
          child: Icon(
            payment.status == PaymentStatus.paid ? Icons.check : Icons.receipt,
            color: statusColors[payment.status],
          ),
        ),
        title: Text(payment.description ?? 'Mensalidade'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Venc: ${DateFormat('dd/MM/yyyy').format(payment.dueDate)}'),
            if (payment.paidAt != null)
              Text(
                'Pago em: ${DateFormat('dd/MM/yyyy').format(payment.paidAt!)}',
                style: const TextStyle(color: Colors.green),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'R\$ ${payment.value.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColors[payment.status]?.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                payment.status.label,
                style: TextStyle(
                  fontSize: 9,
                  color: statusColors[payment.status],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// History Item Helper Class
class _HistoryItem {
  final DateTime date;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  _HistoryItem({
    required this.date,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
  });
}

/// Achievement Card Widget
class _AchievementCard extends StatelessWidget {
  final Achievement achievement;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AchievementCard({
    required this.achievement,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getTypeColor().withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getTypeIcon(),
                  color: _getTypeColor(),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      achievement.title,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (achievement.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        achievement.description!,
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('dd/MM/yyyy').format(achievement.date),
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getTypeColor().withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _getTypeLabel(),
                            style: AppTheme.labelSmall.copyWith(
                              color: _getTypeColor(),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: AppTheme.textSecondary),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text('Editar data'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Excluir', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getTypeIcon() {
    switch (achievement.type) {
      case AchievementType.graduation:
        return Icons.military_tech;
      case AchievementType.stripe:
        return LucideIcons.award;
      case AchievementType.competition:
        return Icons.emoji_events;
      case AchievementType.milestone:
        return Icons.star;
    }
  }

  Color _getTypeColor() {
    switch (achievement.type) {
      case AchievementType.graduation:
        return Colors.purple;
      case AchievementType.stripe:
        return Colors.blue;
      case AchievementType.competition:
        return Colors.amber;
      case AchievementType.milestone:
        return Colors.green;
    }
  }

  String _getTypeLabel() {
    switch (achievement.type) {
      case AchievementType.graduation:
        return 'Graduação';
      case AchievementType.stripe:
        return 'Grau';
      case AchievementType.competition:
        return 'Competição';
      case AchievementType.milestone:
        return 'Marco';
    }
  }
}

/// Store Order Card Widget
class _StoreOrderCard extends StatelessWidget {
  final StoreOrder order;

  const _StoreOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final statusColors = {
      StoreOrderStatus.pendingPayment: Colors.orange,
      StoreOrderStatus.paid: Colors.green,
      StoreOrderStatus.preparing: Colors.blue,
      StoreOrderStatus.ready: Colors.purple,
      StoreOrderStatus.delivered: Colors.teal,
      StoreOrderStatus.cancelled: Colors.grey,
    };

    final itemNames = order.items.map((i) => i.productName).join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColors[order.status]?.withValues(alpha: 0.2),
          child: Icon(
            LucideIcons.shoppingBag,
            color: statusColors[order.status],
            size: 20,
          ),
        ),
        title: Text(
          itemNames.isNotEmpty ? itemNames : 'Pedido',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('dd/MM/yyyy').format(order.createdAt)),
            if (order.paidAt != null)
              Text(
                'Pago em: ${DateFormat('dd/MM/yyyy').format(order.paidAt!)}',
                style: const TextStyle(color: Colors.green),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'R\$ ${order.total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColors[order.status]?.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                order.status.label,
                style: TextStyle(
                  fontSize: 9,
                  color: statusColors[order.status],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Assessment Card Widget for admin behavior tab
class _AssessmentCard extends StatelessWidget {
  final Assessment assessment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AssessmentCard({
    required this.assessment,
    required this.onEdit,
    required this.onDelete,
  });

  Color _getScoreColor(double score) {
    if (score >= 4.5) return Colors.green;
    if (score >= 4.0) return Colors.lightGreen;
    if (score >= 3.0) return Colors.orange;
    if (score >= 2.0) return Colors.deepOrange;
    return Colors.red;
  }

  String _getScoreLabel(double score) {
    if (score >= 4.5) return 'Excelente';
    if (score >= 4.0) return 'Muito Bom';
    if (score >= 3.0) return 'Bom';
    if (score >= 2.0) return 'Regular';
    return 'Precisa Melhorar';
  }

  @override
  Widget build(BuildContext context) {
    final average = assessment.averageScore;
    final scoreColor = _getScoreColor(average);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd/MM/yyyy').format(assessment.date),
                        style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scoreColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${average.toStringAsFixed(1)} - ${_getScoreLabel(average)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
                        onSelected: (value) {
                          if (value == 'edit') onEdit();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 20),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 20, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Excluir', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Scores grid
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: AssessmentCategory.values.map((category) {
                  final score = assessment.getScoreForCategory(category) ?? 0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.star, size: 12, color: _getScoreColor(score.toDouble())),
                      const SizedBox(width: 4),
                      Text(
                        '${category.label}: $score',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),

              // Notes
              if (assessment.notes != null && assessment.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '"${assessment.notes}"',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab with Badge Widget
class _TabWithBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _TabWithBadge({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
