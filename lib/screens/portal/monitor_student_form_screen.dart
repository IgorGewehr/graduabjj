import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/student_dto.dart' as api_student;
import '../../api/repositories.dart' as tatami_repos;
import '../../core/constants.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/selected_academy_provider.dart';

/// Monitor Student Form Screen - Create or edit student (no financial fields)
class MonitorStudentFormScreen extends ConsumerStatefulWidget {
  final String? studentId; // null for new student

  const MonitorStudentFormScreen({super.key, this.studentId});

  @override
  ConsumerState<MonitorStudentFormScreen> createState() => _MonitorStudentFormScreenState();
}

class _MonitorStudentFormScreenState extends ConsumerState<MonitorStudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Form controllers
  final _fullNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  final _notesController = TextEditingController();

  // Guardian (for kids)
  final _guardianNameController = TextEditingController();
  final _guardianPhoneController = TextEditingController();
  final _guardianEmailController = TextEditingController();

  // Form values
  DateTime? _birthDate;
  DateTime _startDate = DateTime.now();
  StudentCategory? _category;
  String _belt = 'white';
  int _stripes = 0;
  StudentStatus _status = StudentStatus.active;

  bool get isEditing => widget.studentId != null;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _nicknameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    _notesController.dispose();
    _guardianNameController.dispose();
    _guardianPhoneController.dispose();
    _guardianEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!isEditing) return;

    setState(() => _isLoading = true);

    try {
      final academyId = ref.read(safeAcademyIdProvider) ?? '';
      ref.invalidate(tatami.tatamiStudentByIdLegacyProvider(
        tatami.studentRef(academyId, widget.studentId!),
      ));
      final student = await ref.read(
        tatami.tatamiStudentByIdLegacyProvider(
          tatami.studentRef(academyId, widget.studentId!),
        ).future,
      );

      _populateForm(student);
    } catch (e) {
      // Handle error
    }

    setState(() => _isLoading = false);
  }

  void _populateForm(Student student) {
    _fullNameController.text = student.fullName;
    _nicknameController.text = student.nickname ?? '';
    _emailController.text = student.email ?? '';
    _phoneController.text = student.phone ?? '';
    _emergencyContactNameController.text = student.emergencyContact?.name ?? '';
    _emergencyContactPhoneController.text = student.emergencyContact?.phone ?? '';
    _notesController.text = student.healthNotes ?? '';
    _guardianNameController.text = student.guardianName ?? '';
    _guardianPhoneController.text = student.guardianPhone ?? '';
    _guardianEmailController.text = student.guardianEmail ?? '';
    _birthDate = student.birthDate;
    _startDate = student.startDate;
    _category = student.category;
    _belt = student.currentBelt;
    _stripes = student.currentStripes;
    _status = student.status;
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null) {
      context.showWarning('Selecione a categoria do aluno');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final academyId = ref.read(safeAcademyIdProvider) ?? '';
      final repo = ref.read(tatami_repos.studentRepoProvider);

      // Guardian (for kids)
      api_student.ApiGuardian? guardianDto;
      if (_category == StudentCategory.kids &&
          _guardianNameController.text.trim().isNotEmpty) {
        guardianDto = api_student.ApiGuardian(
          name: _guardianNameController.text.trim(),
          phone: _guardianPhoneController.text.trim().isEmpty
              ? null
              : _guardianPhoneController.text.trim(),
          email: _guardianEmailController.text.trim().isEmpty
              ? null
              : _guardianEmailController.text.trim(),
        );
      }

      // Emergency contact (string "name | phone").
      String? emergencyContactStr;
      if (_emergencyContactNameController.text.trim().isNotEmpty) {
        emergencyContactStr =
            '${_emergencyContactNameController.text.trim()} | ${_emergencyContactPhoneController.text.trim()}';
      }

      if (isEditing) {
        await repo.update(
          academyId,
          widget.studentId!,
          api_student.UpdateStudentRequest(
            fullName: _fullNameController.text.trim(),
            nickname: _nicknameController.text.trim().isEmpty
                ? null
                : _nicknameController.text.trim(),
            email: _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
            phone: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
            birthDate: _birthDate,
            startDate: _startDate,
            category: _category == StudentCategory.kids
                ? api_student.ApiStudentCategory.kids
                : api_student.ApiStudentCategory.adult,
            status: api_student.ApiStudentStatusX.fromWire(_status.value),
            healthNotes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            guardian: guardianDto,
            emergencyContact: emergencyContactStr,
          ),
        );
      } else {
        await repo.create(
          academyId,
          api_student.CreateStudentRequest(
            fullName: _fullNameController.text.trim(),
            nickname: _nicknameController.text.trim().isEmpty
                ? null
                : _nicknameController.text.trim(),
            email: _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
            phone: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
            birthDate: _birthDate,
            startDate: _startDate,
            category: _category == StudentCategory.kids
                ? api_student.ApiStudentCategory.kids
                : api_student.ApiStudentCategory.adult,
            currentBelt: api_student.ApiBeltX.fromWire(_belt),
            currentStripes: _stripes,
            initialAttendanceCount: 0,
            healthNotes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            guardian: guardianDto,
            emergencyContact: emergencyContactStr,
          ),
        );
      }

      if (mounted) {
        context.showSuccess(
          isEditing ? 'Aluno atualizado com sucesso!' : 'Aluno cadastrado com sucesso!',
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _selectBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now().subtract(const Duration(days: 365 * 15)),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          isEditing ? 'Editar Aluno' : 'Novo Aluno',
          style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveStudent,
              child: Text(
                'Salvar',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.divider),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPersonalInfoSection(),
                    const SizedBox(height: 24),
                    _buildContactSection(),
                    const SizedBox(height: 24),
                    if (_category == StudentCategory.kids) ...[
                      _buildGuardianSection(),
                      const SizedBox(height: 24),
                    ],
                    _buildAcademyInfoSection(),
                    const SizedBox(height: 24),
                    _buildNotesSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPersonalInfoSection() {
    return _FormSection(
      title: 'Informacoes Pessoais',
      icon: LucideIcons.user,
      children: [
        TextFormField(
          controller: _fullNameController,
          decoration: InputDecoration(
            labelText: 'Nome Completo *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (value) => value?.isEmpty == true ? 'Nome e obrigatorio' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nicknameController,
          decoration: InputDecoration(
            labelText: 'Apelido',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _selectBirthDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data de Nascimento',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: const Icon(LucideIcons.calendar),
                  ),
                  child: Text(
                    _birthDate != null
                        ? DateFormat('dd/MM/yyyy').format(_birthDate!)
                        : 'Selecionar',
                    style: AppTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<StudentCategory>(
                value: _category,
                decoration: InputDecoration(
                  labelText: 'Categoria *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: StudentCategory.values.map((cat) {
                  return DropdownMenuItem(value: cat, child: Text(cat.label));
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _category = value;
                      _belt = 'white';
                      _stripes = 0;
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContactSection() {
    return _FormSection(
      title: 'Contato',
      icon: LucideIcons.phone,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'E-mail',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Telefone',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _emergencyContactNameController,
                decoration: InputDecoration(
                  labelText: 'Contato de Emergencia',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _emergencyContactPhoneController,
                decoration: InputDecoration(
                  labelText: 'Telefone de Emergencia',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGuardianSection() {
    return _FormSection(
      title: 'Responsavel',
      icon: LucideIcons.users,
      children: [
        TextFormField(
          controller: _guardianNameController,
          decoration: InputDecoration(
            labelText: 'Nome do Responsavel',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _guardianPhoneController,
                decoration: InputDecoration(
                  labelText: 'Telefone',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _guardianEmailController,
                decoration: InputDecoration(
                  labelText: 'E-mail',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAcademyInfoSection() {
    return _FormSection(
      title: 'Informacoes da Academia',
      icon: LucideIcons.award,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _selectStartDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data de Inicio *',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: const Icon(LucideIcons.calendar),
                  ),
                  child: Text(
                    DateFormat('dd/MM/yyyy').format(_startDate),
                    style: AppTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<StudentStatus>(
                value: _status,
                decoration: InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: StudentStatus.values.map((status) {
                  return DropdownMenuItem(value: status, child: Text(status.label));
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: (_category == StudentCategory.kids
                        ? BeltConstants.kidsBelts
                        : BeltConstants.adultBelts)
                    .contains(_belt)
                    ? _belt
                    : 'white',
                decoration: InputDecoration(
                  labelText: 'Faixa',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: (_category == StudentCategory.kids
                        ? BeltConstants.kidsBelts
                        : BeltConstants.adultBelts)
                    .map((beltKey) {
                  final label = BeltConstants.beltLabels[beltKey] ?? beltKey;
                  final color = AppTheme.getBeltColor(beltKey);
                  final hasStripe = beltKey.contains('-');
                  final isWhiteStripe = beltKey.endsWith('-white');

                  return DropdownMenuItem(
                    value: beltKey,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 8,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                  border: beltKey == 'white'
                                      ? Border.all(color: AppTheme.divider)
                                      : null,
                                ),
                              ),
                              if (hasStripe)
                                Positioned(
                                  top: 3,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 2,
                                    color: isWhiteStripe
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(label),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _belt = value);
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _stripes,
                decoration: InputDecoration(
                  labelText: 'Graus',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: List.generate(5, (i) => i).map((s) {
                  return DropdownMenuItem(value: s, child: Text('$s grau(s)'));
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _stripes = value);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return _FormSection(
      title: 'Observacoes',
      icon: LucideIcons.fileText,
      children: [
        TextFormField(
          controller: _notesController,
          decoration: InputDecoration(
            labelText: 'Observacoes medicas ou gerais',
            hintText: 'Ex: Alergias, lesoes anteriores, etc.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          maxLines: 4,
        ),
      ],
    );
  }
}

/// Form Section Widget
class _FormSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _FormSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
