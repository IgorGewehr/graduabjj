import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';
import '../../widgets/form/form_widgets.dart';

/// Admin Student Form Screen - Modern tabbed form with progress tracking
class AdminStudentFormScreen extends ConsumerStatefulWidget {
  final String? studentId;

  const AdminStudentFormScreen({super.key, this.studentId});

  @override
  ConsumerState<AdminStudentFormScreen> createState() => _AdminStudentFormScreenState();
}

class _AdminStudentFormScreenState extends ConsumerState<AdminStudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;
  Student? _existingStudent;
  String _activeTab = 'personal';

  // Form controllers
  final _fullNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cpfController = TextEditingController();
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  final _guardianNameController = TextEditingController();
  final _guardianPhoneController = TextEditingController();
  final _tuitionValueController = TextEditingController();
  final _tuitionDayController = TextEditingController(text: '10');
  final _healthNotesController = TextEditingController();
  final _allergiesController = TextEditingController();

  // Form values
  DateTime? _birthDate;
  DateTime _startDate = DateTime.now();
  StudentCategory _category = StudentCategory.adult;
  String _belt = 'white';
  int _stripes = 0;
  StudentStatus _status = StudentStatus.active;
  Plan? _selectedPlan;
  List<Plan> _availablePlans = [];

  // Error tracking per tab
  final Map<String, bool> _tabErrors = {
    'personal': false,
    'contact': false,
    'academy': false,
    'financial': false,
  };

  bool get isEditing => widget.studentId != null;

  // Calculate form progress
  double get _formProgress {
    int filled = 0;
    int total = 8; // Required fields

    if (_fullNameController.text.isNotEmpty) filled++;
    if (_category != null) filled++;
    if (_belt.isNotEmpty) filled++;
    if (_tuitionValueController.text.isNotEmpty) filled++;
    if (_tuitionDayController.text.isNotEmpty) filled++;

    // Optional but valuable
    total += 6;
    if (_phoneController.text.isNotEmpty) filled++;
    if (_emailController.text.isNotEmpty) filled++;
    if (_birthDate != null) filled++;
    if (_emergencyContactNameController.text.isNotEmpty) filled++;
    if (_selectedPlan != null) filled++;
    if (_nicknameController.text.isNotEmpty) filled++;

    return (filled / total) * 100;
  }

  List<FormTab> get _tabs => [
    FormTab(
      key: 'personal',
      label: 'Pessoal',
      icon: LucideIcons.user,
      hasErrors: _tabErrors['personal'] ?? false,
    ),
    FormTab(
      key: 'contact',
      label: 'Contato',
      icon: LucideIcons.phone,
      hasErrors: _tabErrors['contact'] ?? false,
    ),
    FormTab(
      key: 'academy',
      label: 'Academia',
      icon: LucideIcons.award,
      hasErrors: _tabErrors['academy'] ?? false,
    ),
    FormTab(
      key: 'financial',
      label: 'Financeiro',
      icon: LucideIcons.wallet,
      hasErrors: _tabErrors['financial'] ?? false,
    ),
  ];

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
    _cpfController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    _guardianNameController.dispose();
    _guardianPhoneController.dispose();
    _tuitionValueController.dispose();
    _tuitionDayController.dispose();
    _healthNotesController.dispose();
    _allergiesController.dispose();
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
    _cpfController.text = student.cpf ?? '';
    _emergencyContactNameController.text = student.emergencyContact?.name ?? '';
    _emergencyContactPhoneController.text = student.emergencyContact?.phone ?? '';
    _guardianNameController.text = student.guardian?.name ?? '';
    _guardianPhoneController.text = student.guardian?.phone ?? '';
    _tuitionValueController.text = student.tuitionValue.toStringAsFixed(2).replaceAll('.', ',');
    _tuitionDayController.text = student.tuitionDay.toString();
    _healthNotesController.text = student.healthNotes ?? '';
    _birthDate = student.birthDate;
    _startDate = student.startDate;
    _category = student.category;
    _belt = student.currentBelt;
    _stripes = student.currentStripes;
    _status = student.status;

    if (student.planId != null) {
      _selectedPlan = _availablePlans.where((p) => p.id == student.planId).firstOrNull;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: FormTabs(
                tabs: _tabs,
                activeTab: _activeTab,
                onTabChange: (tab) => setState(() => _activeTab = tab),
                progress: _formProgress,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Personal Tab
                      FormTabPanel(
                        tabKey: 'personal',
                        activeTab: _activeTab,
                        child: _buildPersonalTab(),
                      ),

                      // Contact Tab
                      FormTabPanel(
                        tabKey: 'contact',
                        activeTab: _activeTab,
                        child: _buildContactTab(),
                      ),

                      // Academy Tab
                      FormTabPanel(
                        tabKey: 'academy',
                        activeTab: _activeTab,
                        child: _buildAcademyTab(),
                      ),

                      // Financial Tab
                      FormTabPanel(
                        tabKey: 'financial',
                        activeTab: _activeTab,
                        child: _buildFinancialTab(),
                      ),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditing ? 'Editar Aluno' : 'Novo Aluno',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          if (_existingStudent != null)
            Text(
              _existingStudent!.fullName,
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
            ),
        ],
      ),
      centerTitle: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.divider),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          // Navigation buttons
          if (_activeTab != 'personal')
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _goToPreviousTab,
                icon: const Icon(LucideIcons.chevronLeft, size: 18),
                label: const Text('Anterior'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: BorderSide(color: AppTheme.divider),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          if (_activeTab != 'personal') const SizedBox(width: 12),

          // Next / Save button
          Expanded(
            flex: _activeTab == 'personal' ? 1 : 1,
            child: _activeTab == 'financial'
                ? ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveStudent,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.check, size: 18),
                    label: Text(_isSaving ? 'Salvando...' : 'Salvar Aluno'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _goToNextTab,
                    icon: const Icon(LucideIcons.chevronRight, size: 18),
                    label: const Text('Próximo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _goToPreviousTab() {
    final currentIndex = _tabs.indexWhere((t) => t.key == _activeTab);
    if (currentIndex > 0) {
      setState(() => _activeTab = _tabs[currentIndex - 1].key);
    }
  }

  void _goToNextTab() {
    final currentIndex = _tabs.indexWhere((t) => t.key == _activeTab);
    if (currentIndex < _tabs.length - 1) {
      setState(() => _activeTab = _tabs[currentIndex + 1].key);
    }
  }

  // ============================================
  // PERSONAL TAB
  // ============================================
  Widget _buildPersonalTab() {
    return Column(
      children: [
        FormSection(
          title: 'Dados Pessoais',
          subtitle: 'Informações básicas do aluno',
          icon: LucideIcons.user,
          badge: 'Obrigatório',
          badgeVariant: BadgeVariant.warning,
          child: Column(
            children: [
              InputField(
                controller: _fullNameController,
                label: 'Nome Completo',
                prefixIcon: LucideIcons.user,
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value?.isEmpty == true ? 'Nome é obrigatório' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              FormRow(
                children: [
                  InputField(
                    controller: _nicknameController,
                    label: 'Apelido',
                    hintText: 'Como prefere ser chamado',
                    prefixIcon: LucideIcons.smile,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                  ),
                  CPFInput(
                    controller: _cpfController,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              FormRow(
                children: [
                  DateInput(
                    value: _birthDate,
                    label: 'Data de Nascimento',
                    lastDate: DateTime.now(),
                    firstDate: DateTime(1930),
                    onChanged: (date) => setState(() => _birthDate = date),
                  ),
                  _buildCategoryDropdown(),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Guardian section (for kids)
        if (_category == StudentCategory.kids)
          FormSection(
            title: 'Responsável',
            subtitle: 'Dados do responsável pelo menor',
            icon: LucideIcons.users,
            badge: 'Obrigatório',
            badgeVariant: BadgeVariant.warning,
            child: Column(
              children: [
                InputField(
                  controller: _guardianNameController,
                  label: 'Nome do Responsável',
                  prefixIcon: LucideIcons.user,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (_category == StudentCategory.kids && (value?.isEmpty ?? true)) {
                      return 'Responsável obrigatório para menores';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                PhoneInput(
                  controller: _guardianPhoneController,
                  label: 'Telefone do Responsável',
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<StudentCategory>(
        value: _category,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown, color: AppTheme.textSecondary, size: 20),
        decoration: InputDecoration(
          labelText: 'Categoria',
          prefixIcon: Icon(LucideIcons.users, size: 20, color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: StudentCategory.values.map((cat) {
          return DropdownMenuItem(
            value: cat,
            child: Text(cat.label, style: AppTheme.bodyMedium),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _category = value);
        },
        dropdownColor: AppTheme.surface,
      ),
    );
  }

  // ============================================
  // CONTACT TAB
  // ============================================
  Widget _buildContactTab() {
    return Column(
      children: [
        FormSection(
          title: 'Contato Principal',
          subtitle: 'Formas de contato com o aluno',
          icon: LucideIcons.phone,
          child: Column(
            children: [
              FormRow(
                children: [
                  EmailInput(
                    controller: _emailController,
                    onChanged: (_) => setState(() {}),
                  ),
                  PhoneInput(
                    controller: _phoneController,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        FormSection(
          title: 'Contato de Emergência',
          subtitle: 'Pessoa para contato em caso de emergência',
          icon: LucideIcons.alertTriangle,
          badge: 'Recomendado',
          badgeVariant: BadgeVariant.success,
          child: Column(
            children: [
              InputField(
                controller: _emergencyContactNameController,
                label: 'Nome do Contato',
                prefixIcon: LucideIcons.user,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              PhoneInput(
                controller: _emergencyContactPhoneController,
                label: 'Telefone de Emergência',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================
  // ACADEMY TAB
  // ============================================
  Widget _buildAcademyTab() {
    return Column(
      children: [
        FormSection(
          title: 'Informações da Academia',
          subtitle: 'Dados de matrícula e graduação',
          icon: LucideIcons.award,
          badge: 'Obrigatório',
          badgeVariant: BadgeVariant.warning,
          child: Column(
            children: [
              FormRow(
                children: [
                  DateInput(
                    value: _startDate,
                    label: 'Data de Início',
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime(2015),
                    onChanged: (date) {
                      if (date != null) setState(() => _startDate = date);
                    },
                  ),
                  _buildStatusDropdown(),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        FormSection(
          title: 'Graduação',
          subtitle: 'Faixa e graus atuais',
          icon: LucideIcons.medal,
          child: Column(
            children: [
              FormRow(
                children: [
                  _buildBeltSelector(),
                  _buildStripesSelector(),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        FormSection(
          title: 'Saúde',
          subtitle: 'Informações médicas relevantes',
          icon: LucideIcons.heart,
          collapsible: true,
          defaultCollapsed: _healthNotesController.text.isEmpty && _allergiesController.text.isEmpty,
          child: Column(
            children: [
              InputField(
                controller: _allergiesController,
                label: 'Alergias',
                hintText: 'Liste alergias conhecidas...',
                prefixIcon: LucideIcons.alertCircle,
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              InputField(
                controller: _healthNotesController,
                label: 'Observações de Saúde',
                hintText: 'Lesões, condições médicas, restrições...',
                prefixIcon: LucideIcons.clipboardList,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<StudentStatus>(
        value: _status,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown, color: AppTheme.textSecondary, size: 20),
        decoration: InputDecoration(
          labelText: 'Status',
          prefixIcon: Icon(LucideIcons.activity, size: 20, color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: StudentStatus.values.map((status) {
          return DropdownMenuItem(
            value: status,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getStatusColor(status),
                  ),
                ),
                const SizedBox(width: 8),
                Text(status.label, style: AppTheme.bodyMedium),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _status = value);
        },
        dropdownColor: AppTheme.surface,
      ),
    );
  }

  Color _getStatusColor(StudentStatus status) {
    switch (status) {
      case StudentStatus.active:
        return AppTheme.success;
      case StudentStatus.injured:
        return Colors.orange;
      case StudentStatus.inactive:
        return AppTheme.textDisabled;
      case StudentStatus.suspended:
        return AppTheme.error;
    }
  }

  Widget _buildBeltSelector() {
    final belts = [
      ('white', 'Branca', const Color(0xFFF5F5F5)),
      ('blue', 'Azul', const Color(0xFF2563EB)),
      ('purple', 'Roxa', const Color(0xFF7C3AED)),
      ('brown', 'Marrom', const Color(0xFF92400E)),
      ('black', 'Preta', const Color(0xFF171717)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<String>(
        value: _belt,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown, color: AppTheme.textSecondary, size: 20),
        decoration: InputDecoration(
          labelText: 'Faixa',
          prefixIcon: Icon(LucideIcons.award, size: 20, color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: belts.map((belt) {
          return DropdownMenuItem(
            value: belt.$1,
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 8,
                  decoration: BoxDecoration(
                    color: belt.$3,
                    borderRadius: BorderRadius.circular(2),
                    border: belt.$1 == 'white'
                        ? Border.all(color: AppTheme.divider)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Text(belt.$2, style: AppTheme.bodyMedium),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _belt = value);
        },
        dropdownColor: AppTheme.surface,
      ),
    );
  }

  Widget _buildStripesSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<int>(
        value: _stripes,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown, color: AppTheme.textSecondary, size: 20),
        decoration: InputDecoration(
          labelText: 'Graus',
          prefixIcon: Icon(LucideIcons.hash, size: 20, color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: List.generate(5, (i) {
          return DropdownMenuItem(
            value: i,
            child: Row(
              children: [
                ...List.generate(
                  i,
                  (_) => Container(
                    width: 12,
                    height: 3,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.textSecondary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                if (i > 0) const SizedBox(width: 6),
                Text('$i grau${i != 1 ? 's' : ''}', style: AppTheme.bodyMedium),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _stripes = value);
        },
        dropdownColor: AppTheme.surface,
      ),
    );
  }

  // ============================================
  // FINANCIAL TAB
  // ============================================
  Widget _buildFinancialTab() {
    return Column(
      children: [
        FormSection(
          title: 'Plano e Mensalidade',
          subtitle: 'Configurações financeiras do aluno',
          icon: LucideIcons.wallet,
          badge: 'Obrigatório',
          badgeVariant: BadgeVariant.warning,
          child: Column(
            children: [
              _buildPlanDropdown(),
              const SizedBox(height: 16),

              FormRow(
                children: [
                  CurrencyInput(
                    controller: _tuitionValueController,
                    label: 'Valor da Mensalidade',
                    validator: (value) {
                      if (value?.isEmpty == true) return 'Valor obrigatório';
                      final parsed = double.tryParse(
                        value!.replaceAll(',', '.'),
                      );
                      if (parsed == null) return 'Valor inválido';
                      return null;
                    },
                  ),
                  InputField(
                    controller: _tuitionDayController,
                    label: 'Dia de Vencimento',
                    hintText: '1-28',
                    prefixIcon: LucideIcons.calendar,
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
                ],
              ),
            ],
          ),
        ),

      ],
    );
  }

  Widget _buildPlanDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<Plan?>(
        value: _selectedPlan,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown, color: AppTheme.textSecondary, size: 20),
        decoration: InputDecoration(
          labelText: 'Plano',
          prefixIcon: Icon(LucideIcons.package, size: 20, color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: [
          DropdownMenuItem<Plan?>(
            value: null,
            child: Text('Sem plano', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary)),
          ),
          ..._availablePlans.map((plan) {
            return DropdownMenuItem(
              value: plan,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(plan.name, style: AppTheme.bodyMedium),
                  Text(
                    'R\$ ${plan.monthlyValue.toStringAsFixed(2).replaceAll('.', ',')}',
                    style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            );
          }),
        ],
        onChanged: (value) {
          setState(() {
            _selectedPlan = value;
            if (value != null) {
              _tuitionValueController.text = value.monthlyValue.toStringAsFixed(2).replaceAll('.', ',');
            }
          });
        },
        dropdownColor: AppTheme.surface,
        selectedItemBuilder: (context) {
          return [
            Text('Sem plano', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary)),
            ..._availablePlans.map((plan) {
              return Text(
                '${plan.name} - R\$ ${plan.monthlyValue.toStringAsFixed(2).replaceAll('.', ',')}',
                style: AppTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              );
            }),
          ];
        },
      ),
    );
  }

  // ============================================
  // SAVE STUDENT
  // ============================================
  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) {
      // Find first tab with errors
      _updateTabErrors();
      final errorTab = _tabErrors.entries.firstWhere(
        (e) => e.value,
        orElse: () => MapEntry('personal', false),
      );
      if (errorTab.value) {
        setState(() => _activeTab = errorTab.key);
      }

      context.showError('Corrija os erros no formulário');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final academyId = FirebaseService.academyId;
      final studentService = StudentService(academyId);

      final data = <String, dynamic>{
        'fullName': _fullNameController.text.trim(),
        'nickname': _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'cpf': _cpfController.text.trim().isEmpty ? null : _cpfController.text.trim(),
        'birthDate': _birthDate != null ? Timestamp.fromDate(_birthDate!) : null,
        'category': _category.value,
        'startDate': Timestamp.fromDate(_startDate),
        'currentBelt': _belt,
        'currentStripes': _stripes,
        'status': _status.value,
        'planId': _selectedPlan?.id,
        'tuitionValue': double.parse(_tuitionValueController.text.replaceAll(',', '.')),
        'tuitionDay': int.parse(_tuitionDayController.text),
        'healthNotes': _healthNotesController.text.trim().isEmpty ? null : _healthNotesController.text.trim(),
      };

      // Emergency contact
      if (_emergencyContactNameController.text.isNotEmpty) {
        data['emergencyContact'] = {
          'name': _emergencyContactNameController.text.trim(),
          'phone': _emergencyContactPhoneController.text.trim(),
          'relationship': 'Emergência',
        };
      }

      // Guardian (for kids)
      if (_category == StudentCategory.kids && _guardianNameController.text.isNotEmpty) {
        data['guardian'] = {
          'name': _guardianNameController.text.trim(),
          'phone': _guardianPhoneController.text.trim(),
        };
      }

      if (isEditing) {
        await studentService.update(widget.studentId!, data);
      } else {
        data['isProfilePublic'] = false;
        data['attendanceCount'] = 0;
        data['initialAttendanceCount'] = 0;
        await studentService.createFromMap(data);
      }

      if (mounted) {
        context.showSuccess(isEditing ? 'Aluno atualizado!' : 'Aluno cadastrado!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _updateTabErrors() {
    // Check each tab for validation errors
    _tabErrors['personal'] = _fullNameController.text.isEmpty ||
        (_category == StudentCategory.kids && _guardianNameController.text.isEmpty);
    _tabErrors['financial'] = _tuitionValueController.text.isEmpty ||
        _tuitionDayController.text.isEmpty;
    // Add more checks as needed
  }
}
