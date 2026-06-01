import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/formatters.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

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
  // Esporte primário do aluno: define quais faixas/graus o seletor mostra.
  // Novos alunos por esta tela são BJJ; ao editar, vem de getPrimarySport().
  SportId _sport = SportId.bjj;
  String _muaythaiVariant = muaythaiVariantCbmt;

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
      final academyId = FirebaseService.academyId;
      final studentService = StudentService(academyId);
      final student = await studentService.getById(widget.studentId!);

      if (student != null) {
        _populateForm(student);
      }
    } catch (e) {
      // Handle error
    }

    setState(() => _isLoading = false);
  }

  void _populateForm(Student student) {
    _fullNameController.text = student.fullName;
    _nicknameController.text = student.nickname ?? '';
    _emailController.text = student.email ?? '';
    _phoneController.text = formatPhone(student.phone);
    _emergencyContactNameController.text = student.emergencyContact?.name ?? '';
    _emergencyContactPhoneController.text =
        formatPhone(student.emergencyContact?.phone);
    _notesController.text = student.healthNotes ?? '';
    _guardianNameController.text = student.guardianName ?? '';
    _guardianPhoneController.text = formatPhone(student.guardianPhone);
    _guardianEmailController.text = student.guardianEmail ?? '';
    _birthDate = student.birthDate;
    _startDate = student.startDate;
    _category = student.category;
    // Faixa do esporte PRIMÁRIO (não BJJ fixo). getGrade cai em currentBelt
    // pra BJJ legado; pra outros esportes lê de sportData.
    _sport = student.getPrimarySport();
    final grade = student.getGrade(_sport);
    _belt = grade?.currentGrade ?? student.currentBelt;
    _stripes = grade?.currentStripes ?? student.currentStripes;
    if (_sport == SportId.muaythai) {
      _muaythaiVariant = resolveMuaythaiVariant(_belt);
    }
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
      final academyId = FirebaseService.academyId;
      final studentService = StudentService(academyId);

      // Build student data (without financial fields)
      final studentData = <String, dynamic>{
        'fullName': _fullNameController.text.trim(),
        'nickname': _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : onlyDigits(_phoneController.text),
        'birthDate': _birthDate,
        'category': _category!.name,
        'startDate': _startDate,
        'currentBelt': _belt,
        'currentStripes': _stripes,
        'status': _status.name,
        'healthNotes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      };

      // Guardian info (for kids)
      if (_category == StudentCategory.kids) {
        studentData['guardianName'] = _guardianNameController.text.trim().isEmpty
            ? null
            : _guardianNameController.text.trim();
        studentData['guardianPhone'] = _guardianPhoneController.text.trim().isEmpty
            ? null
            : onlyDigits(_guardianPhoneController.text);
        studentData['guardianEmail'] = _guardianEmailController.text.trim().isEmpty
            ? null
            : _guardianEmailController.text.trim();
      }

      // Emergency contact
      if (_emergencyContactNameController.text.trim().isNotEmpty) {
        studentData['emergencyContact'] = {
          'name': _emergencyContactNameController.text.trim(),
          'phone': onlyDigits(_emergencyContactPhoneController.text),
        };
      }

      // Multi-esporte: a faixa autoritativa de um esporte não-BJJ vive em
      // sportData[esporte]; currentBelt/currentStripes seguem sincronizados ao
      // primário (mesma convenção do student_form_screen). Atualiza só a entrada
      // do esporte via dot-path pra não apagar os outros esportes do aluno.
      if (isEditing && _sport != SportId.bjj) {
        studentData['sportData.${_sport.value}'] = {
          'currentGrade': _belt,
          'currentStripes': _stripes,
        };
      }

      if (isEditing) {
        await studentService.update(widget.studentId!, studentData);
        if (mounted) {
          context.showSuccess('Aluno atualizado com sucesso!');
          context.pop();
        }
      } else {
        // Set default financial values for new students
        studentData['tuitionValue'] = 0.0;
        studentData['tuitionDay'] = 10;
        studentData['totalAttendanceCount'] = 0;
        studentData['monthlyAttendanceCount'] = 0;

        await studentService.createFromMap(studentData);
        if (mounted) {
          context.showSuccess('Aluno cadastrado com sucesso!');
          context.pop();
        }
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
                      // Volta pra primeira faixa válida do esporte na nova
                      // categoria (kids/adulto mudam a lista no BJJ).
                      final list = getGradesForSport(
                        _sport,
                        category: value.value,
                        muaythaiVariant: _sport == SportId.muaythai
                            ? _muaythaiVariant
                            : null,
                      );
                      _belt = list.isNotEmpty ? list.first.id : 'white';
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
                inputFormatters: [PhoneInputFormatter()],
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
                inputFormatters: [PhoneInputFormatter()],
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
                inputFormatters: [PhoneInputFormatter()],
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
        _buildBeltAndStripesRow(),
      ],
    );
  }

  /// Seletor de faixa + graus do esporte PRIMÁRIO do aluno (sport-aware).
  /// Mostra os graus daquele esporte (não BJJ fixo) e limita os graus ao
  /// maxStripes da faixa escolhida. Para Muay Thai usa a variante resolvida da
  /// faixa atual. Substitui o seletor legado preso ao BeltConstants (BJJ-only).
  Widget _buildBeltAndStripesRow() {
    final grades = getGradesForSport(
      _sport,
      category: (_category ?? StudentCategory.adult).value,
      muaythaiVariant: _sport == SportId.muaythai ? _muaythaiVariant : null,
    );
    if (grades.isEmpty) return const SizedBox.shrink();
    final gradeIds = grades.map((g) => g.id).toList();
    final beltValue = gradeIds.contains(_belt) ? _belt : grades.first.id;
    final maxStripes = grades.firstWhere((g) => g.id == beltValue).maxStripes;
    final stripeValue = _stripes.clamp(0, maxStripes);

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: beltValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Faixa',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: grades.map((grade) {
              final hasStripe = grade.id.contains('-');
              final isWhiteStripe = grade.id.endsWith('-white');
              return DropdownMenuItem(
                value: grade.id,
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 8,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: grade.color,
                              borderRadius: BorderRadius.circular(2),
                              border: grade.id == 'white'
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
                                color:
                                    isWhiteStripe ? Colors.white : Colors.black,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child:
                          Text(grade.label, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _belt = value;
                // Reajusta os graus ao teto da nova faixa.
                final m = grades.firstWhere((g) => g.id == value).maxStripes;
                if (_stripes > m) _stripes = 0;
              });
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: stripeValue,
            decoration: InputDecoration(
              labelText: 'Graus',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: List.generate(maxStripes + 1, (i) => i).map((s) {
              return DropdownMenuItem(value: s, child: Text('$s grau(s)'));
            }).toList(),
            onChanged: (value) {
              if (value != null) setState(() => _stripes = value);
            },
          ),
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
