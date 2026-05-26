import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/feedback_utils.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../models/user.dart';
import '../../providers/providers.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/delete_account_helper.dart';
import '../../widgets/common/grade_display.dart';
import '../../widgets/common/profile_photo_picker.dart';
import '../../widgets/loading_button.dart';
import '../../widgets/skeletons/skeletons.dart';

/// Profile Screen - Redesigned with hero header, stats, and collapsed sections
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildEmptyState();
        }

        final attendanceCountAsync = ref.watch(
          studentAttendanceCountProvider(student.id),
        );
        final plansAsync = ref.watch(studentPlansProvider(student.id));
        final startDate = student.jiujitsuStartDate ?? student.startDate;
        final trainingTime = _formatTrainingTime(startDate);

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            ref.invalidate(currentStudentProvider);
            ref.invalidate(studentAttendanceCountProvider(student.id));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Hero Header
                _HeroHeader(student: student),

                const SizedBox(height: 20),

                // Stats Row
                Row(
                  children: [
                    _StatCard(
                      icon: LucideIcons.clipboardCheck,
                      value: '${attendanceCountAsync.valueOrNull ?? 0}',
                      label: 'presencas',
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      icon: LucideIcons.calendar,
                      value: trainingTime,
                      label: 'de treino',
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Quick Actions
                _QuickActions(
                  onTimeline: () => context.go('/portal/linha-do-tempo'),
                  onEdit: () =>
                      _showEditPersonalDataSheet(context, ref, student),
                ),

                const SizedBox(height: 24),

                // Academy-managed section
                Align(
                  alignment: Alignment.centerLeft,
                  child: _SectionHeader(title: 'GERENCIADO PELA ACADEMIA'),
                ),
                const SizedBox(height: 8),
                _InfoCard(
                  children: [
                    _InfoRow(
                      label: 'Inicio',
                      value: DateFormat('dd/MM/yyyy').format(student.startDate),
                    ),
                    _InfoRow(
                      label: 'Status',
                      value: student.status.label,
                      valueColor: AppTheme.getStatusColor(student.status.value),
                    ),
                    if ((plansAsync.valueOrNull ?? []).isNotEmpty)
                      _InfoRow(
                        label:
                            'Plano${(plansAsync.valueOrNull ?? []).length > 1 ? 's' : ''}',
                        value: (plansAsync.valueOrNull ?? [])
                            .map((p) => p.name)
                            .join(', '),
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // My Data section
                Align(
                  alignment: Alignment.centerLeft,
                  child: _SectionHeader(title: 'MEUS DADOS'),
                ),
                const SizedBox(height: 8),
                _InfoCard(
                  children: [
                    _DataTile(
                      icon: LucideIcons.user,
                      title: 'Dados Pessoais',
                      subtitle: _getPersonalDataSummary(student),
                      isSubtitleEmpty: _isPersonalDataEmpty(student),
                      onTap: () =>
                          _showEditPersonalDataSheet(context, ref, student),
                    ),
                    _DataTile(
                      icon: LucideIcons.mapPin,
                      title: 'Endereco',
                      subtitle: _getAddressSummary(student),
                      isSubtitleEmpty:
                          student.address == null ||
                          !_hasAddress(student.address!),
                      onTap: () => _showEditAddressSheet(context, ref, student),
                    ),
                    _DataTile(
                      icon: LucideIcons.heartPulse,
                      title: 'Saude e Emergencia',
                      subtitle: _getHealthEmergencySummary(student),
                      isSubtitleEmpty:
                          _isHealthDataEmpty(student) &&
                          student.emergencyContact == null,
                      onTap: () => _showEditHealthAndEmergencySheet(
                        context,
                        ref,
                        student,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Preferences
                Align(
                  alignment: Alignment.centerLeft,
                  child: _SectionHeader(title: 'PREFERENCIAS'),
                ),
                const SizedBox(height: 8),
                _PrivacyToggle(
                  value: student.isProfilePublic,
                  onChanged: (value) =>
                      _updatePrivacy(context, ref, student, value),
                ),

                const SizedBox(height: 24),

                // Academies
                _AcademiesSection(),

                const SizedBox(height: 24),

                // Account
                _AccountSection(),

                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
      loading: () => _buildLoadingState(),
      error: (_, __) => _buildEmptyState(),
    );
  }

  // ============================================
  // HELPERS
  // ============================================

  String _formatTrainingTime(DateTime startDate) {
    final now = DateTime.now();
    final difference = now.difference(startDate);
    final months = difference.inDays ~/ 30;

    if (months >= 12) {
      final years = months ~/ 12;
      final remainingMonths = months % 12;
      if (remainingMonths > 0) {
        return '${years}a ${remainingMonths}m';
      }
      return '$years ano${years > 1 ? 's' : ''}';
    } else if (months > 0) {
      return '$months mes${months > 1 ? 'es' : ''}';
    } else {
      final days = difference.inDays;
      return '$days dia${days != 1 ? 's' : ''}';
    }
  }

  String _getPersonalDataSummary(Student student) {
    final parts = <String>[];
    if (student.phone != null && student.phone!.isNotEmpty)
      parts.add(formatPhone(student.phone));
    if (student.email != null && student.email!.isNotEmpty)
      parts.add(student.email!);
    if (student.nickname != null && student.nickname!.isNotEmpty)
      parts.add(student.nickname!);
    if (parts.isEmpty) return 'Nenhum dado';
    return parts.join(', ');
  }

  String _getAddressSummary(Student student) {
    if (student.address == null || !_hasAddress(student.address!)) {
      return 'Nenhum endereco cadastrado';
    }
    final city = student.address!.city;
    final state = student.address!.state;
    if (city.isNotEmpty && state.isNotEmpty) {
      return '$city - $state';
    }
    if (city.isNotEmpty) return city;
    return student.address!.street;
  }

  String _getHealthEmergencySummary(Student student) {
    final parts = <String>[];
    if (student.bloodType != null && student.bloodType!.isNotEmpty) {
      parts.add('Tipo ${student.bloodType}');
    }
    if (student.emergencyContact != null &&
        student.emergencyContact!.name.isNotEmpty) {
      parts.add(student.emergencyContact!.name);
    }
    if (parts.isEmpty) return 'Nenhum dado';
    return parts.join(', ');
  }

  bool _isPersonalDataEmpty(Student student) {
    return (student.nickname == null || student.nickname!.isEmpty) &&
        student.birthDate == null &&
        (student.phone == null || student.phone!.isEmpty) &&
        (student.email == null || student.email!.isEmpty) &&
        (student.cpf == null || student.cpf!.isEmpty) &&
        (student.rg == null || student.rg!.isEmpty) &&
        student.weight == null;
  }

  bool _isHealthDataEmpty(Student student) {
    return (student.bloodType == null || student.bloodType!.isEmpty) &&
        (student.allergies == null || student.allergies!.isEmpty) &&
        (student.healthNotes == null || student.healthNotes!.isEmpty);
  }

  bool _hasAddress(Address address) {
    return address.street.isNotEmpty || address.city.isNotEmpty;
  }

  // ============================================
  // ACTIONS
  // ============================================

  Future<void> _updatePrivacy(
    BuildContext context,
    WidgetRef ref,
    Student student,
    bool value,
  ) async {
    try {
      final studentService = ref.read(studentServiceProvider);
      if (studentService == null) return;

      await studentService.update(student.id, {'isProfilePublic': value});
      ref.invalidate(currentStudentProvider);

      if (context.mounted) {
        context.showSuccess(
          value ? 'Perfil agora e publico' : 'Perfil agora e privado',
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showError('Erro ao atualizar: $e');
      }
    }
  }

  void _showEditPersonalDataSheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditPersonalDataSheet(
        student: student,
        onSave: (data) async {
          final studentService = ref.read(studentServiceProvider);
          if (studentService == null) return;
          await studentService.update(student.id, data);
          ref.invalidate(currentStudentProvider);
        },
      ),
    );
  }

  void _showEditAddressSheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditAddressSheet(
        student: student,
        onSave: (data) async {
          final studentService = ref.read(studentServiceProvider);
          if (studentService == null) return;
          await studentService.update(student.id, data);
          ref.invalidate(currentStudentProvider);
        },
      ),
    );
  }

  void _showEditHealthAndEmergencySheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditHealthAndEmergencySheet(
        student: student,
        onSave: (data) async {
          final studentService = ref.read(studentServiceProvider);
          if (studentService == null) return;
          await studentService.update(student.id, data);
          ref.invalidate(currentStudentProvider);
        },
      ),
    );
  }

  // ============================================
  // LOADING & EMPTY STATES
  // ============================================

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: const [
          SizedBox(height: 16),
          // Avatar shimmer
          SkeletonAvatar(size: 88),
          SizedBox(height: 20),
          // Stats shimmer
          SkeletonStats(count: 2, height: 80),
          SizedBox(height: 24),
          // Card shimmer
          SkeletonCard(
            height: 150,
            showAvatar: false,
            padding: EdgeInsets.all(16),
          ),
          SizedBox(height: 12),
          SkeletonCard(height: 80, showAvatar: true),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          Icon(LucideIcons.userX, size: 48, color: AppTheme.textDisabled),
          const SizedBox(height: 16),
          Text(
            'Perfil nao encontrado',
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Sua conta nao esta vinculada a um aluno',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // Account section always visible for account deletion
          _AccountSection(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ============================================
// NEW WIDGETS
// ============================================

/// Hero Header — Centered avatar, name, belt, status
class _HeroHeader extends ConsumerWidget {
  final Student student;

  const _HeroHeader({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final academyId = ref.watch(selectedAcademyIdProvider);

    return Column(
      children: [
        // Avatar
        ProfilePhotoPicker(
          academyId: academyId ?? '',
          studentId: student.id,
          photoUrl: student.photoUrl,
          fullName: student.fullName,
          currentBelt: student.currentBelt,
          editable: true,
          size: 88.0,
          onPhotoUpdated: () {
            ref.invalidate(currentStudentProvider);
          },
        ),
        const SizedBox(height: 12),
        // Name
        Text(
          student.fullName,
          style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        // Grade Display (sport-aware)
        GradeDisplay(
          sportId: student.getPrimarySport(),
          grade: student.currentBelt,
          stripes: student.currentStripes,
          size: GradeDisplaySize.large,
          showLabel: true,
        ),
        const SizedBox(height: 8),
        // Status Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.getStatusBackgroundColor(student.status.value),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            student.status.label,
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.getStatusColor(student.status.value),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Stat Card — Shows a single statistic
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTheme.headlineMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick Actions — Timeline + Edit profile chips
class _QuickActions extends StatelessWidget {
  final VoidCallback onTimeline;
  final VoidCallback onEdit;

  const _QuickActions({required this.onTimeline, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionChip(
            icon: LucideIcons.history,
            label: 'Linha do tempo',
            onTap: onTimeline,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionChip(
            icon: LucideIcons.pencil,
            label: 'Editar perfil',
            onTap: onEdit,
          ),
        ),
      ],
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Data Tile — Navigable collapsed tile for "Meus Dados" section
class _DataTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSubtitleEmpty;
  final VoidCallback onTap;

  const _DataTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSubtitleEmpty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Leading icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 12),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.labelSmall.copyWith(
                      color: isSubtitleEmpty
                          ? AppTheme.textDisabled
                          : AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Trailing chevron
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// KEPT WIDGETS (unchanged)
// ============================================

/// Section Header with optional edit button
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onEdit;

  const _SectionHeader({required this.title, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        if (onEdit != null)
          GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.pencil,
                    size: 12,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Editar',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Info Card container
class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final filteredChildren = children.where((c) => c is! SizedBox).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          for (int i = 0; i < filteredChildren.length; i++) ...[
            filteredChildren[i],
            if (i < filteredChildren.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

/// Info Row
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: AppTheme.bodyMedium.copyWith(
                color: valueColor ?? AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Privacy Toggle
class _PrivacyToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrivacyToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              value ? LucideIcons.eye : LucideIcons.eyeOff,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Perfil publico',
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Outros alunos podem ver seu perfil',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

// ============================================
// EDIT SHEETS
// ============================================

/// Edit Personal Data Sheet
class _EditPersonalDataSheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditPersonalDataSheet({required this.student, required this.onSave});

  @override
  State<_EditPersonalDataSheet> createState() => _EditPersonalDataSheetState();
}

class _EditPersonalDataSheetState extends State<_EditPersonalDataSheet> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _cpfController;
  late final TextEditingController _rgController;
  late final TextEditingController _weightController;
  DateTime? _birthDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.student.nickname);
    _phoneController =
        TextEditingController(text: formatPhone(widget.student.phone));
    _emailController = TextEditingController(text: widget.student.email);
    _cpfController =
        TextEditingController(text: formatCpfCnpj(widget.student.cpf));
    _rgController = TextEditingController(text: widget.student.rg);
    _weightController = TextEditingController(
      text: widget.student.weight?.toString(),
    );
    _birthDate = widget.student.birthDate;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _rgController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.onSave({
        'nickname': _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : onlyDigits(_phoneController.text),
        'email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'cpf': _cpfController.text.trim().isEmpty
            ? null
            : onlyDigits(_cpfController.text),
        'rg': _rgController.text.trim().isEmpty
            ? null
            : _rgController.text.trim(),
        'weight': _weightController.text.trim().isEmpty
            ? null
            : double.tryParse(_weightController.text.trim()),
        'birthDate': _birthDate,
      });
      if (mounted) {
        context.showSuccess('Dados atualizados!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheet(
      title: 'Dados Pessoais',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        _SheetTextField(
          label: 'Apelido',
          controller: _nicknameController,
          hint: 'Como gostaria de ser chamado',
        ),
        _SheetDateField(
          label: 'Data de nascimento',
          value: _birthDate,
          onChanged: (d) => setState(() => _birthDate = d),
        ),
        _SheetTextField(
          label: 'Telefone',
          controller: _phoneController,
          hint: '(00) 00000-0000',
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneInputFormatter()],
        ),
        _SheetTextField(
          label: 'Email',
          controller: _emailController,
          hint: 'seu@email.com',
          keyboardType: TextInputType.emailAddress,
        ),
        _SheetTextField(
          label: 'CPF',
          controller: _cpfController,
          hint: '000.000.000-00',
          keyboardType: TextInputType.number,
          inputFormatters: [CpfCnpjInputFormatter()],
        ),
        _SheetTextField(
          label: 'RG',
          controller: _rgController,
          hint: 'Numero do RG',
        ),
        _SheetTextField(
          label: 'Peso (kg)',
          controller: _weightController,
          hint: 'Ex: 75.5',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
  }
}

/// Edit Address Sheet
class _EditAddressSheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditAddressSheet({required this.student, required this.onSave});

  @override
  State<_EditAddressSheet> createState() => _EditAddressSheetState();
}

class _EditAddressSheetState extends State<_EditAddressSheet> {
  late final TextEditingController _zipCodeController;
  late final TextEditingController _streetController;
  late final TextEditingController _numberController;
  late final TextEditingController _complementController;
  late final TextEditingController _neighborhoodController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final address = widget.student.address;
    _zipCodeController = TextEditingController(text: address?.zipCode);
    _streetController = TextEditingController(text: address?.street);
    _numberController = TextEditingController(text: address?.number);
    _complementController = TextEditingController(text: address?.complement);
    _neighborhoodController = TextEditingController(
      text: address?.neighborhood,
    );
    _cityController = TextEditingController(text: address?.city);
    _stateController = TextEditingController(text: address?.state);
  }

  @override
  void dispose() {
    _zipCodeController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final hasData =
          _streetController.text.trim().isNotEmpty ||
          _cityController.text.trim().isNotEmpty;
      await widget.onSave({
        'address': hasData
            ? {
                'zipCode': _zipCodeController.text.trim(),
                'street': _streetController.text.trim(),
                'number': _numberController.text.trim(),
                'complement': _complementController.text.trim().isEmpty
                    ? null
                    : _complementController.text.trim(),
                'neighborhood': _neighborhoodController.text.trim(),
                'city': _cityController.text.trim(),
                'state': _stateController.text.trim(),
              }
            : null,
      });
      if (mounted) {
        context.showSuccess('Endereco atualizado!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheet(
      title: 'Endereco',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        _SheetTextField(
          label: 'CEP',
          controller: _zipCodeController,
          hint: '00000-000',
          keyboardType: TextInputType.number,
        ),
        _SheetTextField(
          label: 'Rua',
          controller: _streetController,
          hint: 'Nome da rua',
        ),
        _SheetTextField(
          label: 'Numero',
          controller: _numberController,
          hint: '123',
          keyboardType: TextInputType.number,
        ),
        _SheetTextField(
          label: 'Complemento',
          controller: _complementController,
          hint: 'Apto, bloco...',
        ),
        _SheetTextField(
          label: 'Bairro',
          controller: _neighborhoodController,
          hint: 'Nome do bairro',
        ),
        _SheetTextField(
          label: 'Cidade',
          controller: _cityController,
          hint: 'Nome da cidade',
        ),
        _SheetTextField(
          label: 'Estado',
          controller: _stateController,
          hint: 'UF',
        ),
      ],
    );
  }
}

/// Combined Edit Health & Emergency Contact Sheet
class _EditHealthAndEmergencySheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditHealthAndEmergencySheet({
    required this.student,
    required this.onSave,
  });

  @override
  State<_EditHealthAndEmergencySheet> createState() =>
      _EditHealthAndEmergencySheetState();
}

class _EditHealthAndEmergencySheetState
    extends State<_EditHealthAndEmergencySheet> {
  // Health controllers
  late final TextEditingController _bloodTypeController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _healthNotesController;
  // Emergency controllers
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyPhoneController;
  late final TextEditingController _emergencyRelationshipController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _bloodTypeController = TextEditingController(
      text: widget.student.bloodType,
    );
    _allergiesController = TextEditingController(
      text: widget.student.allergies?.join(', '),
    );
    _healthNotesController = TextEditingController(
      text: widget.student.healthNotes,
    );
    _emergencyNameController = TextEditingController(
      text: widget.student.emergencyContact?.name,
    );
    _emergencyPhoneController = TextEditingController(
      text: formatPhone(widget.student.emergencyContact?.phone),
    );
    _emergencyRelationshipController = TextEditingController(
      text: widget.student.emergencyContact?.relationship,
    );
  }

  @override
  void dispose() {
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _healthNotesController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyRelationshipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final allergiesText = _allergiesController.text.trim();
      final hasEmergencyData =
          _emergencyNameController.text.trim().isNotEmpty ||
          _emergencyPhoneController.text.trim().isNotEmpty;

      await widget.onSave({
        'bloodType': _bloodTypeController.text.trim().isEmpty
            ? null
            : _bloodTypeController.text.trim(),
        'allergies': allergiesText.isEmpty
            ? null
            : allergiesText
                  .split(',')
                  .map((a) => a.trim())
                  .where((a) => a.isNotEmpty)
                  .toList(),
        'healthNotes': _healthNotesController.text.trim().isEmpty
            ? null
            : _healthNotesController.text.trim(),
        'emergencyContact': hasEmergencyData
            ? {
                'name': _emergencyNameController.text.trim(),
                'phone': onlyDigits(_emergencyPhoneController.text),
                'relationship': _emergencyRelationshipController.text.trim(),
              }
            : null,
      });
      if (mounted) {
        context.showSuccess('Dados atualizados!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheet(
      title: 'Saude e Emergencia',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        // Health section label
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'SAUDE',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _SheetTextField(
          label: 'Tipo sanguineo',
          controller: _bloodTypeController,
          hint: 'Ex: A+, O-, AB+',
        ),
        _SheetTextField(
          label: 'Alergias',
          controller: _allergiesController,
          hint: 'Separe por virgula',
        ),
        _SheetTextField(
          label: 'Observacoes',
          controller: _healthNotesController,
          hint: 'Lesoes, medicamentos...',
          maxLines: 3,
        ),
        // Emergency section label
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Text(
            'CONTATO DE EMERGENCIA',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _SheetTextField(
          label: 'Nome',
          controller: _emergencyNameController,
          hint: 'Nome do contato',
        ),
        _SheetTextField(
          label: 'Telefone',
          controller: _emergencyPhoneController,
          hint: '(00) 00000-0000',
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneInputFormatter()],
        ),
        _SheetTextField(
          label: 'Parentesco',
          controller: _emergencyRelationshipController,
          hint: 'Ex: Mae, Pai, Conjuge',
        ),
      ],
    );
  }
}

// ============================================
// SHARED SHEET COMPONENTS
// ============================================

/// Base Edit Sheet
class _EditSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isSaving;
  final VoidCallback onSave;

  const _EditSheet({
    required this.title,
    required this.children,
    required this.isSaving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTheme.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
            // Save Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: LoadingButton(
                    isLoading: isSaving,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onSave();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Salvar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet Text Field
class _SheetTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _SheetTextField({
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: AppTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textDisabled,
              ),
              filled: true,
              fillColor: AppTheme.surfaceVariant.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet Date Field
class _SheetDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _SheetDateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    value ??
                    DateTime.now().subtract(const Duration(days: 365 * 20)),
                firstDate: DateTime(1940),
                lastDate: DateTime.now(),
              );
              if (picked != null) onChanged(picked);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value != null
                          ? DateFormat('dd/MM/yyyy').format(value!)
                          : 'Selecionar data',
                      style: AppTheme.bodyMedium.copyWith(
                        color: value != null
                            ? AppTheme.textPrimary
                            : AppTheme.textDisabled,
                      ),
                    ),
                  ),
                  Icon(
                    LucideIcons.calendar,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// ACADEMIES SECTION (Multi-Academy Support)
// ============================================

/// Academies Section - Shows linked academies for multi-academy users
class _AcademiesSection extends ConsumerWidget {
  const _AcademiesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);
    final academiesAsync = ref.watch(userAcademiesInfoProvider);
    final selectedId = ref.watch(selectedAcademyIdProvider);
    final mapping = ref.watch(userAcademyMappingProvider).valueOrNull;
    final primaryId = mapping?.primaryAcademyId;

    // Only show section if user has academies (show even for single academy)
    return academiesAsync.when(
      data: (academies) {
        if (academies.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'MINHAS ACADEMIAS',
              onEdit: hasMultiple
                  ? () => context.push('/portal/academias')
                  : null,
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < academies.length; i++) ...[
                    _AcademyTile(
                      academy: academies[i],
                      isSelected: academies[i].id == selectedId,
                      isPrimary: academies[i].id == primaryId,
                      onTap: hasMultiple
                          ? () => ref
                                .read(selectedAcademyProvider.notifier)
                                .selectAcademy(academies[i].id)
                          : null,
                    ),
                    if (i < academies.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
            if (hasMultiple) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => context.push('/portal/academias'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.settings,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Gerenciar academias',
                        style: AppTheme.labelMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Academy Tile for the academies list
class _AcademyTile extends StatelessWidget {
  final AcademyInfo academy;
  final bool isSelected;
  final bool isPrimary;
  final VoidCallback? onTap;

  const _AcademyTile({
    required this.academy,
    required this.isSelected,
    required this.isPrimary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Logo
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: academy.logoUrl == null ? AppTheme.primary : null,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: academy.logoUrl != null
                  ? AppCachedImage(
                      imageUrl: academy.logoUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorIcon: _buildDefaultLogo(),
                    )
                  : _buildDefaultLogo(),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          academy.name,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Principal',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    academy.role.label,
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Selected indicator
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  LucideIcons.check,
                  size: 14,
                  color: AppTheme.success,
                ),
              )
            else if (onTap != null)
              const Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: AppTheme.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          academy.name.isNotEmpty ? academy.name[0].toUpperCase() : 'A',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Account section with delete account option
class _AccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONTA',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: [
              // Change password
              _AccountTile(
                icon: LucideIcons.lock,
                title: 'Trocar senha',
                onTap: () => _showChangePasswordDialog(context, ref),
              ),
              const Divider(height: 1),
              // Redeem instructor code (for users invited as instructor in
              // another academy — they enter the 8-char code here)
              _AccountTile(
                icon: LucideIcons.key,
                title: 'Resgatar código de equipe',
                onTap: () => context.push('/codigo-equipe'),
              ),
              const Divider(height: 1),
              // Legal links
              _AccountTile(
                icon: LucideIcons.fileText,
                title: 'Termos de Uso',
                onTap: () => _openUrl(AppConstants.termsOfServiceUrl),
              ),
              const Divider(height: 1),
              _AccountTile(
                icon: LucideIcons.shield,
                title: 'Politica de Privacidade',
                onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
              ),
              const Divider(height: 1),
              // Delete account
              _AccountTile(
                icon: LucideIcons.trash2,
                title: 'Excluir minha conta',
                isDestructive: true,
                onTap: () => DeleteAccountHelper.showConfirmation(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        onSubmit: (current, next) async {
          final authService = ref.read(authServiceProvider);
          await authService.updatePassword(
            currentPassword: current,
            newPassword: next,
          );
        },
      ),
    );
  }
}

/// Dialog that asks for current password + new password + confirmation, then
/// triggers reauth + update. Validates new password length and confirmation
/// match client-side; Firebase errors (`wrong-password`,
/// `requires-recent-login`, etc.) are surfaced inline.
class _ChangePasswordDialog extends StatefulWidget {
  final Future<void> Function(String currentPassword, String newPassword)
  onSubmit;

  const _ChangePasswordDialog({required this.onSubmit});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _saving = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cur = _currentController.text;
    final next = _newController.text;
    final conf = _confirmController.text;

    if (cur.isEmpty) {
      setState(() => _error = 'Informe sua senha atual.');
      return;
    }
    if (next.length < 6) {
      setState(
        () => _error = 'A nova senha precisa ter pelo menos 6 caracteres.',
      );
      return;
    }
    if (next != conf) {
      setState(() => _error = 'A confirmacao nao bate com a nova senha.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(cur, next);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _success = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _mapError(e);
      });
    }
  }

  String _mapError(Object e) {
    final s = e.toString();
    if (s.contains('wrong-password') || s.contains('invalid-credential')) {
      return 'Senha atual incorreta.';
    }
    if (s.contains('requires-recent-login')) {
      return 'Por seguranca, saia e entre novamente antes de trocar a senha.';
    }
    if (s.contains('weak-password')) {
      return 'Senha muito fraca. Use ao menos 6 caracteres.';
    }
    return 'Erro ao trocar a senha. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_success ? 'Senha atualizada' : 'Trocar senha'),
      content: _success
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.checkCircle,
                  color: AppTheme.success,
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  'Sua senha foi alterada com sucesso.',
                  style: AppTheme.bodyMedium,
                ),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _currentController,
                    obscureText: !_showCurrent,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: 'Senha atual',
                      prefixIcon: const Icon(LucideIcons.lock, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showCurrent ? LucideIcons.eyeOff : LucideIcons.eye,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _showCurrent = !_showCurrent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newController,
                    obscureText: !_showNew,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: 'Nova senha',
                      prefixIcon: const Icon(LucideIcons.key, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showNew ? LucideIcons.eyeOff : LucideIcons.eye,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _showNew = !_showNew),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: !_showNew,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar nova senha',
                      prefixIcon: Icon(LucideIcons.key, size: 18),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: _success
          ? [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('Salvar'),
              ),
            ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  const _AccountTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppTheme.error : AppTheme.textPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: AppTheme.bodyMedium.copyWith(color: color),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: isDestructive
                  ? AppTheme.error.withValues(alpha: 0.5)
                  : AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
