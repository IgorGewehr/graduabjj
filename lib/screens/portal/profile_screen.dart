import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../widgets/common/belt_badge.dart';

/// Belt labels for display
const Map<String, String> _beltLabels = {
  'white': 'Branca',
  'blue': 'Azul',
  'purple': 'Roxa',
  'brown': 'Marrom',
  'black': 'Preta',
  'grey': 'Cinza',
  'grey-white': 'Cinza/Branca',
  'grey-black': 'Cinza/Preta',
  'yellow': 'Amarela',
  'yellow-white': 'Amarela/Branca',
  'yellow-black': 'Amarela/Preta',
  'orange': 'Laranja',
  'orange-white': 'Laranja/Branca',
  'orange-black': 'Laranja/Preta',
  'green': 'Verde',
  'green-white': 'Verde/Branca',
  'green-black': 'Verde/Preta',
};

/// Profile Screen - Clean read-only view with edit via bottom sheet
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
        final planAsync = student.planId != null
            ? ref.watch(planByIdProvider(student.planId!))
            : const AsyncValue<dynamic>.data(null);

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(currentStudentProvider);
            ref.invalidate(studentAttendanceCountProvider(student.id));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline Link
                _TimelineLink(
                  onTap: () => context.go('/portal/linha-do-tempo'),
                ),

                const SizedBox(height: 16),

                // Section title
                Text(
                  'Meu Perfil',
                  style: AppTheme.titleLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 12),

                // Profile Card
                _ProfileCard(
                  student: student,
                  attendanceCount: attendanceCountAsync.valueOrNull ?? 0,
                ),

                const SizedBox(height: 24),

                // Academy Info (read-only)
                _SectionHeader(title: 'GERENCIADO PELA ACADEMIA'),
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
                    if (planAsync.valueOrNull != null)
                      _InfoRow(
                        label: 'Plano',
                        value: planAsync.valueOrNull?.name ?? '',
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // Personal Data
                _SectionHeader(
                  title: 'DADOS PESSOAIS',
                  onEdit: () => _showEditPersonalDataSheet(context, ref, student),
                ),
                const SizedBox(height: 8),
                _InfoCard(
                  children: [
                    if (student.nickname != null && student.nickname!.isNotEmpty)
                      _InfoRow(label: 'Apelido', value: student.nickname!),
                    if (student.birthDate != null)
                      _InfoRow(
                        label: 'Nascimento',
                        value: DateFormat('dd/MM/yyyy').format(student.birthDate!),
                      ),
                    if (student.phone != null && student.phone!.isNotEmpty)
                      _InfoRow(label: 'Telefone', value: student.phone!),
                    if (student.email != null && student.email!.isNotEmpty)
                      _InfoRow(label: 'Email', value: student.email!),
                    if (student.cpf != null && student.cpf!.isNotEmpty)
                      _InfoRow(label: 'CPF', value: student.cpf!),
                    if (student.rg != null && student.rg!.isNotEmpty)
                      _InfoRow(label: 'RG', value: student.rg!),
                    if (student.weight != null)
                      _InfoRow(label: 'Peso', value: '${student.weight} kg'),
                    // Empty state
                    if (_isPersonalDataEmpty(student))
                      _EmptyFieldHint(
                        text: 'Toque em editar para adicionar seus dados',
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // Address
                _SectionHeader(
                  title: 'ENDERECO',
                  onEdit: () => _showEditAddressSheet(context, ref, student),
                ),
                const SizedBox(height: 8),
                _InfoCard(
                  children: [
                    if (student.address != null && _hasAddress(student.address!)) ...[
                      if (student.address!.street != null)
                        _InfoRow(
                          label: 'Endereco',
                          value: _formatAddress(student.address!),
                        ),
                      if (student.address!.neighborhood != null)
                        _InfoRow(label: 'Bairro', value: student.address!.neighborhood!),
                      if (student.address!.city != null)
                        _InfoRow(
                          label: 'Cidade',
                          value: '${student.address!.city}${student.address!.state != null ? ' - ${student.address!.state}' : ''}',
                        ),
                      if (student.address!.zipCode != null)
                        _InfoRow(label: 'CEP', value: student.address!.zipCode!),
                    ] else
                      _EmptyFieldHint(text: 'Nenhum endereco cadastrado'),
                  ],
                ),

                const SizedBox(height: 24),

                // Health Info
                _SectionHeader(
                  title: 'SAUDE',
                  onEdit: () => _showEditHealthSheet(context, ref, student),
                ),
                const SizedBox(height: 8),
                _InfoCard(
                  children: [
                    if (student.bloodType != null && student.bloodType!.isNotEmpty)
                      _InfoRow(label: 'Tipo sanguineo', value: student.bloodType!),
                    if (student.allergies != null && student.allergies!.isNotEmpty)
                      _InfoRow(label: 'Alergias', value: student.allergies!.join(', ')),
                    if (student.healthNotes != null && student.healthNotes!.isNotEmpty)
                      _InfoRow(label: 'Observacoes', value: student.healthNotes!),
                    if (_isHealthDataEmpty(student))
                      _EmptyFieldHint(text: 'Nenhuma informacao de saude'),
                  ],
                ),

                const SizedBox(height: 24),

                // Emergency Contact
                _SectionHeader(
                  title: 'CONTATO DE EMERGENCIA',
                  onEdit: () => _showEditEmergencySheet(context, ref, student),
                ),
                const SizedBox(height: 8),
                _InfoCard(
                  children: [
                    if (student.emergencyContact != null) ...[
                      _InfoRow(label: 'Nome', value: student.emergencyContact!.name),
                      _InfoRow(label: 'Telefone', value: student.emergencyContact!.phone),
                      if (student.emergencyContact!.relationship.isNotEmpty)
                        _InfoRow(label: 'Parentesco', value: student.emergencyContact!.relationship),
                    ] else
                      _EmptyFieldHint(text: 'Nenhum contato de emergencia'),
                  ],
                ),

                const SizedBox(height: 24),

                // Privacy Toggle
                _PrivacyToggle(
                  value: student.isProfilePublic,
                  onChanged: (value) => _updatePrivacy(context, ref, student, value),
                ),

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

  String _formatAddress(Address address) {
    final parts = <String>[];
    if (address.street.isNotEmpty) {
      parts.add(address.street);
    }
    if (address.number.isNotEmpty) {
      parts.add(address.number);
    }
    if (address.complement != null && address.complement!.isNotEmpty) {
      parts.add(address.complement!);
    }
    return parts.join(', ');
  }

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

  void _showEditHealthSheet(BuildContext context, WidgetRef ref, Student student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditHealthSheet(
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

  void _showEditEmergencySheet(BuildContext context, WidgetRef ref, Student student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditEmergencySheet(
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

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 40,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 24),
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
// WIDGETS
// ============================================

/// Timeline link at the top
class _TimelineLink extends StatelessWidget {
  final VoidCallback onTap;

  const _TimelineLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.history, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Ver linha do tempo',
              style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 4),
            const Icon(LucideIcons.chevronRight, size: 14, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Profile Card
class _ProfileCard extends StatelessWidget {
  final Student student;
  final int attendanceCount;

  const _ProfileCard({
    required this.student,
    required this.attendanceCount,
  });

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

  @override
  Widget build(BuildContext context) {
    final beltLabel = _beltLabels[student.currentBelt] ?? student.currentBelt;
    final startDate = student.jiujitsuStartDate ?? student.startDate;
    final trainingTime = _formatTrainingTime(startDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppTheme.primary,
            backgroundImage: student.photoUrl != null ? NetworkImage(student.photoUrl!) : null,
            child: student.photoUrl == null
                ? Text(
                    student.displayName[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    BeltBadge(
                      belt: student.currentBelt,
                      stripes: student.currentStripes,
                      size: BeltSize.small,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      beltLabel,
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(LucideIcons.clipboardCheck, size: 12, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '$attendanceCount presencas',
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Icon(LucideIcons.calendar, size: 12, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '$trainingTime de treino',
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

/// Empty field hint
class _EmptyFieldHint extends StatelessWidget {
  final String text;

  const _EmptyFieldHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 14, color: AppTheme.textDisabled),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textDisabled),
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

/// Edit Health Sheet
class _EditHealthSheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditHealthSheet({required this.student, required this.onSave});

  @override
  State<_EditHealthSheet> createState() => _EditHealthSheetState();
}

class _EditHealthSheetState extends State<_EditHealthSheet> {
  late final TextEditingController _bloodTypeController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _healthNotesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _bloodTypeController = TextEditingController(text: widget.student.bloodType);
    _allergiesController = TextEditingController(text: widget.student.allergies?.join(', '));
    _healthNotesController = TextEditingController(text: widget.student.healthNotes);
  }

  @override
  void dispose() {
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _healthNotesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final allergiesText = _allergiesController.text.trim();
      await widget.onSave({
        'bloodType': _bloodTypeController.text.trim().isEmpty ? null : _bloodTypeController.text.trim(),
        'allergies': allergiesText.isEmpty ? null : allergiesText.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList(),
        'healthNotes': _healthNotesController.text.trim().isEmpty ? null : _healthNotesController.text.trim(),
      });
      if (mounted) {
        context.showSuccess('Dados de saude atualizados!');
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
      title: 'Saude',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        _SheetTextField(label: 'Tipo sanguineo', controller: _bloodTypeController, hint: 'Ex: A+, O-, AB+'),
        _SheetTextField(label: 'Alergias', controller: _allergiesController, hint: 'Separe por virgula'),
        _SheetTextField(label: 'Observacoes', controller: _healthNotesController, hint: 'Lesoes, medicamentos...', maxLines: 3),
      ],
    );
  }
}

/// Edit Emergency Contact Sheet
class _EditEmergencySheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditEmergencySheet({required this.student, required this.onSave});

  @override
  State<_EditEmergencySheet> createState() => _EditEmergencySheetState();
}

class _EditEmergencySheetState extends State<_EditEmergencySheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _relationshipController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.student.emergencyContact?.name);
    _phoneController = TextEditingController(text: widget.student.emergencyContact?.phone);
    _relationshipController = TextEditingController(text: widget.student.emergencyContact?.relationship);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final hasData = _nameController.text.trim().isNotEmpty || _phoneController.text.trim().isNotEmpty;
      await widget.onSave({
        'emergencyContact': hasData
            ? {
                'name': _nameController.text.trim(),
                'phone': _phoneController.text.trim(),
                'relationship': _relationshipController.text.trim(),
              }
            : null,
      });
      if (mounted) {
        context.showSuccess('Contato de emergencia atualizado!');
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
      title: 'Contato de Emergencia',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        _SheetTextField(label: 'Nome', controller: _nameController, hint: 'Nome do contato'),
        _SheetTextField(label: 'Telefone', controller: _phoneController, hint: '(00) 00000-0000', keyboardType: TextInputType.phone),
        _SheetTextField(label: 'Parentesco', controller: _relationshipController, hint: 'Ex: Mae, Pai, Conjuge'),
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
