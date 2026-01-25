import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

/// Admin Student Form Screen - Create or edit student
class AdminStudentFormScreen extends ConsumerStatefulWidget {
  final String? studentId; // null for new student

  const AdminStudentFormScreen({super.key, this.studentId});

  @override
  ConsumerState<AdminStudentFormScreen> createState() => _AdminStudentFormScreenState();
}

class _AdminStudentFormScreenState extends ConsumerState<AdminStudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;
  Student? _existingStudent;

  // Form controllers
  final _fullNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  final _tuitionValueController = TextEditingController();
  final _tuitionDayController = TextEditingController(text: '10');
  final _notesController = TextEditingController();

  // Form values
  DateTime? _birthDate;
  DateTime _startDate = DateTime.now();
  StudentCategory? _category;
  String _belt = 'white';
  int _stripes = 0;
  StudentStatus _status = StudentStatus.active;
  Plan? _selectedPlan;
  List<Plan> _availablePlans = [];

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
    _tuitionValueController.dispose();
    _tuitionDayController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;
      final planService = PlanService(academyId);

      _availablePlans = await planService.list();

      if (isEditing) {
        final studentService = StudentService(academyId);
        final student = await studentService.getById(widget.studentId!);

        if (student != null) {
          _existingStudent = student;
          _populateForm(student);
        }
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
    _phoneController.text = student.phone ?? '';
    _emergencyContactNameController.text = student.emergencyContact?.name ?? '';
    _emergencyContactPhoneController.text = student.emergencyContact?.phone ?? '';
    _tuitionValueController.text = student.tuitionValue.toString();
    _tuitionDayController.text = student.tuitionDay.toString();
    _notesController.text = student.healthNotes ?? '';
    _birthDate = student.birthDate;
    _startDate = student.startDate;
    _category = student.category;
    _belt = student.currentBelt;
    _stripes = student.currentStripes;
    _status = student.status;

    // Find matching plan
    if (student.planId != null) {
      _selectedPlan = _availablePlans.where((p) => p.id == student.planId).firstOrNull;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Aluno' : 'Novo Aluno'),
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
            TextButton.icon(
              onPressed: _saveStudent,
              icon: const Icon(Icons.save),
              label: const Text('Salvar'),
            ),
        ],
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
                    _buildAcademyInfoSection(),
                    const SizedBox(height: 24),
                    _buildFinancialSection(),
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
      title: 'Informações Pessoais',
      icon: Icons.person,
      children: [
        TextFormField(
          controller: _fullNameController,
          decoration: const InputDecoration(
            labelText: 'Nome Completo *',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value?.isEmpty == true ? 'Nome é obrigatório' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nicknameController,
          decoration: const InputDecoration(
            labelText: 'Apelido',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _selectBirthDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data de Nascimento',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _birthDate != null
                        ? DateFormat('dd/MM/yyyy').format(_birthDate!)
                        : 'Selecionar',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<StudentCategory>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Categoria',
                  border: OutlineInputBorder(),
                ),
                items: StudentCategory.values.map((cat) {
                  return DropdownMenuItem(value: cat, child: Text(cat.label));
                }).toList(),
                onChanged: (value) => setState(() => _category = value),
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
      icon: Icons.contact_phone,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Telefone',
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'Contato de Emergência',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _emergencyContactPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Telefone de Emergência',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAcademyInfoSection() {
    return _FormSection(
      title: 'Informações da Academia',
      icon: Icons.sports_martial_arts,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _selectStartDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data de Início *',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(DateFormat('dd/MM/yyyy').format(_startDate)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<StudentStatus>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
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
                value: _belt,
                decoration: const InputDecoration(
                  labelText: 'Faixa',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'white', child: Text('Branca')),
                  DropdownMenuItem(value: 'blue', child: Text('Azul')),
                  DropdownMenuItem(value: 'purple', child: Text('Roxa')),
                  DropdownMenuItem(value: 'brown', child: Text('Marrom')),
                  DropdownMenuItem(value: 'black', child: Text('Preta')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _belt = value);
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _stripes,
                decoration: const InputDecoration(
                  labelText: 'Graus',
                  border: OutlineInputBorder(),
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

  Widget _buildFinancialSection() {
    return _FormSection(
      title: 'Financeiro',
      icon: Icons.attach_money,
      children: [
        DropdownButtonFormField<Plan>(
          value: _selectedPlan,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Plano',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<Plan>(
              value: null,
              child: Text('Sem plano'),
            ),
            ..._availablePlans.map((plan) {
              return DropdownMenuItem(
                value: plan,
                child: Text(
                  '${plan.name} - R\$ ${plan.monthlyValue.toStringAsFixed(2)}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: (value) {
            setState(() {
              _selectedPlan = value;
              if (value != null) {
                _tuitionValueController.text = value.monthlyValue.toString();
              }
            });
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _tuitionValueController,
                decoration: const InputDecoration(
                  labelText: 'Valor da Mensalidade *',
                  border: OutlineInputBorder(),
                  prefixText: 'R\$ ',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty == true) return 'Valor é obrigatório';
                  if (double.tryParse(value!) == null) return 'Valor inválido';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _tuitionDayController,
                decoration: const InputDecoration(
                  labelText: 'Dia Vencimento *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty == true) return 'Obrigatório';
                  final day = int.tryParse(value!);
                  if (day == null || day < 1 || day > 28) {
                    return 'Dia inválido (1-28)';
                  }
                  return null;
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
      title: 'Observações',
      icon: Icons.notes,
      children: [
        TextFormField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Observações',
            hintText: 'Informações adicionais sobre o aluno...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
      ],
    );
  }

  void _selectBirthDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(2000),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() => _birthDate = date);
    }
  }

  void _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date != null) {
      setState(() => _startDate = date);
    }
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final academyId = FirebaseService.academyId;
      final studentService = StudentService(academyId);

      // Build the data map
      final data = <String, dynamic>{
        'fullName': _fullNameController.text,
        'nickname': _nicknameController.text.isEmpty ? null : _nicknameController.text,
        'email': _emailController.text.isEmpty ? null : _emailController.text,
        'phone': _phoneController.text.isEmpty ? null : _phoneController.text,
        'birthDate': _birthDate != null ? Timestamp.fromDate(_birthDate!) : null,
        'category': _category?.value ?? 'adult',
        'startDate': Timestamp.fromDate(_startDate),
        'currentBelt': _belt,
        'currentStripes': _stripes,
        'status': _status.value,
        'planId': _selectedPlan?.id,
        'tuitionValue': double.parse(_tuitionValueController.text),
        'tuitionDay': int.parse(_tuitionDayController.text),
        'healthNotes': _notesController.text.isEmpty ? null : _notesController.text,
      };

      // Add emergency contact if provided
      if (_emergencyContactNameController.text.isNotEmpty) {
        data['emergencyContact'] = {
          'name': _emergencyContactNameController.text,
          'phone': _emergencyContactPhoneController.text,
          'relationship': 'Emergência',
        };
      }

      if (isEditing) {
        await studentService.update(widget.studentId!, data);
      } else {
        // For new students, add required fields
        data['isProfilePublic'] = false;
        data['attendanceCount'] = 0;
        data['initialAttendanceCount'] = 0;
        data['createdAt'] = FieldValue.serverTimestamp();
        data['updatedAt'] = FieldValue.serverTimestamp();

        await FirebaseService.firestore
            .collection('academies/$academyId/students')
            .add(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'Aluno atualizado!' : 'Aluno cadastrado!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
