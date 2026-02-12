import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../models/user.dart';
import '../../providers/providers.dart';
import '../../widgets/common/belt_badge.dart';
import '../../widgets/common/profile_photo_picker.dart';

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

        final attendanceCountAsync = ref.watch(studentAttendanceCountProvider(student.id));
        final plansAsync = ref.watch(studentPlansProvider(student.id));
        final startDate = student.jiujitsuStartDate ?? student.startDate;
        final trainingTime = _formatTrainingTime(startDate);

        return RefreshIndicator(
          onRefresh: () async {
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
                  onEdit: () => _showEditPersonalDataSheet(context, ref, student),
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
                        label: 'Plano${(plansAsync.valueOrNull ?? []).length > 1 ? 's' : ''}',
                        value: (plansAsync.valueOrNull ?? []).map((p) => p.name).join(', '),
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
                      onTap: () => _showEditPersonalDataSheet(context, ref, student),
                    ),
                    _DataTile(
                      icon: LucideIcons.mapPin,
                      title: 'Endereco',
                      subtitle: _getAddressSummary(student),
                      isSubtitleEmpty: student.address == null || !_hasAddress(student.address!),
                      onTap: () => _showEditAddressSheet(context, ref, student),
                    ),
                    _DataTile(
                      icon: LucideIcons.heartPulse,
                      title: 'Saude e Emergencia',
                      subtitle: _getHealthEmergencySummary(student),
                      isSubtitleEmpty: _isHealthDataEmpty(student) && student.emergencyContact == null,
                      onTap: () => _showEditHealthAndEmergencySheet(context, ref, student),
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
                  onChanged: (value) => _updatePrivacy(context, ref, student, value),
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
    if (student.phone != null && student.phone!.isNotEmpty) parts.add(student.phone!);
    if (student.email != null && student.email!.isNotEmpty) parts.add(student.email!);
    if (student.nickname != null && student.nickname!.isNotEmpty) parts.add(student.nickname!);
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
    if (student.emergencyContact != null && student.emergencyContact!.name.isNotEmpty) {
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
        context.showSuccess(value ? 'Perfil agora e publico' : 'Perfil agora e privado');
      }
    } catch (e) {
      if (context.mounted) {
        context.showError('Erro ao atualizar: $e');
      }
    }
  }

  void _showEditPersonalDataSheet(BuildContext context, WidgetRef ref, Student student) {
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

  void _showEditAddressSheet(BuildContext context, WidgetRef ref, Student student) {
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

  void _showEditHealthAndEmergencySheet(BuildContext context, WidgetRef ref, Student student) {
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
        children: [
          const SizedBox(height: 16),
          // Avatar shimmer
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 12),
          // Name shimmer
          Container(
            height: 20,
            width: 160,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 8),
          // Belt shimmer
          Container(
            height: 28,
            width: 140,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 20),
          // Stats shimmer
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Card shimmer
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
        // Belt Badge
        BeltBadge(
          belt: student.currentBelt,
          stripes: student.currentStripes,
          size: BeltSize.large,
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
              style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
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
                style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
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
                    style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.labelSmall.copyWith(
                      color: isSubtitleEmpty ? AppTheme.textDisabled : AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Trailing chevron
            Icon(LucideIcons.chevronRight, size: 16, color: AppTheme.textSecondary),
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
                  Icon(LucideIcons.pencil, size: 12, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Editar',
                    style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
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

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

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
                  style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  'Outros alunos podem ver seu perfil',
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
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
    _phoneController = TextEditingController(text: widget.student.phone);
    _emailController = TextEditingController(text: widget.student.email);
    _cpfController = TextEditingController(text: widget.student.cpf);
    _rgController = TextEditingController(text: widget.student.rg);
    _weightController = TextEditingController(text: widget.student.weight?.toString());
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
        'nickname': _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'cpf': _cpfController.text.trim().isEmpty ? null : _cpfController.text.trim(),
        'rg': _rgController.text.trim().isEmpty ? null : _rgController.text.trim(),
        'weight': _weightController.text.trim().isEmpty ? null : double.tryParse(_weightController.text.trim()),
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
        _SheetTextField(label: 'Apelido', controller: _nicknameController, hint: 'Como gostaria de ser chamado'),
        _SheetDateField(
          label: 'Data de nascimento',
          value: _birthDate,
          onChanged: (d) => setState(() => _birthDate = d),
        ),
        _SheetTextField(label: 'Telefone', controller: _phoneController, hint: '(00) 00000-0000', keyboardType: TextInputType.phone),
        _SheetTextField(label: 'Email', controller: _emailController, hint: 'seu@email.com', keyboardType: TextInputType.emailAddress),
        _SheetTextField(label: 'CPF', controller: _cpfController, hint: '000.000.000-00', keyboardType: TextInputType.number),
        _SheetTextField(label: 'RG', controller: _rgController, hint: 'Numero do RG'),
        _SheetTextField(label: 'Peso (kg)', controller: _weightController, hint: 'Ex: 75.5', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
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
    _neighborhoodController = TextEditingController(text: address?.neighborhood);
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
      final hasData = _streetController.text.trim().isNotEmpty || _cityController.text.trim().isNotEmpty;
      await widget.onSave({
        'address': hasData
            ? {
                'zipCode': _zipCodeController.text.trim(),
                'street': _streetController.text.trim(),
                'number': _numberController.text.trim(),
                'complement': _complementController.text.trim().isEmpty ? null : _complementController.text.trim(),
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
        _SheetTextField(label: 'CEP', controller: _zipCodeController, hint: '00000-000', keyboardType: TextInputType.number),
        _SheetTextField(label: 'Rua', controller: _streetController, hint: 'Nome da rua'),
        _SheetTextField(label: 'Numero', controller: _numberController, hint: '123', keyboardType: TextInputType.number),
        _SheetTextField(label: 'Complemento', controller: _complementController, hint: 'Apto, bloco...'),
        _SheetTextField(label: 'Bairro', controller: _neighborhoodController, hint: 'Nome do bairro'),
        _SheetTextField(label: 'Cidade', controller: _cityController, hint: 'Nome da cidade'),
        _SheetTextField(label: 'Estado', controller: _stateController, hint: 'UF'),
      ],
    );
  }
}

/// Combined Edit Health & Emergency Contact Sheet
class _EditHealthAndEmergencySheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditHealthAndEmergencySheet({required this.student, required this.onSave});

  @override
  State<_EditHealthAndEmergencySheet> createState() => _EditHealthAndEmergencySheetState();
}

class _EditHealthAndEmergencySheetState extends State<_EditHealthAndEmergencySheet> {
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
    _bloodTypeController = TextEditingController(text: widget.student.bloodType);
    _allergiesController = TextEditingController(text: widget.student.allergies?.join(', '));
    _healthNotesController = TextEditingController(text: widget.student.healthNotes);
    _emergencyNameController = TextEditingController(text: widget.student.emergencyContact?.name);
    _emergencyPhoneController = TextEditingController(text: widget.student.emergencyContact?.phone);
    _emergencyRelationshipController = TextEditingController(text: widget.student.emergencyContact?.relationship);
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
      final hasEmergencyData = _emergencyNameController.text.trim().isNotEmpty ||
          _emergencyPhoneController.text.trim().isNotEmpty;

      await widget.onSave({
        'bloodType': _bloodTypeController.text.trim().isEmpty ? null : _bloodTypeController.text.trim(),
        'allergies': allergiesText.isEmpty
            ? null
            : allergiesText.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList(),
        'healthNotes': _healthNotesController.text.trim().isEmpty ? null : _healthNotesController.text.trim(),
        'emergencyContact': hasEmergencyData
            ? {
                'name': _emergencyNameController.text.trim(),
                'phone': _emergencyPhoneController.text.trim(),
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
        _SheetTextField(label: 'Tipo sanguineo', controller: _bloodTypeController, hint: 'Ex: A+, O-, AB+'),
        _SheetTextField(label: 'Alergias', controller: _allergiesController, hint: 'Separe por virgula'),
        _SheetTextField(label: 'Observacoes', controller: _healthNotesController, hint: 'Lesoes, medicamentos...', maxLines: 3),
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
        _SheetTextField(label: 'Nome', controller: _emergencyNameController, hint: 'Nome do contato'),
        _SheetTextField(label: 'Telefone', controller: _emergencyPhoneController, hint: '(00) 00000-0000', keyboardType: TextInputType.phone),
        _SheetTextField(label: 'Parentesco', controller: _emergencyRelationshipController, hint: 'Ex: Mae, Pai, Conjuge'),
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
                    child: Text(title, style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600)),
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
                  child: ElevatedButton(
                    onPressed: isSaving ? null : onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w600)),
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

  const _SheetTextField({
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: AppTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textDisabled),
              filled: true,
              fillColor: AppTheme.surfaceVariant.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          Text(label, style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now().subtract(const Duration(days: 365 * 20)),
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
                      value != null ? DateFormat('dd/MM/yyyy').format(value!) : 'Selecionar data',
                      style: AppTheme.bodyMedium.copyWith(
                        color: value != null ? AppTheme.textPrimary : AppTheme.textDisabled,
                      ),
                    ),
                  ),
                  Icon(LucideIcons.calendar, size: 18, color: AppTheme.textSecondary),
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
              onEdit: hasMultiple ? () => context.push('/portal/academias') : null,
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
                          ? () => ref.read(selectedAcademyProvider.notifier).selectAcademy(academies[i].id)
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.settings, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Gerenciar academias',
                        style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 4),
                      const Icon(LucideIcons.chevronRight, size: 14, color: AppTheme.textSecondary),
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
                  ? Image.network(
                      academy.logoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildDefaultLogo(),
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
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
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
                onTap: () => _showDeleteAccountDialog(context, ref),
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

  Future<void> _showDeleteAccountDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir conta'),
        content: const Text(
          'Tem certeza que deseja excluir sua conta? Esta acao nao pode ser desfeita.\n\n'
          'Todos os seus dados serao removidos permanentemente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // Show second confirmation
      final finalConfirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmacao final'),
          content: const Text(
            'Esta e sua ultima chance. Todos os dados serao perdidos:\n\n'
            '- Historico de treinos\n'
            '- Graduacoes\n'
            '- Resultados de competicoes\n'
            '- Dados pessoais\n\n'
            'Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              child: const Text('Excluir permanentemente'),
            ),
          ],
        ),
      );

      if (finalConfirm == true && context.mounted) {
        await _deleteAccount(context, ref);
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final authService = ref.read(authServiceProvider);
      await authService.deleteAccount();
      // User will be automatically redirected to login by auth state change
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Remove loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
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
              color: isDestructive ? AppTheme.error.withValues(alpha: 0.5) : AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
