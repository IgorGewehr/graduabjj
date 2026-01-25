import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

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

/// Profile Screen - Meu Perfil (New Layout with Editable Forms)
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Controllers for editable fields
  final _nicknameController = TextEditingController();
  final _bloodTypeController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _healthNotesController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _emergencyRelationshipController = TextEditingController();

  bool _isProfilePublic = false;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _healthNotesController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyRelationshipController.dispose();
    super.dispose();
  }

  void _initializeControllers(Student student) {
    // Only initialize if controllers are empty (first load)
    if (_nicknameController.text.isEmpty && student.nickname != null) {
      _nicknameController.text = student.nickname!;
    }
    if (_bloodTypeController.text.isEmpty && student.bloodType != null) {
      _bloodTypeController.text = student.bloodType!;
    }
    if (_allergiesController.text.isEmpty && student.allergies != null) {
      _allergiesController.text = student.allergies!.join(', ');
    }
    if (_healthNotesController.text.isEmpty && student.healthNotes != null) {
      _healthNotesController.text = student.healthNotes!;
    }
    if (_emergencyNameController.text.isEmpty && student.emergencyContact != null) {
      _emergencyNameController.text = student.emergencyContact!.name;
    }
    if (_emergencyPhoneController.text.isEmpty && student.emergencyContact != null) {
      _emergencyPhoneController.text = student.emergencyContact!.phone;
    }
    if (_emergencyRelationshipController.text.isEmpty && student.emergencyContact != null) {
      _emergencyRelationshipController.text = student.emergencyContact!.relationship;
    }
    _isProfilePublic = student.isProfilePublic;
  }

  void _markAsChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _saveChanges(Student student) async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final studentService = ref.read(studentServiceProvider);
      if (studentService == null) {
        throw Exception('Servico de aluno nao disponivel');
      }

      // Build update data
      final updateData = <String, dynamic>{
        'nickname': _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        'bloodType': _bloodTypeController.text.trim().isEmpty
            ? null
            : _bloodTypeController.text.trim(),
        'healthNotes': _healthNotesController.text.trim().isEmpty
            ? null
            : _healthNotesController.text.trim(),
        'isProfilePublic': _isProfilePublic,
      };

      // Handle allergies (comma-separated to list)
      final allergiesText = _allergiesController.text.trim();
      if (allergiesText.isEmpty) {
        updateData['allergies'] = null;
      } else {
        updateData['allergies'] = allergiesText
            .split(',')
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList();
      }

      // Handle emergency contact
      final emergencyName = _emergencyNameController.text.trim();
      final emergencyPhone = _emergencyPhoneController.text.trim();
      final emergencyRelationship = _emergencyRelationshipController.text.trim();

      if (emergencyName.isNotEmpty || emergencyPhone.isNotEmpty) {
        updateData['emergencyContact'] = {
          'name': emergencyName,
          'phone': emergencyPhone,
          'relationship': emergencyRelationship,
        };
      } else {
        updateData['emergencyContact'] = null;
      }

      await studentService.update(student.id, updateData);

      // Invalidate cache to refresh data
      ref.invalidate(currentStudentProvider);

      setState(() {
        _hasChanges = false;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil atualizado com sucesso'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildEmptyState();
        }

        // Initialize controllers with student data
        _initializeControllers(student);

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

                // Compact Profile Card
                _CompactProfileCard(
                  student: student,
                  attendanceCount: attendanceCountAsync.valueOrNull ?? 0,
                ),

                const SizedBox(height: 24),

                // Managed by Academy Section (read-only)
                _SectionHeader(title: 'GERENCIADO PELA ACADEMIA'),
                const SizedBox(height: 8),
                _ManagedByAcademySection(
                  student: student,
                  plan: planAsync.valueOrNull,
                ),

                const SizedBox(height: 24),

                // Personal Data Section (editable)
                _SectionHeader(title: 'DADOS PESSOAIS'),
                const SizedBox(height: 8),
                _EditableSection(
                  children: [
                    _EditableTextField(
                      label: 'Apelido',
                      controller: _nicknameController,
                      hint: 'Como voce gostaria de ser chamado',
                      onChanged: (_) => _markAsChanged(),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Health Section (editable)
                _SectionHeader(title: 'SAUDE'),
                const SizedBox(height: 8),
                _EditableSection(
                  children: [
                    _EditableTextField(
                      label: 'Tipo sanguineo',
                      controller: _bloodTypeController,
                      hint: 'Ex: A+, O-, AB+',
                      onChanged: (_) => _markAsChanged(),
                    ),
                    const Divider(height: 1),
                    _EditableTextField(
                      label: 'Alergias',
                      controller: _allergiesController,
                      hint: 'Separe por virgula',
                      onChanged: (_) => _markAsChanged(),
                    ),
                    const Divider(height: 1),
                    _EditableTextField(
                      label: 'Observacoes de saude',
                      controller: _healthNotesController,
                      hint: 'Lesoes, condicoes, medicamentos...',
                      maxLines: 3,
                      onChanged: (_) => _markAsChanged(),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Emergency Contact Section (editable)
                _SectionHeader(title: 'CONTATO DE EMERGENCIA'),
                const SizedBox(height: 8),
                _EditableSection(
                  children: [
                    _EditableTextField(
                      label: 'Nome',
                      controller: _emergencyNameController,
                      hint: 'Nome do contato',
                      onChanged: (_) => _markAsChanged(),
                    ),
                    const Divider(height: 1),
                    _EditableTextField(
                      label: 'Telefone',
                      controller: _emergencyPhoneController,
                      hint: '(00) 00000-0000',
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => _markAsChanged(),
                    ),
                    const Divider(height: 1),
                    _EditableTextField(
                      label: 'Parentesco',
                      controller: _emergencyRelationshipController,
                      hint: 'Ex: Mae, Pai, Conjuge',
                      onChanged: (_) => _markAsChanged(),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Profile Public Toggle
                _ProfilePublicToggle(
                  value: _isProfilePublic,
                  onChanged: (value) {
                    setState(() => _isProfilePublic = value);
                    _markAsChanged();
                  },
                ),

                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _hasChanges && !_isSaving
                        ? () => _saveChanges(student)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.surfaceVariant,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Salvar alteracoes',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
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
            const Icon(
              LucideIcons.history,
              size: 16,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Ver linha do tempo',
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
    );
  }
}

/// Compact profile card with avatar on left, info on right
class _CompactProfileCard extends StatelessWidget {
  final Student student;
  final int attendanceCount;

  const _CompactProfileCard({
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
          // Avatar
          CircleAvatar(
            radius: 32,
            backgroundColor: AppTheme.primary,
            backgroundImage: student.photoUrl != null
                ? NetworkImage(student.photoUrl!)
                : null,
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
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
                      '$beltLabel${student.currentStripes > 0 ? ' ${student.currentStripes}°' : ''}',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MiniStat(
                      icon: LucideIcons.clipboardCheck,
                      value: attendanceCount.toString(),
                      label: 'presencas',
                    ),
                    const SizedBox(width: 16),
                    _MiniStat(
                      icon: LucideIcons.calendar,
                      value: trainingTime,
                      label: 'de treino',
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

/// Mini stat display
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTheme.labelSmall.copyWith(
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Section header
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTheme.labelSmall.copyWith(
        color: AppTheme.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Managed by academy section (read-only info)
class _ManagedByAcademySection extends StatelessWidget {
  final Student student;
  final dynamic plan;

  const _ManagedByAcademySection({
    required this.student,
    this.plan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          _ReadOnlyField(
            label: 'Inicio',
            value: DateFormat('dd/MM/yyyy').format(student.startDate),
          ),
          const Divider(height: 1),
          _ReadOnlyField(
            label: 'Status',
            value: student.status.label,
            valueColor: AppTheme.getStatusColor(student.status.value),
          ),
          if (plan != null || student.planId != null) ...[
            const Divider(height: 1),
            _ReadOnlyField(
              label: 'Plano',
              value: plan?.name ?? 'Carregando...',
            ),
          ],
        ],
      ),
    );
  }
}

/// Read-only field for managed section
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReadOnlyField({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: AppTheme.bodyMedium.copyWith(
              fontWeight: FontWeight.w500,
              color: valueColor ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Editable section container
class _EditableSection extends StatelessWidget {
  final List<Widget> children;

  const _EditableSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

/// Editable text field
class _EditableTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _EditableTextField({
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: AppTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textDisabled,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Profile public toggle
class _ProfilePublicToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ProfilePublicToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
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
                  'Permitir que outros alunos vejam seu perfil',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}
